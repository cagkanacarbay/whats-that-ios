import Foundation
import SwiftUI
import UIKit

@MainActor
final class KeyboardState: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var height: CGFloat = 0

    private var willShowObserver: NSObjectProtocol?
    private var willHideObserver: NSObjectProtocol?

    init() {
        let center = NotificationCenter.default
        // Update only on show/hide to avoid 60fps frame-change churn
        willShowObserver = center.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let endFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
            let screenHeight = UIScreen.main.bounds.height
            let keyboardTop = endFrame.origin.y
            let overlap = max(0, screenHeight - keyboardTop)
            Task { @MainActor [weak self] in
                self?.height = overlap
                self?.isVisible = overlap > 0
            }
        }

        willHideObserver = center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.height = 0
                self?.isVisible = false
            }
        }
    }

    deinit {
        if let willShowObserver { NotificationCenter.default.removeObserver(willShowObserver) }
        if let willHideObserver { NotificationCenter.default.removeObserver(willHideObserver) }
    }
}
