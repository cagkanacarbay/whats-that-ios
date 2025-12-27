import Foundation

/// Protocol for any component that holds user-specific data that should be cleared on sign-out.
public protocol UserDataClearable: Sendable {
    /// Clears all user-specific data from this component.
    func clearUserData() async
}

/// Centralized coordinator that clears all registered user data stores.
/// Used during sign-out and account deletion to prevent data leakage between accounts.
public actor UserDataClearingService {
    private var clearables: [UserDataClearable] = []
    
    public init() {}
    
    /// Registers a clearable component with this service.
    public func register(_ clearable: UserDataClearable) {
        clearables.append(clearable)
    }
    
    /// Clears all registered user data stores concurrently.
    public func clearAll() async {
        await withTaskGroup(of: Void.self) { group in
            for clearable in clearables {
                group.addTask {
                    await clearable.clearUserData()
                }
            }
        }
    }
}
