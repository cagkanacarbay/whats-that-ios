import SwiftUI
import WhatsThatDomain
import WhatsThatShared

public struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: CreditsViewModel
    private let backButtonTitle: String
    private let onClose: (() -> Void)?

    public init(
        viewModel: CreditsViewModel,
        backButtonTitle: String = "Back",
        onClose: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.backButtonTitle = backButtonTitle
        self.onClose = onClose
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: BrandSpacing.medium) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        balanceCard
                        packSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 80)
                    .padding(.top, BrandSpacing.small)
                }
            }

            if let toast = viewModel.toastMessage {
                toastBanner(toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.load()
        }
        .alert(item: $viewModel.alertContent) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: viewModel.toastMessage?.id) { _, id in
            guard id != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run {
                    if viewModel.toastMessage?.id == id {
                        withAnimation(.easeInOut) {
                            viewModel.toastMessage = nil
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.small) {
            HStack {
                Button {
                    close()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(backButtonTitle)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                }

                Spacer()
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.top, BrandSpacing.large)

            Text("Credits")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, BrandSpacing.large)
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                palette.background,
                palette.background.opacity(0.92),
                palette.background
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(palette.primaryAction.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(palette.primaryAction)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Current balance")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.textSecondary)

                    if let balance = viewModel.balance {
                        HStack(spacing: 8) {
                            Text("\(balance) credits")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                            if viewModel.isRefreshingBalance {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                        }
                    
                    } else {
                        HStack(spacing: 6) {
                            ProgressView()
                                .progressViewStyle(.circular)
                            Text("Loading…")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                        }
                    }
                }
                Spacer()
            }

            Button {
                Task { await viewModel.refreshBalance() }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh balance")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.primaryAction)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(
                    Capsule()
                        .fill(palette.primaryAction.opacity(0.12))
                )
            }
            .disabled(viewModel.isLoading || viewModel.isFetchingProducts)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.surface)
                .shadow(color: Color.black.opacity(0.08), radius: 30, x: 0, y: 20)
        )
    }

    private var packSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Available packs")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)

                Spacer()

                if viewModel.isFetchingProducts {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }

            VStack(spacing: 16) {
                ForEach(viewModel.creditPacks) { pack in
                    CreditPackCard(
                        pack: pack,
                        isLoading: viewModel.isPurchasing && viewModel.activePurchaseIdentifier == pack.id,
                        action: {
                            Task { await viewModel.purchase(pack) }
                        },
                        theme: palette
                    )
                }
            }
        }
    }

    private func toastBanner(_ toast: CreditsViewModel.ToastMessage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: toastIcon(for: toast.style))
                .font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(toast.message)
                    .font(.system(size: 13, weight: .medium))
            }
            .multilineTextAlignment(.leading)
        }
        .foregroundStyle(Color.white)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(toastGradient(for: toast.style))
                .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 12)
        )
    }

    private func toastIcon(for style: CreditsViewModel.ToastMessage.Style) -> String {
        switch style {
        case .success:
            return "checkmark.circle.fill"
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    private func toastGradient(for style: CreditsViewModel.ToastMessage.Style) -> LinearGradient {
        switch style {
        case .success:
            return LinearGradient(
                gradient: Gradient(colors: [Color.green.opacity(0.92), Color.green]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .info:
            return LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.95), Color.blue]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .warning:
            return LinearGradient(
                gradient: Gradient(colors: [Color.orange.opacity(0.95), Color.orange]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct CreditPackCard: View {
    let pack: CreditsViewModel.CreditPackItem
    let isLoading: Bool
    let action: () -> Void
    let theme: BrandTheme.Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: pack.iconSystemName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(theme.primaryAction)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(theme.primaryAction.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(pack.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(pack.description)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.price)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("\(pack.creditAmount) credits")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer()

                Button(action: action) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.white)
                            .frame(width: 20, height: 20)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 24)
                    } else {
                        Text(pack.isAvailable ? "Buy now" : "Unavailable")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 24)
                            .frame(minWidth: 120)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .background(
                    Capsule()
                        .fill(pack.isAvailable ? theme.primaryAction : theme.primaryAction.opacity(0.4))
                )
                .disabled(isLoading || !pack.isAvailable)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(theme.surface)
                .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 12)
        )
    }
}
