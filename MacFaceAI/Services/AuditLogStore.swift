import Foundation
import Observation

@MainActor
@Observable
final class AuditLogStore {
    private(set) var events: [AuditEvent] = []
    private let fileURL: URL?
    private let limit = 200

    init() {
        let url = try? AppPaths.supportDirectory().appendingPathComponent("audit.json")
        fileURL = url
        if let url, let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([AuditEvent].self, from: data) {
            events = decoded
        }
    }

    func append(method: AuthMethod, success: Bool, detail: String, similarity: Double?) {
        let event = AuditEvent(
            id: UUID(),
            date: Date(),
            method: method,
            success: success,
            detail: detail,
            similarity: similarity
        )
        events.append(event)
        if events.count > limit {
            events.removeFirst(events.count - limit)
        }
        guard let fileURL else { return }
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func clear() {
        events = []
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
