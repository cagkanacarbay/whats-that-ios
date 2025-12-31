import SwiftUI
import WhatsThatShared

/// A toggle component for enabling/disabling audio guide generation on the confirmation page.
/// Styled to match the autoplay toggle in AudioGuidesPageView.
struct AudioToggleView: View {
    @Binding var isOn: Bool
    let palette: DiscoveryCreationPalette
    
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .subheadline) private var popoverMaxWidth: CGFloat = 300
    @State private var showInfoPopover: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Audio label + Info button combined
            Button {
                showInfoPopover = true
            } label: {
                HStack(spacing: 4) {
                    Text("Audio")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        // Use textSecondary matching the icon's color logic or keep somewhat distinct?
                        // User wants "Audio text a part of that info system".
                        // Usually distinct colors for text vs icon are fine, but let's keep them consistent with previous style.
                        .foregroundColor(palette.textSecondary)
                    
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(palette.textSecondary.opacity(0.8))
                }
            }
            .buttonStyle(.plain) // Ensure it doesn't look like a standard button with background
            .popover(isPresented: $showInfoPopover, arrowEdge: .bottom) {
                infoPopoverContent
            }
            
            // Toggle styled like AudioGuidesPageView autoplay
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: BrandColors.logo))
        }
    }
    
    private var infoPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Guide")
                .font(.headline)
                .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
            
            Text("This option will generate an audio guide after the discovery is made.")
                .font(.subheadline)
                .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundColor(BrandColors.logo)
                
                Text("Costs 1 credit")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(BrandColors.logo)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(maxWidth: popoverMaxWidth)
        .presentationCompactAdaptation(.popover)
    }
}
