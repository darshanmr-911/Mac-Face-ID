import CoreMedia
import CoreVideo
import Foundation
import Vision

struct FaceSnapshot: Sendable {
    var frameID: UInt64
    var time: TimeInterval
    var facesCount: Int
    var boundingBox: CGRect?
    var yaw: Float?
    var pitch: Float?
    var roll: Float?
    var quality: Float?
    var eyeOpenness: Float?
    var featurePrint: [Float]?
    var geometry: [Float]?
    var statusNote: String?

    static func empty(frameID: UInt64, time: TimeInterval) -> FaceSnapshot {
        FaceSnapshot(
            frameID: frameID,
            time: time,
            facesCount: 0,
            boundingBox: nil,
            yaw: nil,
            pitch: nil,
            roll: nil,
            quality: nil,
            eyeOpenness: nil,
            featurePrint: nil,
            geometry: nil,
            statusNote: nil
        )
    }
}

final class FaceAnalyzer: @unchecked Sendable {
    private let processor = FaceImageProcessor()
    private var lastEmbeddingTime: TimeInterval = -.greatestFiniteMagnitude
    private let embeddingInterval: TimeInterval = 0.2

    func analyze(pixelBuffer: CVPixelBuffer, frameID: UInt64, embed: Bool) -> FaceSnapshot {
        let time = CACurrentMediaTime()
        var snapshot = FaceSnapshot.empty(frameID: frameID, time: time)
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            let detect = VNDetectFaceRectanglesRequest()
            detect.revision = VNDetectFaceRectanglesRequest.currentRevision
            try handler.perform([detect])
            let faces = detect.results ?? []
            snapshot.facesCount = faces.count
            guard let primary = largestFace(in: faces) else {
                snapshot.statusNote = "No face detected"
                return snapshot
            }
            if faces.count > 1 {
                snapshot.statusNote = "More than one face is in frame"
            }
            snapshot.boundingBox = primary.boundingBox
            snapshot.yaw = floatNumber(primary.yaw)
            snapshot.pitch = floatNumber(primary.pitch)
            snapshot.roll = floatNumber(primary.roll)

            let landmarksRequest = VNDetectFaceLandmarksRequest()
            landmarksRequest.revision = VNDetectFaceLandmarksRequest.currentRevision
            if VNDetectFaceLandmarksRequest.revision(landmarksRequest.revision, supports: .constellation76Points) {
                landmarksRequest.constellation = .constellation76Points
            } else {
                landmarksRequest.constellation = .constellation65Points
            }
            landmarksRequest.inputFaceObservations = [primary]
            try handler.perform([landmarksRequest])

            let qualityRequest = VNDetectFaceCaptureQualityRequest()
            qualityRequest.inputFaceObservations = [primary]
            try handler.perform([qualityRequest])
            if let quality = qualityRequest.results?.first?.faceCaptureQuality {
                snapshot.quality = quality.floatValue
            }

            guard let landmarked = landmarksRequest.results?.first else {
                snapshot.statusNote = snapshot.statusNote ?? "Face landmarks were not available"
                return snapshot
            }
            if let aligned = processor.alignedFace(pixelBuffer: pixelBuffer, observation: landmarked) {
                snapshot.geometry = aligned.geometry
                snapshot.eyeOpenness = aligned.eyeOpenness
                if embed && faces.count == 1 && time - lastEmbeddingTime >= embeddingInterval {
                    lastEmbeddingTime = time
                    snapshot.featurePrint = try FaceEmbedder.featurePrint(of: aligned.image)
                }
            } else {
                snapshot.statusNote = snapshot.statusNote ?? "Keep both eyes visible so the face can be aligned"
            }
        } catch {
            snapshot.statusNote = "Face analysis failed: \(error.localizedDescription)"
        }
        return snapshot
    }

    private func largestFace(in faces: [VNFaceObservation]) -> VNFaceObservation? {
        faces.max { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
        }
    }

    private func floatNumber(_ number: NSNumber?) -> Float? {
        number.map { Float(truncating: $0) }
    }
}
