import Combine
import Foundation

@MainActor
public final class PasswordResetLinkCoordinator: ObservableObject {
    private let subject = PassthroughSubject<URL, Never>()

    public init() {}

    public var urlPublisher: AnyPublisher<URL, Never> {
        subject.eraseToAnyPublisher()
    }

    public func handle(_ url: URL) {
        subject.send(url)
    }
}

