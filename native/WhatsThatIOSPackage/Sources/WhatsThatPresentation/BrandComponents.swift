import SwiftUI
import WhatsThatShared

struct BrandPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(title)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
        .background(primaryBackground)
        .cornerRadius(BrandCornerRadius.medium)
        .overlay {
            RoundedRectangle(cornerRadius: BrandCornerRadius.medium)
                .stroke(primaryBackground, lineWidth: 1)
        }
        .opacity(isLoading ? 0.7 : 1)
    }

    private var primaryBackground: Color {
        colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
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
        }
        .buttonStyle(.plain)
        .foregroundStyle(primaryColor)
        .background(secondaryBackground)
        .cornerRadius(BrandCornerRadius.medium)
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
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
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

                Text(title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
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
                } else {
#if os(iOS)
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
#else
                    TextField(placeholder, text: $text)
                        .autocorrectionDisabled(true)
#endif
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
#if os(iOS)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.emailAddress)
#else
            TextField(placeholder, text: $text)
                .autocorrectionDisabled(true)
#endif
        case .plain:
            TextField(placeholder, text: $text)
        }
    }
}
