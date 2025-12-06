import XCTest
@testable import WhatsThatPresentation

@MainActor
final class AudioGuidesQueueStoreTests: XCTestCase {
    
    private func makeStore() -> AudioGuidesQueueStore {
        // Use an ephemeral UserDefaults for test isolation
        let suiteName = "test.audioguides.queue.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AudioGuidesQueueStore(defaults: defaults)
    }
    
    // MARK: - Initial State Tests
    
    func testInitialStateIsEmpty() {
        let store = makeStore()
        
        XCTAssertNil(store.current)
        XCTAssertTrue(store.immediate.isEmpty)
        XCTAssertTrue(store.deferred.isEmpty)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertFalse(store.autoplayEnabled)
    }
    
    // MARK: - Play Now Tests
    
    func testPlayNowSetsCurrent() {
        let store = makeStore()
        let baseSnapshot: [Int64] = [100, 101, 102, 103, 104]
        
        store.playNow(102, recentering: baseSnapshot)
        
        XCTAssertEqual(store.current, 102)
        XCTAssertTrue(store.baseList.contains(102))
    }
    
    func testPlayNowPushesPreviousToHistory() {
        let store = makeStore()
        let baseSnapshot: [Int64] = [100, 101, 102, 103, 104]
        
        store.playNow(100, recentering: baseSnapshot)
        store.playNow(101, recentering: baseSnapshot)
        
        XCTAssertEqual(store.current, 101)
        XCTAssertEqual(store.history.first, 100)
    }
    
    func testPlayNowRemovesFromQueues() {
        let store = makeStore()
        let baseSnapshot: [Int64] = [100, 101, 102]
        
        store.playNow(100, recentering: baseSnapshot)
        store.playNext(101)
        store.addToEnd(102)
        
        XCTAssertTrue(store.isQueued(101))
        XCTAssertTrue(store.isQueued(102))
        
        store.playNow(101, recentering: baseSnapshot)
        
        XCTAssertFalse(store.isQueued(101))
        XCTAssertTrue(store.isQueued(102))
    }
    
    // MARK: - Play Next Tests (LIFO)
    
    func testPlayNextInsertsAtFrontLIFO() {
        let store = makeStore()
        store.playNow(100, recentering: [100])
        
        store.playNext(101)
        store.playNext(102)
        store.playNext(103)
        
        // LIFO: most recent first
        XCTAssertEqual(store.immediate, [103, 102, 101])
    }
    
    func testPlayNextMovesDeferredToImmediate() {
        let store = makeStore()
        store.playNow(100, recentering: [100])
        
        store.addToEnd(101)
        XCTAssertTrue(store.deferred.contains(101))
        
        store.playNext(101)
        
        XCTAssertTrue(store.immediate.contains(101))
        XCTAssertFalse(store.deferred.contains(101))
    }
    
    func testPlayNextIgnoresCurrentItem() {
        let store = makeStore()
        store.playNow(100, recentering: [100])
        
        store.playNext(100)
        
        XCTAssertTrue(store.immediate.isEmpty)
    }
    
    // MARK: - Add to End Tests (FIFO)
    
    func testAddToEndAppendsFIFO() {
        let store = makeStore()
        store.playNow(100, recentering: [100])
        
        store.addToEnd(101)
        store.addToEnd(102)
        store.addToEnd(103)
        
        // FIFO: first added first
        XCTAssertEqual(store.deferred, [101, 102, 103])
    }
    
    func testAddToEndIgnoresAlreadyQueued() {
        let store = makeStore()
        store.playNow(100, recentering: [100])
        
        store.addToEnd(101)
        store.addToEnd(101)
        
        XCTAssertEqual(store.deferred.filter { $0 == 101 }.count, 1)
    }
    
    func testAddToEndIgnoresCurrentItem() {
        let store = makeStore()
        store.playNow(100, recentering: [100])
        
        store.addToEnd(100)
        
        XCTAssertTrue(store.deferred.isEmpty)
    }
    
    // MARK: - Next Tests
    
    func testNextTakesFromImmediateFirst() {
        let store = makeStore()
        store.playNow(100, recentering: [100])
        store.playNext(101)
        store.addToEnd(102)
        
        let next = store.next()
        
        XCTAssertEqual(next, 101)
        XCTAssertEqual(store.current, 101)
        XCTAssertEqual(store.history.first, 100)
    }
    
    func testNextTakesFromDeferredWhenImmediateEmpty() {
        let store = makeStore()
        store.playNow(100, recentering: [100])
        store.addToEnd(101)
        store.addToEnd(102)
        
        let next = store.next()
        
        XCTAssertEqual(next, 101)
        XCTAssertEqual(store.deferred.first, 102)
    }
    
    func testNextFallsBackToBaseList() {
        let store = makeStore()
        // baseList is newest-first (index 0 = newest)
        // So [100, 101, 102, 103, 104] means 100 is newest, 104 is oldest
        let baseSnapshot: [Int64] = [100, 101, 102, 103, 104]
        // Starting at 102 (index 2), next() goes to index 1 (101, which is newer)
        store.playNow(102, recentering: baseSnapshot)
        
        let next = store.next()
        
        // next() goes towards newer items (lower index)
        XCTAssertEqual(next, 101)
    }
    
    func testNextReturnsNilWhenExhausted() {
        let store = makeStore()
        store.playNow(100, recentering: [100])
        
        let next = store.next()
        
        XCTAssertNil(next)
    }
    
    // MARK: - Previous Tests
    
    func testPreviousRestartsCurrentWhenPastThreshold() {
        let store = makeStore()
        store.playNow(100, recentering: [100])
        
        let prev = store.previous(currentPosition: 5.0, restartThreshold: 3.0)
        
        XCTAssertEqual(prev, 100) // Same current, restart
        XCTAssertEqual(store.current, 100)
    }
    
    func testPreviousTraversesBaseListNotHistory() {
        let store = makeStore()
        // baseList: [100, 101, 102] (newest-first)
        // Start at 101 (index 1), history should have 100 from the playNow call
        let baseSnapshot: [Int64] = [100, 101, 102]
        store.playNow(100, recentering: baseSnapshot)
        store.playNow(101, recentering: baseSnapshot)
        
        // History has 100, but Previous should traverse baseList, not history
        XCTAssertEqual(store.history.first, 100)
        
        let prev = store.previous(currentPosition: 1.0, restartThreshold: 3.0)
        
        // Should go to 102 (index 2, older in baseList), NOT 100 (from history)
        XCTAssertEqual(prev, 102)
        XCTAssertEqual(store.current, 102)
        // History should be unchanged (not popped)
        XCTAssertEqual(store.history.first, 100)
    }
    
    // MARK: - Removal Tests
    
    func testRemoveFromQueuesOnly() {
        let store = makeStore()
        store.playNow(100, recentering: [100, 101])
        store.playNext(101)
        
        store.remove(101)
        
        XCTAssertFalse(store.isQueued(101))
    }
    
    func testRemoveFromAllLists() {
        let store = makeStore()
        let baseSnapshot: [Int64] = [100, 101, 102]
        store.playNow(100, recentering: baseSnapshot)
        store.playNow(101, recentering: baseSnapshot)
        store.playNext(102)
        
        store.removeFromAllLists(100)
        
        XCTAssertFalse(store.history.contains(100))
        XCTAssertFalse(store.baseList.contains(100))
    }
    
    func testRemoveFromAllListsClearsCurrent() {
        let store = makeStore()
        store.playNow(100, recentering: [100])
        
        store.removeFromAllLists(100)
        
        XCTAssertNil(store.current)
    }
    
    // MARK: - Clear Queue Tests
    
    func testClearQueueKeepsHistoryAndCurrent() {
        let store = makeStore()
        let baseSnapshot: [Int64] = [100, 101]
        store.playNow(100, recentering: baseSnapshot)
        store.playNow(101, recentering: baseSnapshot)
        store.playNext(102)
        store.addToEnd(103)
        
        store.clearQueue()
        
        XCTAssertTrue(store.immediate.isEmpty)
        XCTAssertTrue(store.deferred.isEmpty)
        XCTAssertEqual(store.current, 101)
        XCTAssertEqual(store.history.first, 100)
    }
    
    // MARK: - Query Methods Tests
    
    func testIsQueued() {
        let store = makeStore()
        store.playNow(100, recentering: [100])
        store.playNext(101)
        store.addToEnd(102)
        
        XCTAssertTrue(store.isQueued(101))
        XCTAssertTrue(store.isQueued(102))
        XCTAssertFalse(store.isQueued(100))
        XCTAssertFalse(store.isQueued(999))
    }
    
    func testIsPlaying() {
        let store = makeStore()
        store.playNow(100, recentering: [100])
        
        XCTAssertTrue(store.isPlaying(100))
        XCTAssertFalse(store.isPlaying(101))
    }
    
    func testUpNextQueue() {
        let store = makeStore()
        store.playNow(100, recentering: [100])
        store.playNext(101)
        store.playNext(102)
        store.addToEnd(103)
        store.addToEnd(104)
        
        let queue = store.upNextQueue
        
        // immediate (LIFO order) + deferred (FIFO order)
        XCTAssertEqual(queue, [102, 101, 103, 104])
    }
    
    // MARK: - Autoplay Tests
    
    func testAutoplayToggle() {
        let store = makeStore()
        
        XCTAssertFalse(store.autoplayEnabled)
        
        store.autoplayEnabled = true
        
        XCTAssertTrue(store.autoplayEnabled)
    }
    
    // MARK: - History Limit Tests
    
    func testHistoryMaxSize() {
        let store = makeStore()
        let baseSnapshot = Array((1...60).map { Int64($0) })
        
        // Play through more than 50 items
        for id in baseSnapshot {
            store.playNow(id, recentering: baseSnapshot)
        }
        
        // History should be capped at 50
        XCTAssertLessThanOrEqual(store.history.count, 50)
    }
    
    // MARK: - Queue Limit Tests
    
    func testQueueMaxSize() {
        let store = makeStore()
        store.playNow(1, recentering: [1])
        
        // Try to add 150 items
        for i in 2...150 {
            store.addToEnd(Int64(i))
        }
        
        // Queue should be capped at 100
        let totalQueued = store.immediate.count + store.deferred.count
        XCTAssertLessThanOrEqual(totalQueued, 100)
    }
    
    // MARK: - Skipped Stack Tests
    
    func testSkippedStackBidirectionalNavigation() {
        let store = makeStore()
        // newest-first: [100, 101, 102, 103, 104]
        let baseSnapshot: [Int64] = [100, 101, 102, 103, 104]
        
        // Start at middle (102 at index 2)
        store.playNow(102, recentering: baseSnapshot)
        XCTAssertEqual(store.current, 102)
        
        // Press Previous (position < 3s) - should go to older (103)
        let prev = store.previous(currentPosition: 1.0)
        XCTAssertEqual(prev, 103)
        XCTAssertEqual(store.current, 103)
        
        // 102 should now be in skipped stack
        XCTAssertTrue(store.skipped.contains(102))
        
        // Press Next - should return to 102 from skipped (not go to queue/baseList)
        let next = store.next()
        XCTAssertEqual(next, 102)
        XCTAssertEqual(store.current, 102)
        XCTAssertFalse(store.skipped.contains(102))
    }
    
    func testSkippedStackClearedOnPlayNow() {
        let store = makeStore()
        let baseSnapshot: [Int64] = [100, 101, 102, 103, 104]
        
        store.playNow(102, recentering: baseSnapshot)
        _ = store.previous(currentPosition: 1.0) // Puts 102 in skipped
        XCTAssertFalse(store.skipped.isEmpty)
        
        // Explicit playNow should clear skipped
        store.playNow(100, recentering: baseSnapshot)
        XCTAssertTrue(store.skipped.isEmpty)
    }
    
    func testSkippedStackPriorityOverQueue() {
        let store = makeStore()
        let baseSnapshot: [Int64] = [100, 101, 102, 103, 104]
        
        store.playNow(102, recentering: baseSnapshot)
        store.playNext(200) // Add something to queue
        
        _ = store.previous(currentPosition: 1.0) // Puts 102 in skipped
        XCTAssertEqual(store.current, 103)
        
        // Next should take from skipped first, not queue
        let next = store.next()
        XCTAssertEqual(next, 102) // From skipped, not 200 from queue
        
        // Now next should take from queue
        let next2 = store.next()
        XCTAssertEqual(next2, 200)
    }
    
    // MARK: - Insert Voiceover Ready Tests
    
    func testInsertVoiceoverReadyNewerThanCurrent() {
        let store = makeStore()
        // Full ordered list: [100, 101, 102, 103, 104] (newest-first)
        // But baseList only has [102, 103, 104] initially
        store.playNow(103, recentering: [102, 103, 104])
        XCTAssertEqual(store.baseIndex, 1) // 103 is at index 1 in [102, 103, 104]
        
        // Simulate voiceover becoming ready for 101 (newer than 103)
        store.insertVoiceoverReady(101) { id -> Int? in
            // Full chronological order: 100=0, 101=1, 102=2, 103=3, 104=4
            return [100: 0, 101: 1, 102: 2, 103: 3, 104: 4][id]
        }
        
        // 101 should be inserted before 102 (at position 0)
        XCTAssertTrue(store.baseList.contains(101))
        XCTAssertEqual(store.baseList.firstIndex(of: 101), 0)
        // baseIndex should be adjusted
        XCTAssertEqual(store.baseIndex, 2) // Was 1, now 2 because we inserted before
    }
    
    func testInsertVoiceoverReadyOlderThanCurrent() {
        let store = makeStore()
        // baseList: [100, 101, 102] (newest-first), playing 101
        store.playNow(101, recentering: [100, 101, 102])
        XCTAssertEqual(store.baseIndex, 1)
        
        // Simulate voiceover becoming ready for 105 (older than 102)
        store.insertVoiceoverReady(105) { id -> Int? in
            return [100: 0, 101: 1, 102: 2, 103: 3, 104: 4, 105: 5][id]
        }
        
        // 105 should be inserted at the end
        XCTAssertTrue(store.baseList.contains(105))
        XCTAssertEqual(store.baseList.last, 105)
        // baseIndex should stay the same (inserted after)
        XCTAssertEqual(store.baseIndex, 1)
    }
    
    func testInsertVoiceoverReadySkipsDuplicates() {
        let store = makeStore()
        store.playNow(101, recentering: [100, 101, 102])
        
        let originalCount = store.baseList.count
        
        // Try to insert 100 which is already in baseList
        store.insertVoiceoverReady(100) { _ in 0 }
        
        XCTAssertEqual(store.baseList.count, originalCount)
    }
    
    // MARK: - Validate BaseList Tests
    
    func testValidateBaseListRemovesDeletedItems() {
        let store = makeStore()
        store.playNow(102, recentering: [100, 101, 102, 103, 104])
        store.playNext(200)
        
        // Simulate that 101 and 200 were deleted
        let validIds: Set<Int64> = [100, 102, 103, 104]
        store.validateBaseList(validIds: validIds)
        
        XCTAssertFalse(store.baseList.contains(101))
        XCTAssertFalse(store.immediate.contains(200))
        XCTAssertTrue(store.baseList.contains(102))
    }
    
    func testValidateBaseListRecalculatesBaseIndex() {
        let store = makeStore()
        // [100, 101, 102, 103, 104], current=102 at index 2
        store.playNow(102, recentering: [100, 101, 102, 103, 104])
        XCTAssertEqual(store.baseIndex, 2)
        
        // Delete 100 and 101
        let validIds: Set<Int64> = [102, 103, 104]
        store.validateBaseList(validIds: validIds)
        
        // Now baseList is [102, 103, 104], current=102 should be at index 0
        XCTAssertEqual(store.baseIndex, 0)
    }
    
    // MARK: - Clear Queue vs Clear All Tests
    
    func testClearQueuePreservesBaseList() {
        let store = makeStore()
        store.playNow(102, recentering: [100, 101, 102, 103, 104])
        store.playNext(200)
        store.addToEnd(201)
        
        let originalBaseList = store.baseList
        
        store.clearQueue()
        
        XCTAssertTrue(store.immediate.isEmpty)
        XCTAssertTrue(store.deferred.isEmpty)
        XCTAssertEqual(store.baseList, originalBaseList) // Preserved!
        XCTAssertEqual(store.current, 102) // Preserved!
    }
    
    func testClearAllRemovesEverything() {
        let store = makeStore()
        store.playNow(102, recentering: [100, 101, 102, 103, 104])
        store.playNext(200)
        
        store.clearAll()
        
        XCTAssertTrue(store.immediate.isEmpty)
        XCTAssertTrue(store.deferred.isEmpty)
        XCTAssertTrue(store.baseList.isEmpty)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertTrue(store.skipped.isEmpty)
        XCTAssertNil(store.current)
    }
    
    // MARK: - Expansion Signal Tests
    
    func testNeedsExpansionNearNewerEdge() {
        let store = makeStore()
        // Start near the newer edge (index 2 with 10 items)
        let baseSnapshot: [Int64] = Array(100...109).map { Int64($0) }
        store.playNow(102, recentering: baseSnapshot) // index 2, only 2 items ahead in "next" direction
        
        // With expansionThreshold of 5, being at index 2 should trigger .newer expansion
        XCTAssertEqual(store.needsExpansion, .newer)
    }
    
    func testNeedsExpansionNearOlderEdge() {
        let store = makeStore()
        // Start near the older edge
        let baseSnapshot: [Int64] = Array(100...109).map { Int64($0) }
        store.playNow(108, recentering: baseSnapshot) // index 8, only 1 item behind in "previous" direction
        
        // With expansionThreshold of 5, being at index 8 should trigger .older expansion
        XCTAssertEqual(store.needsExpansion, .older)
    }
    
    func testExpandBaseListNewer() {
        let store = makeStore()
        store.playNow(102, recentering: [100, 101, 102, 103, 104])
        let originalIndex = store.baseIndex // 2
        
        // Expand with newer items
        store.expandBaseList(with: [98, 99], direction: .newer)
        
        // New items prepended, baseIndex adjusted
        XCTAssertEqual(store.baseList.first, 98)
        XCTAssertEqual(store.baseIndex, originalIndex + 2) // Shifted by 2
    }
    
    func testExpandBaseListOlder() {
        let store = makeStore()
        store.playNow(102, recentering: [100, 101, 102, 103, 104])
        let originalIndex = store.baseIndex
        
        // Expand with older items
        store.expandBaseList(with: [105, 106], direction: .older)
        
        // New items appended, baseIndex unchanged
        XCTAssertEqual(store.baseList.last, 106)
        XCTAssertEqual(store.baseIndex, originalIndex)
    }
    
    // MARK: - Has Next/Previous with Skipped Tests
    
    func testHasNextIncludesSkipped() {
        let store = makeStore()
        // [100, 101, 102] - play 101, then previous goes to 102, puts 101 in skipped
        store.playNow(101, recentering: [100, 101, 102])
        XCTAssertEqual(store.baseIndex, 1) // 101 at index 1
        
        // Has next should be true (100 is at index 0)
        XCTAssertTrue(store.hasNext)
        
        // Go to previous (102 at index 2), puts 101 in skipped
        _ = store.previous(currentPosition: 1.0)
        XCTAssertEqual(store.current, 102)
        XCTAssertTrue(store.skipped.contains(101))
        
        // hasNext should still be true because skipped has items
        XCTAssertTrue(store.hasNext)
    }
    
    func testHasPreviousOnlyChecksBaseList() {
        let store = makeStore()
        // [100, 101, 102], play 102 (at end, oldest)
        store.playNow(102, recentering: [100, 101, 102])
        XCTAssertEqual(store.baseIndex, 2)
        
        // No items after index 2, so hasPrevious should be false
        // Even though we could build up history by playing items
        XCTAssertFalse(store.hasPrevious)
        
        // Play 101 (puts 102 in history)
        store.playNow(101, recentering: [100, 101, 102])
        XCTAssertFalse(store.history.isEmpty) // History has 102
        
        // hasPrevious should be true because there's an item after baseIndex (102)
        XCTAssertTrue(store.hasPrevious)
    }
}
