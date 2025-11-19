import SwiftUI
import UIKit

struct ShimmerTextView: View {
    let text: String
    let availableWidth: CGFloat
    let color: Color
    let isActive: Bool
    var logger: ((String) -> Void)? = nil
    var onFinished: (() -> Void)? = nil

    init(
        text: String,
        availableWidth: CGFloat,
        color: Color,
        isActive: Bool = true,
        logger: ((String) -> Void)? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        self.text = text
        self.availableWidth = availableWidth
        self.color = color
        self.isActive = isActive
        self.logger = logger
        self.onFinished = onFinished
    }

    // Tunables
    private let fontSize: CGFloat = 30
    private let passDuration: Double = 1.0   // seconds for one shimmer pass
    private let startDelay: Double = 0.2     // delay before starting shimmer after text changes
    private let highlightWidthRatio: CGFloat = 0.42 // fraction of availableWidth

    @Environment(\.colorScheme) private var colorScheme
    @State private var notified = false

    @State private var progress: CGFloat = 0
    @State private var lastAnimatedText: String = ""

    var body: some View {
        Group {
            if isActive {
                shimmeringBody
            } else {
                staticBody
            }
        }
    }

    private var shimmeringBody: some View {
        let scale = scaleFactor(for: availableWidth)
        let width = max(availableWidth, 1)
        let stripeWidth = max(80, min(width * highlightWidthRatio, 220))
        let travel = width + stripeWidth
        let xOffset = -stripeWidth/2 + Double(progress) * travel - (travel - width)/2

        let highlightPalette = ShimmerHighlightPalette.palette(
            for: color,
            fallbackScheme: colorScheme
        )
        return ShimmerFrameView(
            text: text,
            color: color,
            highlightPalette: highlightPalette,
            fontSize: fontSize,
            scale: scale,
            stripeWidth: stripeWidth,
            xOffset: xOffset
        )
        .compositingGroup()
        .onAppear {
            triggerShimmerIfNeeded(for: text)
        }
        .onChange(of: text) { _, newValue in
            triggerShimmerIfNeeded(for: newValue)
        }
        .onDisappear {
            stopShimmer()
        }
    }

    private var staticBody: some View {
        let scale = scaleFactor(for: availableWidth)
        return Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(color)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .scaleEffect(scale, anchor: .center)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    private func triggerShimmerIfNeeded(for newText: String) {
        guard isActive else { return }
        guard lastAnimatedText != newText else {
            log("startShimmer skipped text=\"\(newText)\" (unchanged)")
            return
        }
        lastAnimatedText = newText
        log("startShimmer text=\"\(newText)\" availableWidth=\(availableWidth)")
        startShimmerAnimation()
    }

    private func startShimmerAnimation() {
        notified = false
        withAnimation(.none) {
            progress = 0
        }
        let animation = Animation.linear(duration: passDuration)

        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
            withAnimation(animation) {
                progress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay + passDuration) {
            if !notified {
                notified = true
                log("shimmerCompleted text=\"\(text)\" notifying=true")
                onFinished?()
            } else {
                log("shimmerCompleted text=\"\(text)\" notifying=false (already notified)")
            }
        }
    }

    private func stopShimmer() {
        withAnimation(.none) {
            progress = 0
        }
    }

    private func log(_ message: String) {
        guard let logger else { return }
        logger("[ShimmerTextView] \(message)")
    }

    private struct ShimmerHighlightPalette {
        let textHighlight: Color
        let beamEdge: Color
        let beamFeather: Color
        let beamCore: Color

        static func palette(for textColor: Color, fallbackScheme scheme: ColorScheme) -> ShimmerHighlightPalette {
            if let brightness = perceivedBrightness(for: textColor) {
                if brightness > 0.8 {
                    // Very bright text (typically on darker backgrounds) gets a cooler glint.
                    return .silvery
                } else if brightness < 0.35, scheme == .light {
                    // Dark lettering on light backgrounds gets a stronger white-hot beam.
                    return .whiteHot
                }
            }

            // Fall back to a mode-based default so shimmer stays obvious in both themes.
            return scheme == .dark ? .whiteHot : .silvery
        }

        // Keep the shimmer white-hot against darker text so it pops instantly.
        static let whiteHot = ShimmerHighlightPalette(
            textHighlight: Color.white,
            beamEdge: Color.white.opacity(0.0),
            beamFeather: Color.white.opacity(0.7),
            beamCore: Color.white
        )

        // Cool-toned glint maintains contrast against already-bright lettering.
        static let silvery = ShimmerHighlightPalette(
            textHighlight: Color(red: 0.9, green: 0.96, blue: 1.0),
            beamEdge: Color(red: 0.56, green: 0.72, blue: 0.96).opacity(0.0),
            beamFeather: Color(red: 0.66, green: 0.8, blue: 1.0).opacity(0.8),
            beamCore: Color(red: 0.96, green: 0.99, blue: 1.0)
        )

        private static func perceivedBrightness(for color: Color) -> CGFloat? {
            let uiColor = UIColor(color)

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                return (0.299 * red) + (0.587 * green) + (0.114 * blue)
            }

            var white: CGFloat = 0
            if uiColor.getWhite(&white, alpha: &alpha) {
                return white
            }

            return nil
        }
    }

    private struct ShimmerStripe: View {
        let width: CGFloat
        let height: CGFloat
        let xOffset: CGFloat
        let palette: ShimmerHighlightPalette

        var body: some View {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: palette.beamEdge, location: 0.0),
                    .init(color: palette.beamFeather, location: 0.18),
                    .init(color: palette.beamCore, location: 0.5),
                    .init(color: palette.beamFeather, location: 0.82),
                    .init(color: palette.beamEdge, location: 1.0)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width, height: height)
            .offset(x: xOffset)
            .blur(radius: 8)
        }
    }

    private struct ShimmerFrameView: View {
        let text: String
        let color: Color
        let highlightPalette: ShimmerHighlightPalette
        let fontSize: CGFloat
        let scale: CGFloat
        let stripeWidth: CGFloat
        let xOffset: CGFloat

        var body: some View {
            let textLayer = Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .allowsHitTesting(false)

            return textLayer
                .foregroundStyle(color.opacity(0.68))
                .overlay {
                    textLayer
                        .foregroundStyle(color)
                        .opacity(0.94)
                }
                .overlay {
                    textLayer
                        .foregroundStyle(highlightPalette.textHighlight)
                        .mask(
                            ShimmerStripe(
                                width: stripeWidth,
                                height: fontSize * 2.8,
                                xOffset: xOffset,
                                palette: highlightPalette
                            )
                        )
                        .blendMode(.screen)
                        .shadow(color: highlightPalette.beamCore.opacity(0.7), radius: 10, x: 0, y: 0)
                        .shadow(color: highlightPalette.beamFeather.opacity(0.5), radius: 20, x: 0, y: 0)
                }
                .scaleEffect(scale, anchor: .center)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private func scaleFactor(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        guard textWidth > 0 else { return 1 }
        if textWidth <= width { return 1 }
        let adjusted = max(width - 12, 0)
        if adjusted <= 0 { return 0.65 }
        let scaled = adjusted / textWidth
        return max(0.65, scaled)
    }
}
