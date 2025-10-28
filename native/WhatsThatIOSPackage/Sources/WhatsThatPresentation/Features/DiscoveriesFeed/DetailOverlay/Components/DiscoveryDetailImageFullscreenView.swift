import SwiftUI
import UIKit
import WhatsThatShared

struct DiscoveryDetailImageFullscreenView: View {
    let discoveryId: Int64
    let imageURL: URL?
    let placeholderImage: UIImage?
    let onClose: () -> Void

    @State private var safeAreaInsets = EdgeInsets()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    closeButton
                        .padding(.trailing, BrandSpacing.large)
                }
                .padding(.top, closedTopPadding)
                .frame(maxWidth: .infinity)

                ZoomableScrollView {
                    imageContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onPreferenceChange(SafeAreaInsetPreferenceKey.self) { value in
            safeAreaInsets = value
        }
        .background(
            SafeAreaInsetReader()
                .allowsHitTesting(false)
        )
    }

    private var imageContent: some View {
        DiscoveryCachedImage(discoveryId: discoveryId, remoteURL: imageURL) { phase in
            switch phase {
            case .success(let platformImage):
                Image(platformImage: platformImage)
                    .resizable()
                    .scaledToFit()
            case .failure:
                fallbackContent
            case .loading, .empty:
                if let placeholderImage {
                    Image(platformImage: placeholderImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    fallbackContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var fallbackContent: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color(hex: "#20293A"), Color(hex: "#141927")]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "photo")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
        }
    }

    private var closeButton: some View {
        DiscoveryOverlayButton(
            systemName: "xmark",
            action: dismiss,
            accessibilityLabel: "Close image"
        )
        .allowsHitTesting(true)
    }

    private var closedTopPadding: CGFloat {
        if safeAreaInsets.top > 0 {
            return safeAreaInsets.top + 12
        }

        let windowScene = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        let topInset = windowScene?.keyWindow?.safeAreaInsets.top ?? 0
        return topInset + 12
    }

    private func dismiss() {
        onClose()
    }
}

private struct SafeAreaInsetReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: SafeAreaInsetPreferenceKey.self,
                    value: proxy.safeAreaInsets
                )
        }
    }
}

private struct SafeAreaInsetPreferenceKey: PreferenceKey {
    static var defaultValue = EdgeInsets()

    static func reduce(value: inout EdgeInsets, nextValue: () -> EdgeInsets) {
        value = nextValue()
    }
}

private struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let minScale: CGFloat
    let maxScale: CGFloat
    private let contentBuilder: () -> Content

    init(minScale: CGFloat = 1, maxScale: CGFloat = 4, @ViewBuilder content: @escaping () -> Content) {
        self.minScale = minScale
        self.maxScale = maxScale
        self.contentBuilder = content
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = maxScale
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let hostingController = context.coordinator.hostingController
        hostingController.rootView = contentBuilder()
        hostingController.view.translatesAutoresizingMaskIntoConstraints = true
        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = scrollView.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(hostingController.view)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostingController.rootView = contentBuilder()
        context.coordinator.centerContentIfNeeded(scrollView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableScrollView
        let hostingController: UIHostingController<Content>

        init(parent: ZoomableScrollView) {
            self.parent = parent
            hostingController = UIHostingController(rootView: parent.contentBuilder())
            hostingController.view.backgroundColor = .clear
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContentIfNeeded(scrollView)
        }

        func centerContentIfNeeded(_ scrollView: UIScrollView) {
            let contentView = hostingController.view ?? UIView()
            let bounds = scrollView.bounds.size
            let contentSize = contentView.frame.size

            let horizontalInset = max((bounds.width - contentSize.width) * 0.5, 0)
            let verticalInset = max((bounds.height - contentSize.height) * 0.5, 0)

            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            let targetScale = scrollView.zoomScale > parent.minScale ? parent.minScale : min(parent.maxScale, parent.minScale * 2)
            let zoomRect = zoomRect(for: scrollView, scale: targetScale, center: gesture.location(in: gesture.view))
            scrollView.zoom(to: zoomRect, animated: true)
        }

        private func zoomRect(for scrollView: UIScrollView, scale: CGFloat, center: CGPoint) -> CGRect {
            var rect = CGRect()
            rect.size.height = scrollView.bounds.size.height / scale
            rect.size.width = scrollView.bounds.size.width / scale
            rect.origin.x = center.x - (rect.size.width * 0.5)
            rect.origin.y = center.y - (rect.size.height * 0.5)
            return rect
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first(where: { $0.isKeyWindow })
    }
}

private extension Image {
    init(platformImage: UIImage) {
        self = Image(uiImage: platformImage)
    }
}
