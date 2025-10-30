# fdb-knowledge-layer

**Unified Knowledge Layer for FoundationDB**

[![Swift Version](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS-blue.svg)](https://www.apple.com/macos/)
[![FoundationDB](https://img.shields.io/badge/FoundationDB-7.1+-green.svg)](https://www.foundationdb.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 🎯 Overview

`fdb-knowledge-layer` is the **unified integration layer** that combines structure, semantics, and semantic similarity to implement the **ODKE+ (Ontology-Driven Knowledge Extraction)** knowledge circulation system on FoundationDB.

### Core Concept

This layer integrates three fundamental aspects of knowledge:

- **Structure (Triple)** - Facts and relationships
- **Semantics (Ontology)** - Types and constraints
- **Semantic Similarity (Embedding)** - Vector representations

By managing these three dimensions in a single ACID transaction, we enable **self-consistent knowledge generation and evolution**.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────┐
│        fdb-knowledge-layer                  │
│  ┌──────────────────────────────────────┐   │
│  │  KnowledgeStore (Public API)         │   │
│  │  - insert() / query() / delete()     │   │
│  │  - ODKE+ Knowledge Circulation       │   │
│  └──────────────┬───────────────────────┘   │
│                 │                            │
│    ┌────────────┼────────────────┐          │
│    │            │                │          │
│  ┌─▼──────┐  ┌─▼────────┐  ┌───▼──────┐    │
│  │Triple  │  │Ontology  │  │Embedding │    │
│  │Layer   │  │Layer     │  │Layer     │    │
│  └────────┘  └──────────┘  └──────────┘    │
└─────────────────────────────────────────────┘
                  │
           ┌──────▼──────┐
           │FoundationDB │
           └─────────────┘
```

---

## 🧩 Key Features

### 1. **ODKE+ Knowledge Circulation**

Implements the complete knowledge lifecycle:

1. **LLM Extraction** → Generate candidate knowledge
2. **Existence Validation** → Check against existing triples
3. **Ontology Validation** → Verify type constraints
4. **Triple Storage** → Persist structured facts
5. **Embedding Generation** → Create vector representations
6. **Feedback Loop** → Improve extraction quality

### 2. **ACID Consistency**

All operations (Triple + Ontology + Embedding) execute in a **single FoundationDB transaction**, ensuring:

- ✅ Atomicity - All or nothing
- ✅ Consistency - Ontology constraints enforced
- ✅ Isolation - Concurrent safe
- ✅ Durability - Persisted reliably

### 3. **Hybrid Search**

Combines three search strategies:

- **Structural Search** (TripleStore) - Pattern matching
- **Semantic Search** (OntologyStore) - Type-based inference
- **Similarity Search** (EmbeddingStore) - Vector proximity

---

## 📦 Installation

### Requirements

- **Swift**: 6.0+
- **FoundationDB**: 7.1.0+
- **macOS**: 15.0+ (Sequoia)

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/fdb-knowledge-layer.git", branch: "main")
]
```

### Dependencies

This layer depends on three sub-layers:

```swift
.package(url: "https://github.com/1amageek/fdb-triple-layer.git", branch: "main"),
.package(url: "https://github.com/1amageek/fdb-ontology-layer.git", branch: "main"),
.package(url: "https://github.com/1amageek/fdb-embedding-layer.git", branch: "main")
```

---

## 🚀 Quick Start

### 1. Initialize FoundationDB

```swift
import FoundationDB
import KnowledgeLayer

// Initialize FDB client
try await FDBClient.initialize()
let database = try FDBClient.openDatabase()

// Create KnowledgeStore
let store = KnowledgeStore(
    database: database,
    rootPrefix: "myapp"
)
```

### 2. Insert Knowledge (ODKE+ Flow)

```swift
import TripleLayer

// Create a knowledge record
let record = KnowledgeRecord(
    subject: .uri("http://example.org/Alice"),
    predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
    object: .uri("http://example.org/Bob"),
    subjectClass: "Person",
    objectClass: "Person",
    confidence: 0.95,
    source: "GPT-4 extraction"
)

// Insert with full validation
try await store.insert(record)
```

**What happens internally:**

1. ✅ Check if triple already exists (TripleStore)
2. ✅ Validate domain/range constraints (OntologyValidator)
3. ✅ Store triple (TripleStore)
4. ✅ Generate embedding vector (EmbeddingGenerator)
5. ✅ Store embedding (EmbeddingStore)

### 3. Query Knowledge

```swift
// Structural query
let results = try await store.query(
    subject: .uri("http://example.org/Alice"),
    predicate: nil,
    object: nil
)

for record in results {
    print("\(record.subject) \(record.predicate) \(record.object)")
}
```

### 4. Similarity Search (Coming Soon)

```swift
// Find similar knowledge by vector
let similar = try await store.findSimilar(
    to: queryVector,
    topK: 10
)
```

---

## 📚 Documentation

### Core Documents

- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - System architecture and design philosophy
- **[API_DESIGN.md](docs/API_DESIGN.md)** - Complete API reference
- **[INTEGRATION.md](docs/INTEGRATION.md)** - Integration guide with 3 sub-layers
- **[ODKE_IMPLEMENTATION.md](docs/ODKE_IMPLEMENTATION.md)** - ODKE+ knowledge circulation implementation

### Sub-Layer Documentation

- [fdb-triple-layer](https://github.com/1amageek/fdb-triple-layer) - Triple storage
- [fdb-ontology-layer](https://github.com/1amageek/fdb-ontology-layer) - Ontology management
- [fdb-embedding-layer](https://github.com/1amageek/fdb-embedding-layer) - Vector embeddings

---

## 🧪 Testing

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter KnowledgeStoreTests

# Verbose output
swift test -v
```

**Note:** Requires FoundationDB service running locally.

---

## 🎯 Roadmap

### Phase 1: Core Implementation (Current)
- [x] KnowledgeRecord data model
- [x] KnowledgeStore basic API
- [x] Integration with 3 sub-layers
- [ ] ODKE+ circulation flow
- [ ] End-to-end tests

### Phase 2: Advanced Features
- [ ] EmbeddingGenerator integration (MLX)
- [ ] KnowledgeQueryEngine (hybrid search)
- [ ] Knowledge versioning
- [ ] Provenance tracking

### Phase 3: Knowledge Evolution
- [ ] KnowledgeLoop (automatic circulation)
- [ ] Feedback mechanism
- [ ] Confidence scoring
- [ ] Knowledge aging

### Phase 4: Performance & Scale
- [ ] Batch operations optimization
- [ ] Caching strategies
- [ ] Statistics collection
- [ ] Monitoring & metrics

---

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Swift 6 concurrency (Actor model)
- Document all public APIs
- Add tests for new features
- Follow existing code style

---

## 📖 Related Research

This implementation is inspired by:

- **ODKE+ Paper** (Apple, 2025) - [arXiv:2509.04696](https://www.arxiv.org/pdf/2509.04696)
  - "Ontology-Driven Knowledge Extraction with LLMs"
  - Knowledge circulation methodology

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details

---

## 🙏 Acknowledgments

This project builds upon:

- [FoundationDB](https://www.foundationdb.org) - Distributed transactional database
- [fdb-swift-bindings](https://github.com/apple/foundationdb-swift) - Swift bindings
- [MLX Swift](https://github.com/ml-explore/mlx-swift) - Apple Silicon ML framework
- Apple's ODKE+ research - Knowledge extraction methodology

---

**Built with ❤️ using Swift and FoundationDB**
