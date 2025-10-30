import Foundation

enum EmailValidator {
    private static let regex: NSRegularExpression = {
        // Basic sanity pattern; fast to evaluate and compiled once
        let pattern = "[^\\s@]+@[^\\s@]+\\.[^\\s@]+"
        return try! NSRegularExpression(pattern: pattern)
    }()

    static func isValid(_ email: String) -> Bool {
        guard !email.isEmpty else { return false }
        let range = NSRange(location: 0, length: email.utf16.count)
        return regex.firstMatch(in: email, options: [], range: range) != nil
    }
}

