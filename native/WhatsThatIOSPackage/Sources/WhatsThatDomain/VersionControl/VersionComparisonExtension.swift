import Foundation

public extension String {
    /// Compares semantic versions. Returns true if self < other.
    /// Examples: "1.2.0".isVersionLessThan("1.10.0") → true
    ///           "2.0.0".isVersionLessThan("1.9.0") → false
    ///           "1.0".isVersionLessThan("1.0.0") → false (equal after padding)
    func isVersionLessThan(_ other: String) -> Bool {
        let v1Components = self.split(separator: ".").compactMap { Int($0) }
        let v2Components = other.split(separator: ".").compactMap { Int($0) }

        // Pad shorter array with zeros for comparison
        let maxLength = max(v1Components.count, v2Components.count)
        let v1Padded = v1Components + Array(repeating: 0, count: maxLength - v1Components.count)
        let v2Padded = v2Components + Array(repeating: 0, count: maxLength - v2Components.count)

        for i in 0..<maxLength {
            if v1Padded[i] < v2Padded[i] { return true }
            if v1Padded[i] > v2Padded[i] { return false }
        }
        return false // Equal versions
    }

    /// Compares semantic versions. Returns true if self > other.
    func isVersionGreaterThan(_ other: String) -> Bool {
        other.isVersionLessThan(self)
    }

    /// Compares semantic versions. Returns true if self == other.
    func isVersionEqualTo(_ other: String) -> Bool {
        !isVersionLessThan(other) && !isVersionGreaterThan(other)
    }
}
