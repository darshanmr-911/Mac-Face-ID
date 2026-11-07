import Foundation

enum AuthMethod: String, Codable, Sendable {
    case face
    case touchID
    case password
}

struct LastAuthResult: Codable, Equatable, Sendable {
    var date: Date
    var success: Bool
    var method: AuthMethod
    var detail: String
    var similarity: Double?
}

struct AppSettings: Codable, Equatable, Sendable {
    var similarityThreshold: Double
    var requireLiveness: Bool
    var allowTouchID: Bool
    var successfulAuthentications: Int
    var lastResult: LastAuthResult?

    static let `default` = AppSettings(
        similarityThreshold: 0.80,
        requireLiveness: true,
        allowTouchID: true,
        successfulAuthentications: 0,
        lastResult: nil
    )

    private enum CodingKeys: String, CodingKey {
        case similarityThreshold
        case requireLiveness
        case allowTouchID
        case successfulAuthentications
        case lastResult
    }

    init(
        similarityThreshold: Double,
        requireLiveness: Bool,
        allowTouchID: Bool,
        successfulAuthentications: Int,
        lastResult: LastAuthResult?
    ) {
        self.similarityThreshold = similarityThreshold
        self.requireLiveness = requireLiveness
        self.allowTouchID = allowTouchID
        self.successfulAuthentications = successfulAuthentications
        self.lastResult = lastResult
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings.default
        similarityThreshold = try container.decodeIfPresent(Double.self, forKey: .similarityThreshold) ?? fallback.similarityThreshold
        requireLiveness = try container.decodeIfPresent(Bool.self, forKey: .requireLiveness) ?? fallback.requireLiveness
        allowTouchID = try container.decodeIfPresent(Bool.self, forKey: .allowTouchID) ?? fallback.allowTouchID
        successfulAuthentications = try container.decodeIfPresent(Int.self, forKey: .successfulAuthentications) ?? 0
        lastResult = try container.decodeIfPresent(LastAuthResult.self, forKey: .lastResult)
    }
}

struct EnrollmentSample: Codable, Equatable, Sendable {
    var featurePrint: [Float]
    var geometry: [Float]
    var quality: Float
    var capturedAt: Date
}

struct FaceProfile: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var displayName: String
    var createdAt: Date
    var updatedAt: Date
    var samples: [EnrollmentSample]

    var averageQuality: Float {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0) { $0 + $1.quality } / Float(samples.count)
    }
}

struct TemplateDatabase: Codable, Equatable, Sendable {
    var version: Int
    var featurePrintRevision: Int
    var profiles: [FaceProfile]

    static let currentVersion = 1

    static func empty(featurePrintRevision: Int) -> TemplateDatabase {
        TemplateDatabase(version: currentVersion, featurePrintRevision: featurePrintRevision, profiles: [])
    }
}

struct ProbeEmbedding: Equatable, Sendable {
    var featurePrint: [Float]
    var geometry: [Float]
}

struct MatchDecision: Equatable, Sendable {
    var accepted: Bool
    var profileID: UUID?
    var displayName: String?
    var similarity: Double
    var geometrySimilarity: Double?
    var sampleCount: Int
    var reason: String
}

struct AuditEvent: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var date: Date
    var method: AuthMethod
    var success: Bool
    var detail: String
    var similarity: Double?
}
