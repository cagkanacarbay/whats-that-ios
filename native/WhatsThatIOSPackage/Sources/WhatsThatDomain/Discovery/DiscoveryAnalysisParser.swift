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
    private static let metadataHeadingPattern = #"^\s*(?:#{1,6}\s*)?metadata_json\b[:\-]?"#

    private let metadataHeadingRegex: NSRegularExpression?

    public init() {
        metadataHeadingRegex = try? NSRegularExpression(
            pattern: Self.metadataHeadingPattern,
            options: [.caseInsensitive, .anchorsMatchLines]
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

        var metadataResult = extractMetadata(from: &working)
        // If no explicit metadata section was found, attempt an inline JSON extraction.
        if metadataResult == nil {
            metadataResult = extractInlineMetadata(from: &working)
        }
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

        if
            let data = jsonSubstring.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let dictionary = object as? [String: Any]
        {
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

        // Fallback: attempt to extract string fields even if other values are invalid JSON.
        if let fallback = fallbackMetadata(from: jsonSubstring) {
            return fallback
        }

        return nil
    }

    // Some streams may emit the metadata JSON early without the `metadata_json` heading.
    // This fallback scans for a JSON object that contains `title` and/or `shortDescription`
    // and removes it from the working string while returning the parsed fields.
    private func extractInlineMetadata(from working: inout String) -> DiscoveryAnalysisContent.Metadata? {
        guard let jsonRange = inlineMetadataJSONRange(in: working) else {
            return nil
        }

        let jsonSubstring = working[jsonRange]

        // Remove JSON from the narrative body, also trim any trailing comma and whitespace.
        var removalEnd = jsonRange.upperBound
        if removalEnd < working.endIndex, working[removalEnd] == "," {
            removalEnd = working.index(after: removalEnd)
        }
        working.removeSubrange(jsonRange.lowerBound..<removalEnd)

        // Parse into dictionary and extract fields.
        if let data = String(jsonSubstring).data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: []),
           let dictionary = object as? [String: Any] {
            let title = dictionary["title"].flatMap(Self.stringValue)
            let short =
                dictionary["shortDescription"].flatMap(Self.stringValue)
                ?? dictionary["short_description"].flatMap(Self.stringValue)

            if title == nil, short == nil { return nil }
            return DiscoveryAnalysisContent.Metadata(title: title, shortDescription: short)
        }

        // Best-effort fallback for partially-streamed JSON content.
        if let fallback = fallbackMetadata(from: jsonSubstring) {
            return fallback
        }
        return nil
    }

    private func inlineMetadataJSONRange(in source: String) -> Range<String.Index>? {
        // Find likely metadata keys first
        let candidates = ["\"title\"", "\"shortDescription\"", "\"short_description\""]
        guard let keyRange = candidates
            .compactMap({ source.range(of: $0) })
            .sorted(by: { $0.lowerBound < $1.lowerBound })
            .first
        else {
            return nil
        }

        // Walk backwards from key to the nearest '{'
        guard let openBrace = source[..<keyRange.lowerBound].lastIndex(of: "{") else {
            return nil
        }
        return jsonBounds(in: source, searchStart: openBrace)
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

    private func fallbackMetadata(from json: Substring) -> DiscoveryAnalysisContent.Metadata? {
        let source = String(json)
        let title = captureString(for: "title", in: source)
        let short =
            captureString(for: "shortDescription", in: source)
            ?? captureString(for: "short_description", in: source)

        if title == nil, short == nil {
            return nil
        }

        return DiscoveryAnalysisContent.Metadata(
            title: title,
            shortDescription: short
        )
    }

    private func captureString(for key: String, in source: String) -> String? {
        let pattern = #"\"\#(key)\"\s*:\s*\"((?:\\.|[^"\\])*)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(location: 0, length: (source as NSString).length)
        guard
            let match = regex.firstMatch(in: source, options: [], range: range),
            match.numberOfRanges >= 3
        else {
            return nil
        }

        let captured = (source as NSString).substring(with: match.range(at: 2))
        let wrapped = "\"\(captured)\""
        guard let data = wrapped.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data, options: []) as? String
        else {
            return nil
        }

        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
