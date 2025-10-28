import SwiftUI
import UIKit

struct ScrollViewContentOffsetObserver: UIViewRepresentable {
    typealias OffsetChangeHandler = (CGFloat) -> Void

    let onChange: OffsetChangeHandler

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> PassthroughView {
        let view = PassthroughView()
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        context.coordinator.registerIfNeeded(from: view)
        return view
    }

    func updateUIView(_ uiView: PassthroughView, context: Context) {
        uiView.coordinator = context.coordinator
        context.coordinator.registerIfNeeded(from: uiView)
    }

    static func dismantleUIView(_ uiView: PassthroughView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class PassthroughView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            coordinator?.registerIfNeeded(from: self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            coordinator?.registerIfNeeded(from: self)
        }
    }

    final class Coordinator: NSObject {
        private let onChange: OffsetChangeHandler
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        init(onChange: @escaping OffsetChangeHandler) {
            self.onChange = onChange
        }

        func registerIfNeeded(from view: UIView) {
            guard scrollView == nil else { return }
            guard let scrollView = view.enclosingScrollView() else {
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let view else { return }
                    self?.registerIfNeeded(from: view)
                }
                return
            }
            self.scrollView = scrollView
            observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scrollView, _ in
                guard let self else { return }
                // Normalize to a stable "distance from top" that is 0 when scrolled to the top
                // (regardless of adjusted content inset) and increases as we scroll down.
                // This prevents false positives for vertical-dismiss activation when the
                // raw contentOffset is still near zero or negative due to insets.
                let rawY = scrollView.contentOffset.y
                let insetTop = scrollView.adjustedContentInset.top
                let distanceFromTop = max(rawY + insetTop, 0)
                self.onChange(distanceFromTop)
            }
        }

        func teardown() {
            observation?.invalidate()
            observation = nil
            scrollView = nil
        }
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        if let scrollView = superview as? UIScrollView {
            return scrollView
        }
        return superview?.enclosingScrollView()
    }
}
