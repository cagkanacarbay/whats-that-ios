import Foundation

struct IdentifiedError: Identifiable {
    let id = UUID()
    let error: DiscoveryCreationFlowViewModel.FlowError
}
