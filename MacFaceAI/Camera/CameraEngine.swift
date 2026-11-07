import AVFoundation
import Foundation
import os

enum CameraStatus: Equatable, Sendable {
    case stopped
    case requestingPermission
    case running
    case denied
    case failed(String)
}

final class CameraEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.macfaceai.camera.session")
    private let outputQueue = DispatchQueue(label: "com.macfaceai.camera.output")
    private let analyzer = FaceAnalyzer()
    private let callbackLock = NSLock()
    private var snapshotHandler: (@Sendable (FaceSnapshot) -> Void)?
    private var statusHandler: (@Sendable (CameraStatus) -> Void)?
    private var configured = false
    private var askedPermission = false
    private var nextFrame: UInt64 = 0
    private let logger = Logger(subsystem: "com.macfaceai.MacFaceAI", category: "camera")

    func setHandlers(
        snapshot: @escaping @Sendable (FaceSnapshot) -> Void,
        status: @escaping @Sendable (CameraStatus) -> Void
    ) {
        callbackLock.lock()
        snapshotHandler = snapshot
        statusHandler = status
        callbackLock.unlock()
    }

    func start() {
        sessionQueue.async { [weak self] in
            self?.startOnSessionQueue()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.askedPermission = false
            self.emit(status: .stopped)
        }
    }

    static func builtInCameraPresent() -> Bool {
        selectDevice() != nil
    }

    private func startOnSessionQueue() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard !askedPermission else { return }
            askedPermission = true
            emit(status: .requestingPermission)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                self?.sessionQueue.async {
                    guard let self else { return }
                    self.askedPermission = false
                    if granted {
                        self.startOnSessionQueue()
                    } else {
                        self.emit(status: .denied)
                    }
                }
            }
            return
        case .denied, .restricted:
            emit(status: .denied)
            return
        @unknown default:
            emit(status: .denied)
            return
        }

        if !configured {
            do {
                try configureSession()
                configured = true
            } catch {
                logger.error("Camera configuration failed: \(error.localizedDescription, privacy: .public)")
                emit(status: .failed(error.localizedDescription))
                return
            }
        }
        if !session.isRunning {
            session.startRunning()
        }
        emit(status: session.isRunning ? .running : .failed("The camera session did not start."))
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        guard let device = Self.selectDevice() else {
            throw MacFaceError.message("No camera was found. Connect a camera or use the built-in MacBook camera.")
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw MacFaceError.message("This camera cannot be added to the capture session.")
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: outputQueue)
        guard session.canAddOutput(output) else {
            throw MacFaceError.message("Video output is not available for this camera.")
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirroringEnabled = false
            }
        }

        do {
            try device.lockForConfiguration()
            let frameDuration = CMTime(value: 1, timescale: 15)
            if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameDuration <= frameDuration && frameDuration <= $0.maxFrameDuration }) {
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration
            }
            device.unlockForConfiguration()
        } catch {
            logger.error("Could not lock the camera frame rate: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func selectDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        if let builtInFront = discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera && $0.position == .front }) {
            return builtInFront
        }
        if let builtIn = discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) {
            return builtIn
        }
        return discovery.devices.first
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        nextFrame += 1
        let snapshot = analyzer.analyze(pixelBuffer: pixelBuffer, frameID: nextFrame, embed: true)
        emit(snapshot: snapshot)
    }

    private func emit(snapshot: FaceSnapshot) {
        callbackLock.lock()
        let handler = snapshotHandler
        callbackLock.unlock()
        guard let handler else { return }
        DispatchQueue.main.async {
            handler(snapshot)
        }
    }

    private func emit(status: CameraStatus) {
        callbackLock.lock()
        let handler = statusHandler
        callbackLock.unlock()
        guard let handler else { return }
        DispatchQueue.main.async {
            handler(status)
        }
    }
}
