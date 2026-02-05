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
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        payload: DiscoveryAnalysisPayload,
        media: DiscoveryCapturedMedia,
        generateAudioGuide: Bool
    ) {
        self.id = id
        self.payload = payload
        self.media = media
        self.generateAudioGuide = generateAudioGuide
        self.createdAt = Date()
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
/// - Maintains a serial queue: processes one discovery at a time
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
    
    /// Number of pending discoveries (queued + processing)
    public var pendingCount: Int {
        pendingQueue.count + (activeSession != nil ? 1 : 0)
    }
    
    // MARK: - Internal State
    
    /// Queue of pending discovery requests (not published directly to avoid re-renders)
    private var pendingQueue: [PendingDiscoveryRequest] = []
    
    /// Currently active session (if any)
    private var activeSession: ActiveDiscoverySession?
    
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
    
    /// Start a discovery session immediately with an optional subscriber.
    /// The manager owns the stream; use subscribe()/unsubscribe() to control event forwarding.
    /// Returns the session ID for tracking.
    @discardableResult
    public func startSession(
        payload: DiscoveryAnalysisPayload,
        media: DiscoveryCapturedMedia,
        generateAudioGuide: Bool,
        subscriber: DiscoverySessionSubscriber? = nil
    ) -> UUID {
        let request = PendingDiscoveryRequest(
            payload: payload,
            media: media,
            generateAudioGuide: generateAudioGuide
        )
        
        sessionStatuses[request.id] = .processing
        print("[DiscoverySessionManager] Starting session \(request.id) with subscriber: \(subscriber != nil)")
        
        // Start processing immediately (don't queue)
        startProcessing(request, subscriber: subscriber)
        
        return request.id
    }
    
    /// Subscribe to an active session to receive events.
    /// If already subscribed, replaces the existing subscriber.
    /// Replays all accumulated events to the new subscriber to catch them up.
    public func subscribe(to sessionId: UUID, subscriber: DiscoverySessionSubscriber) {
        guard var session = activeSession, session.id == sessionId else {
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
        activeSession = session
    }
    
    /// Unsubscribe from a session. Stream continues, but events are no longer forwarded.
    public func unsubscribe(from sessionId: UUID) {
        guard var session = activeSession, session.id == sessionId else {
            print("[DiscoverySessionManager] Cannot unsubscribe - session \(sessionId) not active")
            return
        }
        session.subscriber = nil
        activeSession = session
        print("[DiscoverySessionManager] Unsubscribed from session \(sessionId) - stream continues in background")
    }
    
    /// Cancel a specific session (if still queued or processing).
    public func cancelSession(_ id: UUID) {
        // Remove from queue if still waiting
        if let index = pendingQueue.firstIndex(where: { $0.id == id }) {
            pendingQueue.remove(at: index)
            sessionStatuses.removeValue(forKey: id)
            print("[DiscoverySessionManager] Cancelled queued session \(id)")
            return
        }
        
        // Cancel active session if it's the one being processed
        if activeSession?.id == id {
            activeSession?.task.cancel()
            activeSession = nil
            sessionStatuses.removeValue(forKey: id)
            print("[DiscoverySessionManager] Cancelled active session \(id)")
            processNextIfAvailable()
        }
    }
    
    /// Clear all pending sessions (e.g., on sign out).
    public func clearAll() {
        activeSession?.task.cancel()
        activeSession = nil
        pendingQueue.removeAll()
        sessionStatuses.removeAll()
        pendingCompletionToasts.removeAll()
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
        // Already processing something
        guard activeSession == nil else { return }
        
        // Nothing in queue
        guard let nextRequest = pendingQueue.first else { return }
        
        // Move from queue to active
        pendingQueue.removeFirst()
        
        // Start processing
        startProcessing(nextRequest, subscriber: nil)
    }
    
    private func startProcessing(_ request: PendingDiscoveryRequest, subscriber: DiscoverySessionSubscriber?) {
        guard let client = analysisClient else {
            print("[DiscoverySessionManager] Error: analysisClient not configured")
            sessionStatuses[request.id] = .failed("Not configured")
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
        
        activeSession = ActiveDiscoverySession(
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
        guard var session = activeSession, session.id == sessionId else { return }

        // Accumulate event for potential replay to late subscribers
        session.accumulatedEvents.append(event)
        activeSession = session

        if let subscriber = session.subscriber {
            // Subscriber attached → forward event
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

        // Check if this interruption is for the currently active session
        let isActiveSession = activeSession?.id == request.id

        // If subscriber is attached AND this is the active session, notify them so they can show polling UI
        if isActiveSession, let subscriber = activeSession?.subscriber {
            // Forward the stream interrupted error to the subscriber
            // The subscriber (ViewModel) will handle showing polling UI
            let interruptedError = DiscoveryAnalysisError.streamInterrupted
            subscriber.sessionDidFail(error: interruptedError)
            // The subscriber takes over recovery, clear our session
            activeSession = nil
            processNextIfAvailable()
            return
        }

        // No subscriber (or not active session) - handle polling in the background
        do {
            let summary = try await pollForMostRecentDiscovery()
            handleCompletion(request: request, summary: summary, discoveryId: summary.id)
        } catch {
            // Polling failed - report as failure
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

        // Check if this completion is for the currently active session
        // This is important when multiple sessions run concurrently (e.g., user taps "Discover More")
        let isActiveSession = activeSession?.id == request.id
        let hadSubscriber = isActiveSession && activeSession?.subscriber != nil

        // Clear session state
        sessionStatuses[request.id] = .completed(summary)

        // IMPORTANT: Call onDiscoveryCompleted FIRST to trigger audio generation
        // This populates assetStates with .processing BEFORE sessionDidComplete updates the UI
        onDiscoveryCompleted?(summary, request.generateAudioGuide)

        // THEN notify subscriber to update UI state - but ONLY if this was the active session
        // Otherwise we'd notify the wrong subscriber (for a different session)
        if isActiveSession {
            activeSession?.subscriber?.sessionDidComplete(discoveryId: discoveryId, summary: summary)
            activeSession = nil
        }

        // Only show toast if there was NO subscriber (background completion)
        // If subscriber was attached, the ViewModel handles the UI flow
        if !hadSubscriber {
            let toast = DiscoveryCompletionToast(
                discovery: summary,
                generateAudioGuide: request.generateAudioGuide
            )
            pendingCompletionToasts.append(toast)
        }

        // Process next in queue
        processNextIfAvailable()
    }
    
    @MainActor
    private func handleFailure(request: PendingDiscoveryRequest, error: Error) {
        let message = error.localizedDescription
        print("[DiscoverySessionManager] Session \(request.id) failed: \(message)")

        // Check if this failure is for the currently active session
        // This is important when multiple sessions run concurrently (e.g., user taps "Discover More")
        let isActiveSession = activeSession?.id == request.id

        // Notify subscriber if still attached - but ONLY if this was the active session
        if isActiveSession {
            activeSession?.subscriber?.sessionDidFail(error: error)
            activeSession = nil
        }

        sessionStatuses[request.id] = .failed(message)

        // Notify listener
        onDiscoveryFailed?(request.id, message)

        // Process next in queue
        processNextIfAvailable()
    }
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
