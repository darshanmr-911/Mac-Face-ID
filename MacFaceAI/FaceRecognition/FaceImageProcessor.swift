import CoreImage
import CoreVideo
import Foundation
import Vision

final class FaceImageProcessor: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let outputSide = 224

    func alignedFace(pixelBuffer: CVPixelBuffer, observation: VNFaceObservation) -> (image: CGImage, geometry: [Float], eyeOpenness: Float?)? {
        guard let landmarks = observation.landmarks else { return nil }
        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        let leftEye = points(landmarks.leftEye, imageSize: imageSize)
        let rightEye = points(landmarks.rightEye, imageSize: imageSize)
        let allPoints = points(landmarks.allPoints, imageSize: imageSize)
        guard let geometry = FaceGeometry.embed(allPoints: allPoints, leftEye: leftEye, rightEye: rightEye),
              let leftCenter = FaceGeometry.centroid(leftEye),
              let rightCenter = FaceGeometry.centroid(rightEye) else {
            return nil
        }
        let openness = FaceGeometry.eyeOpenness(leftEye: leftEye, rightEye: rightEye)
        guard let image = renderAligned(
            pixelBuffer: pixelBuffer,
            left: leftCenter,
            right: rightCenter
        ) else {
            return nil
        }
        return (image, geometry, openness)
    }

    private func renderAligned(pixelBuffer: CVPixelBuffer, left: Point2, right: Point2) -> CGImage? {
        let dx = CGFloat(right.x - left.x)
        let dy = CGFloat(right.y - left.y)
        let distance = hypot(dx, dy)
        guard distance > 8 else { return nil }
        let angle = atan2(dy, dx)
        let scale = (CGFloat(outputSide) * 0.38) / distance
        let midX = CGFloat(left.x + right.x) * 0.5
        let midY = CGFloat(left.y + right.y) * 0.5
        let side = CGFloat(outputSide)
        let transform = CGAffineTransform(translationX: -midX, y: -midY)
            .rotated(by: -angle)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: side * 0.5, y: side * 0.5)
        let aligned = CIImage(cvPixelBuffer: pixelBuffer)
            .transformed(by: transform)
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        return context.createCGImage(aligned, from: aligned.extent)
    }

    private func points(_ region: VNFaceLandmarkRegion2D?, imageSize: CGSize) -> [Point2] {
        guard let region, region.pointCount > 0 else {
            return []
        }
        let pointer = region.__pointsInImage(imageSize: imageSize)
        return (0..<region.pointCount).map { index in
            let point = pointer[index]
            return Point2(x: Float(point.x), y: Float(point.y))
        }
    }
}
