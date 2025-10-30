# ODKE+ Implementation Guide

**Ontology-Driven Knowledge Extraction with fdb-knowledge-layer**

**Version:** 0.1
**Date:** 2025-10-30
**Reference:** [Apple ODKE+ Paper (arXiv:2509.04696)](https://www.arxiv.org/pdf/2509.04696)

---

## Table of Contents

1. [ODKE+ Overview](#1-odke-overview)
2. [Knowledge Circulation Flow](#2-knowledge-circulation-flow)
3. [Implementation Components](#3-implementation-components)
4. [LLM Integration](#4-llm-integration)
5. [Feedback Mechanism](#5-feedback-mechanism)
6. [MLX Embedding Generation](#6-mlx-embedding-generation)
7. [Production Deployment](#7-production-deployment)

---

## 1. ODKE+ Overview

### 1.1 What is ODKE+?

**ODKE+ (Ontology-Driven Knowledge Extraction)** is a methodology developed by Apple Research for extracting structured knowledge from unstructured text using Large Language Models (LLMs) with ontology-based validation.

**Key Principles:**

1. **Ontology Guidance**: Use domain ontologies to constrain and validate LLM outputs
2. **Iterative Refinement**: Feedback loop improves extraction quality over time
3. **Semantic Consistency**: All knowledge adheres to predefined semantic constraints
4. **Knowledge Circulation**: Extracted knowledge feeds back into the extraction process

### 1.2 ODKE+ vs. Traditional Extraction

| Aspect | Traditional NLP | ODKE+ |
|--------|----------------|-------|
| **Validation** | Post-hoc manual review | Real-time ontology checking |
| **Consistency** | No guarantees | Schema-enforced |
| **Evolution** | Static rules | Self-improving via feedback |
| **Integration** | Separate pipelines | Unified circulation loop |
| **LLM Usage** | Unguided generation | Ontology-constrained prompts |

---

## 2. Knowledge Circulation Flow

### 2.1 Complete Circulation Diagram

```
┌──────────────────────────────────────────────────────────┐
│                   ODKE+ Knowledge Circulation            │
└──────────────────────────────────────────────────────────┘

    ┌────────────────┐
    │  Input Text    │ (Document, article, conversation)
    └────────┬───────┘
             │
    ┌────────▼───────────────────────────────┐
    │  LLM Extraction (GPT-4, Claude, etc.)  │
    │  - Ontology-guided prompt              │
    │  - Generate candidate triples          │
    └────────┬───────────────────────────────┘
             │
    ┌────────▼───────────┐
    │ Candidate Triples  │ [(S, P, O), ...]
    └────────┬───────────┘
             │
    ┌────────▼───────────────────────────────┐
    │  Existence Validation                  │
    │  - Check if triple already exists      │
    │  - Skip duplicates                     │
    └────────┬───────────────────────────────┘
             │ (New triples only)
    ┌────────▼───────────────────────────────┐
    │  Ontology Validation                   │
    │  - Domain/Range checking               │
    │  - Class hierarchy reasoning           │
    │  - Constraint satisfaction             │
    └────────┬───────────────────────────────┘
             │
        ┌────┴────┐
        │         │
    Valid?    Invalid?
        │         │
        │    ┌────▼──────────┐
        │    │ Rejection Log │ → Feedback
        │    └───────────────┘
        │
    ┌───▼────────────────────────────────────┐
    │  Triple Storage (TripleStore)          │
    │  - Persist to FoundationDB             │
    │  - Update indices                      │
    └────────┬───────────────────────────────┘
             │
    ┌────────▼───────────────────────────────┐
    │  Embedding Generation (MLX/OpenAI)     │
    │  - Convert triple to text              │
    │  - Generate vector representation      │
    └────────┬───────────────────────────────┘
             │
    ┌────────▼───────────────────────────────┐
    │  Embedding Storage (EmbeddingStore)    │
    │  - Persist vector to FDB               │
    │  - Index for similarity search         │
    └────────┬───────────────────────────────┘
             │
    ┌────────▼───────────────────────────────┐
    │  Knowledge Base (Unified)              │
    │  - Triple + Ontology + Embedding       │
    └────────┬───────────────────────────────┘
             │
    ┌────────▼───────────────────────────────┐
    │  Retrieval (Hybrid Search)             │
    │  - Structural query (TripleStore)      │
    │  - Similarity search (EmbeddingStore)  │
    │  - Semantic reasoning (OntologyStore)  │
    └────────┬───────────────────────────────┘
             │
    ┌────────▼───────────────────────────────┐
    │  Context Enrichment                    │
    │  - Augment LLM prompts with context    │
    │  - Provide domain constraints          │
    └────────┬───────────────────────────────┘
             │
    ┌────────▼───────────────────────────────┐
    │  Feedback Generation                   │
    │  - Analyze accepted/rejected triples   │
    │  - Generate improvement suggestions    │
    └────────┬───────────────────────────────┘
             │
             └──────────┐
                        │
            (Loop back to LLM Extraction)
```

### 2.2 Iteration Metrics

Each circulation iteration produces:

```swift
public struct IterationResult: Sendable {
    public let candidatesExtracted: Int     // Total triples from LLM
    public let duplicatesSkipped: Int       // Already in KB
    public let validationPassed: Int        // Passed ontology check
    public let validationFailed: Int        // Failed ontology check
    public let inserted: [KnowledgeRecord]  // Successfully added
    public let rejections: [RejectionRecord] // Failed with reasons
    public let embeddingsGenerated: Int     // Vector count
    public let duration: TimeInterval       // Processing time
}
```

---

## 3. Implementation Components

### 3.1 KnowledgeLoop Actor

**Primary controller for ODKE+ circulation:**

```swift
// Sources/KnowledgeLayer/Circulation/KnowledgeLoop.swift

import Foundation
@preconcurrency import FoundationDB
import Logging

public actor KnowledgeLoop {
    // Dependencies
    private let store: KnowledgeStore
    private let extractor: any LLMExtractorProtocol
    private let embeddingGenerator: any EmbeddingGeneratorProtocol
    private let logger: Logger

    // Feedback state
    private var rejectionHistory: [RejectionRecord] = []
    private var acceptanceHistory: [KnowledgeRecord] = []

    public init(
        store: KnowledgeStore,
        extractor: any LLMExtractorProtocol,
        embeddingGenerator: any EmbeddingGeneratorProtocol,
        logger: Logger? = nil
    ) {
        self.store = store
        self.extractor = extractor
        self.embeddingGenerator = embeddingGenerator
        self.logger = logger ?? Logger(label: "com.knowledge.loop")
    }

    /// Execute one ODKE+ iteration
    public func iterate(text: String) async throws -> IterationResult {
        let startTime = Date()

        logger.info("Starting ODKE+ iteration", metadata: [
            "textLength": "\(text.count)"
        ])

        // Step 1: LLM Extraction
        let candidates = try await extractor.extract(from: text)
        logger.debug("Extracted \(candidates.count) candidates")

        var inserted: [KnowledgeRecord] = []
        var rejections: [RejectionRecord] = []
        var duplicatesSkipped = 0

        // Step 2-5: Validate and insert each candidate
        for candidate in candidates {
            do {
                try await store.insert(candidate)
                inserted.append(candidate)
                acceptanceHistory.append(candidate)

            } catch KnowledgeError.alreadyExists {
                duplicatesSkipped += 1

            } catch KnowledgeError.ontologyViolation(let errors) {
                let rejection = RejectionRecord(
                    candidate: candidate,
                    reason: .ontologyViolation(errors),
                    timestamp: Date()
                )
                rejections.append(rejection)
                rejectionHistory.append(rejection)
                logger.warning("Rejected candidate", metadata: [
                    "subject": "\(candidate.subject)",
                    "errors": "\(errors)"
                ])

            } catch {
                let rejection = RejectionRecord(
                    candidate: candidate,
                    reason: .transactionFailed(error),
                    timestamp: Date()
                )
                rejections.append(rejection)
                rejectionHistory.append(rejection)
            }
        }

        let duration = Date().timeIntervalSince(startTime)

        let result = IterationResult(
            candidatesExtracted: candidates.count,
            duplicatesSkipped: duplicatesSkipped,
            validationPassed: inserted.count,
            validationFailed: rejections.count,
            inserted: inserted,
            rejections: rejections,
            embeddingsGenerated: inserted.count,
            duration: duration
        )

        logger.info("Iteration complete", metadata: [
            "inserted": "\(result.validationPassed)",
            "rejected": "\(result.validationFailed)",
            "duration": "\(duration)s"
        ])

        return result
    }
}
```

### 3.2 RejectionRecord

```swift
public struct RejectionRecord: Codable, Sendable {
    public let candidate: KnowledgeRecord
    public let reason: KnowledgeError
    public let timestamp: Date

    /// Human-readable explanation
    public var explanation: String {
        switch reason {
        case .ontologyViolation(let errors):
            return "Ontology validation failed: \(errors.map { $0.message }.joined(separator: ", "))"
        case .alreadyExists:
            return "Triple already exists in knowledge base"
        case .embeddingGenerationFailed(let msg):
            return "Embedding generation failed: \(msg)"
        case .transactionFailed(let error):
            return "Transaction error: \(error.localizedDescription)"
        default:
            return "Unknown error"
        }
    }
}
```

---

## 4. LLM Integration

### 4.1 LLMExtractorProtocol

```swift
public protocol LLMExtractorProtocol: Sendable {
    func extract(from text: String) async throws -> [KnowledgeRecord]
}
```

### 4.2 OpenAI GPT-4 Implementation

```swift
import OpenAI

public actor GPT4Extractor: LLMExtractorProtocol {
    private let client: OpenAI
    private let ontologySnippet: String

    public init(apiKey: String, ontologySnippet: String) {
        self.client = OpenAI(apiKey: apiKey)
        self.ontologySnippet = ontologySnippet
    }

    public func extract(from text: String) async throws -> [KnowledgeRecord] {
        let prompt = buildPrompt(text: text, ontology: ontologySnippet)

        let response = try await client.chat(
            model: "gpt-4",
            messages: [
                .system("You are a knowledge extraction assistant."),
                .user(prompt)
            ],
            temperature: 0.3
        )

        let jsonString = response.choices.first?.message.content ?? "[]"
        let triples = try parseTriples(from: jsonString)

        return triples.map { triple in
            KnowledgeRecord(
                subject: .uri(triple.subject),
                predicate: .uri(triple.predicate),
                object: .uri(triple.object),
                confidence: triple.confidence,
                source: "GPT-4"
            )
        }
    }

    private func buildPrompt(text: String, ontology: String) -> String {
        """
        Extract knowledge triples from the following text.
        Use the ontology constraints provided below.

        **Ontology:**
        \(ontology)

        **Text:**
        \(text)

        **Output Format (JSON):**
        [
          {
            "subject": "http://example.org/Entity",
            "predicate": "http://example.org/relation",
            "object": "http://example.org/Entity",
            "confidence": 0.95
          }
        ]

        Only extract triples that conform to the ontology.
        """
    }
}
```

### 4.3 Anthropic Claude Implementation

```swift
import Anthropic

public actor ClaudeExtractor: LLMExtractorProtocol {
    private let client: Anthropic
    private let ontologySnippet: String

    public init(apiKey: String, ontologySnippet: String) {
        self.client = Anthropic(apiKey: apiKey)
        self.ontologySnippet = ontologySnippet
    }

    public func extract(from text: String) async throws -> [KnowledgeRecord] {
        let prompt = buildPrompt(text: text, ontology: ontologySnippet)

        let response = try await client.messages.create(
            model: "claude-3-opus-20240229",
            maxTokens: 1024,
            messages: [
                .user(prompt)
            ]
        )

        let jsonString = response.content.first?.text ?? "[]"
        return try parseTriples(from: jsonString).map { ... }
    }
}
```

---

## 5. Feedback Mechanism

### 5.1 Feedback Generation

```swift
extension KnowledgeLoop {
    /// Generate feedback prompt for LLM
    public func generateFeedback() async throws -> String {
        let recentRejections = rejectionHistory.suffix(100)
        let recentAcceptances = acceptanceHistory.suffix(100)

        let feedback = """
        **Extraction Feedback Report**

        **Accepted Triples (\(recentAcceptances.count)):**
        \(formatAcceptedTriples(recentAcceptances))

        **Rejected Triples (\(recentRejections.count)):**
        \(formatRejectedTriples(recentRejections))

        **Common Rejection Patterns:**
        \(analyzeRejectionPatterns(recentRejections))

        **Recommendations:**
        \(generateRecommendations(recentRejections))
        """

        return feedback
    }

    private func formatRejectedTriples(_ rejections: [RejectionRecord]) -> String {
        rejections.map { rejection in
            "- (\(rejection.candidate.subject), \(rejection.candidate.predicate), \(rejection.candidate.object))\n" +
            "  Reason: \(rejection.explanation)"
        }.joined(separator: "\n")
    }

    private func analyzeRejectionPatterns(_ rejections: [RejectionRecord]) -> String {
        var domainMismatches = 0
        var rangeMismatches = 0

        for rejection in rejections {
            if case .ontologyViolation(let errors) = rejection.reason {
                for error in errors {
                    if error.errorType == .domainMismatch {
                        domainMismatches += 1
                    } else if error.errorType == .rangeMismatch {
                        rangeMismatches += 1
                    }
                }
            }
        }

        return """
        - Domain mismatches: \(domainMismatches)
        - Range mismatches: \(rangeMismatches)
        """
    }

    private func generateRecommendations(_ rejections: [RejectionRecord]) -> String {
        // Analyze patterns and suggest improvements
        """
        1. Review domain/range constraints for frequently rejected predicates
        2. Consider expanding ontology to cover new entity types
        3. Improve prompt specificity for entity recognition
        """
    }
}
```

### 5.2 Continuous Improvement Loop

```swift
extension KnowledgeLoop {
    /// Run continuous circulation with periodic feedback
    public func run(
        textStream: any AsyncSequence<String, Never>,
        feedbackInterval: Int = 10
    ) -> AsyncStream<IterationResult> {
        AsyncStream { continuation in
            Task {
                var iterationCount = 0

                for try await text in textStream {
                    // Execute iteration
                    let result = try await iterate(text: text)
                    continuation.yield(result)

                    iterationCount += 1

                    // Generate feedback every N iterations
                    if iterationCount % feedbackInterval == 0 {
                        let feedback = try await generateFeedback()
                        logger.info("Generated feedback", metadata: [
                            "iteration": "\(iterationCount)"
                        ])

                        // Optionally: Send feedback back to LLM for prompt refinement
                        await updateExtractorWithFeedback(feedback)
                    }
                }

                continuation.finish()
            }
        }
    }
}
```

---

## 6. MLX Embedding Generation

### 6.1 MLXEmbeddingGenerator Implementation

```swift
import MLX
import MLXNN

public actor MLXEmbeddingGenerator: EmbeddingGeneratorProtocol {
    private let model: EmbeddingModel
    private let tokenizer: Tokenizer
    private let dimension: Int

    public init(modelPath: String) async throws {
        // Load MLX embedding model (e.g., sentence-transformers)
        self.model = try await EmbeddingModel.load(from: modelPath)
        self.tokenizer = try Tokenizer.load(from: modelPath)
        self.dimension = model.dimension
    }

    public func generateEmbedding(for text: String) async throws -> [Float] {
        // Tokenize
        let tokens = tokenizer.encode(text)

        // Generate embedding using MLX
        let output = await model.encode(tokens)

        // Convert to Float array
        let embedding = output.asArray(Float.self)

        return embedding
    }
}

// MLX model wrapper
private actor EmbeddingModel {
    private let network: Module
    let dimension: Int

    static func load(from path: String) async throws -> EmbeddingModel {
        // Load MLX model weights
        let weights = try MLX.load(path)
        let network = BERTEmbedding(weights: weights)
        return EmbeddingModel(network: network, dimension: 384)
    }

    func encode(_ tokens: [Int]) async -> MLXArray {
        // Run inference on Apple Silicon
        return await network.forward(tokens)
    }
}
```

### 6.2 OpenAI Embedding Alternative

```swift
import OpenAI

public actor OpenAIEmbeddingGenerator: EmbeddingGeneratorProtocol {
    private let client: OpenAI
    private let model: String

    public init(apiKey: String, model: String = "text-embedding-3-small") {
        self.client = OpenAI(apiKey: apiKey)
        self.model = model
    }

    public func generateEmbedding(for text: String) async throws -> [Float] {
        let response = try await client.embeddings.create(
            input: text,
            model: model
        )

        guard let embedding = response.data.first?.embedding else {
            throw EmbeddingError.generationFailed
        }

        return embedding.map { Float($0) }
    }
}
```

---

## 7. Production Deployment

### 7.1 Complete Setup Example

```swift
import FoundationDB
import KnowledgeLayer
import MLX

@main
struct ODKEApp {
    static func main() async throws {
        // 1. Initialize FoundationDB
        try await FDBClient.initialize()
        let database = try FDBClient.openDatabase()

        // 2. Set up ontology
        let ontologyStore = OntologyStore(
            database: database,
            rootPrefix: "prod:ontology"
        )

        let personClass = OntologyClass(name: "Person", parent: nil, properties: [])
        try await ontologyStore.defineClass(personClass)

        let knowsPredicate = OntologyPredicate(
            name: "http://xmlns.com/foaf/0.1/knows",
            domain: "Person",
            range: "Person",
            isDataProperty: false
        )
        try await ontologyStore.definePredicate(knowsPredicate)

        // 3. Initialize KnowledgeStore
        let embeddingGen = try await MLXEmbeddingGenerator(
            modelPath: "/path/to/model"
        )

        let store = KnowledgeStore(
            database: database,
            rootPrefix: "prod",
            embeddingGenerator: embeddingGen
        )

        // 4. Initialize KnowledgeLoop
        let ontologySnippet = try await ontologyStore.generateSnippet()

        let extractor = GPT4Extractor(
            apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!,
            ontologySnippet: ontologySnippet
        )

        let loop = KnowledgeLoop(
            store: store,
            extractor: extractor,
            embeddingGenerator: embeddingGen
        )

        // 5. Run circulation
        let documents = loadDocuments()

        for document in documents {
            let result = try await loop.iterate(text: document)

            print("""
            Iteration complete:
              Extracted: \(result.candidatesExtracted)
              Inserted: \(result.validationPassed)
              Rejected: \(result.validationFailed)
              Duration: \(result.duration)s
            """)
        }

        // 6. Generate final feedback
        let feedback = try await loop.generateFeedback()
        print("Feedback:\n\(feedback)")
    }
}
```

### 7.2 Monitoring & Metrics

```swift
extension KnowledgeLoop {
    public func metrics() -> CirculationMetrics {
        CirculationMetrics(
            totalIterations: iterationCount,
            totalExtracted: totalExtractedCount,
            totalInserted: totalInsertedCount,
            totalRejected: rejectionHistory.count,
            averageDuration: averageDuration,
            acceptanceRate: Float(totalInsertedCount) / Float(totalExtractedCount)
        )
    }
}
```

---

## 8. Summary

**fdb-knowledge-layer** implements the complete ODKE+ knowledge circulation:

✅ **LLM Extraction** → GPT-4/Claude integration
✅ **Ontology Validation** → Real-time constraint checking
✅ **Triple Storage** → ACID-compliant FoundationDB
✅ **Embedding Generation** → MLX on Apple Silicon
✅ **Feedback Loop** → Continuous quality improvement
✅ **Hybrid Search** → Structure + Semantics + Similarity

**The result:** A self-improving knowledge base that evolves with each extraction iteration.

---

**Built with ❤️ using Swift and FoundationDB**
