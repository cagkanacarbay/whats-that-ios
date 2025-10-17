import Foundation

public enum DiscoveryStreamFormatter {
    private static let userResponseDelimiter = "=== USER RESPONSE ==="
    private static let confidencePrefix = "confidence level"
    private static let metadataHeadingRegex = try? NSRegularExpression(
        pattern: #"###\s*metadata_json"#,
        options: [.caseInsensitive]
    )

    public static func narrative(from source: String) -> String {
        guard !source.isEmpty else { return "" }

        var working = source

        if let delimiterRange = working.range(of: userResponseDelimiter) {
            let afterDelimiter = working[delimiterRange.upperBound...]
            working = String(afterDelimiter).trimmingCharacters(in: .whitespacesAndNewlines)

            if working.lowercased().hasPrefix(confidencePrefix) {
                if let newlineIndex = working.firstIndex(of: "\n") {
                    let trimmed = working[newlineIndex...].dropFirst()
                    working = String(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    working = ""
                }
            }
        }

        working = removeMetadataSection(from: working)
        working = working.trimmingCharacters(in: .whitespacesAndNewlines)

        if let headingRange = working.range(of: #"##\s+"#, options: .regularExpression) {
            working = String(working[headingRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return working.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func visibleLength(for text: String) -> Int {
        narrative(from: text).trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private static func removeMetadataSection(from source: String) -> String {
        guard
            let regex = metadataHeadingRegex,
            let match = regex.firstMatch(
                in: source,
                options: [],
                range: NSRange(location: 0, length: source.utf16.count)
            ),
            let headingRange = Range(match.range, in: source)
        else {
            return source
        }

        if let jsonRange = findJsonBounds(in: source, startingAt: headingRange.upperBound) {
            var mutable = source
            mutable.removeSubrange(headingRange.lowerBound..<jsonRange.upperBound)
            return mutable
        } else {
            var mutable = source
            mutable.removeSubrange(headingRange.lowerBound..<mutable.endIndex)
            return mutable
        }
    }

    private static func findJsonBounds(in source: String, startingAt startIndex: String.Index) -> Range<String.Index>? {
        guard let start = source[startIndex...].firstIndex(of: "{") else {
            return nil
        }

        var index = start
        var depth = 0

        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let end = source.index(after: index)
                    return start..<end
                }
            }

            index = source.index(after: index)
        }

        return nil
    }
}
