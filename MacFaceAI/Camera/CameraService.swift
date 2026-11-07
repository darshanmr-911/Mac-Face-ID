import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class CameraService {
    private(set) var status: CameraStatus = .stopped
    private(set) var snapshot: FaceSnapshot?
    private(set) var frameID: UInt64 = 0
    private var clients = 0
    private let engine = CameraEngine()

    var session: AVCaptureSession { engine.session }

    init() {
        engine.setHandlers(
            snapshot: { [weak self] snapshot in
                Task { @MainActor in
                    self?.snapshot = snapshot
                    self?.frameID = snapshot.frameID
                }
            },
            status: { [weak self] status in
                Task { @MainActor in
                    self?.status = status
                }
            }
        )
    }

    func acquire() {
        clients += 1
        if clients == 1 {
            engine.start()
        }
    }

    func release() {
        clients = max(0, clients - 1)
        if clients == 0 {
            engine.stop()
            snapshot = nil
        }
    }

    var dashboardStatus: String {
        switch status {
        case .running:
            return "Camera is on"
        case .requestingPermission:
            return "Waiting for camera permission"
        case .denied:
            return "Camera access is denied"
        case .failed(let message):
            return message
        case .stopped:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                return CameraEngine.builtInCameraPresent() ? "Camera is ready" : "No camera found"
            case .denied, .restricted:
                return "Camera access is denied in System Settings"
            case .notDetermined:
                return "Camera permission has not been requested yet"
            @unknown default:
                return "Camera status is unknown"
            }
        }
    }
}
