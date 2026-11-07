import CommonCrypto
import CryptoKit
import Foundation

struct PasswordRecord: Codable, Equatable, Sendable {
    var salt: Data
    var hash: Data
    var iterations: Int
}

enum PasswordRules {
    static let minimumLength = 8

    static func validate(_ password: String) -> String? {
        if password.count < minimumLength {
            return "Use at least \(minimumLength) characters."
        }
        return nil
    }
}

enum PasswordError: LocalizedError, Equatable {
    case rejected(String)
    case hasherFailed

    var errorDescription: String? {
        switch self {
        case .rejected(let message):
            return message
        case .hasherFailed:
            return "Could not hash the app password."
        }
    }
}

enum PasswordHasher {
    static let defaultIterations = 100_000

    static func make(_ password: String, iterations: Int = defaultIterations) throws -> PasswordRecord {
        let salt = randomSalt(count: 16)
        let hash = try derive(password: password, salt: salt, iterations: iterations)
        return PasswordRecord(salt: salt, hash: hash, iterations: iterations)
    }

    static func verify(_ password: String, record: PasswordRecord) -> Bool {
        guard let hash = try? derive(password: password, salt: record.salt, iterations: record.iterations) else {
            return false
        }
        return constantTimeEquals(hash, record.hash)
    }

    static func derive(password: String, salt: Data, iterations: Int, length: Int = 32) throws -> Data {
        let passwordData = Data(password.utf8)
        var derived = Data(count: length)
        let status: CCStatus = passwordData.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                derived.withUnsafeMutableBytes { derivedBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        length
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw PasswordError.hasherFailed
        }
        return derived
    }

    static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }

    private static func randomSalt(count: Int) -> Data {
        SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
    }
}

struct PasswordService: Sendable {
    var keychain: KeychainStore
    var account = "app.password"

    func hasPassword() throws -> Bool {
        let stored = try keychain.data(account: account)
        return stored?.isEmpty == false
    }

    func create(password: String, confirmation: String) throws {
        if let message = PasswordRules.validate(password) {
            throw PasswordError.rejected(message)
        }
        guard password == confirmation else {
            throw PasswordError.rejected("Those passwords do not match.")
        }
        if try hasPassword() {
            throw PasswordError.rejected("An app password is already set.")
        }
        let record = try PasswordHasher.make(password)
        try keychain.set(JSONEncoder().encode(record), account: account)
    }

    func verify(_ password: String) throws -> Bool {
        guard let data = try keychain.data(account: account) else { return false }
        let record = try JSONDecoder().decode(PasswordRecord.self, from: data)
        return PasswordHasher.verify(password, record: record)
    }

    func change(old: String, new: String, confirmation: String) throws {
        guard try verify(old) else {
            throw PasswordError.rejected("The current app password is incorrect.")
        }
        if let message = PasswordRules.validate(new) {
            throw PasswordError.rejected(message)
        }
        guard new == confirmation else {
            throw PasswordError.rejected("Those passwords do not match.")
        }
        let record = try PasswordHasher.make(new)
        try keychain.set(JSONEncoder().encode(record), account: account)
    }

    func delete() throws {
        try keychain.delete(account: account)
    }
}
