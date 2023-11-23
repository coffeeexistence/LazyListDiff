//
//  LazyDiffTests.swift
//  ListDiff
//
//  Created by Rivera, John on 11/22/23.
//  Copyright © 2023 ListDiff. All rights reserved.
//

import XCTest
import ListDiff

fileprivate struct TestItem: Diffable, Equatable {
    var diffIdentifier: AnyHashable { "\(diffId)" }

    let diffId: String
    let equalityVersion: Int
    
    init(diffId: String, equalityVersion: Int = 1) {
        self.diffId = diffId
        self.equalityVersion = equalityVersion
    }
}

fileprivate struct TestStore: LazyDiffItemStoreProtocol {
    typealias Item = TestItem
    
    let totalCount: Int
    let stateId: UUID = UUID()
    let items: [TestItem]
    
    func lazyDiffCollectItems(in range: ClosedRange<Int>) -> [TestItem]? {
        range.compactMap { self.items[safe: $0] }
    }
}

fileprivate extension DiffableList.Result {
    func XCTAssert(
        expectedChangeCount: Int,
        expectedDeletes: [Int] = [],
        expectedInserts: [Int] = [],
        expectedUpdates: [Int] = [],
        expectedMoves: [DiffableList.MoveIndex] = []
    ) {
        XCTAssertEqual(hasChanges, expectedChangeCount > 0)
        // Updates are treated as delete+insert due to update being unsafe to call in
        // performBatchUpdates, context: https://github.com/Instagram/IGListKit/issues/297
        XCTAssertEqual(Array(deletes), expectedDeletes)
        XCTAssertEqual(Array(inserts), expectedInserts)
        XCTAssertEqual(Array(updates), expectedUpdates)
        XCTAssertEqual(moves, expectedMoves)
        XCTAssertEqual(changeCount, expectedChangeCount)
    }
}

extension Collection {
    subscript(safe index: Index) -> Iterator.Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

fileprivate let A = TestItem(diffId: "A", equalityVersion: 1)
fileprivate let B = TestItem(diffId: "B", equalityVersion: 1)
fileprivate let C = TestItem(diffId: "C", equalityVersion: 1)
fileprivate let D = TestItem(diffId: "D", equalityVersion: 1)
fileprivate let E = TestItem(diffId: "E", equalityVersion: 1)
fileprivate let F = TestItem(diffId: "F", equalityVersion: 1)
fileprivate let G = TestItem(diffId: "G", equalityVersion: 1)
fileprivate let H = TestItem(diffId: "H", equalityVersion: 1)
fileprivate let I = TestItem(diffId: "I", equalityVersion: 1)

fileprivate let A1 = TestItem(diffId: "A", equalityVersion: 1)
fileprivate let B1 = TestItem(diffId: "B", equalityVersion: 1)
fileprivate let C1 = TestItem(diffId: "C", equalityVersion: 1)
fileprivate let D1 = TestItem(diffId: "D", equalityVersion: 1)
fileprivate let E1 = TestItem(diffId: "E", equalityVersion: 1)
fileprivate let F1 = TestItem(diffId: "F", equalityVersion: 1)
fileprivate let G1 = TestItem(diffId: "G", equalityVersion: 1)

fileprivate let A2 = TestItem(diffId: "A", equalityVersion: 2)
fileprivate let B2 = TestItem(diffId: "B", equalityVersion: 2)
fileprivate let C2 = TestItem(diffId: "C", equalityVersion: 2)
fileprivate let D2 = TestItem(diffId: "D", equalityVersion: 2)
fileprivate let E2 = TestItem(diffId: "E", equalityVersion: 2)
fileprivate let F2 = TestItem(diffId: "F", equalityVersion: 2)
fileprivate let G2 = TestItem(diffId: "G", equalityVersion: 2)

class LazyDiffTests: XCTestCase {
    private func getDiff(
        visible: ClosedRange<Int>,
        old: [TestItem],
        new: [TestItem]
    ) -> DiffableList.Result? {
        LazyDiff.diffing(
            old: TestStore(totalCount: old.count, items: old),
            new:  TestStore(totalCount: new.count, items: new),
            currentVisibleRange: visible
        )
    }
    
    // MARK: - Basic tests where all items are visible
    
    func testIdentical_AllVisible() throws {
        let oldStore = TestStore(totalCount: 4, items: [A1, B1, C1, D1])
        let newStore = TestStore(totalCount: 4, items: [A1, B1, C1, D1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 0...3)
        diff!.XCTAssert(expectedChangeCount: 0)
    }
    
    func testPureUpdate_AllVisible() throws {
        let oldStore = TestStore(totalCount: 4, items: [A1, B1, C1, D1])
        let newStore = TestStore(totalCount: 4, items: [A2, B1, C2, D1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 0...3)
        // Updates are treated as delete+insert due to update being unsafe to call in
        // performBatchUpdates, context: https://github.com/Instagram/IGListKit/issues/297
        // However: If there are no shifting changes (delete/move/insert) then we'll send the updates
        // through directly, which is desirable since we'll get the correct animation behavior for
        // actions like favoriting.
        diff!.XCTAssert(
            expectedChangeCount: 2,
            expectedUpdates: [0, 2]
        )
    }
    
    func testMixedUpdate_AllVisible() throws {
        let oldStore = TestStore(totalCount: 4, items: [A1, B1, C1, D1])
        let newStore = TestStore(totalCount: 5, items: [A2, B1, C2, D1, E1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 0...3)
        // Updates are treated as delete+insert due to update being unsafe to call in
        // performBatchUpdates, context: https://github.com/Instagram/IGListKit/issues/297
        diff!.XCTAssert(
            expectedChangeCount: 5,
            expectedDeletes: [0, 2],
            expectedInserts: [0, 2, 4]
        )
    }
    
    // Revisit visibleRange with more realistic visibleRange
    func testInsert_AllVisible() throws {
        let oldStore = TestStore(totalCount: 2, items: [B1, D1])
        let newStore = TestStore(totalCount: 4, items: [A1, B1, C1, D1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 0...1)
        // Old: [0B 1D]
        // New: [0A 1B] 2C 3D
        // Expected: Delete D at 1, Insert A at 0, insert +2 at end
        diff!.XCTAssert(
            expectedChangeCount: 4,
            expectedDeletes: [1],
            expectedInserts: [0, 2, 3]
        )
    }
    
    func testDelete_AllVisible() throws {
        let oldStore = TestStore(totalCount: 4, items: [A1, B1, C1, D1])
        let newStore = TestStore(totalCount: 3, items: [A1, C1, D1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 0...3)
        diff!.XCTAssert(
            expectedChangeCount: 1,
            expectedDeletes: [1],
            expectedInserts: []
        )
    }
    
    func testDeleteAt0_AllVisible() throws {
        let oldStore = TestStore(totalCount: 4, items: [A1, B1, C1, D1])
        let newStore = TestStore(totalCount: 3, items: [B1, C1, D1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 0...3)
        diff!.XCTAssert(
            expectedChangeCount: 1,
            expectedDeletes: [0],
            expectedInserts: []
        )
    }
    
    func testDeleteAt0_BeginningVisible() throws {
        let oldStore = TestStore(totalCount: 4, items: [A1, B1, C1, D1])
        let newStore = TestStore(totalCount: 3, items: [B1, C1, D1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 0...1)
        diff!.XCTAssert(
            expectedChangeCount: 3,
            expectedDeletes: [0, 3],
            expectedInserts: [1]
        )
    }
    
    func testMove_AllVisible() throws {
        let oldStore = TestStore(totalCount: 4, items: [A1, B1, C1, D1])
        let newStore = TestStore(totalCount: 4, items: [A1, C1, B1, D1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 0...3)
        diff!.XCTAssert(
            expectedChangeCount: 2,
            expectedDeletes: [],
            expectedInserts: [],
            expectedMoves: [.init(from: 2, to: 1), .init(from: 1, to: 2)]
        )
    }
    
    // MARK: - Basic tests where subset items are visible
    
    func testIdentical_MiddleVisible() throws {
        let oldStore = TestStore(totalCount: 5, items: [A1, B1, C1, D1, E1])
        let newStore = TestStore(totalCount: 5, items: [A1, B1, C1, D1, E1])
        // Visibility: A[BCD]E
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 1...3)
        diff!.XCTAssert(expectedChangeCount: 0)
    }
    
    func testMiddleUpdate_MiddleVisible() throws {
        let oldStore = TestStore(totalCount: 4, items: [A1, B1, C1, D1, E1])
        let newStore = TestStore(totalCount: 4, items: [A2, B1, C2, D1, E1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 1...3)
        // Visibility: A[BCD]E
        diff!.XCTAssert(
            expectedChangeCount: 1,
            expectedUpdates: [2]
        )
    }
    
    func testEndUpdate_MiddleVisible() throws {
        let oldStore = TestStore(totalCount: 4, items: [A1, B1, C1, D1, E1])
        let newStore = TestStore(totalCount: 4, items: [A1, B1, C1, D1, E2])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 1...3)
        // Changes are outside visible bounds
        diff!.XCTAssert(
            expectedChangeCount: 0,
            expectedDeletes: [],
            expectedInserts: []
        )
    }
    
    func testBeginningUpdate_MiddleVisible() throws {
        let oldStore = TestStore(totalCount: 4, items: [A1, B1, C1, D1, E1])
        let newStore = TestStore(totalCount: 4, items: [A2, B1, C1, D1, E1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 1...3)
        // Changes are outside visible bounds
        diff!.XCTAssert(
            expectedChangeCount: 0,
            expectedDeletes: [],
            expectedInserts: []
        )
    }
    
    func testMiddleInsert_MiddleVisible() throws {
        let oldStore = TestStore(totalCount: 5, items: [A1, B1, C1, D1, E1])
        let newStore = TestStore(totalCount: 6, items: [A1, B1, F1, C1, D1, E1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 1...3)
        // Old: A[BCD]E
        // New: A[BFC]DE
        diff!.XCTAssert(
            expectedChangeCount: 3,
            expectedDeletes: [3], // [D] deleted from visible range
            expectedInserts: [2, 5] // [F] inserted into visible range, +1 unknown index added to end.
        )
    }
    
    func testBeginningInsert_MiddleVisible() throws {
        let oldStore = TestStore(totalCount: 5, items: [A1, B1, C1, D1, E1])
        let newStore = TestStore(totalCount: 6, items: [F1, A1, B1, C1, D1, E1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 1...3)
        // Old: 0A [1B 2C 3D] 4E
        // New: 0F [1A 2B 3C] 4D 5E
        // Expected: Insert A at 1, Delete D at 3, Insert at 5
        diff!.XCTAssert(
            expectedChangeCount: 3,
            expectedDeletes: [3],
            expectedInserts: [1, 5]
        )
    }
    
    func testEndInsert_MiddleVisible() throws {
        let oldStore = TestStore(totalCount: 5, items: [A1, B1, C1, D1, E1])
        let newStore = TestStore(totalCount: 6, items: [A1, B1, C1, D1, E1, F1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 1...3)
        // Old: 0A [1B 2C 3D] 4E
        // New: 0A [1B 2C 3D] 4E 5F
        // Expected: Insert at 5
        diff!.XCTAssert(
            expectedChangeCount: 1,
            expectedDeletes: [],
            expectedInserts: [5]
        )
    }
    
    func testMiddleDelete_MiddleVisible() throws {
        let oldStore = TestStore(totalCount: 6, items: [A1, B1, C1, D1, E1, F1])
        let newStore = TestStore(totalCount: 5, items: [A1, B1, D1, E1, F1])
        // Old: 0A [1B 2C 3D] 4E 5F
        // New: 0A [1B 2D 3E] 4F
        // Expected: Delete C at 2, Insert E at 3, Delete at 5
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 1...3)
        diff!.XCTAssert(
            expectedChangeCount: 3,
            expectedDeletes: [2, 5],
            expectedInserts: [3]
        )
    }
    
    func testMiddleMove_MiddleVisible() throws {
        let oldStore = TestStore(totalCount: 5, items: [A1, B1, D1, E1, F1])
        let newStore = TestStore(totalCount: 5, items: [A1, D1, B1, E1, F1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 1...3)
        diff!.XCTAssert(
            expectedChangeCount: 2,
            expectedDeletes: [],
            expectedInserts: [],
            expectedMoves: [.init(from: 2, to: 1), .init(from: 1, to: 2)]
        )
    }
    
    func testMiddleMoveToEnd_MiddleVisible() throws {
        let oldStore = TestStore(totalCount: 5, items: [A1, B1, C1, D1, E1])
        let newStore = TestStore(totalCount: 5, items: [A1, B1, D1, E1, C1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 1...3)
        // Old: 0A [1B 2C 3D] 4E
        // New: 0A [1B 2D 3E] 4C
        // Expected: Delete C at 2, Insert E at 3
        diff!.XCTAssert(
            expectedChangeCount: 2,
            expectedDeletes: [2],
            expectedInserts: [3],
            expectedMoves: []
        )
    }
    
    func testInsertEnd_BeginningVisible() throws {
        let oldStore = TestStore(totalCount: 5, items: [A1, B1, C1, D1, E1])
        let newStore = TestStore(totalCount: 6, items: [A1, B1, C1, D1, F1, E1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 0...0)
        // Old: [0A] 1B 2C 3D 4E
        // New: [0A] 1B 2C 3D 4F, 5E
        // Expected: Delete C at 2, Insert E at 3
        diff!.XCTAssert(
            expectedChangeCount: 1,
            expectedDeletes: [],
            expectedInserts: [5],
            expectedMoves: []
        )
    }
    
    func testDeletion_deletedBeyondVisibleRange() throws {
        let oldStore = TestStore(totalCount: 7, items: [A1, B1, C1, D1, E1, F1, G1])
        let newStore = TestStore(totalCount: 2, items: [F1, E1])
        let diff = LazyDiff.diffing(old: oldStore, new: newStore, currentVisibleRange: 4...6)
        // Old: A1, B1, C1, D1, [E1, F1, G1]
        // New: 4F, 5E []
        // Expected:
            // Core diff: Delete: G at 6, F at 5, E at 4
            // outer diff reconcilliation: Delete 2 & 3
        // MARK: Updated behavior: Will fall-back to nil since new set is empty for visible range.
        XCTAssertNil(diff)
    }
    
    func testLazyDiff_adjustOffset_deletionShifting() {
        let old: [TestItem] = [A, B, C, D]
        let new: [TestItem] = []
        XCTAssertTrue(
            DiffableList.diffing(oldArray: old, newArray: new)
                .validate(old, new)
        )
        
        XCTAssertTrue(
            DiffableList.diffing(oldArray: old, newArray: new)
                .forBatchUpdates()
                .validate(old, new)
        )
        
        XCTAssertTrue(
            DiffableList.diffing(oldArray: old, newArray: new)
                .forBatchUpdates()
                .adjustingOffset(by: 3)
                .validate(old, new)
        )
        
        XCTAssertTrue(
            DiffableList.diffing(oldArray: old, newArray: new)
                .forBatchUpdates()
                .adjustingOffset(by: 1)
                .validate(old, new)
        )
        
        XCTAssertTrue(
            DiffableList.diffing(oldArray: old, newArray: new)
                .forBatchUpdates()
                .adjustingOffset(by: 0)
                .validate(old, new)
        )
        
        XCTAssertTrue(
            DiffableList.diffing(oldArray: old, newArray: new)
                .forBatchUpdates()
                .adjustingOffset(by: 4)
                .validate(old, new)
        )
    }
    
    func testWeirdDeletionCases() throws {
        // Old: 0A 1B [2C 3D 4E 5F 6G] 7H 8I
        // New: 0A []
        // Expected: 1 through 8
        // MARK: Will now return nil since new set is empty for visible range.
        
        let diff1 = getDiff(
            visible: 2...6,
            old: [A, B, C, D, E, F, G, H, I],
            new: [A]
        )
        XCTAssertNil(diff1)
        
        // Test equivalent insertion scenario
        getDiff(
            visible: 0...0,
            old: [A],
            new: [A, B, C, D, E, F, G, H, I]
        )!.XCTAssert(
            expectedChangeCount: 8,
            expectedInserts: [1, 2, 3, 4, 5, 6, 7, 8]
        )
    }
    
    func testReturnsNilWhenVisibleRangeOutOfBounds() {
        XCTAssertNil(
            getDiff(
                visible: 2...6,
                old: [A],
                new: [A, B, C, D, E, F, G, H, I]
            )
        )
    }
    
    func testDeletion_deletedPartiallyWithinAndBeyondVisibleRange() throws {
        func sanityCheck(visible: ClosedRange<Int>, old: [TestItem], new: [TestItem], expectNil: Bool = false) {
            let diff = LazyDiff.diffing(
                old: TestStore(totalCount: old.count, items: old),
                new:  TestStore(totalCount: new.count, items: new),
                currentVisibleRange: visible
            )
            if expectNil {
                XCTAssertNil(diff)
            } else {
                XCTAssertNotNil(diff)
            }
            
        }
        
        sanityCheck(
            visible: 3...6,
            old: [A, B, C, D, E, F, G],
            new: [A, B, C],
            expectNil: true
        )
        
        sanityCheck(
            visible: 2...6,
            old: [A, B, C, D, E, F, G],
            new: [A, B, C]
        )
        
        sanityCheck(
            visible: 1...6,
            old: [A, B, C, D, E, F, G],
            new: [F, E]
        )
        
        sanityCheck(
            visible: 0...6,
            old: [A, B, C, D, E, F, G, H, I],
            new: [A]
        )
    }
    
    func testGetExtendedLazyDiffVisibleRange() {
        func Assert(
            maxTotalCount: Int,
            visibleRange: ClosedRange<Int>,
            expectedResult: ClosedRange<Int>?
        ) {
            let result = LazyDiff.getExtendedLazyDiffVisibleRange(
                maxTotalCount: maxTotalCount,
                visibleRange: visibleRange
            )
            XCTAssertEqual(result, expectedResult)
        }
        
        // Base case
        Assert(maxTotalCount: 50, visibleRange: 20...30, expectedResult: 9...41)
        
        // Make sure upper bound stops at last valid index.
        Assert(maxTotalCount: 50, visibleRange: 35...45, expectedResult: 24...49)
        
        // Sanity check with small numbers
        Assert(maxTotalCount: 0, visibleRange: 0...0, expectedResult: 0...0)
        Assert(maxTotalCount: 1, visibleRange: 0...0, expectedResult: 0...0)
        Assert(maxTotalCount: 2, visibleRange: 0...0, expectedResult: 0...1)
        
        // If maxTotalCount lower than lower bound of visible range, fall back to visibleRange
        Assert(maxTotalCount: 8, visibleRange: 20...30, expectedResult: 20...30)
        Assert(maxTotalCount: 0, visibleRange: 20...30, expectedResult: 20...30)
        
    }
}

