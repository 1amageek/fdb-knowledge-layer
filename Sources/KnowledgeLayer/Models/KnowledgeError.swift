import Foundation
@preconcurrency import FoundationDB
import OntologyLayer

/// Errors that can occur during knowledge operations
public enum KnowledgeError: Error, Sendable {
    /// Knowledge record with the given ID already exists
    case alreadyExists(UUID)

    /// Knowledge record with the given ID was not found
    case notFound(UUID)

    /// Ontology validation failed with specific errors
    case ontologyViolation([ValidationError])

    /// Embedding generation failed
    case embeddingGenerationFailed(String)

    /// FoundationDB transaction failed
    case transactionFailed(any Error)

    /// Invalid knowledge record structure
    case invalidRecord(String)
}

// MARK: - LocalizedError

extension KnowledgeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyExists(let id):
            return "Knowledge record already exists: \(id)"

        case .notFound(let id):
            return "Knowledge record not found: \(id)"

        case .ontologyViolation(let errors):
            let errorMessages = errors.map { $0.message }.joined(separator: ", ")
            return "Ontology validation failed: \(errorMessages)"

        case .embeddingGenerationFailed(let message):
            return "Embedding generation failed: \(message)"

        case .transactionFailed(let error):
            return "Transaction failed: \(error.localizedDescription)"

        case .invalidRecord(let message):
            return "Invalid knowledge record: \(message)"
        }
    }

    public var failureReason: String? {
        switch self {
        case .alreadyExists:
            return "The knowledge record already exists in the store."

        case .notFound:
            return "The requested knowledge record was not found."

        case .ontologyViolation(let errors):
            return "The knowledge record violates \(errors.count) ontology constraint(s)."

        case .embeddingGenerationFailed:
            return "Failed to generate embedding vector for the knowledge record."

        case .transactionFailed:
            return "The FoundationDB transaction failed."

        case .invalidRecord:
            return "The knowledge record structure is invalid."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .alreadyExists:
            return "Use update() to modify existing records, or query() to check existence first."

        case .notFound:
            return "Verify the UUID is correct, or use query() to find records."

        case .ontologyViolation:
            return "Check domain/range constraints in your ontology definitions, or use validate() before inserting."

        case .embeddingGenerationFailed:
            return "Verify the embedding generator is properly configured and the text is valid."

        case .transactionFailed(let error):
            if let fdbError = error as? FDBError, fdbError.isRetryable {
                return "This error is retryable. withTransaction() will automatically retry."
            }
            return "Check FoundationDB connectivity and transaction size limits."

        case .invalidRecord:
            return "Ensure all required fields are properly set and value types are correct."
        }
    }
}

// MARK: - CustomStringConvertible

extension KnowledgeError: CustomStringConvertible {
    public var description: String {
        return errorDescription ?? "Unknown knowledge error"
    }
}
