import SwiftUI

struct PulsingDotsView: View {
    let primaryColor: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSince1970
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(primaryColor.opacity(colorScheme == .dark ? 0.9 : 1))
                        .frame(width: 10, height: 10)
                        .scaleEffect(scale(for: time, index: index))
                        .opacity(opacity(for: time, index: index))
                }
            }
        }
    }

    private func scale(for time: TimeInterval, index: Int) -> CGFloat {
        let progress = (time + Double(index) * 0.22).remainder(dividingBy: 1.0)
        return 0.75 + 0.25 * CGFloat(sin(progress * 2 * .pi))
    }

    private func opacity(for time: TimeInterval, index: Int) -> Double {
        let progress = (time + Double(index) * 0.22).remainder(dividingBy: 1.0)
        return 0.5 + 0.5 * sin(progress * 2 * .pi + .pi / 2)
    }
}
