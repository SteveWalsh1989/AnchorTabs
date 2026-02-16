import Foundation

// Carries the chosen window plus the strategy used to pick it.
struct PinMatchResult {
  let window: WindowSnapshot
  let method: PinMatchMethod
}

// Stateless matching engine used by PinnedStore reconciliation.
enum PinMatcher {
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
  ) -> PinMatchResult? {
    let candidates = windows.filter {
      $0.bundleID == reference.bundleID && !consumedWindowIDs.contains($0.id)
    }
    guard !candidates.isEmpty else { return nil }

    if let runtimeID = reference.lastKnownRuntimeID,
      let runtimeMatch = candidates.first(where: { $0.id == runtimeID })
    {
      return PinMatchResult(window: runtimeMatch, method: .runtimeID)
    }

    if let windowNumber = reference.windowNumber,
      let numberMatch = candidates.first(where: { $0.windowNumber == windowNumber })
    {
      return PinMatchResult(window: numberMatch, method: .windowNumber)
    }

    if let referenceSignature = signature(for: reference),
      let signatureMatch = candidates.first(where: { signature(for: $0) == referenceSignature })
    {
      return PinMatchResult(window: signatureMatch, method: .signature)
    }

    let referenceNormalizedTitle = reference.normalizedTitle ?? normalizedTitle(reference.title)
    var bestWindow: WindowSnapshot?
    var bestMethod: PinMatchMethod = .fuzzyTitle
    var bestScore = Int.min

    for candidate in candidates {
      let candidateNormalizedTitle = normalizedTitle(candidate.title)
      let isExactTitle = candidateNormalizedTitle == referenceNormalizedTitle
      let isFuzzyTitle =
        candidateNormalizedTitle.contains(referenceNormalizedTitle)
        || referenceNormalizedTitle.contains(candidateNormalizedTitle)

      guard isExactTitle || isFuzzyTitle else { continue }

      var score = isExactTitle ? 240 : 130
      let method: PinMatchMethod = isExactTitle ? .exactTitle : .fuzzyTitle

      if let role = reference.role, role == candidate.role {
        score += 55
      }

      if let subrole = reference.subrole, subrole == candidate.subrole {
        score += 35
      }

      if let referenceFrame = reference.frame, let candidateFrame = candidate.frame {
        score += frameSimilarityScore(reference: referenceFrame, candidate: candidateFrame)
      }

      if score > bestScore {
        bestScore = score
        bestWindow = candidate
        bestMethod = method
      }
    }

    guard let bestWindow else { return nil }
    return PinMatchResult(window: bestWindow, method: bestMethod)
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
}
