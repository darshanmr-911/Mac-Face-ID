import CoreGraphics
import Foundation
import Vision

enum FaceEmbedder {
    static var preferredRevision: Int {
        let supported = VNGenerateImageFeaturePrintRequest.supportedRevisions
        if supported.contains(VNGenerateImageFeaturePrintRequestRevision2) {
            return VNGenerateImageFeaturePrintRequestRevision2
        }
        return VNGenerateImageFeaturePrintRequestRevision1
    }

    static func featurePrint(of image: CGImage, revision: Int? = nil) throws -> [Float] {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = revision ?? preferredRevision
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw MacFaceError.message("Vision did not return a feature print for this face.")
        }
        return try vector(from: observation)
    }

    static func vector(from observation: VNFeaturePrintObservation) throws -> [Float] {
        let data = observation.data
        switch observation.elementType {
        case .float:
            let count = observation.elementCount
            guard data.count >= count * MemoryLayout<Float>.size else {
                throw MacFaceError.message("Feature print data is shorter than Vision reported.")
            }
            return data.withUnsafeBytes { raw in
                let buffer = raw.bindMemory(to: Float.self)
                return Array(buffer.prefix(count))
            }
        case .double:
            let count = observation.elementCount
            guard data.count >= count * MemoryLayout<Double>.size else {
                throw MacFaceError.message("Feature print data is shorter than Vision reported.")
            }
            return data.withUnsafeBytes { raw in
                let buffer = raw.bindMemory(to: Double.self)
                return buffer.prefix(count).map { Float($0) }
            }
        case .unknown:
            throw MacFaceError.message("Vision returned an unknown feature-print element type.")
        @unknown default:
            throw MacFaceError.message("Vision returned an unsupported feature-print element type.")
        }
    }
}
