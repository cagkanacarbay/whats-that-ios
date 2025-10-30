import Foundation

public enum PasswordRequirement: String, CaseIterable {
    case length
    case uppercase
    case lowercase
    case number
    case symbol
}

public struct PasswordValidationResult: Equatable {
    public let isStrong: Bool
    public let missing: [PasswordRequirement]
}

public enum PasswordValidator {
    public static func validate(_ password: String) -> PasswordValidationResult {
        var missing: [PasswordRequirement] = []

        if password.count < 8 { missing.append(.length) }
        if password.range(of: "[A-Z]", options: .regularExpression) == nil { missing.append(.uppercase) }
        if password.range(of: "[a-z]", options: .regularExpression) == nil { missing.append(.lowercase) }
        if password.range(of: "[0-9]", options: .regularExpression) == nil { missing.append(.number) }
        if password.range(of: "[^A-Za-z0-9]", options: .regularExpression) == nil { missing.append(.symbol) }

        return PasswordValidationResult(isStrong: missing.isEmpty, missing: missing)
    }

    public static func missingRequirementsMessage(for password: String) -> String? {
        let result = validate(password)
        guard result.isStrong == false else { return nil }

        var parts: [String] = []
        if result.missing.contains(.length) { parts.append("at least 8 characters") }
        if result.missing.contains(.uppercase) { parts.append("an uppercase letter") }
        if result.missing.contains(.lowercase) { parts.append("a lowercase letter") }
        if result.missing.contains(.number) { parts.append("a number") }
        if result.missing.contains(.symbol) { parts.append("a symbol") }

        if parts.isEmpty { return nil }

        let list: String
        if parts.count == 1 {
            list = parts[0]
        } else if parts.count == 2 {
            list = parts.joined(separator: " and ")
        } else {
            list = parts.dropLast().joined(separator: ", ") + ", and " + parts.last!
        }

        return "Password is not strong. It must include \(list)."
    }
}
