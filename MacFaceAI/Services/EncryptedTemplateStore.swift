import CryptoKit
import Foundation

struct EncryptedTemplateStore: Sendable {
    var fileURL: URL
    var key: SymmetricKey

    func load(featurePrintRevision: Int) throws -> TemplateDatabase {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return TemplateDatabase.empty(featurePrintRevision: featurePrintRevision)
        }
        let sealed = try Data(contentsOf: fileURL)
        let plaintext = try TemplateCrypto.open(sealed, using: key)
        return try JSONDecoder().decode(TemplateDatabase.self, from: plaintext)
    }

    func save(_ database: TemplateDatabase) throws -> Void {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let plaintext = try JSONEncoder().encode(database)
        let sealed = try TemplateCrypto.seal(plaintext, using: key)
        try sealed.write(to: fileURL, options: .atomic)
    }

    func deleteFile() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
