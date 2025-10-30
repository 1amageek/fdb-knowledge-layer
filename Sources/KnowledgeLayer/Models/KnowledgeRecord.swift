import Foundation
import TripleLayer

/// Unified knowledge representation integrating Triple, Ontology, and Embedding
///
/// `KnowledgeRecord` is the core data model that combines:
/// - **Structure** (Triple) - Subject-Predicate-Object relationships
/// - **Semantics** (Ontology) - Type information and constraints
/// - **Similarity** (Embedding) - Vector representations for semantic search
///
/// ## Example
/// ```swift
/// let record = KnowledgeRecord(
///     subject: .uri("http://example.org/Alice"),
///     predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
///     object: .uri("http://example.org/Bob"),
///     subjectClass: "Person",
///     objectClass: "Person",
///     confidence: 0.95,
///     source: "GPT-4 extraction"
/// )
/// ```
public struct KnowledgeRecord: Codable, Hashable, Sendable {

    // MARK: - Identity

    /// Unique identifier for this knowledge record
    public let id: UUID

    // MARK: - Triple (Structure)

    /// Subject of the triple
    public let subject: Value

    /// Predicate of the triple
    public let predicate: Value

    /// Object of the triple
    public let object: Value

    /// Optional triple metadata (confidence, source, timestamp)
    public let tripleMetadata: Metadata?

    // MARK: - Ontology (Semantics)

    /// Ontology class of the subject (e.g., "Person", "Organization")
    public let subjectClass: String?

    /// Ontology class of the object
    public let objectClass: String?

    // MARK: - Embedding (Similarity)

    /// Embedding record ID (typically the same as `id.uuidString`)
    public let embeddingID: String?

    /// Embedding model used (e.g., "mlx-embed", "text-embedding-3-small")
    public let embeddingModel: String?

    // MARK: - ODKE+ Metadata

    /// Confidence score from LLM extraction (0.0 - 1.0)
    public let confidence: Float?

    /// Provenance: source of this knowledge (URL, document ID, "GPT-4", etc.)
    public let source: String?

    /// Timestamp when this record was created
    public let createdAt: Date

    /// Timestamp of last update (for versioning)
    public let updatedAt: Date?

    // MARK: - Initialization

    /// Full initializer with all fields
    public init(
        id: UUID = UUID(),
        subject: Value,
        predicate: Value,
        object: Value,
        tripleMetadata: Metadata? = nil,
        subjectClass: String? = nil,
        objectClass: String? = nil,
        embeddingID: String? = nil,
        embeddingModel: String? = nil,
        confidence: Float? = nil,
        source: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.tripleMetadata = tripleMetadata
        self.subjectClass = subjectClass
        self.objectClass = objectClass
        self.embeddingID = embeddingID
        self.embeddingModel = embeddingModel
        self.confidence = confidence
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed Properties

    /// Convert to Triple for TripleStore operations
    ///
    /// This includes all ODKE+ metadata embedded in the Triple.Metadata.custom field.
    public var triple: Triple {
        return Triple(
            subject: subject,
            predicate: predicate,
            object: object,
            metadata: toTripleMetadata()
        )
    }

    /// Text representation for embedding generation
    ///
    /// Combines subject, predicate, and object into a single string.
    /// Used as input for embedding models.
    public var text: String {
        let subjectStr = subject.stringValue ?? ""
        let predicateStr = predicate.stringValue ?? ""
        let objectStr = object.stringValue ?? ""
        return "\(subjectStr) \(predicateStr) \(objectStr)"
    }

    /// Convert KnowledgeRecord metadata to Triple.Metadata
    ///
    /// This preserves all ODKE+ metadata fields in the custom dictionary.
    /// Additionally, unknown custom fields from tripleMetadata are preserved.
    internal func toTripleMetadata() -> Metadata {
        var custom: [String: CodableValue] = [:]

        // First, copy unknown custom fields from original tripleMetadata (if present)
        // This preserves fields that aren't part of the KnowledgeRecord schema
        if let originalCustom = tripleMetadata?.custom {
            for (key, value) in originalCustom {
                // Skip known fields - they will be set from KnowledgeRecord fields below
                if key != "knowledgeId" && key != "subjectClass" && key != "objectClass" &&
                   key != "embeddingID" && key != "embeddingModel" && key != "updatedAt" {
                    custom[key] = value
                }
            }
        }

        // Store KnowledgeRecord ID (overrides any original value)
        custom["knowledgeId"] = .string(id.uuidString)

        // Store ontology classes (overrides any original values)
        if let subjectClass = subjectClass {
            custom["subjectClass"] = .string(subjectClass)
        }
        if let objectClass = objectClass {
            custom["objectClass"] = .string(objectClass)
        }

        // Store embedding information (overrides any original values)
        if let embeddingID = embeddingID {
            custom["embeddingID"] = .string(embeddingID)
        }
        if let embeddingModel = embeddingModel {
            custom["embeddingModel"] = .string(embeddingModel)
        }

        // Store updatedAt timestamp (overrides any original value)
        if let updatedAt = updatedAt {
            custom["updatedAt"] = .string(ISO8601DateFormatter().string(from: updatedAt))
        }

        return Metadata(
            confidence: confidence.map { Double($0) },
            source: source,
            timestamp: createdAt,
            custom: custom.isEmpty ? nil : custom
        )
    }

    /// Create KnowledgeRecord from Triple
    ///
    /// Extracts ODKE+ metadata from Triple.Metadata.custom dictionary.
    internal static func from(triple: Triple) -> KnowledgeRecord {
        let metadata = triple.metadata
        let custom = metadata?.custom ?? [:]

        // Extract ID
        let id: UUID
        if case .string(let idString) = custom["knowledgeId"],
           let uuid = UUID(uuidString: idString) {
            id = uuid
        } else {
            id = UUID()
        }

        // Extract ontology classes
        let subjectClass: String?
        if case .string(let value) = custom["subjectClass"] {
            subjectClass = value
        } else {
            subjectClass = nil
        }

        let objectClass: String?
        if case .string(let value) = custom["objectClass"] {
            objectClass = value
        } else {
            objectClass = nil
        }

        // Extract embedding information
        let embeddingID: String?
        if case .string(let value) = custom["embeddingID"] {
            embeddingID = value
        } else {
            embeddingID = nil
        }

        let embeddingModel: String?
        if case .string(let value) = custom["embeddingModel"] {
            embeddingModel = value
        } else {
            embeddingModel = nil
        }

        // Extract updatedAt
        let updatedAt: Date?
        if case .string(let dateString) = custom["updatedAt"],
           let date = ISO8601DateFormatter().date(from: dateString) {
            updatedAt = date
        } else {
            updatedAt = nil
        }

        return KnowledgeRecord(
            id: id,
            subject: triple.subject,
            predicate: triple.predicate,
            object: triple.object,
            tripleMetadata: metadata,
            subjectClass: subjectClass,
            objectClass: objectClass,
            embeddingID: embeddingID,
            embeddingModel: embeddingModel,
            confidence: metadata?.confidence.map { Float($0) },
            source: metadata?.source,
            createdAt: metadata?.timestamp ?? Date(),
            updatedAt: updatedAt
        )
    }
}

// MARK: - Convenience Initializers

extension KnowledgeRecord {
    /// Create a knowledge record from simple string identifiers
    ///
    /// This is the primary initializer for ODKE+ knowledge extraction.
    /// Use simple entity and predicate names as extracted by LLMs.
    ///
    /// - Parameters:
    ///   - subject: Subject entity name (e.g., "Alice")
    ///   - predicate: Predicate name (e.g., "knows")
    ///   - object: Object entity name or literal value (e.g., "Bob")
    ///   - subjectClass: Optional subject class name
    ///   - objectClass: Optional object class name
    ///   - confidence: Optional confidence score
    ///   - source: Optional source identifier
    ///
    /// ## Example
    /// ```swift
    /// let record = KnowledgeRecord(
    ///     subject: "Alice",
    ///     predicate: "knows",
    ///     object: "Bob",
    ///     confidence: 0.95,
    ///     source: "GPT-4"
    /// )
    /// ```
    public init(
        subject: String,
        predicate: String,
        object: String,
        subjectClass: String? = nil,
        objectClass: String? = nil,
        confidence: Float? = nil,
        source: String? = nil
    ) {
        self.init(
            subject: .text(subject),
            predicate: .text(predicate),
            object: .text(object),
            subjectClass: subjectClass,
            objectClass: objectClass,
            confidence: confidence,
            source: source
        )
    }

    /// Create from LLM extraction result
    ///
    /// - Parameters:
    ///   - triple: Tuple of (subject, predicate, object) strings
    ///   - confidence: Confidence score from LLM
    ///   - source: Source identifier (e.g., "GPT-4", "Claude-3")
    ///
    /// ## Example
    /// ```swift
    /// let record = KnowledgeRecord.fromExtraction(
    ///     triple: ("Alice", "knows", "Bob"),
    ///     confidence: 0.95,
    ///     source: "GPT-4"
    /// )
    /// ```
    public static func fromExtraction(
        triple: (subject: String, predicate: String, object: String),
        confidence: Float,
        source: String
    ) -> KnowledgeRecord {
        return KnowledgeRecord(
            subject: triple.subject,
            predicate: triple.predicate,
            object: triple.object,
            confidence: confidence,
            source: source
        )
    }
}

// MARK: - CustomStringConvertible

extension KnowledgeRecord: CustomStringConvertible {
    public var description: String {
        var desc = "KnowledgeRecord(\(id.uuidString.prefix(8))...): \(subject) \(predicate) \(object)"

        if let subjectClass = subjectClass, let objectClass = objectClass {
            desc += " [:\(subjectClass) → :\(objectClass)]"
        }

        if let confidence = confidence {
            desc += " (conf: \(String(format: "%.2f", confidence)))"
        }

        return desc
    }
}
