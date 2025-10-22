import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    private let passDuration: Double = 2.0  // seconds for one shimmer pass (slower)
    private let highlightWidthRatio: CGFloat = 0.22 // fraction of availableWidth

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
        let stripeWidth = max(60, min(width * highlightWidthRatio, 160))
        let travel = width + stripeWidth
        let xOffset = -stripeWidth/2 + Double(progress) * travel - (travel - width)/2

        let highlight = (colorScheme == .dark) ? Color.white.opacity(0.9) : Color.white
        return ShimmerFrameView(
            text: text,
            color: color,
            highlightColor: highlight,
            fontSize: fontSize,
            scale: scale,
            stripeWidth: stripeWidth,
            xOffset: xOffset
        )
        .compositingGroup()
        .onAppear {
            triggerShimmerIfNeeded(for: text)
        }
        .onChange(of: text) { newValue in
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
        let animation = Animation
            .linear(duration: passDuration)
            .repeatForever(autoreverses: false)
        withAnimation(animation) {
            progress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + passDuration) {
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

    private struct ShimmerStripe: View {
        let width: CGFloat
        let height: CGFloat
        let xOffset: CGFloat

        var body: some View {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .white.opacity(0.12), location: 0.28),
                    .init(color: .white, location: 0.5),
                    .init(color: .white.opacity(0.12), location: 0.72),
                    .init(color: .clear, location: 1.0)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width, height: height)
            .offset(x: xOffset)
        }
    }

    private struct ShimmerFrameView: View {
        let text: String
        let color: Color
        let highlightColor: Color
        let fontSize: CGFloat
        let scale: CGFloat
        let stripeWidth: CGFloat
        let xOffset: CGFloat

        var body: some View {
            ZStack {
                Text(text)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(color.opacity(0.58))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .allowsHitTesting(false)

                Text(text)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(highlightColor)
                    .mask(
                        ShimmerStripe(
                            width: stripeWidth,
                            height: fontSize * 1.6,
                            xOffset: xOffset
                        )
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)

                Text(text)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(color.opacity(0.82))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .allowsHitTesting(false)
            }
            .scaleEffect(scale, anchor: .center)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
        }
    }

    private func scaleFactor(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        guard textWidth > 0 else { return 1 }
        if textWidth <= width { return 1 }
        let adjusted = max(width - 12, 0)
        if adjusted <= 0 { return 0.65 }
        let scaled = adjusted / textWidth
        return max(0.65, scaled)
        #else
        return 1
        #endif
    }
}
