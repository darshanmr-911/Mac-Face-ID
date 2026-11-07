import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    var settings: AppSettings {
        didSet { persist() }
    }

    private let fileURL: URL?

    init() {
        let url = try? AppPaths.supportDirectory().appendingPathComponent("settings.json")
        fileURL = url
        if let url, let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // The in-memory settings still apply for this launch. The next successful change retries the write.
        }
    }
}
