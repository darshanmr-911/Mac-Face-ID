import AVFoundation
import SwiftUI

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewView {
        CameraPreviewView(session: session)
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {
        nsView.captureSession = session
    }
}

final class CameraPreviewView: NSView {
    var captureSession: AVCaptureSession? {
        get { (layer as? AVCaptureVideoPreviewLayer)?.session }
        set { (layer as? AVCaptureVideoPreviewLayer)?.session = newValue }
    }

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        wantsLayer = true
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        layer = previewLayer
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        layer?.frame = bounds
    }
}
