//
//  ListChange.swift
//  ListDiff
//
//  Created by Rivera, John on 11/22/23.
//  Copyright © 2023 ListDiff. All rights reserved.
//

import UIKit

public struct ListChange {
    public enum Constants {
        // If totalCount has changed by more than this value, then skip diffing and just to a reloadData().
        public static let defaultLazyDiffMaxTotalCountChange = 1000
    }
    
    // Calculates diff once ListChange reaches collectionView on main thread.
    // Since the diff is minimized to only perform O(n) diffing on currently visible items, the
    // perf hit is usually sub-millisecond on release builds.
    // This lazy diffing algo approximates changes for non-visible cells and exact for visible cells,
    // thus it is important that the diff is calculated on main immediately before the changes are
    // applied.
    public static func applyLazyDiff<T: LazyDiffItemStoreProtocol>(
        old: T?,
        new: T,
        maxTotalCountChange: Int = Constants.defaultLazyDiffMaxTotalCountChange
    ) -> ListChange {
        var action = Action.reloadAll
        
        if let old = old {
            action = .applyLazyDiff { collectionView in
                collectionView.getLazyDiff(old: old, new: new, maxTotalCountChange: maxTotalCountChange)
            }
        }
        
        return ListChange(
            action,
            sectionCounts: [new.totalCount],
            newStateId: new.stateId
        )
    }
    
    public static func reloadAll(sectionCounts: [Int], newStateId: UUID) -> ListChange {
        ListChange(.reloadAll, sectionCounts: sectionCounts, newStateId: newStateId)
    }
    
    public struct Diff {
        let diff: DiffableList.Result
        let prevStateId: UUID?
        var hasChanges: Bool { diff.hasChanges }
        var delta: Int { diff.delta }
        var onlyContainsUpdates: Bool { diff.onlyContainsUpdates }
    }
    
    public enum Action {
        case reloadAll
        case applyDiff(Diff)
        // Don't make any changes to the collectionview, only read values.
        case applyLazyDiff((UICollectionView) -> Diff?)
        case update(IndexSet)
    }
    
    public enum FinalChange {
        case reloadAll(reason: String)
        case reloadAllIntegrityFallback
        case applyDiff(Diff)
        case update(IndexSet)
        case noneExtraneous
        
        var name: String {
            switch self {
            case .reloadAll: return "reloadAll"
            case .reloadAllIntegrityFallback: return "reloadAllIntegrityFallback"
            case .applyDiff: return "applyDiff"
            case .update: return "update"
            case .noneExtraneous:  return "noneExtraneous"
            }
        }
        
        var metric: ListChangeMetric {
            switch self {
            case .reloadAll: return .ListChange_ReloadAll
            case .reloadAllIntegrityFallback: return .ListChange_ReloadAll_IntegrityFallback
            case .applyDiff: return .ListChange_ApplyDiff
            case .update: return .ListChange_Update
            case .noneExtraneous: return .ListChange_None_Extraneous
            }
        }
                
        var isSanityCheckHelpful: Bool {
            switch self {
            case .reloadAll, .reloadAllIntegrityFallback, .noneExtraneous: return false
            case .applyDiff, .update: return true
            }
        }
        
        var isNoneExtraneous: Bool {
            switch self {
            case .noneExtraneous: return true
            default: return false
            }
        }
    }
        
    let sectionCounts: [Int]
    let newStateId: UUID
    private let action: Action
        
    // Must be calculated immediately (synchronously) before applying changes to collectionView.
    func calculateAction(_ collectionView: UICollectionView) -> Action {
        switch action {
        case .applyLazyDiff(let calculateDiff):
            guard let diff = calculateDiff(collectionView) else { return .reloadAll }
            if diff.onlyContainsUpdates {
                return .update(diff.diff.updates)
            } else {
                return .applyDiff(diff)
            }
            
        default:
            return action
        }
    }
    
    public init(_ action: Action, sectionCounts: [Int], newStateId: UUID) {
        self.action = action
        self.sectionCounts = sectionCounts
        self.newStateId = newStateId
    }
    
    var hasChanges: Bool {
        switch self.action {
        case .applyDiff(let diff): return diff.hasChanges
        case .update(let updates): return !updates.isEmpty
        case .reloadAll, .applyLazyDiff: return true
        }
    }
}

public enum ListChangeMetric {
    case ListChange_ReloadAll
    case ListChange_ReloadAll_IntegrityFallback
    case ListChange_ApplyDiff
    case ListChange_Update
    case ListChange_None_Extraneous
}
