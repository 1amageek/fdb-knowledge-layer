# Integration Guide

**fdb-knowledge-layer ↔ Sub-Layers Integration**

**Version:** 0.1
**Date:** 2025-10-30

---

## Table of Contents

1. [Integration Overview](#1-integration-overview)
2. [TripleLayer Integration](#2-triplelayer-integration)
3. [OntologyLayer Integration](#3-ontologylayer-integration)
4. [EmbeddingLayer Integration](#4-embeddinglayer-integration)
5. [Transaction Coordination](#5-transaction-coordination)
6. [Testing Integration](#6-testing-integration)

---

## 1. Integration Overview

### 1.1 Dependency Architecture

```
fdb-knowledge-layer
├── depends on → fdb-triple-layer (v0.1)
├── depends on → fdb-ontology-layer (v0.1)
└── depends on → fdb-embedding-layer (v0.1)
```

### 1.2 Package Configuration

**fdb-knowledge-layer/Package.swift:**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fdb-knowledge-layer",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "KnowledgeLayer",
            targets: ["KnowledgeLayer"]
        )
    ],
    dependencies: [
        // Sub-layer dependencies (local paths for development)
        .package(path: "../fdb-triple-layer"),
        .package(path: "../fdb-ontology-layer"),
        .package(path: "../fdb-embedding-layer"),

        // Direct dependencies
        .package(url: "https://github.com/apple/foundationdb-swift.git", from: "0.1.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "KnowledgeLayer",
            dependencies: [
                .product(name: "TripleLayer", package: "fdb-triple-layer"),
                .product(name: "OntologyLayer", package: "fdb-ontology-layer"),
                .product(name: "EmbeddingLayer", package: "fdb-embedding-layer"),
                .product(name: "FoundationDB", package: "foundationdb-swift"),
                .product(name: "Logging", package: "swift-log")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "KnowledgeLayerTests",
            dependencies: ["KnowledgeLayer"]
        )
    ]
)
```

### 1.3 Directory Structure

```
Desktop/
├── fdb-triple-layer/
│   └── Sources/TripleLayer/
├── fdb-ontology-layer/
│   └── Sources/OntologyLayer/
├── fdb-embedding-layer/
│   └── Sources/EmbeddingLayer/
└── fdb-knowledge-layer/
    ├── Package.swift (references ../fdb-*)
    └── Sources/KnowledgeLayer/
```

---

## 2. TripleLayer Integration

### 2.1 API Surface Used

**From TripleLayer:**

```swift
import TripleLayer

// Data models (re-exported by KnowledgeLayer)
public typealias Triple = TripleLayer.Triple
public typealias Value = TripleLayer.Value
public typealias Metadata = TripleLayer.Metadata

// Store operations
public actor TripleStore {
    public func insert(_ triple: Triple) async throws
    public func delete(_ triple: Triple) async throws
    public func query(
        subject: Value?,
        predicate: Value?,
        object: Value?
    ) async throws -> [Triple]
    public func contains(_ triple: Triple) async throws -> Bool
    public func count() async throws -> UInt64
}
```

### 2.2 Integration Pattern

```swift
// Sources/KnowledgeLayer/Storage/KnowledgeStore.swift

import TripleLayer

public actor KnowledgeStore {
    private let tripleStore: TripleStore

    public init(database: any DatabaseProtocol, rootPrefix: String) async throws {
        // Initialize TripleStore with namespaced prefix
        self.tripleStore = TripleStore(
            database: database,
            rootPrefix: "\(rootPrefix):triple",
            logger: logger
        )
    }

    public func insert(_ record: KnowledgeRecord) async throws {
        // Convert KnowledgeRecord → Triple
        let triple = record.triple

        // Check existence
        let exists = try await tripleStore.contains(triple)
        guard !exists else {
            throw KnowledgeError.alreadyExists(record.id)
        }

        // Insert via TripleStore
        try await tripleStore.insert(triple)
    }
}
```

### 2.3 Value Type Mapping

**KnowledgeRecord uses TripleLayer's Value enum:**

```swift
import TripleLayer

public struct KnowledgeRecord {
    public let subject: Value    // TripleLayer.Value
    public let predicate: Value
    public let object: Value
}

// Example usage
let record = KnowledgeRecord(
    subject: .uri("http://example.org/Alice"),      // Value.uri
    predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
    object: .uri("http://example.org/Bob")
)
```

### 2.4 Query Pattern Translation

```swift
extension KnowledgeStore {
    public func query(
        subject: Value? = nil,
        predicate: Value? = nil,
        object: Value? = nil
    ) async throws -> [KnowledgeRecord] {
        // Delegate to TripleStore
        let triples = try await tripleStore.query(
            subject: subject,
            predicate: predicate,
            object: object
        )

        // Convert Triple[] → KnowledgeRecord[]
        return triples.map { triple in
            KnowledgeRecord(
                subject: triple.subject,
                predicate: triple.predicate,
                object: triple.object,
                tripleMetadata: triple.metadata
            )
        }
    }
}
```

---

## 3. OntologyLayer Integration

### 3.1 API Surface Used

**From OntologyLayer:**

```swift
import OntologyLayer

// Store operations
public actor OntologyStore {
    public func defineClass(_ cls: OntologyClass) async throws
    public func getClass(named: String) async throws -> OntologyClass?
    public func definePredicate(_ predicate: OntologyPredicate) async throws
    public func getPredicate(named: String) async throws -> OntologyPredicate?
}

// Validation
public actor OntologyValidator {
    public func validate(
        _ triple: (subject: String, predicate: String, object: String)
    ) async throws -> ValidationResult

    public func validateDomain(subject: String, predicate: String) async throws -> Bool
    public func validateRange(predicate: String, object: String) async throws -> Bool
}

// Data models
public struct OntologyClass: Codable, Sendable
public struct OntologyPredicate: Codable, Sendable
public struct ValidationResult: Sendable
```

### 3.2 Integration Pattern

```swift
// Sources/KnowledgeLayer/Storage/KnowledgeStore.swift

import OntologyLayer

public actor KnowledgeStore {
    private let ontologyStore: OntologyStore

    public init(database: any DatabaseProtocol, rootPrefix: String) async throws {
        self.ontologyStore = OntologyStore(
            database: database,
            rootPrefix: "\(rootPrefix):ontology",
            logger: logger
        )
    }

    public func insert(_ record: KnowledgeRecord) async throws {
        // Validate against ontology
        if let subjectURI = record.subject.stringValue,
           let predicateURI = record.predicate.stringValue,
           let objectURI = record.object.stringValue {

            let validator = OntologyValidator(
                store: ontologyStore,
                logger: logger
            )

            let validation = try await validator.validate(
                (subject: subjectURI, predicate: predicateURI, object: objectURI)
            )

            guard validation.isValid else {
                throw KnowledgeError.ontologyViolation(validation.errors)
            }
        }

        // Proceed with insertion...
    }
}
```

### 3.3 Ontology Management

```swift
extension KnowledgeStore {
    /// Define an ontology class for knowledge validation
    public func defineOntologyClass(_ cls: OntologyClass) async throws {
        try await ontologyStore.defineClass(cls)
    }

    /// Define a predicate with domain/range constraints
    public func defineOntologyPredicate(_ predicate: OntologyPredicate) async throws {
        try await ontologyStore.definePredicate(predicate)
    }
}
```

**Usage Example:**

```swift
// Define ontology
let personClass = OntologyClass(
    name: "Person",
    parent: nil,
    properties: ["name", "age"]
)

try await store.defineOntologyClass(personClass)

let knowsPredicate = OntologyPredicate(
    name: "http://xmlns.com/foaf/0.1/knows",
    domain: "Person",
    range: "Person",
    isDataProperty: false
)

try await store.defineOntologyPredicate(knowsPredicate)

// Now insertions will validate against this ontology
```

---

## 4. EmbeddingLayer Integration

### 4.1 API Surface Used

**From EmbeddingLayer:**

```swift
import EmbeddingLayer

// Store operations
public actor EmbeddingStore {
    public func save(record: EmbeddingRecord) async throws
    public func get(id: String, model: String) async throws -> EmbeddingRecord?
    public func delete(id: String, model: String) async throws
}

// Search operations
public actor SearchEngine {
    public func search(
        vector: [Float],
        topK: Int,
        metric: SimilarityMetric
    ) async throws -> [SearchResult]
}

// Data models
public struct EmbeddingRecord: Codable, Sendable {
    public let id: String
    public let vector: [Float]
    public let model: String
    public let dimension: Int
    public let sourceType: SourceType
}

public enum SourceType: String, Codable {
    case entity
    case triple
    case text
}

public enum SimilarityMetric {
    case cosine
    case innerProduct
    case euclidean
}
```

### 4.2 Integration Pattern

```swift
// Sources/KnowledgeLayer/Storage/KnowledgeStore.swift

import EmbeddingLayer

public actor KnowledgeStore {
    private let embeddingStore: EmbeddingStore
    private let embeddingGenerator: any EmbeddingGeneratorProtocol

    public init(
        database: any DatabaseProtocol,
        rootPrefix: String,
        embeddingGenerator: any EmbeddingGeneratorProtocol
    ) async throws {
        self.embeddingStore = EmbeddingStore(
            database: database,
            rootPrefix: "\(rootPrefix):embedding",
            logger: logger
        )
        self.embeddingGenerator = embeddingGenerator
    }

    public func insert(_ record: KnowledgeRecord) async throws {
        // ... Triple insertion ...

        // Generate embedding
        let text = record.text  // "subject predicate object"
        let vector = try await embeddingGenerator.generateEmbedding(for: text)

        // Store embedding
        let embedding = EmbeddingRecord(
            id: record.id.uuidString,
            vector: vector,
            model: record.embeddingModel ?? "mlx-embed",
            dimension: vector.count,
            sourceType: .triple,
            createdAt: Date()
        )

        try await embeddingStore.save(record: embedding)
    }
}
```

### 4.3 Similarity Search Integration

```swift
// Sources/KnowledgeLayer/Query/KnowledgeQueryEngine.swift

import EmbeddingLayer

public actor KnowledgeQueryEngine {
    private let searchEngine: SearchEngine

    public func search(
        byText text: String,
        topK: Int
    ) async throws -> [SearchResult] {
        // Generate query embedding
        let queryVector = try await embeddingGenerator.generateEmbedding(for: text)

        // Similarity search
        let results = try await searchEngine.search(
            vector: queryVector,
            topK: topK,
            metric: .cosine
        )

        // Convert to KnowledgeRecords
        var knowledgeResults: [SearchResult] = []
        for result in results {
            if let uuid = UUID(uuidString: result.id),
               let record = try await store.get(id: uuid) {
                knowledgeResults.append(
                    SearchResult(record: record, score: result.similarity)
                )
            }
        }

        return knowledgeResults
    }
}
```

---

## 5. Transaction Coordination

### 5.1 Unified Transaction Pattern

All three layers share the **same FoundationDB database instance** and use `withTransaction`:

```swift
public actor KnowledgeStore {
    nonisolated(unsafe) private let database: any DatabaseProtocol

    private let tripleStore: TripleStore
    private let ontologyStore: OntologyStore
    private let embeddingStore: EmbeddingStore

    public init(database: any DatabaseProtocol, rootPrefix: String) async throws {
        self.database = database

        // All stores share the same database
        self.tripleStore = TripleStore(
            database: database,  // ← Same instance
            rootPrefix: "\(rootPrefix):triple"
        )

        self.ontologyStore = OntologyStore(
            database: database,  // ← Same instance
            rootPrefix: "\(rootPrefix):ontology"
        )

        self.embeddingStore = EmbeddingStore(
            database: database,  // ← Same instance
            rootPrefix: "\(rootPrefix):embedding"
        )
    }
}
```

### 5.2 Transaction Isolation

Each sub-layer uses **namespaced prefixes** to avoid key collisions:

```
FoundationDB Key Space:
├── (myapp:triple, ...)      # TripleStore keys
├── (myapp:ontology, ...)    # OntologyStore keys
└── (myapp:embedding, ...)   # EmbeddingStore keys
```

### 5.3 Atomic Multi-Layer Operations

```swift
extension KnowledgeStore {
    public func insert(_ record: KnowledgeRecord) async throws {
        // All operations in ONE FoundationDB transaction
        try await database.withTransaction { transaction in
            // 1. Existence check (TripleStore)
            let exists = try await tripleStore.contains(record.triple)
            guard !exists else { throw KnowledgeError.alreadyExists(record.id) }

            // 2. Ontology validation (OntologyValidator)
            let validator = OntologyValidator(store: ontologyStore)
            let validation = try await validator.validate(...)
            guard validation.isValid else { throw KnowledgeError.ontologyViolation(...) }

            // 3. Insert triple (TripleStore)
            try await tripleStore.insert(record.triple)

            // 4. Insert embedding (EmbeddingStore)
            let vector = try await embeddingGenerator.generateEmbedding(...)
            let embedding = EmbeddingRecord(...)
            try await embeddingStore.save(record: embedding)

            // All succeed or all rollback
        }
    }
}
```

---

## 6. Testing Integration

### 6.1 Integration Test Setup

```swift
// Tests/KnowledgeLayerTests/IntegrationTests.swift

import XCTest
@testable import KnowledgeLayer
import TripleLayer
import OntologyLayer
import EmbeddingLayer
import FoundationDB

final class IntegrationTests: XCTestCase {
    var database: any DatabaseProtocol!
    var store: KnowledgeStore!

    override func setUp() async throws {
        // Initialize FoundationDB
        try await FDBClient.initialize()
        database = try FDBClient.openDatabase()

        // Create KnowledgeStore
        store = KnowledgeStore(
            database: database,
            rootPrefix: "test-\(UUID().uuidString)",
            embeddingGenerator: MockEmbeddingGenerator()
        )

        // Set up ontology
        try await setupTestOntology()
    }

    override func tearDown() async throws {
        // Clean up test data
        try await cleanupTestData()
    }

    func setupTestOntology() async throws {
        let personClass = OntologyClass(
            name: "Person",
            parent: nil,
            properties: []
        )
        try await store.defineOntologyClass(personClass)

        let knowsPredicate = OntologyPredicate(
            name: "http://xmlns.com/foaf/0.1/knows",
            domain: "Person",
            range: "Person",
            isDataProperty: false
        )
        try await store.defineOntologyPredicate(knowsPredicate)
    }
}
```

### 6.2 End-to-End Test

```swift
func testFullKnowledgeCirculation() async throws {
    // 1. Insert knowledge
    let record = KnowledgeRecord(
        subject: .uri("http://example.org/Alice"),
        predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
        object: .uri("http://example.org/Bob"),
        subjectClass: "Person",
        objectClass: "Person"
    )

    try await store.insert(record)

    // 2. Verify triple stored
    let triples = try await store.query(
        subject: .uri("http://example.org/Alice")
    )
    XCTAssertEqual(triples.count, 1)

    // 3. Verify embedding stored
    let embedding = try await store.embeddingStore.get(
        id: record.id.uuidString,
        model: "mock"
    )
    XCTAssertNotNil(embedding)
    XCTAssertEqual(embedding?.dimension, 384)

    // 4. Similarity search
    let similar = try await store.findSimilar(
        to: embedding!.vector,
        topK: 5
    )
    XCTAssertTrue(similar.contains { $0.id == record.id })
}
```

### 6.3 Mock Generator for Testing

```swift
struct MockEmbeddingGenerator: EmbeddingGeneratorProtocol {
    func generateEmbedding(for text: String) async throws -> [Float] {
        // Generate deterministic mock embedding
        let hash = text.hashValue
        return (0..<384).map { i in
            Float(sin(Double(hash + i)))
        }
    }
}
```

---

## 7. Troubleshooting

### 7.1 Common Integration Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| **Circular dependencies** | Incorrect package paths | Use `.package(path: "../...")` |
| **Key collisions** | Missing prefix namespacing | Ensure each layer uses unique rootPrefix |
| **Transaction timeouts** | Large batch operations | Split into smaller transactions |
| **Type mismatches** | Version incompatibility | Pin all layers to same version |

### 7.2 Debug Logging

Enable detailed logging across all layers:

```swift
import Logging

var logger = Logger(label: "com.knowledge.integration")
logger.logLevel = .debug

let store = KnowledgeStore(
    database: database,
    rootPrefix: "myapp",
    logger: logger
)
```

---

## 8. Production Deployment

### 8.1 GitHub Dependencies

For production, use GitHub URLs instead of local paths:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/fdb-triple-layer.git", from: "0.1.0"),
    .package(url: "https://github.com/1amageek/fdb-ontology-layer.git", from: "0.1.0"),
    .package(url: "https://github.com/1amageek/fdb-embedding-layer.git", from: "0.1.0")
]
```

### 8.2 Version Pinning

Use `Package.resolved` to lock versions:

```bash
swift package resolve
git add Package.resolved
git commit -m "Lock dependency versions"
```

---

**Next:** See [ODKE_IMPLEMENTATION.md](ODKE_IMPLEMENTATION.md) for ODKE+ circulation details.

---

**Built with ❤️ using Swift and FoundationDB**
