//
//  LazyDiff.swift
//  ListDiff
//
//  Created by Rivera, John on 11/22/23.
//  Copyright © 2023 ListDiff. All rights reserved.
//

import Foundation
import UIKit

// MARK: - LazyDiff
public protocol LazyDiffItemStoreProtocol {
    associatedtype Item: Diffable & Equatable
    var stateId: UUID { get }
    var totalCount: Int { get }
    func lazyDiffCollectItems(in range: ClosedRange<Int>) -> [Item]?
}


public enum LazyDiff {
    // Use-case: Ultra-lightweight diffing algo specifically for use in UICollectionView performBatchUpdates.
    //
    // Advantages:
    // - Perf: O(n) perfomance where n is visible cells. O(1) perf relative to total cell count.
    // Instead of diffing 200 - 500,000 items in memory, you can just diff the 24 visible indexPaths.
    // - Memory: This diffing algo doesn't require all items to be loaded into memory, just the visible ones.
    //
    // Considerations:
    // - Although the diff for visible items is accurate, inserts/deletions based on totalCount changes
    // are approximate.
    // - Performing batchUpdates based on a diff that was calculated based on outdated visible indexPaths
    // will result in incorrect cell appearance, the diff is only accurate for the visible cells
    // when it was computed.
    // - Since collectionView.indexPathsForVisibleItems can change at any moment, diffing must be
    // performed on the main thread and then immediately (synchronously) applied.
    // - These diffs are suitable for purely index-based collections.
    // - Only single-section layouts are supported at the moment.
    public static func diffing<T: LazyDiffItemStoreProtocol>(
        old: T,
        new: T,
        currentVisibleRange: ClosedRange<Int>
    ) -> DiffableList.Result? {
        guard old.totalCount > currentVisibleRange.upperBound else {
            return nil
        }
        
        guard let oldItems = old.lazyDiffCollectItems(in: currentVisibleRange),
              let newItems = new.lazyDiffCollectItems(in: currentVisibleRange) else { return nil }
        
        // Lazy diffing should fall back to reloadData() if either set is empty.
        guard !oldItems.isEmpty && !newItems.isEmpty else { return nil }
        
        let baseDiff = DiffableList.diffing(oldArray: oldItems, newArray: newItems)
        
        // Updates are treated as delete+insert due to update being unsafe to call in
        // performBatchUpdates, context: https://github.com/Instagram/IGListKit/issues/297
        // However: If there are no shifting changes (delete/move/insert) then we'll send the updates
        // through directly, which is desirable since we'll get the correct animation behavior for
        // non-insert/delete changes.
        let isPureUpdate = baseDiff.onlyContainsUpdates && (old.totalCount == new.totalCount)
        guard !isPureUpdate else {
            return baseDiff.adjustingOffset(by: currentVisibleRange.lowerBound)
        }
        
        var diff = baseDiff
            .forBatchUpdates()
            .adjustingOffset(by: currentVisibleRange.lowerBound)
                        
        let totalCountDelta = new.totalCount - old.totalCount
        let initialDiffDelta = diff.delta
        let endDelta = totalCountDelta - initialDiffDelta
        
        if endDelta > 0 {
            let indexAfterEnd = old.totalCount
            let upperBoundIncrement = endDelta - 1
            // When endDelta == +1 for a range between 0...3, then we'd want to insert to 4...4
            // For endDelta == +2, we'd want to insert 4...5
            diff.inserts.insert(integersIn: indexAfterEnd...(indexAfterEnd + upperBoundIncrement))
        } else if endDelta < 0 {
            let lastIndex = old.totalCount - 1
            let lowerBoundDecrement = -totalCountDelta - 1
            let lowerBound = lastIndex - lowerBoundDecrement
            guard lowerBound <= lastIndex else { return nil }
            let deletionRange = lowerBound...lastIndex
            // When totalCountDelta == -1, for a range between 0...3, then we'd want to delete 3...3
            // For totalCountDelta == -2, we'd want to delete 2...3
            diff.deletes.insert(integersIn: deletionRange)
        }
        
        // Internal sanity check, this should always work. (but if not we'll fall back to hard reload)
        guard totalCountDelta == diff.delta else {
            assertionFailure("LazyDiff: Expected delta of \(totalCountDelta) but got \(diff.delta)")
            return nil
        }
        
        return diff
    }
    
    // Returns visible range padded on top & bottom by 1*visibleRange.count.
    // If range was 40...50 then this would return 30...60. This is useful when prefetching is enabled
    // since it prevents preloaded cells from being unneccesarily deleted by LazyDiff.
    /// Deep dive: When UICollectionView has prefetching disabled, it has 2 cell "states":
    /// 1) Virtual: Layout space is accounted for off-screen cells but no UI is allocated, therefore these are cheap to modify.
    /// 2) Actual: These cells have corresponding UICollectionViewCells rendered, so updates to these are more expensive.
    /// When isPrefetchingEnabled is set to TRUE, there is another state we need to take into account:
    /// 3) Prefetched: This is a non-visible cell that has been created via `collectionView(cellForItemAt`, this has a corresponding
    ///     UICollectionViewCell ready in memory to be displayed. Deleting cells in this this location is more expensive, and so we should
    ///     minimize the odds of that happening by extending LazyDiff's working range.
    /// Important note: This is _not_ a workaround to synchronization issues that can occur between LazyDiff + prefetching. When
    /// prefetching is enabled we must make sure that cell configuration happens on `cellWillDisplay` rather than
    /// `collectionView(cellForItemAt`.
    // Exposed for testing
    public static func getExtendedLazyDiffVisibleRange(
        maxTotalCount: Int,
        visibleRange: ClosedRange<Int>
    ) -> ClosedRange<Int>? {
        guard maxTotalCount > 0 else { return visibleRange }
        // After items are deleted, UICollectionView's visible range could be out of bounds.
        // Return an empty set now, UICollectionView will send us an updated visibleRange once
        // within totalCount once changes have propagated.
        guard maxTotalCount > visibleRange.lowerBound else { return visibleRange }
        
        let minLowerBound = 0
        let maxUpperBound = maxTotalCount - 1
        let lowerBound = max(minLowerBound, visibleRange.lowerBound - visibleRange.count)
        let upperBound = min(maxUpperBound, visibleRange.upperBound + visibleRange.count)
        
        guard lowerBound <= upperBound else {
            // This fallback is perfectly fine to happen in production code, just a minor performance penalty.
            // But it should still be investigated, as it may indicate other issues.
            assertionFailure("ClosedRange Error: Expected \(lowerBound) <= \(upperBound)")
            return visibleRange
        }
        
        return lowerBound...upperBound
    }
}

// MARK: - Protocols & Helpers

public extension UICollectionView {
    func getLazyDiff<T: LazyDiffItemStoreProtocol>(old: T, new: T, maxTotalCountChange: Int) -> ListChange.Diff? {
        guard maxTotalCountChange > abs(old.totalCount - new.totalCount) else { return nil }
        
        return getLazyDiffWorkingRange(oldTotalCount: old.totalCount, newTotalCount: new.totalCount)
            .flatMap { LazyDiff.diffing(old: old, new: new, currentVisibleRange: $0) }
            .flatMap { ListChange.Diff(diff: $0, prevStateId: old.stateId) }
    }
    
    fileprivate func getLazyDiffWorkingRange(oldTotalCount: Int, newTotalCount: Int) -> ClosedRange<Int>? {
        isPrefetchingEnabled
            ? getExtendedLazyDiffVisibleRange(maxTotalCount: oldTotalCount)
            : getLazyDiffVisibleRange()
    }
    
    fileprivate func getLazyDiffVisibleRange() -> ClosedRange<Int>? {
        // Lazy diffing only supports single-section non-empty Collections
        guard numberOfSections == 1 else { return nil }
        return indexPathsForVisibleItems.lazy.map(\.row).getMinMaxValueRange()
    }
    
    fileprivate func getExtendedLazyDiffVisibleRange(maxTotalCount: Int) -> ClosedRange<Int>? {
        guard let visibleRange = getLazyDiffVisibleRange() else { return nil }
        return LazyDiff.getExtendedLazyDiffVisibleRange(
            maxTotalCount: maxTotalCount,
            visibleRange: visibleRange
        )
    }
}

public extension Collection where Element == Int {
    func getMinMaxValueRange() -> ClosedRange<Int>? {
        guard !isEmpty else { return nil }
        return self.min()!...self.max()!
    }
}
