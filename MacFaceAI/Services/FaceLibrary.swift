import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class FaceLibrary {
    private(set) var profiles: [FaceProfile] = []
    private(set) var loadError: String?
    private(set) var storedRevision: Int?
    private let keychain: KeychainStore
    private let keyAccount = "template.aes256"
    private var fileURL: URL?

    init(keychain: KeychainStore) {
        self.keychain = keychain
        reload()
    }

    func reload() {
        do {
            let store = try makeStore()
            let database = try store.load(featurePrintRevision: FaceEmbedder.preferredRevision)
            storedRevision = database.featurePrintRevision
            profiles = database.profiles.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            if !database.profiles.isEmpty && database.featurePrintRevision != FaceEmbedder.preferredRevision {
                loadError = "Saved templates use Vision feature-print revision \(database.featurePrintRevision), and this Mac is using revision \(FaceEmbedder.preferredRevision). Delete the faces and register them again."
            } else {
                loadError = nil
            }
        } catch {
            profiles = []
            loadError = error.localizedDescription
        }
    }

    func upsert(displayName: String, samples: [EnrollmentSample]) throws {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw MacFaceError.message("Enter a name for this face.")
        }
        guard samples.count >= 6 else {
            throw MacFaceError.message("At least 6 face samples are required.")
        }
        guard samples.allSatisfy({ !$0.featurePrint.isEmpty && !$0.geometry.isEmpty }) else {
            throw MacFaceError.message("One of the captured samples is missing an embedding.")
        }
        var next = profiles
        next.removeAll { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }
        let now = Date()
        next.append(
            FaceProfile(
                id: UUID(),
                displayName: name,
                createdAt: now,
                updatedAt: now,
                samples: samples
            )
        )
        try persist(next)
    }

    func delete(id: UUID) throws {
        try persist(profiles.filter { $0.id != id })
    }

    func deleteAll() throws {
        let store = try makeStore()
        try store.deleteFile()
        try keychain.delete(account: keyAccount)
        profiles = []
        storedRevision = FaceEmbedder.preferredRevision
        loadError = nil
    }

    private func persist(_ profiles: [FaceProfile]) throws {
        let store = try makeStore()
        let existingRevision = storedRevision ?? FaceEmbedder.preferredRevision
        let revision = profiles.isEmpty ? FaceEmbedder.preferredRevision : existingRevision
        if !profiles.isEmpty && revision != FaceEmbedder.preferredRevision {
            throw MacFaceError.message(loadError ?? "The saved feature-print revision does not match this Mac.")
        }
        let database = TemplateDatabase(
            version: TemplateDatabase.currentVersion,
            featurePrintRevision: FaceEmbedder.preferredRevision,
            profiles: profiles
        )
        try store.save(database)
        self.profiles = database.profiles.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        storedRevision = database.featurePrintRevision
        loadError = nil
    }

    private func makeStore() throws -> EncryptedTemplateStore {
        let directory = try AppPaths.supportDirectory()
        let url = directory.appendingPathComponent("templates.sealed")
        fileURL = url
        let key = try encryptionKey()
        return EncryptedTemplateStore(fileURL: url, key: key)
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let stored = try keychain.data(account: keyAccount) {
            return try TemplateCrypto.key(from: stored)
        }
        let key = TemplateCrypto.makeKey()
        try keychain.set(TemplateCrypto.rawKey(key), account: keyAccount)
        return key
    }
}
