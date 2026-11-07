import Foundation

struct Point2: Equatable, Sendable {
    var x: Float
    var y: Float
}

enum FaceGeometry {
    static func centroid(_ points: [Point2]) -> Point2? {
        guard !points.isEmpty else { return nil }
        let count = Float(points.count)
        let x = points.reduce(Float(0)) { $0 + $1.x } / count
        let y = points.reduce(Float(0)) { $0 + $1.y } / count
        return Point2(x: x, y: y)
    }

    static func openness(of eye: [Point2]) -> Float? {
        guard eye.count >= 2 else { return nil }
        var minX = eye[0].x
        var maxX = eye[0].x
        var minY = eye[0].y
        var maxY = eye[0].y
        for point in eye.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let width = maxX - minX
        guard width > 1e-5 else { return nil }
        return (maxY - minY) / width
    }

    static func eyeOpenness(leftEye: [Point2], rightEye: [Point2]) -> Float? {
        switch (openness(of: leftEye), openness(of: rightEye)) {
        case let (left?, right?):
            return min(left, right)
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        default:
            return nil
        }
    }

    /// Aligns landmark points by the eye line and scales them by inter-eye distance.
    /// The result is an L2-normalized geometric template, not a Vision feature print.
    static func embed(allPoints: [Point2], leftEye: [Point2], rightEye: [Point2]) -> [Float]? {
        guard allPoints.count >= 5,
              let leftCenter = centroid(leftEye),
              let rightCenter = centroid(rightEye) else {
            return nil
        }
        let dx = rightCenter.x - leftCenter.x
        let dy = rightCenter.y - leftCenter.y
        let distance = hypot(dx, dy)
        guard distance > 1e-4 else { return nil }
        let angle = atan2(dy, dx)
        let cosine = cos(-angle)
        let sine = sin(-angle)
        let midX = (leftCenter.x + rightCenter.x) * 0.5
        let midY = (leftCenter.y + rightCenter.y) * 0.5
        var embedded: [Float] = []
        embedded.reserveCapacity(allPoints.count * 2)
        for point in allPoints {
            let translatedX = point.x - midX
            let translatedY = point.y - midY
            let rotatedX = (translatedX * cosine - translatedY * sine) / distance
            let rotatedY = (translatedX * sine + translatedY * cosine) / distance
            embedded.append(rotatedX)
            embedded.append(rotatedY)
        }
        return Similarity.l2Normalize(embedded)
    }
}
