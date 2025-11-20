import SwiftUI
import WhatsThatShared

struct BrandPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
                .overlay(alignment: .trailing) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .padding(.trailing, 16)
                    }
                }
        }
        .buttonStyle(BrandNoFadeButtonStyle())
        // Disabled uses a ghosted version of the primary green in light mode,
        // and reverts to the original darker ghost in dark mode.
        .foregroundStyle(currentForeground)
        .background(currentBackground)
        .cornerRadius(BrandCornerRadius.medium)
        .overlay {
            RoundedRectangle(cornerRadius: BrandCornerRadius.medium)
                .stroke(currentBorder, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .opacity(isLoading ? 0.7 : 1)
    }

    private var primaryBackground: Color {
        colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
    }

    // Current colors derived from state per the requested behavior
    private var currentBackground: Color {
        if isEnabled { return primaryBackground }
        // Light mode: make ghost a bit less greyed out (higher opacity)
        if colorScheme == .light { return BrandColors.Light.primaryAction.opacity(0.65) }
        // Dark mode: exactly as before (very subtle ghost)
        return BrandColors.Dark.primaryAction.opacity(0.2)
    }

    private var currentForeground: Color {
        if isEnabled { return .white }
        // Light mode: white text for clear contrast; Dark mode: revert to subtle white
        return colorScheme == .light ? Color.white : Color.white.opacity(0.6)
    }

    private var currentBorder: Color {
        if isEnabled { return primaryBackground }
        // Reuse original border ghosting across themes
        return primaryBackground.opacity(0.25)
    }
}

// Custom button style that does NOT reduce opacity when disabled.
// Keeps label fully opaque so disabled text color remains crisp.
struct BrandNoFadeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Optionally add a subtle pressed effect only
            .opacity(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct BrandSecondaryButton: View {
    let title: String
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(primaryColor)
        .background(secondaryBackground)
        .cornerRadius(BrandCornerRadius.medium)
        .contentShape(Rectangle())
        .overlay {
            RoundedRectangle(cornerRadius: BrandCornerRadius.medium)
                .stroke(borderColor, lineWidth: 1)
        }
    }

    private var primaryColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var secondaryBackground: Color {
        colorScheme == .dark ? BrandColors.Dark.secondaryAction : BrandColors.Light.secondaryAction
    }

    private var borderColor: Color {
        colorScheme == .dark ? BrandColors.Dark.border : BrandColors.Light.border
    }
}

struct BrandSocialButton: View {
    enum Kind {
        case google
        case apple

        var title: String {
            switch self {
            case .google:
                return "Continue with Google"
            case .apple:
                return "Continue with Apple"
            }
        }

        var image: Image {
            switch self {
            case .google:
                return Image("GoogleIcon")
            case .apple:
                return Image("AppleIcon")
            }
        }
    }

    let kind: Kind
    var isDisabled: Bool = false
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                kind.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text(kind.title)
                    .fontWeight(.medium)
                Spacer()
            }
            .frame(maxWidth: .infinity) // Ensure full-width tappable content
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle()) // Make the entire visual area clickable
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .foregroundStyle(colorScheme == .dark ? Color.white : BrandColors.Light.accentText)
        .background(socialBackground)
        .cornerRadius(BrandCornerRadius.medium)
        .overlay {
            RoundedRectangle(cornerRadius: BrandCornerRadius.medium)
                .stroke(borderColor, lineWidth: 1)
        }
        .opacity(isDisabled ? 0.5 : 1)
        .disabled(isDisabled)
    }

    private var socialBackground: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }

    private var borderColor: Color {
        colorScheme == .dark ? BrandColors.Dark.border : BrandColors.Light.border
    }
}

struct BrandFloatingField: View {
    enum FieldType {
        case email
        case password(showToggle: Bool)
        case plain
    }

    let title: String
    var placeholder: String = ""
    @Binding var text: String
    var fieldType: FieldType = .plain
    var errorText: String?
    // Optional focus binding so parents can control focus and show validation on blur
    var focus: FocusState<Bool>.Binding? = nil

    @State private var isSecure: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    private var borderColor: Color {
        if let errorText, !errorText.isEmpty {
            return Color.red.opacity(0.8)
        }
        return colorScheme == .dark ? BrandColors.Dark.border : BrandColors.Light.border
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: BrandCornerRadius.medium)
                    .stroke(borderColor, lineWidth: 1)
                    .background((colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background).cornerRadius(BrandCornerRadius.medium))
                    .frame(height: 52)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(labelColor)
                    .padding(.horizontal, 10)
                    .background(colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background)
                    .offset(y: -26)

                HStack {
                    inputField
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                }
            }

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .accessibilityIdentifier("field.error.\(title)")
            }
        }
        .onAppear {
            if case .password = fieldType {
                isSecure = true
            }
        }
        // Keep targeted animation opt-outs for validation and typing without
        // suppressing parent layout animations (e.g., keyboard-driven moves)
        .animation(nil, value: errorText)
        .animation(nil, value: text)
    }

    private var labelColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText.opacity(0.7)
    }

    @ViewBuilder
    private var inputField: some View {
        switch fieldType {
        case .password(let showToggle):
            HStack {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .applyFocus(focus)
                } else {
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .applyFocus(focus)
                }

                if showToggle {
                    Button {
                        isSecure.toggle()
                    } label: {
                        Image(systemName: isSecure ? "eye.slash" : "eye")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(labelColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .email:
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.emailAddress)
                .applyFocus(focus)
        case .plain:
            TextField(placeholder, text: $text)
                .applyFocus(focus)
        }
    }
}

private extension View {
    @ViewBuilder
    func applyFocus(_ binding: FocusState<Bool>.Binding?) -> some View {
        if let binding {
            self.focused(binding)
        } else {
            self
        }
    }
}
