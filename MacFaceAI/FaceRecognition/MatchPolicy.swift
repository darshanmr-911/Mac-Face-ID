import Foundation

enum MatchPolicy {
    /// Loose sanity check. Landmark geometry is similar across different people,
    /// so this only rejects a badly aligned or incompatible shape.
    static let geometryMinimum = 0.50
    static let ambiguityMargin = 0.02

    static func decide(probe: ProbeEmbedding, profiles: [FaceProfile], threshold: Double) -> MatchDecision {
        let usable = profiles.filter { !$0.samples.isEmpty }
        guard !usable.isEmpty else {
            return MatchDecision(
                accepted: false,
                profileID: nil,
                displayName: nil,
                similarity: 0,
                geometrySimilarity: nil,
                sampleCount: 0,
                reason: "No faces are enrolled on this Mac."
            )
        }
        guard !probe.featurePrint.isEmpty else {
            return MatchDecision(
                accepted: false,
                profileID: nil,
                displayName: nil,
                similarity: 0,
                geometrySimilarity: nil,
                sampleCount: 0,
                reason: "The camera frame did not produce a face embedding."
            )
        }

        var scored: [ScoredProfile] = []
        scored.reserveCapacity(usable.count)
        for profile in usable {
            guard let appearance = bestCosine(probe.featurePrint, profile.samples.map(\.featurePrint)) else {
                continue
            }
            let geometry = bestCosine(probe.geometry, profile.samples.map(\.geometry))
            scored.append(ScoredProfile(profile: profile, appearance: appearance, geometry: geometry))
        }

        guard let best = scored.max(by: { $0.appearance < $1.appearance }) else {
            return MatchDecision(
                accepted: false,
                profileID: nil,
                displayName: nil,
                similarity: 0,
                geometrySimilarity: nil,
                sampleCount: 0,
                reason: "Enrolled templates use a different embedding size. Register the face again."
            )
        }

        let ranked = scored.sorted { $0.appearance > $1.appearance }
        if ranked.count >= 2,
           ranked[0].appearance >= threshold,
           ranked[1].appearance >= threshold,
           ranked[0].appearance - ranked[1].appearance < ambiguityMargin {
            return MatchDecision(
                accepted: false,
                profileID: nil,
                displayName: nil,
                similarity: ranked[0].appearance,
                geometrySimilarity: ranked[0].geometry,
                sampleCount: ranked[0].profile.samples.count,
                reason: "Two enrolled faces are too close to tell apart at the current threshold."
            )
        }

        let geometryFailed = best.geometry.map { $0 < geometryMinimum } ?? false
        let aboveThreshold = best.appearance >= threshold
        let accepted = aboveThreshold && !geometryFailed
        let reason: String
        if accepted {
            reason = "Matched \(best.profile.displayName) by cosine similarity of the on-device face embedding."
        } else if geometryFailed {
            reason = "The face shape check did not agree with the appearance embedding."
        } else {
            reason = "This face is below the similarity threshold."
        }

        return MatchDecision(
            accepted: accepted,
            profileID: accepted ? best.profile.id : nil,
            displayName: accepted ? best.profile.displayName : nil,
            similarity: best.appearance,
            geometrySimilarity: best.geometry,
            sampleCount: best.profile.samples.count,
            reason: reason
        )
    }

    private struct ScoredProfile {
        var profile: FaceProfile
        var appearance: Double
        var geometry: Double?
    }

    private static func bestCosine(_ probe: [Float], _ samples: [[Float]]) -> Double? {
        guard !probe.isEmpty else { return nil }
        let scores = samples.compactMap { sample -> Double? in
            guard sample.count == probe.count, !sample.isEmpty else { return nil }
            return Double(Similarity.cosine(probe, sample))
        }
        return scores.max()
    }
}
