import Foundation
import SwiftUI
import WhatsThatDomain

// MARK: - Session Status

/// High-level status for a background discovery session.
/// Only publishes state changes (not individual tokens) to avoid SwiftUI crashes.
public enum DiscoverySessionStatus: Equatable {
    case queued
    case processing
    case completed(DiscoverySummary)
    case failed(String)

    public static func == (lhs: DiscoverySessionStatus, rhs: DiscoverySessionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.queued, .queued): return true
        case (.processing, .processing): return true
        case let (.completed(l), .completed(r)): return l.id == r.id
        case let (.failed(l), .failed(r)): return l == r
        default: return false
        }
    }
}

// MARK: - Session Subscriber Protocol

/// Protocol for subscribing to discovery session events.
/// Subscribers receive events while attached; stream continues if they detach.
@MainActor
public protocol DiscoverySessionSubscriber: AnyObject {
    /// Called for each stream event (tokens, status, metadata, etc.)
    func handleSessionEvent(_ event: DiscoveryAnalysisEvent)
    /// Called when the session completes successfully
    func sessionDidComplete(discoveryId: Int64, summary: DiscoverySummary?)
    /// Called when the session fails
    func sessionDidFail(error: Error)
}

// MARK: - Pending Discovery

/// Represents a discovery request queued for background processing.
public struct PendingDiscoveryRequest: Identifiable {
    public let id: UUID
    public let payload: DiscoveryAnalysisPayload
    public let media: DiscoveryCapturedMedia
    public let generateAudioGuide: Bool
    public let flowType: DiscoveryCreationFlowType
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        payload: DiscoveryAnalysisPayload,
        media: DiscoveryCapturedMedia,
        generateAudioGuide: Bool,
        flowType: DiscoveryCreationFlowType
    ) {
        self.id = id
        self.payload = payload
        self.media = media
        self.generateAudioGuide = generateAudioGuide
        self.flowType = flowType
        self.createdAt = Date()
    }
}

// MARK: - In-Progress Item

/// Display model for in-progress sessions on the Discoveries tab.
public struct InProgressItem: Identifiable, Equatable {
    public let id: UUID
    public let thumbnailData: Data
    public let media: DiscoveryCapturedMedia
    public let flowType: DiscoveryCreationFlowType
    public var title: String?
    public var status: DiscoverySessionStatus
    public let startedAt: Date

    public static func == (lhs: InProgressItem, rhs: InProgressItem) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.status == rhs.status
    }
}

// MARK: - Completion Toast

/// Model for a discovery completion toast notification.
/// Similar to GenerationCompleteToast but for discovery creation.
public struct DiscoveryCompletionToast: Identifiable, Equatable {
    public let id: UUID
    public let discovery: DiscoverySummary
    public let generateAudioGuide: Bool
    public let createdAt: Date

    public init(discovery: DiscoverySummary, generateAudioGuide: Bool) {
        self.id = UUID()
        self.discovery = discovery
        self.generateAudioGuide = generateAudioGuide
        self.createdAt = Date()
    }

    public static func == (lhs: DiscoveryCompletionToast, rhs: DiscoveryCompletionToast) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Discovery Session Manager

/// Manages background discovery sessions independently of the UI.
/// Designed to process discoveries even when the creation overlay is closed.
///
/// Key design:
/// - Only publishes high-level status changes (not token-by-token streaming)
/// - Supports up to 3 concurrent sessions; additional requests are queued
/// - Publishes inProgressItems for UI display on the Discoveries tab
/// - Survives navigation changes without causing SwiftUI crashes
@MainActor
public final class DiscoverySessionManager: ObservableObject {

    // MARK: - Singleton

    public static let shared = DiscoverySessionManager()

    // MARK: - Published State (Coarse-grained only!)

    /// Status of each session by ID - observers get notified only on status changes
    @Published private(set) public var sessionStatuses: [UUID: DiscoverySessionStatus] = [:]

    /// Queue of pending completion toasts (shown when discoveries finish in background)
    @Published public var pendingCompletionToasts: [DiscoveryCompletionToast] = []

    /// In-progress items for display on the Discoveries tab.
    @Published private(set) public var inProgressItems: [InProgressItem] = []

    /// Number of pending discoveries (queued + processing)
    public var pendingCount: Int {
        pendingQueue.count + activeSessions.count
    }

    // MARK: - Internal State

    private let maxConcurrentSessions = 3

    /// Queue of pending discovery requests (not published directly to avoid re-renders)
    private var pendingQueue: [PendingDiscoveryRequest] = []

    /// Currently active sessions (up to maxConcurrentSessions)
    private var activeSessions: [UUID: ActiveDiscoverySession] = [:]

    /// Dependencies - injected after init
    private var analysisClient: DiscoveryAnalysisClient?
    private var historyRepository: DiscoveryHistoryRepository?
    private var creditBalanceStore: CreditBalanceStore?
    private var imageEncoder: DiscoveryImageEncodingService?

    /// Callbacks for integration with MainTabView
    public var onDiscoveryCompleted: ((DiscoverySummary, Bool) -> Void)?
    public var onDiscoveryFailed: ((UUID, String) -> Void)?

    // MARK: - Init

    private init() {}

    // MARK: - Configuration

    /// Configure dependencies. Called once during app setup.
    public func configure(
        analysisClient: DiscoveryAnalysisClient,
        historyRepository: DiscoveryHistoryRepository,
        creditBalanceStore: CreditBalanceStore,
        imageEncoder: DiscoveryImageEncodingService
    ) {
        self.analysisClient = analysisClient
        self.historyRepository = historyRepository
        self.creditBalanceStore = creditBalanceStore
        self.imageEncoder = imageEncoder
    }

    // MARK: - Public API

    /// Start a discovery session with an optional subscriber.
    /// If the concurrent limit is reached, the session is queued.
    /// Returns the session ID for tracking.
    @discardableResult
    public func startSession(
        payload: DiscoveryAnalysisPayload,
        media: DiscoveryCapturedMedia,
        generateAudioGuide: Bool,
        flowType: DiscoveryCreationFlowType,
        subscriber: DiscoverySessionSubscriber? = nil
    ) -> UUID {
        let request = PendingDiscoveryRequest(
            payload: payload,
            media: media,
            generateAudioGuide: generateAudioGuide,
            flowType: flowType
        )

        if activeSessions.count >= maxConcurrentSessions {
            // Queue the request
            sessionStatuses[request.id] = .queued
            pendingQueue.append(request)
            appendInProgressItem(for: request, status: .queued)
            print("[DiscoverySessionManager] Session \(request.id) queued (active: \(activeSessions.count), queued: \(pendingQueue.count))")
        } else {
            sessionStatuses[request.id] = .processing
            appendInProgressItem(for: request, status: .processing)
            startProcessing(request, subscriber: subscriber)
            print("[DiscoverySessionManager] Starting session \(request.id) with subscriber: \(subscriber != nil)")
        }

        return request.id
    }

    /// Subscribe to an active session to receive events.
    /// If already subscribed, replaces the existing subscriber.
    /// Replays all accumulated events to the new subscriber to catch them up.
    public func subscribe(to sessionId: UUID, subscriber: DiscoverySessionSubscriber) {
        guard var session = activeSessions[sessionId] else {
            print("[DiscoverySessionManager] Cannot subscribe - session \(sessionId) not active")
            return
        }

        // Replay accumulated events to catch up the new subscriber
        let eventsToReplay = session.accumulatedEvents
        print("[DiscoverySessionManager] Subscribed to session \(sessionId), replaying \(eventsToReplay.count) accumulated events")
        for event in eventsToReplay {
            subscriber.handleSessionEvent(event)
        }

        session.subscriber = subscriber
        activeSessions[sessionId] = session
    }

    /// Unsubscribe from a session. Stream continues, but events are no longer forwarded.
    public func unsubscribe(from sessionId: UUID) {
        guard var session = activeSessions[sessionId] else {
            print("[DiscoverySessionManager] Cannot unsubscribe - session \(sessionId) not active")
            return
        }
        session.subscriber = nil
        activeSessions[sessionId] = session
        print("[DiscoverySessionManager] Unsubscribed from session \(sessionId) - stream continues in background")
    }

    /// Cancel a specific session (if still queued or processing).
    public func cancelSession(_ id: UUID) {
        // Remove from queue if still waiting
        if let index = pendingQueue.firstIndex(where: { $0.id == id }) {
            pendingQueue.remove(at: index)
            sessionStatuses.removeValue(forKey: id)
            removeInProgressItem(id)
            print("[DiscoverySessionManager] Cancelled queued session \(id)")
            return
        }

        // Cancel active session
        if let session = activeSessions[id] {
            session.task.cancel()
            activeSessions.removeValue(forKey: id)
            sessionStatuses.removeValue(forKey: id)
            removeInProgressItem(id)
            print("[DiscoverySessionManager] Cancelled active session \(id)")
            processNextIfAvailable()
        }
    }

    /// Dismiss a failed session from the in-progress list.
    public func dismissFailedSession(_ id: UUID) {
        removeInProgressItem(id)
        sessionStatuses.removeValue(forKey: id)
    }

    /// Clear all pending sessions (e.g., on sign out).
    public func clearAll() {
        for session in activeSessions.values {
            session.task.cancel()
        }
        activeSessions.removeAll()
        pendingQueue.removeAll()
        sessionStatuses.removeAll()
        pendingCompletionToasts.removeAll()
        inProgressItems.removeAll()
        print("[DiscoverySessionManager] Cleared all sessions")
    }

    // MARK: - Toast Actions

    /// Dismiss the current (frontmost) completion toast.
    public func dismissCompletionToast() {
        guard !pendingCompletionToasts.isEmpty else { return }
        pendingCompletionToasts.removeFirst()
    }

    // MARK: - Private Processing

    private func processNextIfAvailable() {
        guard activeSessions.count < maxConcurrentSessions else { return }
        guard let nextRequest = pendingQueue.first else { return }

        // Move from queue to active
        pendingQueue.removeFirst()
        sessionStatuses[nextRequest.id] = .processing
        updateInProgressItem(sessionId: nextRequest.id) { item in
            item.status = .processing
        }

        startProcessing(nextRequest, subscriber: nil)
    }

    private func startProcessing(_ request: PendingDiscoveryRequest, subscriber: DiscoverySessionSubscriber?) {
        guard let client = analysisClient else {
            print("[DiscoverySessionManager] Error: analysisClient not configured")
            sessionStatuses[request.id] = .failed("Not configured")
            updateInProgressItem(sessionId: request.id) { item in
                item.status = .failed("Not configured")
            }
            subscriber?.sessionDidFail(error: NSError(domain: "DiscoverySessionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not configured"]))
            processNextIfAvailable()
            return
        }

        sessionStatuses[request.id] = .processing
        print("[DiscoverySessionManager] Starting processing for \(request.id) with subscriber: \(subscriber != nil)")

        let task = Task { [weak self] in
            guard let self else { return }
            await self.executeAnalysis(request: request, client: client)
        }

        activeSessions[request.id] = ActiveDiscoverySession(
            id: request.id,
            request: request,
            task: task,
            subscriber: subscriber
        )
    }

    private func executeAnalysis(
        request: PendingDiscoveryRequest,
        client: DiscoveryAnalysisClient
    ) async {
        let networkSessionId = UUID()
        var discoveryId: Int64?

        do {
            let stream = client.startAnalysis(
                payload: request.payload,
                sessionId: networkSessionId,
                cancellationHandler: { }
            )

            // Process stream events with conditional forwarding
            for try await event in stream {
                // Forward event to subscriber if attached
                deliverEvent(event, for: request.id)

                // Always track completion/error regardless of subscriber
                switch event {
                case .complete(let id, _, _, _):
                    discoveryId = id
                case .error(let message, _):
                    throw NSError(domain: "DiscoverySessionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
                default:
                    break
                }
            }

            // Stream completed - fetch the discovery summary
            guard let id = discoveryId else {
                throw NSError(domain: "DiscoverySessionManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No discovery ID received"])
            }

            let summary = try await fetchDiscoverySummary(discoveryId: id)
            handleCompletion(request: request, summary: summary, discoveryId: id)

        } catch is CancellationError {
            print("[DiscoverySessionManager] Session \(request.id) cancelled")
            // Already handled in cancelSession()

        } catch let analysisError as DiscoveryAnalysisError where analysisError == .streamInterrupted {
            // Stream interruption - the server-side work may still complete
            // We need to start polling to detect completion
            print("[DiscoverySessionManager] Session \(request.id) stream interrupted - starting polling recovery")
            await handleStreamInterruption(request: request)

        } catch {
            handleFailure(request: request, error: error)
        }
    }

    /// Deliver an event to the subscriber if attached, otherwise consume silently.
    /// Always accumulates events for replay when a new subscriber joins mid-stream.
    @MainActor
    private func deliverEvent(_ event: DiscoveryAnalysisEvent, for sessionId: UUID) {
        guard var session = activeSessions[sessionId] else { return }

        // Accumulate event for potential replay to late subscribers
        session.accumulatedEvents.append(event)
        activeSessions[sessionId] = session

        // Update in-progress item title from metadata events
        if case let .metadata(title, _) = event, let title, !title.isEmpty {
            updateInProgressItem(sessionId: sessionId) { item in
                item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let subscriber = session.subscriber {
            // Subscriber attached -> forward event
            subscriber.handleSessionEvent(event)
        }
        // If no subscriber, event is accumulated but not forwarded.
        // Completion/error handling happens in executeAnalysis regardless.
    }

    private func fetchDiscoverySummary(discoveryId: Int64) async throws -> DiscoverySummary {
        guard let repo = historyRepository else {
            throw NSError(domain: "DiscoverySessionManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "History repository not configured"])
        }

        // Poll briefly for the discovery to appear
        let maxAttempts = 5
        for attempt in 1...maxAttempts {
            let recents = try await repo.fetchRecentDiscoveries(limit: 10)
            if let match = recents.first(where: { $0.id == discoveryId }) {
                return match
            }
            if attempt < maxAttempts {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5s between attempts
            }
        }

        throw NSError(domain: "DiscoverySessionManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Discovery not found after polling"])
    }

    @MainActor
    private func handleStreamInterruption(request: PendingDiscoveryRequest) async {
        print("[DiscoverySessionManager] Handling stream interruption for session \(request.id)")

        let isActiveSession = activeSessions[request.id] != nil

        // If subscriber is attached AND this is the active session, notify them so they can show polling UI
        if isActiveSession, let subscriber = activeSessions[request.id]?.subscriber {
            let interruptedError = DiscoveryAnalysisError.streamInterrupted
            subscriber.sessionDidFail(error: interruptedError)
            activeSessions.removeValue(forKey: request.id)
            processNextIfAvailable()
            return
        }

        // No subscriber (or not active session) - handle polling in the background
        do {
            let summary = try await pollForMostRecentDiscovery()
            handleCompletion(request: request, summary: summary, discoveryId: summary.id)
        } catch {
            handleFailure(request: request, error: error)
        }
    }

    /// Poll for the most recent discovery when we don't have an ID (stream interrupted scenario)
    private func pollForMostRecentDiscovery() async throws -> DiscoverySummary {
        guard let repo = historyRepository else {
            throw NSError(domain: "DiscoverySessionManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "History repository not configured"])
        }

        // Poll for a new discovery to appear (the one we were creating)
        let startTime = Date()
        let maxAttempts = 10
        for attempt in 1...maxAttempts {
            let recents = try await repo.fetchRecentDiscoveries(limit: 1)
            // Check if we got a discovery created after we started
            if let recent = recents.first, recent.capturedAt > startTime.addingTimeInterval(-30) {
                return recent
            }
            if attempt < maxAttempts {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1s between attempts
            }
        }

        throw NSError(domain: "DiscoverySessionManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Discovery not found after polling"])
    }

    @MainActor
    private func handleCompletion(request: PendingDiscoveryRequest, summary: DiscoverySummary, discoveryId: Int64) {
        print("[DiscoverySessionManager] Session \(request.id) completed: \(summary.title)")

        let isActiveSession = activeSessions[request.id] != nil
        let hadSubscriber = isActiveSession && activeSessions[request.id]?.subscriber != nil

        // Update status
        sessionStatuses[request.id] = .completed(summary)

        // Update in-progress item to completed, then schedule removal
        updateInProgressItem(sessionId: request.id) { item in
            item.status = .completed(summary)
            item.title = summary.title
        }
        scheduleInProgressItemRemoval(request.id, delay: 2.5)

        // IMPORTANT: Call onDiscoveryCompleted FIRST to trigger audio generation
        onDiscoveryCompleted?(summary, request.generateAudioGuide)

        // Notify subscriber if attached
        if isActiveSession {
            activeSessions[request.id]?.subscriber?.sessionDidComplete(discoveryId: discoveryId, summary: summary)
            activeSessions.removeValue(forKey: request.id)
        }

        // Only show toast if there was NO subscriber (background completion)
        if !hadSubscriber {
            let toast = DiscoveryCompletionToast(
                discovery: summary,
                generateAudioGuide: request.generateAudioGuide
            )
            pendingCompletionToasts.append(toast)
        }

        processNextIfAvailable()
    }

    @MainActor
    private func handleFailure(request: PendingDiscoveryRequest, error: Error) {
        let message = error.localizedDescription
        print("[DiscoverySessionManager] Session \(request.id) failed: \(message)")

        let isActiveSession = activeSessions[request.id] != nil

        // Notify subscriber if still attached
        if isActiveSession {
            activeSessions[request.id]?.subscriber?.sessionDidFail(error: error)
            activeSessions.removeValue(forKey: request.id)
        }

        sessionStatuses[request.id] = .failed(message)
        updateInProgressItem(sessionId: request.id) { item in
            item.status = .failed(message)
        }

        onDiscoveryFailed?(request.id, message)

        processNextIfAvailable()
    }

    // MARK: - In-Progress Item Management

    private func appendInProgressItem(for request: PendingDiscoveryRequest, status: DiscoverySessionStatus) {
        let item = InProgressItem(
            id: request.id,
            thumbnailData: request.media.data,
            media: request.media,
            flowType: request.flowType,
            title: nil,
            status: status,
            startedAt: request.createdAt
        )
        inProgressItems.append(item)
    }

    private func updateInProgressItem(sessionId: UUID, transform: (inout InProgressItem) -> Void) {
        guard let index = inProgressItems.firstIndex(where: { $0.id == sessionId }) else { return }
        transform(&inProgressItems[index])
    }

    private func removeInProgressItem(_ id: UUID) {
        inProgressItems.removeAll { $0.id == id }
    }

    private func scheduleInProgressItemRemoval(_ id: UUID, delay: TimeInterval) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.removeInProgressItem(id)
        }
    }

    // MARK: - Debug

    #if DEBUG
    /// Injects a fake in-progress item using the given discovery's image.
    /// Transitions to completed after ~11 seconds, then auto-removes after 2.5s.
    public func debugAddFakeInProgressItem(from discovery: DiscoverySummary) {
        guard let imagePath = discovery.imagePath,
              let url = URL(string: imagePath) else { return }

        let sessionId = UUID()

        // Download thumbnail data in background, then add the item
        Task { @MainActor [weak self] in
            let thumbnailData: Data
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                thumbnailData = data
            } catch {
                // Fallback: 1x1 gray pixel
                thumbnailData = Data()
            }

            let media = DiscoveryCapturedMedia(
                data: thumbnailData,
                contentType: "image/jpeg",
                pixelWidth: 400,
                pixelHeight: 480,
                createdAt: Date(),
                location: nil
            )

            let item = InProgressItem(
                id: sessionId,
                thumbnailData: thumbnailData,
                media: media,
                flowType: .camera,
                title: nil,
                status: .processing,
                startedAt: Date()
            )
            self?.inProgressItems.append(item)

            // Simulate completion after ~11 seconds
            try? await Task.sleep(nanoseconds: 11_000_000_000)
            self?.updateInProgressItem(sessionId: sessionId) { item in
                item.status = .completed(discovery)
                item.title = discovery.title
            }

            // Auto-remove after 2.5 seconds
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self?.removeInProgressItem(sessionId)
        }
    }
    #endif
}

// MARK: - Active Session

/// Represents a currently-processing discovery session.
private struct ActiveDiscoverySession {
    let id: UUID
    let request: PendingDiscoveryRequest
    let task: Task<Void, Never>
    /// Optional subscriber receiving forwarded events. Weak reference to avoid retain cycles.
    weak var subscriber: DiscoverySessionSubscriber?
    /// Accumulated events for replay when a new subscriber joins mid-stream.
    /// This allows users who unsubscribe and re-subscribe to catch up on missed events.
    var accumulatedEvents: [DiscoveryAnalysisEvent] = []
}
