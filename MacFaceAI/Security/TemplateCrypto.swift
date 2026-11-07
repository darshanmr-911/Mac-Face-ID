import CryptoKit
import Foundation

enum TemplateCrypto {
    static func makeKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    static func rawKey(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    static func key(from data: Data) throws -> SymmetricKey {
        guard data.count == 32 else {
            throw MacFaceError.message("The template encryption key has the wrong length.")
        }
        return SymmetricKey(data: data)
    }

    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else {
            throw MacFaceError.message("Could not seal the face template.")
        }
        return combined
    }

    static func open(_ sealed: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: sealed)
        return try AES.GCM.open(box, using: key)
    }
}
