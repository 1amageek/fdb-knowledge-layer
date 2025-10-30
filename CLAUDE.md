# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

`fdb-knowledge-layer` is the **unified integration layer** that implements **ODKE+ (Ontology-Driven Knowledge Extraction)** on FoundationDB. It combines three fundamental aspects of knowledge:

- **Structure** (via fdb-triple-layer) - SPO facts and relationships
- **Semantics** (via fdb-ontology-layer) - Types, constraints, validation
- **Semantic Similarity** (via fdb-embedding-layer) - Vector representations

All three layers are coordinated in **single ACID transactions** to ensure knowledge consistency.

---

## Build & Test Commands

### Building

```bash
# Build the package
swift build

# Build with verbose output
swift build -v

# Build in release mode
swift build -c release
```

### Testing

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter KnowledgeStoreTests

# Run verbose tests
swift test -v

# Run single test
swift test --filter KnowledgeStoreTests/testInsert
```

**Important:** FoundationDB must be running locally for tests to pass:

```bash
# Check FDB status
brew services list | grep foundationdb

# Start FDB if needed
brew services start foundationdb
```

### Development

```bash
# Clean build artifacts
swift package clean

# Resolve dependencies
swift package resolve

# Update dependencies
swift package update
```

---

## Architecture: The Big Picture

### Three-Layer Integration Pattern

This layer **orchestrates** three independent sub-layers that all share the **same FoundationDB database instance**:

```
KnowledgeStore (orchestrator)
    ├── TripleStore    (database, rootPrefix: "knowledge:triple")
    ├── OntologyStore  (database, rootPrefix: "knowledge:ontology")
    └── EmbeddingStore (database, rootPrefix: "knowledge:embedding")
```

**Critical Design Decision:** All sub-layers use **namespaced key prefixes** to avoid collisions in FoundationDB's global key space.

### Transaction Coordination Pattern

The core architectural pattern is **unified transaction execution** across all three layers:

```swift
try await database.withTransaction { transaction in
    // 1. Check existence (TripleStore)
    let exists = try await tripleStore.contains(triple)

    // 2. Validate semantics (OntologyValidator)
    let validation = try await validator.validate(record)

    // 3. Store triple (TripleStore)
    try await tripleStore.insert(triple)

    // 4. Generate & store embedding (EmbeddingStore)
    let vector = try await embeddingGen.generateEmbedding(...)
    try await embeddingStore.save(embedding)

    // All succeed or all rollback atomically
}
```

This pattern **must** be preserved in all write operations to maintain ACID guarantees.

### ODKE+ Knowledge Circulation

The knowledge lifecycle implements Apple's ODKE+ methodology:

1. **LLM Extraction** → Generate candidate triples from text
2. **Existence Check** → Avoid duplicates (via TripleStore)
3. **Ontology Validation** → Enforce domain/range constraints (via OntologyValidator)
4. **Storage** → Persist triple + embedding atomically
5. **Feedback Loop** → Track rejections to improve extraction quality

**Key Actor:** `KnowledgeLoop` manages this circulation, tracking acceptance/rejection history for feedback generation.

---

## Dependency Management

### Local Development Setup

During development, use **local path dependencies** in Package.swift:

```swift
dependencies: [
    .package(path: "../fdb-triple-layer"),
    .package(path: "../fdb-ontology-layer"),
    .package(path: "../fdb-embedding-layer")
]
```

Expected directory structure:

```
Desktop/
├── fdb-triple-layer/
├── fdb-ontology-layer/
├── fdb-embedding-layer/
└── fdb-knowledge-layer/  # (this repo)
```

### Production Dependencies

For production/release, switch to GitHub URLs:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/fdb-triple-layer.git", from: "0.1.0"),
    .package(url: "https://github.com/1amageek/fdb-ontology-layer.git", from: "0.1.0"),
    .package(url: "https://github.com/1amageek/fdb-embedding-layer.git", from: "0.1.0")
]
```

---

## Core Data Models

### KnowledgeRecord (The Unified Model)

`KnowledgeRecord` is the **integration point** that combines data from all three layers:

```swift
public struct KnowledgeRecord {
    // Triple data (from fdb-triple-layer)
    public let subject: Value      // .uri, .text, .integer, etc.
    public let predicate: Value
    public let object: Value

    // Ontology data (from fdb-ontology-layer)
    public let subjectClass: String?    // e.g., "Person"
    public let objectClass: String?

    // Embedding data (from fdb-embedding-layer)
    public let embeddingID: String?
    public let embeddingModel: String?  // e.g., "mlx-embed"

    // ODKE+ metadata
    public let confidence: Float?       // LLM confidence score
    public let source: String?          // Provenance tracking
}
```

**Value Type (from TripleLayer):** Unlike RDF, any Value type can be subject/predicate/object:

```swift
public enum Value {
    case uri(String)
    case text(String, language: String?)
    case integer(Int64)
    case float(Double)
    case boolean(Bool)
    case binary(Data)  // For embeddings, serialized data
}
```

---

## Implementation Status (Roadmap Reference)

**Current Phase:** Core Implementation (Phase 1)

```
✅ KnowledgeRecord data model
✅ Documentation complete (README, ARCHITECTURE, API_DESIGN, INTEGRATION, ODKE_IMPLEMENTATION)
⚠️  KnowledgeStore - Needs implementation
⚠️  KnowledgeTransaction - Needs implementation
⚠️  KnowledgeQueryEngine - Needs implementation
⚠️  KnowledgeLoop - Needs implementation
❌ End-to-end tests
```

**When implementing new components:**

1. Follow the Actor-based concurrency model (Swift 6)
2. Use `nonisolated(unsafe)` for DatabaseProtocol (FDB not yet Sendable-compliant)
3. All multi-layer operations must use the unified transaction pattern
4. Add comprehensive logging with structured metadata
5. Write tests that mock FoundationDB operations

---

## Key Design Patterns

### Actor Isolation Pattern

All stateful components are Actors for thread safety:

```swift
public actor KnowledgeStore {
    nonisolated(unsafe) private let database: any DatabaseProtocol
    private let tripleStore: TripleStore      // Also an Actor
    private let ontologyStore: OntologyStore  // Also an Actor
    private let embeddingStore: EmbeddingStore // Also an Actor
}
```

**Why `nonisolated(unsafe)`:** FoundationDB's `DatabaseProtocol` is not yet marked `Sendable` in Swift 6, but the design is safe because all mutable state is protected by Actor isolation.

### Protocol-Based Abstraction

Embedding and LLM extraction are abstracted via protocols for flexibility:

```swift
public protocol EmbeddingGeneratorProtocol: Sendable {
    func generateEmbedding(for text: String) async throws -> [Float]
}

public protocol LLMExtractorProtocol: Sendable {
    func extract(from text: String) async throws -> [KnowledgeRecord]
}
```

This allows swapping implementations (MLX, OpenAI, Claude) without changing core logic.

### Error Handling Strategy

```swift
public enum KnowledgeError: Error, Sendable {
    case alreadyExists(UUID)
    case notFound(UUID)
    case ontologyViolation([ValidationError])
    case embeddingGenerationFailed(String)
    case transactionFailed(Error)
}
```

- `alreadyExists` → **Idempotent handling** (log and skip, don't throw)
- `ontologyViolation` → **Hard failure** (rollback transaction, record for feedback)
- `embeddingGenerationFailed` → **Retry with exponential backoff**

---

## Testing Strategy

### Integration Test Pattern

Tests must initialize all three sub-layers with **unique test prefixes**:

```swift
final class IntegrationTests: XCTestCase {
    var database: any DatabaseProtocol!
    var store: KnowledgeStore!

    override func setUp() async throws {
        try await FDBClient.initialize()
        database = try FDBClient.openDatabase()

        // Use UUID prefix to avoid test collisions
        let testPrefix = "test-\(UUID().uuidString)"

        store = try await KnowledgeStore(
            database: database,
            rootPrefix: testPrefix,
            embeddingGenerator: MockEmbeddingGenerator()
        )
    }

    override func tearDown() async throws {
        // Clean up test data by clearing key range
        try await cleanupTestData()
    }
}
```

### Mock Generators

For tests, use deterministic mock implementations:

```swift
struct MockEmbeddingGenerator: EmbeddingGeneratorProtocol {
    func generateEmbedding(for text: String) async throws -> [Float] {
        // Generate deterministic embedding based on text hash
        let hash = text.hashValue
        return (0..<384).map { i in Float(sin(Double(hash + i))) }
    }
}
```

---

## Common Pitfalls

### 1. Key Namespace Collisions

**Problem:** Multiple layers writing to same FoundationDB keys
**Solution:** Always use distinct `rootPrefix` for each layer:

```swift
tripleStore = TripleStore(database: db, rootPrefix: "\(rootPrefix):triple")
ontologyStore = OntologyStore(database: db, rootPrefix: "\(rootPrefix):ontology")
```

### 2. Transaction Timeout

**Problem:** Operations exceed 5-second FDB transaction limit
**Solution:** Break large batch operations into smaller transactions (1000 records/tx)

### 3. Value Type Mismatches

**Problem:** Attempting to use `.uri()` values where `.text()` is expected
**Solution:** Use `Value.stringValue` for conversion, check types explicitly

### 4. Missing Ontology Definitions

**Problem:** Validation fails because ontology classes/predicates not defined
**Solution:** Define ontology schema **before** inserting knowledge records

---

## Documentation References

When implementing features, refer to:

- **ARCHITECTURE.md** - Design philosophy, transaction patterns
- **API_DESIGN.md** - Complete API specifications with examples
- **INTEGRATION.md** - Sub-layer integration patterns
- **ODKE_IMPLEMENTATION.md** - Knowledge circulation details, LLM integration

---

## Version Compatibility

- **Swift:** 6.0+ (requires strict concurrency checking)
- **FoundationDB:** 7.1.0+ (tested with 7.1.x)
- **macOS:** 15.0+ (Sequoia)
- **Sub-layers:** All must be version 0.1.x (API compatibility)

---

## Future Implementation Priorities

Based on the roadmap, implement in this order:

1. **KnowledgeStore Actor** - Core CRUD + unified transaction pattern
2. **KnowledgeTransaction** - Explicit transaction control helper
3. **Integration Tests** - End-to-end with all 3 layers
4. **KnowledgeLoop** - ODKE+ circulation controller
5. **KnowledgeQueryEngine** - Hybrid search implementation
6. **MLX Integration** - Real embedding generation (currently mocked)

Each component should be fully tested before moving to the next.
