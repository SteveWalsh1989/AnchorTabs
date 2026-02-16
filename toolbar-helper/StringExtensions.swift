import Foundation

extension String {
  func normalizedForMatching() -> String {
    trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  func truncated(maxCharacters: Int) -> String {
    guard maxCharacters > 0 else { return "" }
    if count <= maxCharacters {
      return self
    }

    let endIndex = index(startIndex, offsetBy: max(0, maxCharacters - 1))
    return "\(self[..<endIndex])…"
  }
}
