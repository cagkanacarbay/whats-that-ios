import SwiftUI
import WhatsThatShared

struct DiscoveryOverlayButton: View {
    let systemName: String
    let action: () -> Void
    var rotation: Angle = .zero
    var accessibilityLabel: String? = nil
    var isDisabled: Bool = false

    private let buttonSize: CGFloat = 48
    private let iconSize: CGFloat = 20
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(palette.overlayButtonBackground)
                .frame(width: buttonSize, height: buttonSize)
                .overlay {
                    Image(systemName: systemName)
                        .font(.system(size: iconSize, weight: .semibold))
                        .rotationEffect(rotation)
                        .foregroundStyle(palette.overlayButtonForeground)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1)
        .shadow(
            color: Color.black.opacity(palette.overlayButtonShadowOpacity),
            radius: 8,
            x: 0,
            y: 4
        )
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }
}

struct DiscoveryDetailOptionsSheet: View {
    @Binding var isPresented: Bool
    let isDeleting: Bool
    let onDelete: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDeleteConfirmation = false
    private let sheetCornerRadius: CGFloat = 24
    private let sheetWidth: CGFloat = 320

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    guard !isDeleting else { return }
                    isPresented = false
                }

            VStack(spacing: BrandSpacing.large * 0.5) {
                Text("More Options")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)

                VStack(spacing: BrandSpacing.medium) {
                    destructiveButton
                    cancelButton
                }
            }
            .padding(.vertical, BrandSpacing.large)
            .padding(.horizontal, BrandSpacing.large)
            .frame(maxWidth: sheetWidth)
            .background(
                RoundedRectangle(cornerRadius: sheetCornerRadius, style: .continuous)
                    .fill(sheetBackground)
                    .shadow(color: Color.black.opacity(0.25), radius: 28, x: 0, y: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: sheetCornerRadius, style: .continuous)
                    .stroke(BrandColors.Light.tabSelected.opacity(0.3), lineWidth: 1.5)
            }
            .padding(.horizontal, BrandSpacing.large)
        }
        .transition(.scale.combined(with: .opacity))
        .alert("Delete Discovery?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("All data related to this discovery will be permanently deleted and cannot be recovered.")
        }
    }

    private var destructiveButton: some View {
        let isDisabled = onDelete == nil || isDeleting

        return Button {
            guard !isDisabled else { return }
            showDeleteConfirmation = true
        } label: {
            ZStack {
                Text(isDeleting ? "Deleting…" : "Delete")
                    .font(.system(size: 16, weight: .semibold))

                HStack(spacing: BrandSpacing.small) {
                    Image(systemName: "trash.fill")
                    Spacer()
                    if isDeleting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(deleteForeground)
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.medium)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(deleteForeground)
        .background(deleteBackground)
        .cornerRadius(BrandCornerRadius.medium)
        .overlay {
            RoundedRectangle(cornerRadius: BrandCornerRadius.medium, style: .continuous)
                .stroke(deleteBorder, lineWidth: 1.5)
        }
        .opacity(isDisabled ? 0.5 : 1)
        .disabled(isDisabled)
    }

    private var cancelButton: some View {
        Button {
            guard !isDeleting else { return }
            isPresented = false
        } label: {
            Text("Cancel")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, BrandSpacing.medium)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.textPrimary)
        .background(cancelBackground)
        .cornerRadius(BrandCornerRadius.medium)
        .overlay {
            RoundedRectangle(cornerRadius: BrandCornerRadius.medium, style: .continuous)
                .stroke(cancelBorder, lineWidth: 1.5)
        }
        .disabled(isDeleting)
        .opacity(isDeleting ? 0.6 : 1)
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    private var sheetBackground: Color {
        palette.surface
    }

    private var deleteBackground: Color {
        Color.red.opacity(0.12)
    }

    private var deleteBorder: Color {
        Color.red.opacity(0.3)
    }

    private var deleteForeground: Color {
        Color.red
    }

    private var cancelBackground: Color {
        palette.secondaryAction.opacity(0.3)
    }

    private var cancelBorder: Color {
        palette.border.opacity(0.5)
    }
}

