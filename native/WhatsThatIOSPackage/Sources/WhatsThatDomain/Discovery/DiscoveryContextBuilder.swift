import Foundation

public struct DiscoveryContextBuilder: Sendable {
    public init() {}

    public func buildContext(
        from discoveries: [DiscoverySummary],
        limit: Int = 25,
        ipopPreferences: IPoPPreferences? = nil,
        imageSource: String? = nil
    ) -> String? {
        guard !discoveries.isEmpty || ipopPreferences != nil || imageSource != nil else { return nil }

        let sorted = discoveries.sorted(by: { $0.capturedAt > $1.capturedAt })
        let truncated = Array(sorted.prefix(limit))

        let recentSection = buildRecentSection(from: Array(truncated.prefix(3)))
        let historySection = buildHistorySection(from: Array(truncated.dropFirst(3)))

        let payload = DiscoveryContextPayload(
            recentFullDiscoveries: recentSection,
            aggregatedHistory: historySection,
            ipopPreferences: ipopPreferences,
            imageSource: imageSource
        )

        guard let data = try? JSONEncoder().encode(payload) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func buildRecentSection(from discoveries: [DiscoverySummary]) -> String {
        guard !discoveries.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("User's last 3 discoveries (most recent first):")

        for (index, discovery) in discoveries.enumerated() {
            let location = makeLocationString(from: discovery)
            let timeLabel = self.relativeDateString(for: discovery.capturedAt)
            let narrative = discovery.detailDescription ?? discovery.shortDescription ?? discovery.highlight

            lines.append("\n\(index + 1). \"\(discovery.title)\" - \(location), \(timeLabel)")
            lines.append("The quoted text below is the user's previous discovery in its entirety:")
            lines.append("\"\"\"\n\(narrative)\n\"\"\"")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func relativeDateString(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "today"
        }
        if calendar.isDateInYesterday(date) {
            return "yesterday"
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full

        let now = Date()
        if let formatted = formatter.string(from: date, to: now), !formatted.isEmpty {
            return "\(formatted) ago"
        }

        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateStyle = .medium
        return fallbackFormatter.string(from: date)
    }

    private func buildHistorySection(from discoveries: [DiscoverySummary]) -> String {
        guard !discoveries.isEmpty else { return "" }

        let grouped = Dictionary(grouping: discoveries) { summary -> HistoryGroupKey in
            let relative = self.relativeInfo(for: summary.capturedAt)
            let location = self.makeLocationString(from: summary)
            return HistoryGroupKey(date: relative.label, location: location, sortOrder: relative.order)
        }

        var lines: [String] = []
        lines.append("User's discovery history (\(discoveries.count) discoveries):")

        for key in grouped.keys.sorted(by: { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.location.localizedCaseInsensitiveCompare(rhs.location) == .orderedAscending
        }) {
            guard let items = grouped[key] else { continue }
            let titles = items.map { "\"\($0.title)\"" }.joined(separator: ", ")
            if items.count == 1 {
                lines.append("- \(key.date) in \(key.location): \(titles)")
            } else {
                lines.append("- \(key.date) in \(key.location) (\(items.count)): \(titles)")
            }
        }

        let uniqueLocations = Set(discoveries.map { makeLocationString(from: $0) })
        lines.append("\nTotal: \(discoveries.count) discoveries across \(uniqueLocations.count) locations.")

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func relativeInfo(for date: Date) -> (label: String, order: Int) {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return ("today", 0)
        }
        if calendar.isDateInYesterday(date) {
            return ("yesterday", 1)
        }

        let components = calendar.dateComponents([.day], from: date, to: Date())
        if let days = components.day, days < 7 {
            return ("\(days) days ago", days)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let label = formatter.string(from: date)
        let days = components.day ?? 30
        return (label, days)
    }

    private func makeLocationString(from summary: DiscoverySummary) -> String {
        if let closest = summary.location?.closestPlace, !closest.isEmpty {
            return closest
        }
        if let locality = summary.location?.locality, let country = summary.location?.country {
            return "\(locality), \(country)"
        }
        if let country = summary.location?.country {
            return country
        }
        if let latitude = summary.location?.latitude, let longitude = summary.location?.longitude {
            return String(format: "%.4f, %.4f", latitude, longitude)
        }
        return "Unknown location"
    }
}

private struct DiscoveryContextPayload: Codable {
    let recentFullDiscoveries: String
    let aggregatedHistory: String
    let ipopPreferences: IPoPPreferences?
    let imageSource: String?
}

private struct HistoryGroupKey: Hashable {
    let date: String
    let location: String
    let sortOrder: Int
}
