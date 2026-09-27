import Foundation

struct FixedAssessmentMatch: Equatable {
    let phrase: String
}

enum FixedAssessmentRecognizer {
    private static let phrases = ["summative assessment", "assessment", "midterm", "final", "exam", "test", "quiz"]
    private static let abbreviations: Set<String> = ["PA", "SA"]

    static func match(in title: String) -> FixedAssessmentMatch? {
        let normalized = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        for phrase in phrases where containsWholePhrase(phrase, in: normalized) {
            return FixedAssessmentMatch(phrase: displayName(for: phrase))
        }
        let tokens = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if let token = tokens.first(where: { abbreviations.contains($0.uppercased()) }) {
            return FixedAssessmentMatch(phrase: token.uppercased())
        }
        return nil
    }

    private static func containsWholePhrase(_ phrase: String, in value: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        guard let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])",
                                                   options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    private static func displayName(for phrase: String) -> String {
        phrase.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }
}
