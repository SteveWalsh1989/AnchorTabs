import Foundation

// Carries the chosen matching live window.
struct PinnedWindowMatchResult {
  let window: WindowSnapshot
}

// Stateless matching engine used by PinnedWindowsStore reconciliation.
enum PinnedWindowMatcher {
  // Produces a normalized title token for matching and signatures.
  static func normalizedTitle(_ title: String) -> String {
    title.normalizedForMatching()
  }

  // Builds a stable signature for a live window snapshot.
  static func signature(for window: WindowSnapshot) -> String {
    signature(
      role: window.role,
      subrole: window.subrole,
      normalizedTitle: normalizedTitle(window.title),
      frame: window.frame
    )
  }

  // Rebuilds a persisted signature when legacy records are missing it.
  static func signature(for reference: PinnedWindowReference) -> String? {
    if let signature = reference.signature, !signature.isEmpty {
      return signature
    }

    guard let role = reference.role else { return nil }
    let normalizedTitle = reference.normalizedTitle ?? normalizedTitle(reference.title)
    return signature(
      role: role,
      subrole: reference.subrole,
      normalizedTitle: normalizedTitle,
      frame: reference.frame
    )
  }

  // Picks the best live match for a persisted pin using prioritized strategies.
  static func findBestMatch(
    for reference: PinnedWindowReference,
    in windows: [WindowSnapshot],
    consumedWindowIDs: Set<String>
  ) -> PinnedWindowMatchResult? {
    let candidates = windows.filter {
      $0.bundleID == reference.bundleID && !consumedWindowIDs.contains($0.id)
    }
    guard !candidates.isEmpty else { return nil }
    let orderedCandidates = candidates.sorted(by: candidateSortOrder)
    let referenceSignature = signature(for: reference)

    if let runtimeID = reference.lastKnownRuntimeID,
      let runtimeMatch = orderedCandidates.first(where: { $0.id == runtimeID })
    {
      if !isLegacyOccurrenceFallbackRuntimeID(runtimeID) {
        return PinnedWindowMatchResult(window: runtimeMatch)
      }

      let shouldTrustFallbackRuntimeID: Bool
      if let referenceSignature {
        let signatureMatchCount = orderedCandidates.filter { signature(for: $0) == referenceSignature }
          .count
        shouldTrustFallbackRuntimeID = signatureMatchCount <= 1
      } else {
        shouldTrustFallbackRuntimeID = orderedCandidates.count == 1
      }

      if shouldTrustFallbackRuntimeID {
        return PinnedWindowMatchResult(window: runtimeMatch)
      }
    }

    if let windowNumber = reference.windowNumber,
      let numberMatch = orderedCandidates.first(where: { $0.windowNumber == windowNumber })
    {
      return PinnedWindowMatchResult(window: numberMatch)
    }

    if let referenceSignature {
      let signatureMatches = orderedCandidates.filter { signature(for: $0) == referenceSignature }
      if signatureMatches.count == 1, let match = signatureMatches.first {
        return PinnedWindowMatchResult(window: match)
      }
      if signatureMatches.count > 1 {
        return nil
      }
    }

    guard orderedCandidates.count == 1,
      let bestCandidate = bestScoredCandidate(for: reference, candidates: orderedCandidates)
    else {
      return nil
    }
    return PinnedWindowMatchResult(window: bestCandidate)
  }

  // Combines role/title/frame buckets into a deterministic signature string.
  private static func signature(
    role: String,
    subrole: String?,
    normalizedTitle: String,
    frame: WindowFrame?
  ) -> String {
    let bucket = bucketedFrameString(frame)
    return "\(role)|\(subrole ?? "-")|\(normalizedTitle)|\(bucket)"
  }

  // Coarsens frame coordinates to reduce false negatives from minor moves.
  private static func bucketedFrameString(_ frame: WindowFrame?) -> String {
    guard let frame else { return "-" }
    let sizeBucket = 24
    let positionBucket = 48
    let x = (frame.x / positionBucket) * positionBucket
    let y = (frame.y / positionBucket) * positionBucket
    let width = (frame.width / sizeBucket) * sizeBucket
    let height = (frame.height / sizeBucket) * sizeBucket
    return "\(x),\(y),\(width),\(height)"
  }

  // Scores geometric proximity when comparing similarly titled windows.
  private static func frameSimilarityScore(reference: WindowFrame, candidate: WindowFrame) -> Int {
    let dx = abs(reference.x - candidate.x)
    let dy = abs(reference.y - candidate.y)
    let dw = abs(reference.width - candidate.width)
    let dh = abs(reference.height - candidate.height)

    if dx <= 24 && dy <= 24 && dw <= 24 && dh <= 24 {
      return 60
    }

    if dx <= 96 && dy <= 96 && dw <= 96 && dh <= 96 {
      return 30
    }

    return 0
  }

  // Breaks score ties using exact frame distance so adjacent windows do not swap.
  private static func frameDistance(reference: WindowFrame?, candidate: WindowFrame?) -> Int {
    guard let reference, let candidate else { return Int.max }
    let dx = abs(reference.x - candidate.x)
    let dy = abs(reference.y - candidate.y)
    let dw = abs(reference.width - candidate.width)
    let dh = abs(reference.height - candidate.height)
    return dx + dy + dw + dh
  }

  // Picks the strongest title/role/frame-based candidate from a pre-filtered list.
  private static func bestScoredCandidate(
    for reference: PinnedWindowReference,
    candidates: [WindowSnapshot]
  ) -> WindowSnapshot? {
    let referenceNormalizedTitle = reference.normalizedTitle ?? normalizedTitle(reference.title)
    var bestWindow: WindowSnapshot?
    var bestScore = Int.min
    var bestFrameDistance = Int.max

    for candidate in candidates {
      let candidateNormalizedTitle = normalizedTitle(candidate.title)
      let isExactTitle = candidateNormalizedTitle == referenceNormalizedTitle
      let isFuzzyTitle =
        !referenceNormalizedTitle.isEmpty
        && (candidateNormalizedTitle.contains(referenceNormalizedTitle)
          || referenceNormalizedTitle.contains(candidateNormalizedTitle))

      guard isExactTitle || isFuzzyTitle else { continue }

      var score = isExactTitle ? 240 : 130

      if let role = reference.role, role == candidate.role {
        score += 55
      }

      if let subrole = reference.subrole, subrole == candidate.subrole {
        score += 35
      }

      if let referenceFrame = reference.frame, let candidateFrame = candidate.frame {
        score += frameSimilarityScore(reference: referenceFrame, candidate: candidateFrame)
      }

      let candidateFrameDistance = frameDistance(
        reference: reference.frame,
        candidate: candidate.frame
      )

      if score > bestScore
        || (score == bestScore && candidateFrameDistance < bestFrameDistance)
        || (score == bestScore && candidateFrameDistance == bestFrameDistance
          && bestWindow.map { candidateSortOrder(candidate, $0) } == true)
      {
        bestScore = score
        bestFrameDistance = candidateFrameDistance
        bestWindow = candidate
      }
    }

    return bestWindow
  }

  // Provides deterministic ordering for tie-breaking and "first match" fallbacks.
  private static func candidateSortOrder(_ lhs: WindowSnapshot, _ rhs: WindowSnapshot) -> Bool {
    if let result = compareOrderedInts(lhs.windowNumber ?? Int.max, rhs.windowNumber ?? Int.max) {
      return result
    }
    if let result = compareOrderedInts(lhs.frame?.x ?? Int.max, rhs.frame?.x ?? Int.max) {
      return result
    }
    if let result = compareOrderedInts(lhs.frame?.y ?? Int.max, rhs.frame?.y ?? Int.max) {
      return result
    }
    if let result = compareOrderedInts(lhs.frame?.width ?? Int.max, rhs.frame?.width ?? Int.max) {
      return result
    }
    if let result = compareOrderedInts(lhs.frame?.height ?? Int.max, rhs.frame?.height ?? Int.max) {
      return result
    }

    let lhsTitle = normalizedTitle(lhs.title)
    let rhsTitle = normalizedTitle(rhs.title)
    if lhsTitle != rhsTitle {
      return lhsTitle < rhsTitle
    }
    return lhs.id < rhs.id
  }

  // Returns ordering when values differ; nil means values were equal.
  private static func compareOrderedInts(_ lhs: Int, _ rhs: Int) -> Bool? {
    guard lhs != rhs else { return nil }
    return lhs < rhs
  }

  // Legacy fallback ids use an occurrence suffix and can swap when AX list order changes.
  private static func isLegacyOccurrenceFallbackRuntimeID(_ runtimeID: String) -> Bool {
    runtimeID.contains("-fallback-")
  }
}
