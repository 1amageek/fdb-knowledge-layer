import Testing
import Foundation
@preconcurrency import FoundationDB
@testable import KnowledgeLayer
import TripleLayer
import OntologyLayer
import Logging

/// Integration tests for KnowledgeStore
///
/// These tests verify the complete ODKE+ knowledge circulation:
/// 1. Existence checking
/// 2. Ontology validation
/// 3. Triple storage
/// 4. Embedding generation (TODO)
/// 5. Query operations
@Suite("KnowledgeStore Integration Tests")
struct KnowledgeStoreTests {

    // MARK: - Setup & Teardown

    /// Initialize FDB and create test store
    private static func createTestStore() async throws -> KnowledgeStore {
        // Initialize FoundationDB (ignore error if already initialized)
        do {
            try await FDBClient.initialize()
        } catch {
            // Already initialized, ignore
        }

        let database = try FDBClient.openDatabase()

        // Create store with unique prefix for this test run
        let prefix = "test-knowledge-\(UUID().uuidString.prefix(8))"

        var logger = Logger(label: "com.knowledge.test")
        logger.logLevel = .warning  // Reduce logging overhead

        return KnowledgeStore(
            database: database,
            rootPrefix: prefix,
            logger: logger
        )
    }

    // MARK: - Basic CRUD Tests

    @Test("Insert and query a simple knowledge record")
    func testBasicInsertAndQuery() async throws {
        let store = try await Self.createTestStore()

        // Create a simple knowledge record (as extracted by LLM)
        let record = KnowledgeRecord(
            subject: "Alice",
            predicate: "knows",
            object: "Bob",
            confidence: 0.95,
            source: "test"
        )

        // Insert
        try await store.insert(record)

        // Query by subject
        let results = try await store.query(
            subject: .text("Alice")
        )

        #expect(results.count == 1)
        #expect(results.first?.subject == record.subject)
        #expect(results.first?.predicate == record.predicate)
        #expect(results.first?.object == record.object)
    }

    @Test("Insert duplicate record throws alreadyExists error")
    func testDuplicateInsertThrows() async throws {
        let store = try await Self.createTestStore()

        let record = KnowledgeRecord(
            subject: "Alice",
            predicate: "name",
            object: "Alice"
        )

        // First insert succeeds
        try await store.insert(record)

        // Second insert should throw
        await #expect(throws: KnowledgeError.self) {
            try await store.insert(record)
        }
    }

    @Test("Delete a knowledge record")
    func testDelete() async throws {
        let store = try await Self.createTestStore()

        let record = KnowledgeRecord(
            subject: "Alice",
            predicate: "knows",
            object: "Bob"
        )

        // Insert
        try await store.insert(record)

        // Verify exists
        var results = try await store.query(subject: record.subject)
        #expect(results.count == 1)

        // Delete
        try await store.delete(record)

        // Verify deleted
        results = try await store.query(subject: record.subject)
        #expect(results.isEmpty)
    }

    @Test("Update a knowledge record")
    func testUpdate() async throws {
        let store = try await Self.createTestStore()

        let original = KnowledgeRecord(
            subject: "Alice",
            predicate: "knows",
            object: "Bob"
        )

        // Insert original
        try await store.insert(original)

        // Create updated version (same triple, will replace)
        let updated = KnowledgeRecord(
            id: original.id,
            subject: original.subject,
            predicate: original.predicate,
            object: original.object,
            confidence: 0.99,  // Higher confidence
            source: "updated"
        )

        // Update
        try await store.update(updated)

        // Query and verify
        let results = try await store.query(subject: original.subject)
        #expect(results.count == 1)
    }

    @Test("Update non-existent record throws notFound error")
    func testUpdateNonExistentThrows() async throws {
        let store = try await Self.createTestStore()

        let record = KnowledgeRecord(
            subject: "NonExistent",
            predicate: "knows",
            object: "Nobody"
        )

        await #expect(throws: KnowledgeError.self) {
            try await store.update(record)
        }
    }

    // MARK: - Query Pattern Tests

    @Test("Query with wildcard patterns")
    func testWildcardQueries() async throws {
        let store = try await Self.createTestStore()

        // Insert multiple records
        let records = [
            KnowledgeRecord(
                subject: "Alice",
                predicate: "knows",
                object: "Bob"
            ),
            KnowledgeRecord(
                subject: "Alice",
                predicate: "knows",
                object: "Carol"
            ),
            KnowledgeRecord(
                subject: "Bob",
                predicate: "knows",
                object: "Carol"
            )
        ]

        for record in records {
            try await store.insert(record)
        }

        // Query: All triples about Alice (S, ?, ?)
        let aliceResults = try await store.query(
            subject: .text("Alice")
        )
        #expect(aliceResults.count == 2)

        // Query: All "knows" relationships (?, P, ?)
        let knowsResults = try await store.query(
            predicate: .text("knows")
        )
        #expect(knowsResults.count == 3)

        // Query: All who know Carol (?, ?, O)
        let carolResults = try await store.query(
            object: .text("Carol")
        )
        #expect(carolResults.count == 2)

        // Query: Specific triple (S, P, O)
        let specificResults = try await store.query(
            subject: .text("Alice"),
            predicate: .text("knows"),
            object: .text("Bob")
        )
        #expect(specificResults.count == 1)
    }

    @Test("Query returns empty array when no matches")
    func testQueryNoMatches() async throws {
        let store = try await Self.createTestStore()

        let results = try await store.query(
            subject: .text("NonExistent")
        )

        #expect(results.isEmpty)
    }

    // MARK: - Batch Operation Tests

    @Test("Batch insert multiple records")
    func testBatchInsert() async throws {
        let store = try await Self.createTestStore()

        // Create batch of records
        let records = (0..<10).map { i in
            KnowledgeRecord(
                subject: "Person\(i)",
                predicate: "name",
                object: "Person \(i)"
            )
        }

        // Batch insert
        let inserted = try await store.insertBatch(records, batchSize: 5)

        #expect(inserted == 10)

        // Verify all inserted
        let count = try await store.count()
        #expect(count == 10)
    }

    @Test("Batch insert skips duplicates")
    func testBatchInsertSkipsDuplicates() async throws {
        let store = try await Self.createTestStore()

        let record = KnowledgeRecord(
            subject: "Alice",
            predicate: "name",
            object: "Alice"
        )

        // Insert same record twice in batch
        let records = [record, record]

        let inserted = try await store.insertBatch(records)

        // Only one should be inserted
        #expect(inserted == 1)

        let count = try await store.count()
        #expect(count == 1)
    }

    // MARK: - Ontology Validation Tests

    @Test("Insert with ontology validation")
    func testOntologyValidation() async throws {
        let store = try await Self.createTestStore()

        // Note: This test assumes ontology definitions exist
        // In a real test, you would first define the ontology

        let record = KnowledgeRecord(
            subject: "Alice",
            predicate: "knows",
            object: "Bob",
            subjectClass: "Person",
            objectClass: "Person"
        )

        // Should succeed if ontology is properly defined
        try await store.insert(record)

        let results = try await store.query(subject: record.subject)
        #expect(results.count == 1)
    }

    @Test("Validate record without inserting")
    func testValidateOnly() async throws {
        let store = try await Self.createTestStore()

        let record = KnowledgeRecord(
            subject: "Alice",
            predicate: "knows",
            object: "Bob"
        )

        // Validate only
        let validation = try await store.validate(record)

        // In ODKE+, undefined predicates are validation errors (isValid = false)
        // but they don't block insertion (advisory only)
        #expect(!validation.isValid)
        #expect(validation.errors.count > 0)
        #expect(validation.errors[0].message.contains("Predicate"))
    }

    // MARK: - Value Type Tests

    @Test("Insert and query with different value types")
    func testDifferentValueTypes() async throws {
        let store = try await Self.createTestStore()

        // Text values (entity names)
        let textEntityRecord = KnowledgeRecord(
            subject: .text("Alice"),
            predicate: .text("knows"),
            object: .text("Bob")
        )
        try await store.insert(textEntityRecord)

        // Text value
        let textRecord = KnowledgeRecord(
            subject: .text("Alice"),
            predicate: .text("name"),
            object: .text("Alice Smith")
        )
        try await store.insert(textRecord)

        // Integer value
        let intRecord = KnowledgeRecord(
            subject: .text("Alice"),
            predicate: .text("age"),
            object: .integer(30)
        )
        try await store.insert(intRecord)

        // Float value
        let floatRecord = KnowledgeRecord(
            subject: .text("Alice"),
            predicate: .text("score"),
            object: .float(98.5)
        )
        try await store.insert(floatRecord)

        // Boolean value
        let boolRecord = KnowledgeRecord(
            subject: .text("Alice"),
            predicate: .text("active"),
            object: .boolean(true)
        )
        try await store.insert(boolRecord)

        // Query all records about Alice
        let results = try await store.query(
            subject: .text("Alice")
        )

        #expect(results.count == 5)
    }

    // MARK: - Statistics Tests

    @Test("Get knowledge base statistics")
    func testStatistics() async throws {
        let store = try await Self.createTestStore()

        // Insert some records
        let records = (0..<5).map { i in
            KnowledgeRecord(
                subject: "Person\(i)",
                predicate: "name",
                object: "Person \(i)"
            )
        }

        for record in records {
            try await store.insert(record)
        }

        // Get statistics
        let stats = try await store.statistics()

        #expect(stats.tripleCount == 5)
        #expect(stats.lastUpdated <= Date())
    }

    @Test("Count returns correct number of records")
    func testCount() async throws {
        let store = try await Self.createTestStore()

        // Initially empty
        var count = try await store.count()
        #expect(count == 0)

        // Insert records
        let records = (0..<3).map { i in
            KnowledgeRecord(
                subject: "Person\(i)",
                predicate: "name",
                object: "Person \(i)"
            )
        }

        for record in records {
            try await store.insert(record)
        }

        // Count should increase
        count = try await store.count()
        #expect(count == 3)
    }

    @Test("Get all records")
    func testGetAll() async throws {
        let store = try await Self.createTestStore()

        // Insert records
        let records = (0..<3).map { i in
            KnowledgeRecord(
                subject: "Person\(i)",
                predicate: "name",
                object: "Person \(i)"
            )
        }

        for record in records {
            try await store.insert(record)
        }

        // Get all
        let all = try await store.all()

        #expect(all.count == 3)
    }

    // MARK: - Metadata Tests

    @Test("Insert with ODKE+ metadata")
    func testODKEMetadata() async throws {
        let store = try await Self.createTestStore()

        let record = KnowledgeRecord(
            subject: "Alice",
            predicate: "knows",
            object: "Bob",
            subjectClass: "Person",
            objectClass: "Person",
            confidence: 0.95,
            source: "GPT-4"
        )

        try await store.insert(record)

        let results = try await store.query(subject: record.subject)

        #expect(results.count == 1)

        let retrieved = results.first!
        #expect(retrieved.confidence == 0.95)
        #expect(retrieved.source == "GPT-4")
        #expect(retrieved.subjectClass == "Person")
        #expect(retrieved.objectClass == "Person")
    }

    // MARK: - Error Handling Tests

    @Test("KnowledgeError descriptions are informative")
    func testErrorDescriptions() {
        let id = UUID()

        let alreadyExistsError = KnowledgeError.alreadyExists(id)
        #expect(alreadyExistsError.description.contains(id.uuidString))

        let notFoundError = KnowledgeError.notFound(id)
        #expect(notFoundError.description.contains("not found"))

        let invalidRecordError = KnowledgeError.invalidRecord("test message")
        #expect(invalidRecordError.description.contains("test message"))
    }
}
