import SwiftUI
import WhatsThatDomain
import WhatsThatShared
import OSLog

struct OnboardingIPoPSlide: View {
    let title: String
    let message: String
    let titleColor: Color
    let bodyColor: Color
    let containerWidth: CGFloat
    let topInset: CGFloat
    @ObservedObject var viewModel: IPoPPreferencesViewModel
    private let logger = Logger(subsystem: "com.whatsthat.onboarding", category: "OnboardingIPoPSlide")

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
            Spacer().frame(height: topInset + BrandSpacing.large)

            Text(title)
                .font(.adaptiveSystem(size: 28, weight: .bold))
                .foregroundColor(titleColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BrandSpacing.large)

            Text(message)
                .font(.adaptiveSystem(size: 17, weight: .regular))
                .foregroundColor(bodyColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BrandSpacing.large)

            VStack(alignment: .leading, spacing: 4) {
                Text("I care about…")
                    .font(.adaptiveSystem(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, BrandSpacing.large)
                    .padding(.top, BrandSpacing.large)

                IPoPPreferencesListView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Text(IPoPStrings.usageNote)
                .font(.adaptiveFootnote())
                .foregroundStyle(.secondary)
                .padding(.horizontal, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.large)
        }
        .frame(width: containerWidth, alignment: .top)
        .onAppear {
            logger.debug("IPoP slide appear; persisted=\(viewModel.persistedOrder != nil), draftCount=\(viewModel.orderedDraft.count)")
        }
    }
}
