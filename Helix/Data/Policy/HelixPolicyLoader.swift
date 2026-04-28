import Foundation

enum HelixPolicyError: Error, LocalizedError {
    case fileNotFound(String)
    case decodingFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let name):
            return "Policy file not found: \(name).json"
        case .decodingFailed(let name, let error):
            return "Failed to decode \(name): \(error.localizedDescription)"
        }
    }
}

struct HelixPolicyLoader {

    static func load<T: Decodable>(
        filename: String,
        as type: T.Type
    ) throws -> T {
        guard let url = Bundle.main.url(
            forResource: filename,
            withExtension: "json",
            subdirectory: "Policy"
        ) else {
            throw HelixPolicyError.fileNotFound(filename)
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw HelixPolicyError.decodingFailed(filename, error)
        }
    }

    static func loadAll() throws -> HelixPolicyBundle {
        HelixPolicyBundle(
            core: try load(
                filename: "helix_policy",
                as: HelixCorePolicy.self
            ),
            confidence: try load(
                filename: "helix_confidence_policy",
                as: HelixConfidencePolicy.self
            ),
            explanation: try load(
                filename: "helix_explanation_policy",
                as: HelixExplanationPolicy.self
            ),
            history: try load(
                filename: "helix_history_policy",
                as: HelixHistoryPolicy.self
            ),
            crossStrand: try load(
                filename: "helix_cross_strand_policy",
                as: CrossStrandPolicy.self
            )
        )
    }
}
