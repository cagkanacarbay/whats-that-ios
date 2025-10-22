import SwiftUI

struct DiscoveryCardSkeletonView: View {
    let width: CGFloat
    let height: CGFloat
    @State private var animate = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: width, height: height)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.gray.opacity(0.1),
                                    Color.gray.opacity(0.3),
                                    Color.gray.opacity(0.1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .mask {
                            Rectangle()
                                .fill(Color.white.opacity(animate ? 1 : 0))
                                .blur(radius: 40)
                                .offset(x: animate ? width : -width)
                        }
                        .animation(
                            .easeInOut(duration: 1.2)
                                .repeatForever(autoreverses: false),
                            value: animate
                        )
                }
                .onAppear {
                    animate = true
                }

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: width * 0.7, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: width * 0.5, height: 12)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.02),
                        Color.black.opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}
