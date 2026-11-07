import Foundation
import LocalAuthentication

enum BiometricError: LocalizedError, Equatable {
    case unavailable(String)
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .failed(let message):
            return message
        case .cancelled:
            return "Touch ID was cancelled."
        }
    }
}

struct BiometricAvailability: Equatable, Sendable {
    var isAvailable: Bool
    var label: String
    var detail: String
}

struct BiometricAuthService: Sendable {
    func availability() -> BiometricAvailability {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            let detail = error?.localizedDescription ?? "Touch ID is not available on this Mac."
            return BiometricAvailability(isAvailable: false, label: "Touch ID", detail: detail)
        }
        switch context.biometryType {
        case .touchID:
            return BiometricAvailability(isAvailable: true, label: "Touch ID", detail: "Available")
        case .faceID:
            return BiometricAvailability(
                isAvailable: true,
                label: "System biometrics",
                detail: "This Mac reported Face ID hardware. MacFace AI will ask macOS, and it still will not replace the login window."
            )
        case .opticID:
            return BiometricAvailability(isAvailable: true, label: "Optic ID", detail: "Available")
        case .none:
            return BiometricAvailability(isAvailable: false, label: "Touch ID", detail: "No biometric sensor is enrolled.")
        @unknown default:
            return BiometricAvailability(isAvailable: true, label: "System biometrics", detail: "Available")
        }
    }

    func authenticate() async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Use App Password"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw BiometricError.unavailable(error?.localizedDescription ?? "Touch ID is not available.")
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock MacFace AI. This uses Touch ID for the app and does not change the macOS login window."
            )
            if !success {
                throw BiometricError.failed("Touch ID did not succeed.")
            }
        } catch let biometric as BiometricError {
            throw biometric
        } catch let localError as LAError {
            switch localError.code {
            case .userCancel, .appCancel, .systemCancel:
                throw BiometricError.cancelled
            default:
                throw BiometricError.failed(localError.localizedDescription)
            }
        }
    }
}
