# fdb-knowledge-layer API Design

**Version:** 0.1
**Date:** 2025-10-30

---

## Table of Contents

1. [Public API Overview](#1-public-api-overview)
2. [KnowledgeStore](#2-knowledgestore)
3. [KnowledgeRecord](#3-knowledgerecord)
4. [KnowledgeQueryEngine](#4-knowledgequeryengine)
5. [KnowledgeLoop](#5-knowledgeloop)
6. [Error Handling](#6-error-handling)
7. [Usage Examples](#7-usage-examples)

---

## 1. Public API Overview

### 1.1 Core Modules

```swift
import KnowledgeLayer  // Main module
import TripleLayer     // Re-exported for Value types
```

### 1.2 Main Actors

| Actor | Purpose | Thread-Safe |
|-------|---------|-------------|
| `KnowledgeStore` | Primary CRUD interface | ✅ |
| `KnowledgeQueryEngine` | Advanced search | ✅ |
| `KnowledgeLoop` | ODKE+ circulation | ✅ |

### 1.3 Public Protocols

```swift
/// Embedding generation abstraction
public protocol EmbeddingGeneratorProtocol: Sendable {
    func generateEmbedding(for text: String) async throws -> [Float]
}

/// LLM extraction abstraction
public protocol LLMExtractorProtocol: Sendable {
    func extract(from text: String) async throws -> [KnowledgeRecord]
}
```

---

## 2. KnowledgeStore

### 2.1 Actor Definition

```swift
public actor KnowledgeStore {
    public init(
        database: any DatabaseProtocol,
        rootPrefix: String = "knowledge",
        logger: Logger? = nil
    ) async throws
}
```

### 2.2 CRUD Operations

#### 2.2.1 Insert

```swift
/// Insert a knowledge record with full ODKE+ validation
///
/// This method performs:
/// 1. Existence check (TripleStore)
/// 2. Ontology validation (OntologyValidator)
/// 3. Triple storage (TripleStore)
/// 4. Embedding generation & storage (EmbeddingStore)
///
/// All operations execute in a single FoundationDB transaction.
///
/// - Parameter record: The knowledge record to insert
/// - Throws:
///   - `KnowledgeError.alreadyExists` if triple exists
///   - `KnowledgeError.ontologyViolation` if validation fails
///   - `KnowledgeError.transactionFailed` if FDB error occurs
public func insert(_ record: KnowledgeRecord) async throws
```

**Example:**

```swift
let record = KnowledgeRecord(
    subject: .uri("http://example.org/Alice"),
    predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
    object: .uri("http://example.org/Bob"),
    subjectClass: "Person",
    objectClass: "Person"
)

try await store.insert(record)
```

#### 2.2.2 Query

```swift
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
public func query(
    subject: Value? = nil,
    predicate: Value? = nil,
    object: Value? = nil
) async throws -> [KnowledgeRecord]
```

**Example:**

```swift
// Find all knowledge about Alice
let results = try await store.query(
    subject: .uri("http://example.org/Alice"),
    predicate: nil,
    object: nil
)

for record in results {
    print("\(record.predicate) → \(record.object)")
}
```

#### 2.2.3 Update

```swift
/// Update an existing knowledge record
///
/// Note: This creates a new version while preserving the original
/// (soft update). Use `delete()` + `insert()` for hard replacement.
///
/// - Parameter record: Updated knowledge record
/// - Throws: `KnowledgeError.notFound` if original doesn't exist
public func update(_ record: KnowledgeRecord) async throws
```

#### 2.2.4 Delete

```swift
/// Delete a knowledge record
///
/// This removes:
/// - The triple (TripleStore)
/// - Associated embedding (EmbeddingStore)
///
/// Ontology definitions are preserved.
///
/// - Parameter record: Knowledge record to delete
/// - Throws: `KnowledgeError.transactionFailed` on FDB error
public func delete(_ record: KnowledgeRecord) async throws
```

### 2.3 Batch Operations

```swift
/// Insert multiple knowledge records in batches
///
/// Automatically splits into transaction-sized batches
/// (default: 1000 records per transaction).
///
/// - Parameters:
///   - records: Array of knowledge records
///   - batchSize: Records per transaction (default: 1000)
/// - Returns: Number of successfully inserted records
public func insertBatch(
    _ records: [KnowledgeRecord],
    batchSize: Int = 1000
) async throws -> Int
```

### 2.4 Validation

```swift
/// Validate a knowledge record without inserting
///
/// Useful for pre-flight checks before bulk operations.
///
/// - Parameter record: Knowledge record to validate
/// - Returns: ValidationResult with errors/warnings
public func validate(_ record: KnowledgeRecord) async throws -> ValidationResult
```

### 2.5 Statistics

```swift
/// Get knowledge base statistics
///
/// - Returns: Statistics including triple count, ontology classes, embeddings
public func statistics() async throws -> KnowledgeStatistics

public struct KnowledgeStatistics: Codable, Sendable {
    public let tripleCount: UInt64
    public let classCount: Int
    public let predicateCount: Int
    public let embeddingCount: UInt64
    public let lastUpdated: Date
}
```

---

## 3. KnowledgeRecord

### 3.1 Structure

```swift
public struct KnowledgeRecord: Codable, Hashable, Sendable {
    // Identity
    public let id: UUID

    // Triple (Structure)
    public let subject: Value
    public let predicate: Value
    public let object: Value
    public let tripleMetadata: Metadata?

    // Ontology (Semantics)
    public let subjectClass: String?
    public let objectClass: String?

    // Embedding (Similarity)
    public let embeddingID: String?
    public let embeddingModel: String?

    // ODKE+ Metadata
    public let confidence: Float?
    public let source: String?
    public let createdAt: Date
    public let updatedAt: Date?
}
```

### 3.2 Initializers

#### Minimal Initializer

```swift
public init(
    subject: Value,
    predicate: Value,
    object: Value
)
```

**Example:**

```swift
let record = KnowledgeRecord(
    subject: .uri("http://example.org/Alice"),
    predicate: .uri("http://xmlns.com/foaf/0.1/name"),
    object: .text("Alice Smith")
)
```

#### Full Initializer

```swift
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
)
```

### 3.3 Computed Properties

```swift
/// Convert to Triple for TripleStore operations
public var triple: Triple {
    Triple(
        subject: subject,
        predicate: predicate,
        object: object,
        metadata: tripleMetadata
    )
}

/// Text representation for embedding generation
public var text: String {
    "\(subject.stringValue ?? "") \(predicate.stringValue ?? "") \(object.stringValue ?? "")"
}
```

### 3.4 Convenience Initializers

```swift
/// Create from URI strings
public static func fromURIs(
    subject: String,
    predicate: String,
    object: String,
    confidence: Float? = nil
) -> KnowledgeRecord

/// Create from LLM extraction result
public static func fromExtraction(
    triple: (String, String, String),
    confidence: Float,
    source: String
) -> KnowledgeRecord
```

---

## 4. KnowledgeQueryEngine

### 4.1 Actor Definition

```swift
public actor KnowledgeQueryEngine {
    public init(
        store: KnowledgeStore,
        embeddingGenerator: any EmbeddingGeneratorProtocol
    )
}
```

### 4.2 Search Methods

#### 4.2.1 Text Search

```swift
/// Search by natural language query
///
/// Combines:
/// 1. Embedding generation from query text
/// 2. Vector similarity search
/// 3. Triple retrieval
///
/// - Parameters:
///   - text: Natural language query
///   - topK: Number of results to return
/// - Returns: Ranked knowledge records by similarity
public func search(
    byText text: String,
    topK: Int = 10
) async throws -> [SearchResult]

public struct SearchResult: Sendable {
    public let record: KnowledgeRecord
    public let score: Float  // Similarity score [0, 1]
}
```

**Example:**

```swift
let engine = KnowledgeQueryEngine(
    store: store,
    embeddingGenerator: mlxGenerator
)

let results = try await engine.search(
    byText: "people who know each other",
    topK: 5
)

for result in results {
    print("Score: \(result.score): \(result.record.triple)")
}
```

#### 4.2.2 Ontology-Filtered Search

```swift
/// Search with ontology class filtering
///
/// - Parameters:
///   - text: Natural language query
///   - ontologyClass: Filter by subject/object class
///   - topK: Number of results
/// - Returns: Filtered search results
public func search(
    byText text: String,
    ontologyClass: String,
    topK: Int = 10
) async throws -> [SearchResult]
```

**Example:**

```swift
// Find only Person entities
let people = try await engine.search(
    byText: "famous scientists",
    ontologyClass: "Person",
    topK: 10
)
```

#### 4.2.3 Hybrid Search

```swift
/// Hybrid search combining structure + semantics + similarity
///
/// - Parameters:
///   - structuralPattern: Triple pattern (e.g., `(?, "knows", ?)`)
///   - semanticQuery: Natural language filter
///   - ontologyFilter: Optional class filter
///   - topK: Number of results
/// - Returns: Ranked hybrid results
public func hybridSearch(
    structuralPattern: (Value?, Value?, Value?),
    semanticQuery: String? = nil,
    ontologyFilter: String? = nil,
    topK: Int = 10
) async throws -> [SearchResult]
```

**Example:**

```swift
// Find people who know someone, ranked by similarity to "famous scientists"
let results = try await engine.hybridSearch(
    structuralPattern: (nil, .uri("http://xmlns.com/foaf/0.1/knows"), nil),
    semanticQuery: "famous scientists",
    ontologyFilter: "Person",
    topK: 10
)
```

---

## 5. KnowledgeLoop

### 5.1 Actor Definition

```swift
public actor KnowledgeLoop {
    public init(
        store: KnowledgeStore,
        extractor: any LLMExtractorProtocol,
        embeddingGenerator: any EmbeddingGeneratorProtocol,
        logger: Logger? = nil
    )
}
```

### 5.2 Circulation Methods

#### 5.2.1 Single Iteration

```swift
/// Execute one ODKE+ circulation iteration
///
/// Steps:
/// 1. Extract candidate knowledge from text (LLM)
/// 2. Validate each candidate (Ontology)
/// 3. Insert valid knowledge (Store)
/// 4. Generate embeddings (MLX)
/// 5. Record feedback (Accepted/Rejected)
///
/// - Parameter text: Input text for extraction
/// - Returns: Iteration result with statistics
public func iterate(text: String) async throws -> IterationResult

public struct IterationResult: Sendable {
    public let candidatesExtracted: Int
    public let validationPassed: Int
    public let validationFailed: Int
    public let inserted: [KnowledgeRecord]
    public let rejections: [RejectionRecord]
}

public struct RejectionRecord: Sendable {
    public let candidate: KnowledgeRecord
    public let reason: KnowledgeError
    public let timestamp: Date
}
```

**Example:**

```swift
let loop = KnowledgeLoop(
    store: store,
    extractor: gpt4Extractor,
    embeddingGenerator: mlxGenerator
)

let text = """
Albert Einstein was a theoretical physicist.
He developed the theory of relativity.
"""

let result = try await loop.iterate(text: text)

print("Extracted: \(result.candidatesExtracted)")
print("Inserted: \(result.inserted.count)")
print("Rejected: \(result.rejections.count)")
```

#### 5.2.2 Continuous Loop

```swift
/// Run continuous ODKE+ circulation
///
/// - Parameters:
///   - textStream: AsyncSequence of input texts
///   - feedbackInterval: Iterations between feedback generation
/// - Returns: AsyncSequence of iteration results
public func run(
    textStream: any AsyncSequence<String, Never>,
    feedbackInterval: Int = 10
) -> AsyncStream<IterationResult>
```

#### 5.2.3 Feedback Generation

```swift
/// Generate feedback prompt for LLM
///
/// Analyzes accepted/rejected knowledge to improve extraction quality.
///
/// - Returns: Feedback prompt for next iteration
public func generateFeedback() async throws -> String
```

---

## 6. Error Handling

### 6.1 KnowledgeError

```swift
public enum KnowledgeError: Error, Sendable {
    case alreadyExists(UUID)
    case notFound(UUID)
    case ontologyViolation([ValidationError])
    case embeddingGenerationFailed(String)
    case transactionFailed(Error)
}
```

### 6.2 Error Handling Patterns

#### Pattern 1: Try-Catch with Specific Errors

```swift
do {
    try await store.insert(record)
} catch KnowledgeError.alreadyExists(let id) {
    print("Skipping duplicate: \(id)")
} catch KnowledgeError.ontologyViolation(let errors) {
    print("Validation failed: \(errors)")
} catch {
    print("Unexpected error: \(error)")
}
```

#### Pattern 2: Validation Before Insert

```swift
let validation = try await store.validate(record)

if validation.isValid {
    try await store.insert(record)
} else {
    print("Errors: \(validation.errors)")
    print("Warnings: \(validation.warnings)")
}
```

---

## 7. Usage Examples

### 7.1 Complete Workflow

```swift
import FoundationDB
import KnowledgeLayer
import TripleLayer

// 1. Initialize FoundationDB
try await FDBClient.initialize()
let database = try FDBClient.openDatabase()

// 2. Create KnowledgeStore
let store = KnowledgeStore(
    database: database,
    rootPrefix: "myapp"
)

// 3. Insert knowledge
let alice = KnowledgeRecord(
    subject: .uri("http://example.org/Alice"),
    predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
    object: .uri("http://example.org/Bob"),
    subjectClass: "Person",
    objectClass: "Person",
    confidence: 0.95,
    source: "GPT-4"
)

try await store.insert(alice)

// 4. Query
let results = try await store.query(
    subject: .uri("http://example.org/Alice")
)

print("Found \(results.count) triples about Alice")

// 5. Statistics
let stats = try await store.statistics()
print("Total triples: \(stats.tripleCount)")
```

### 7.2 Batch Loading

```swift
// Load knowledge from file
let records = try loadKnowledgeFromJSON("data.json")

// Insert in batches
let inserted = try await store.insertBatch(
    records,
    batchSize: 1000
)

print("Inserted \(inserted) / \(records.count) records")
```

### 7.3 ODKE+ Circulation

```swift
// Initialize loop
let loop = KnowledgeLoop(
    store: store,
    extractor: GPT4Extractor(),
    embeddingGenerator: MLXGenerator()
)

// Process documents
for document in documents {
    let result = try await loop.iterate(text: document)

    print("Iteration complete:")
    print("  Inserted: \(result.inserted.count)")
    print("  Rejected: \(result.rejections.count)")
}

// Generate feedback
let feedback = try await loop.generateFeedback()
print("Feedback: \(feedback)")
```

---

## 8. API Stability

| API | Stability | Notes |
|-----|-----------|-------|
| `KnowledgeStore` CRUD | ✅ Stable | Core API finalized |
| `KnowledgeRecord` | ✅ Stable | Data model finalized |
| `KnowledgeQueryEngine` | ⚠️ Beta | Interface may change |
| `KnowledgeLoop` | ⚠️ Experimental | Under active development |

---

## 9. Migration Guide

### From v0.1 to v1.0 (Planned)

Breaking changes expected:
- `KnowledgeQueryEngine` constructor signature
- `KnowledgeLoop.iterate()` return type
- New optional parameters in `insert()`

Migration path will be documented in v1.0 release notes.

---

**Next:** See [INTEGRATION.md](INTEGRATION.md) for integration with sub-layers.

---

**Built with ❤️ using Swift and FoundationDB**
