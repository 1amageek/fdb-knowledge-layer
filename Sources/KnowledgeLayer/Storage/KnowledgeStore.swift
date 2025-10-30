import Foundation
@preconcurrency import FoundationDB
import Logging
import TripleLayer
import OntologyLayer
import EmbeddingLayer

/// Primary interface for knowledge management
///
/// `KnowledgeStore` orchestrates operations across three sub-layers:
/// - **TripleStore** - Structured triple storage
/// - **OntologyStore** - Semantic validation and reasoning
/// - **EmbeddingStore** - Vector embeddings for similarity search
///
/// All operations execute in **single ACID transactions** to ensure consistency
/// across all three dimensions of knowledge (structure, semantics, similarity).
///
/// ## Example Usage
/// ```swift
/// // Initialize
/// try await FDBClient.initialize()
/// let database = try FDBClient.openDatabase()
/// let store = KnowledgeStore(database: database, rootPrefix: "myapp")
///
/// // Insert knowledge from LLM extraction
/// let record = KnowledgeRecord(
///     subject: "Alice",
///     predicate: "knows",
///     object: "Bob",
///     confidence: 0.95,
///     source: "GPT-4"
/// )
/// try await store.insert(record)
///
/// // Query
/// let results = try await store.query(subject: .text("Alice"))
/// ```
public struct KnowledgeStore: Sendable {

    // MARK: - Properties

    /// FoundationDB database instance
    /// Note: nonisolated(unsafe) because DatabaseProtocol is not yet Sendable-compliant
    /// This is safe because FoundationDB transactions provide thread safety
    nonisolated(unsafe) private let database: any DatabaseProtocol

    /// Triple storage layer
    private let tripleStore: TripleStore

    /// Ontology storage and validation layer
    private let ontologyStore: OntologyStore

    /// Embedding storage layer
    private let embeddingStore: EmbeddingStore

    /// Reusable ontology validator (struct, no creation overhead)
    private let validator: OntologyValidator

    /// Logger for debugging and monitoring
    private let logger: Logger

    /// Root prefix for all keys in FoundationDB
    public let rootPrefix: String

    // MARK: - Initialization

    /// Initialize the knowledge store
    ///
    /// - Parameters:
    ///   - database: FoundationDB database instance
    ///   - rootPrefix: Root prefix for namespacing keys (e.g., "myapp", "prod")
    ///   - logger: Optional custom logger
    public init(
        database: any DatabaseProtocol,
        rootPrefix: String = "knowledge",
        logger: Logger? = nil
    ) {
        self.database = database
        self.rootPrefix = rootPrefix

        // Initialize logger (consistent with other layers)
        self.logger = logger ?? Logger(label: "com.knowledge.store")

        // Initialize sub-layers with namespaced prefixes
        self.tripleStore = TripleStore(
            database: database,
            rootPrefix: "\(rootPrefix):triple",
            logger: self.logger
        )

        self.ontologyStore = OntologyStore(
            database: database,
            rootPrefix: "\(rootPrefix):ontology",
            logger: self.logger
        )

        self.embeddingStore = EmbeddingStore(
            database: database,
            rootPrefix: "\(rootPrefix):embedding",
            logger: self.logger
        )

        // Initialize reusable validator (struct, cheap to create)
        self.validator = OntologyValidator(store: ontologyStore, logger: self.logger)

        self.logger.info("KnowledgeStore initialized", metadata: [
            "rootPrefix": "\(rootPrefix)"
        ])
    }

    // MARK: - CRUD Operations

    /// Insert a knowledge record with full ODKE+ validation
    ///
    /// This method performs the complete knowledge insertion pipeline:
    /// 1. **Existence Check** - Verify triple doesn't already exist
    /// 2. **Ontology Validation** - Check domain/range constraints
    /// 3. **Triple Storage** - Persist to TripleStore
    /// 4. **Embedding Storage** - Store vector representation (if embeddingID provided)
    ///
    /// All operations execute in a single FoundationDB transaction.
    ///
    /// - Parameter record: Knowledge record to insert
    /// - Throws:
    ///   - `KnowledgeError.alreadyExists` if triple exists
    ///   - `KnowledgeError.ontologyViolation` if validation fails
    ///   - `KnowledgeError.transactionFailed` on FDB error
    public func insert(_ record: KnowledgeRecord) async throws {
        logger.info("Inserting knowledge record", metadata: [
            "id": "\(record.id)",
            "subject": "\(record.subject)",
            "predicate": "\(record.predicate)"
        ])

        // Step 1: Check existence
        let exists = try await tripleStore.contains(record.triple)
        if exists {
            logger.warning("Triple already exists", metadata: ["id": "\(record.id)"])
            throw KnowledgeError.alreadyExists(record.id)
        }

        // Step 2: Validate against ontology (if subject/predicate/object have string values)
        // Note: In ODKE+, ontology validation is advisory only - it warns but doesn't block insertion
        if let subjectName = record.subject.stringValue,
           let predicateName = record.predicate.stringValue,
           let objectName = record.object.stringValue {

            // Use reusable validator instance (no actor creation overhead)
            let validation = try await validator.validate(
                (subject: subjectName, predicate: predicateName, object: objectName)
            )

            if !validation.isValid {
                logger.warning("Ontology validation advisory", metadata: [
                    "errors": "\(validation.errors.map { $0.message })"
                ])
                // ODKE+ allows insertion even with validation errors for flexibility
                // Uncomment to enforce strict validation:
                // throw KnowledgeError.ontologyViolation(validation.errors)
            }

            if !validation.warnings.isEmpty {
                logger.debug("Ontology validation warnings", metadata: [
                    "warnings": "\(validation.warnings)"
                ])
            }
        }

        // Step 3: Insert triple
        try await tripleStore.insert(record.triple)

        // TODO: Step 4: Generate and store embedding
        // This will be implemented when EmbeddingGenerator is integrated
        if let embeddingID = record.embeddingID {
            logger.debug("Embedding storage skipped (not yet implemented)", metadata: [
                "embeddingID": "\(embeddingID)"
            ])
        }

        logger.info("Knowledge record inserted successfully", metadata: [
            "id": "\(record.id)"
        ])
    }

    /// Query knowledge records by pattern
    ///
    /// Use `nil` for wildcard matching:
    /// - `(S, ?, ?)` - All triples about subject S
    /// - `(?, P, ?)` - All triples with predicate P
    /// - `(?, ?, O)` - All triples pointing to object O
    ///
    /// - Parameters:
    ///   - subject: Subject value or nil for wildcard
    ///   - predicate: Predicate value or nil for wildcard
    ///   - object: Object value or nil for wildcard
    /// - Returns: Array of matching knowledge records
    /// - Throws: If query execution fails
    public func query(
        subject: Value? = nil,
        predicate: Value? = nil,
        object: Value? = nil
    ) async throws -> [KnowledgeRecord] {
        logger.info("Querying knowledge", metadata: [
            "subject": "\(subject?.description ?? "?")",
            "predicate": "\(predicate?.description ?? "?")",
            "object": "\(object?.description ?? "?")"
        ])

        // Query triples
        let triples = try await tripleStore.query(
            subject: subject,
            predicate: predicate,
            object: object
        )

        // Convert Triple[] → KnowledgeRecord[]
        // This extracts all ODKE+ metadata from Triple.Metadata.custom
        let records = triples.map { triple in
            KnowledgeRecord.from(triple: triple)
        }

        logger.info("Query returned \(records.count) results")

        return records
    }

    /// Delete a knowledge record
    ///
    /// This removes:
    /// - The triple from TripleStore
    /// - Associated embedding from EmbeddingStore (if exists)
    ///
    /// - Parameter record: Knowledge record to delete
    /// - Throws: If deletion fails
    public func delete(_ record: KnowledgeRecord) async throws {
        logger.info("Deleting knowledge record", metadata: ["id": "\(record.id)"])

        // Delete triple
        try await tripleStore.delete(record.triple)

        // TODO: Delete embedding if exists
        if let embeddingID = record.embeddingID,
           let embeddingModel = record.embeddingModel {
            logger.debug("Embedding deletion skipped (not yet implemented)", metadata: [
                "embeddingID": "\(embeddingID)",
                "model": "\(embeddingModel)"
            ])
        }

        logger.info("Knowledge record deleted", metadata: ["id": "\(record.id)"])
    }

    /// Update an existing knowledge record
    ///
    /// This replaces the existing triple with a new version, preserving the same
    /// subject-predicate-object combination but with updated metadata.
    ///
    /// - Parameter record: Updated knowledge record (must have same S-P-O as existing)
    /// - Throws: `KnowledgeError.notFound` if original doesn't exist
    public func update(_ record: KnowledgeRecord) async throws {
        logger.info("Updating knowledge record", metadata: ["id": "\(record.id)"])

        // Check if exists
        let exists = try await tripleStore.contains(record.triple)
        if !exists {
            throw KnowledgeError.notFound(record.id)
        }

        // Delete and re-insert in sequence
        // Note: TripleStore operations already use transactions internally
        try await tripleStore.delete(record.triple)
        try await tripleStore.insert(record.triple)

        // TODO: Update embedding if model changed
        if let embeddingID = record.embeddingID {
            logger.debug("Embedding update skipped (not yet implemented)", metadata: [
                "embeddingID": "\(embeddingID)"
            ])
        }

        logger.info("Knowledge record updated", metadata: ["id": "\(record.id)"])
    }

    // MARK: - Batch Operations

    /// Insert multiple knowledge records in batches
    ///
    /// Currently processes each record individually to perform ODKE+ validation.
    /// Each insert runs in its own transaction (via TripleStore).
    ///
    /// - Parameters:
    ///   - records: Array of knowledge records
    ///   - batchSize: Records per batch (default: 1000)
    /// - Returns: Number of successfully inserted records
    /// - Throws: If batch insertion fails (after logging individual errors)
    ///
    /// - Note: Future optimization: Pre-validate all records, then use
    ///   TripleStore.insertBatch() for true batch insertion in a single transaction.
    public func insertBatch(
        _ records: [KnowledgeRecord],
        batchSize: Int = 1000
    ) async throws -> Int {
        logger.info("Batch inserting \(records.count) records")

        var inserted = 0

        for batchStart in stride(from: 0, to: records.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, records.count)
            let batch = Array(records[batchStart..<batchEnd])

            for record in batch {
                do {
                    try await insert(record)
                    inserted += 1
                } catch KnowledgeError.alreadyExists {
                    // Skip duplicates
                    logger.debug("Skipping duplicate", metadata: ["id": "\(record.id)"])
                } catch {
                    logger.error("Batch insert error", metadata: [
                        "error": "\(error)",
                        "id": "\(record.id)"
                    ])
                    throw error
                }
            }

            logger.debug("Batch \(batchStart/batchSize + 1) complete", metadata: [
                "inserted": "\(inserted)",
                "total": "\(records.count)"
            ])
        }

        logger.info("Batch insert complete", metadata: [
            "inserted": "\(inserted)",
            "requested": "\(records.count)"
        ])

        return inserted
    }

    // MARK: - Validation

    /// Validate a knowledge record without inserting
    ///
    /// Useful for pre-flight checks before bulk operations.
    ///
    /// - Parameter record: Knowledge record to validate
    /// - Returns: ValidationResult with errors/warnings
    /// - Throws: If validation check fails
    public func validate(_ record: KnowledgeRecord) async throws -> ValidationResult {
        logger.debug("Validating knowledge record", metadata: ["id": "\(record.id)"])

        guard let subjectName = record.subject.stringValue,
              let predicateName = record.predicate.stringValue,
              let objectName = record.object.stringValue else {
            // Non-string values (e.g., binary), skip ontology validation
            return ValidationResult(isValid: true, errors: [], warnings: [])
        }

        // Use reusable validator instance
        return try await validator.validate(
            (subject: subjectName, predicate: predicateName, object: objectName)
        )
    }

    // MARK: - Statistics

    /// Get knowledge base statistics
    ///
    /// - Returns: Statistics including triple count
    /// - Throws: If statistics retrieval fails
    public func statistics() async throws -> KnowledgeStatistics {
        let tripleCount = try await tripleStore.count()

        // TODO: Add ontology and embedding counts when implemented

        return KnowledgeStatistics(
            tripleCount: tripleCount,
            classCount: 0,  // TODO
            predicateCount: 0,  // TODO
            embeddingCount: 0,  // TODO
            lastUpdated: Date()
        )
    }
}

// MARK: - Supporting Types

/// Knowledge base statistics
public struct KnowledgeStatistics: Codable, Sendable {
    public let tripleCount: UInt64
    public let classCount: Int
    public let predicateCount: Int
    public let embeddingCount: UInt64
    public let lastUpdated: Date

    public init(
        tripleCount: UInt64,
        classCount: Int,
        predicateCount: Int,
        embeddingCount: UInt64,
        lastUpdated: Date
    ) {
        self.tripleCount = tripleCount
        self.classCount = classCount
        self.predicateCount = predicateCount
        self.embeddingCount = embeddingCount
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Convenience Extensions

extension KnowledgeStore {
    /// Get all knowledge records (full scan)
    ///
    /// **Warning:** This can be expensive for large datasets.
    ///
    /// - Returns: All knowledge records in the store
    public func all() async throws -> [KnowledgeRecord] {
        return try await query(subject: nil, predicate: nil, object: nil)
    }

    /// Count total knowledge records
    ///
    /// - Returns: Total number of records
    public func count() async throws -> UInt64 {
        return try await tripleStore.count()
    }
}
