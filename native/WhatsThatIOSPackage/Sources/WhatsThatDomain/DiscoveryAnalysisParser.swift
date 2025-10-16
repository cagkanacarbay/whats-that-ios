import Foundation

public struct DiscoveryAnalysisContent: Equatable, Sendable {
    public struct Metadata: Equatable, Sendable {
        public let title: String?
        public let shortDescription: String?
    }

    public let markdown: String
    public let metadata: Metadata?
}

public struct DiscoveryAnalysisParser: Sendable {
    private static let userResponseDelimiter = "=== USER RESPONSE ==="
    private static let confidencePrefix = "confidence level"
    private static let metadataHeadingPattern = #"###\s*metadata_json"#

    private let metadataHeadingRegex: NSRegularExpression?

    public init() {
        metadataHeadingRegex = try? NSRegularExpression(
            pattern: Self.metadataHeadingPattern,
            options: [.caseInsensitive]
        )
    }

    public func parse(_ source: String) -> DiscoveryAnalysisContent? {
        guard !source.isEmpty else {
            return nil
        }

        var working = source

        if let delimiterRange = working.range(of: Self.userResponseDelimiter) {
            let afterDelimiter = working[delimiterRange.upperBound...]
            working = String(afterDelimiter).trimmingCharacters(in: .whitespacesAndNewlines)

            if working.lowercased().hasPrefix(Self.confidencePrefix) {
                if let newlineIndex = working.firstIndex(of: "\n") {
                    let trimmed = working[newlineIndex...].dropFirst()
                    working = String(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    working = ""
                }
            }
        }

        let metadataResult = extractMetadata(from: &working)
        working = working.trimmingCharacters(in: .whitespacesAndNewlines)

        if let headingRange = working.range(of: #"##\s+"#, options: .regularExpression) {
            working = String(working[headingRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !working.isEmpty || metadataResult != nil else {
            return nil
        }

        return DiscoveryAnalysisContent(
            markdown: working,
            metadata: metadataResult
        )
    }

    private func extractMetadata(from working: inout String) -> DiscoveryAnalysisContent.Metadata? {
        guard
            let regex = metadataHeadingRegex,
            let match = regex.firstMatch(
                in: working,
                options: [],
                range: NSRange(location: 0, length: working.utf16.count)
            ),
            let headingRange = Range(match.range, in: working)
        else {
            return nil
        }

        guard let jsonRange = jsonBounds(in: working, searchStart: headingRange.upperBound) else {
            working.removeSubrange(headingRange)
            return nil
        }

        let jsonSubstring = working[jsonRange]
        working.removeSubrange(headingRange.lowerBound..<jsonRange.upperBound)

        guard
            let data = jsonSubstring.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let dictionary = object as? [String: Any]
        else {
            return nil
        }

        let title = dictionary["title"].flatMap(Self.stringValue)
        let shortDescription =
            dictionary["shortDescription"].flatMap(Self.stringValue)
            ?? dictionary["short_description"].flatMap(Self.stringValue)

        if title == nil, shortDescription == nil {
            return nil
        }

        return DiscoveryAnalysisContent.Metadata(
            title: title,
            shortDescription: shortDescription
        )
    }

    private func jsonBounds(in source: String, searchStart: String.Index) -> Range<String.Index>? {
        guard let start = source[searchStart...].firstIndex(of: "{") else {
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

    private static func stringValue(from value: Any) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
}
