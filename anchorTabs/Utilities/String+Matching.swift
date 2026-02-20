import Foundation

// Shared string helpers used for matching and compact menu labels.
extension String {
  // Normalizes case/diacritics and trims whitespace for stable comparisons.
  func normalizedForMatching() -> String {
    trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  // Truncates a string and adds an ellipsis when over the limit.
  func truncated(maxCharacters: Int) -> String {
    guard maxCharacters > 0 else { return "" }
    if count <= maxCharacters {
      return self
    }

    let endIndex = index(startIndex, offsetBy: max(0, maxCharacters - 1))
    return "\(self[..<endIndex])…"
  }
}
