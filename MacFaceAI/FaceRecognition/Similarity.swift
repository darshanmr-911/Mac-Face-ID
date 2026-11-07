import Foundation

enum Similarity {
    static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot: Float = 0
        var leftNorm: Float = 0
        var rightNorm: Float = 0
        for index in lhs.indices {
            let left = lhs[index]
            let right = rhs[index]
            dot += left * right
            leftNorm += left * left
            rightNorm += right * right
        }
        let denominator = sqrt(leftNorm) * sqrt(rightNorm)
        guard denominator > 1e-8 else { return 0 }
        return dot / denominator
    }

    static func l2Normalize(_ values: [Float]) -> [Float] {
        var norm: Float = 0
        for value in values {
            norm += value * value
        }
        let denominator = sqrt(norm)
        guard denominator > 1e-8 else { return values }
        return values.map { $0 / denominator }
    }
}
