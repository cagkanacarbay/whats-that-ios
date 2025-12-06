import Network
import Combine
import Foundation

/// Monitors network connectivity and provides auto-retry callbacks when connection is restored.
@MainActor
public final class NetworkMonitor: ObservableObject {
    @Published public private(set) var isConnected: Bool = true
    @Published public private(set) var connectionType: NWInterface.InterfaceType?
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor", qos: .utility)
    
    /// Callbacks registered for retry when connectivity returns
    private var reconnectCallbacks: [() async -> Void] = []
    
    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied
                self.connectionType = path.availableInterfaces.first?.type
                
                // Trigger auto-retry callbacks if we just reconnected
                if !wasConnected && path.status == .satisfied {
                    await self.executeReconnectCallbacks()
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    /// Register a callback to be executed when connectivity returns.
    /// The callback is removed after execution.
    public func onReconnect(_ callback: @escaping () async -> Void) {
        reconnectCallbacks.append(callback)
    }
    
    /// Clears all pending reconnect callbacks
    public func clearReconnectCallbacks() {
        reconnectCallbacks.removeAll()
    }
    
    private func executeReconnectCallbacks() async {
        let callbacks = reconnectCallbacks
        reconnectCallbacks.removeAll()
        for callback in callbacks {
            await callback()
        }
    }
    
    deinit {
        monitor.cancel()
    }
}
