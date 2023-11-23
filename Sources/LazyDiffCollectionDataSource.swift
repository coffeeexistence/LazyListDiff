//
//  LazyDiffCollectionViewManager.swift
//  ListDiff
//
//  Created by Rivera, John on 11/22/23.
//  Copyright © 2023 ListDiff. All rights reserved.
//


import UIKit
import Combine

public enum SelectionReconcilliation {
    case selected(IndexPath)
    case deselected(IndexPath)
}

/// A collection view controller acting as data source.
/// `CollectionType` needs to be a collection of collections to represent sections containing rows.
public class LazyDiffCollectionDataSource<CellType: LazyCollectionCell>: NSObject, UICollectionViewDataSource {
    
    public typealias ConfigureCellForDisplay = (CellType, IndexPath) -> SelectionReconcilliation?
            
    private var cancellables = [AnyCancellable]()
    
    private let cellIdentifier: String
    private let configureCellForDisplay: ConfigureCellForDisplay
        
    private var structure: [Int] = []
    public var offsetAtStartOfSection: [Int: Int] = [:]
    
    /// Should the table updates be animated or static.
    public var animated = true
    
    /// The collection view for the data source
    unowned let collectionView: UICollectionView
    
    /// A fallback data source to implement custom logic like indexes, dragging, etc.
    public var dataSource: UICollectionViewDataSource?
        
    /// Publishes if any new item is added or some item gets removed
    private let itemUpdateHandler: (() -> ())?
    
    private let allowDiffUpdates: Bool
        
    // MARK: - Init
    
    /// An initializer that takes a cell type and identifier and configures the controller to dequeue cells
    /// with that data and configures each cell by calling the developer provided `cellConfig()`.
    /// - Parameter cellIdentifier: A cell identifier to use to dequeue cells from the source collection view
    /// - Parameter cellType: A type to cast dequeued cells as
    /// - Parameter cellConfig: A closure to call before displaying each cell
    public init(
        cellIdentifier: String,
        cellType: CellType.Type,
        configureCellForDisplay: @escaping ConfigureCellForDisplay,
        itemUpdateHandler: (() -> ())? = nil,
        collectionView: UICollectionView,
        allowDiffUpdates: Bool
    ) {
        self.configureCellForDisplay = configureCellForDisplay
        self.cellIdentifier = cellIdentifier
        self.itemUpdateHandler = itemUpdateHandler
        self.collectionView = collectionView
        self.allowDiffUpdates = allowDiffUpdates
        
        super.init()
    }
    
    public func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        let cell = cell as! CellType
        if !cell.isReadyForConfiguration {
            /// When isPrefetchingEnabled is true, it may pluck a recently hidden cell in the prefetch cell pool.
            /// This cell's state might not be up-to-date due to lazy-diffing optimizations, so we should reset it to a configurable state.
            cell.prepareForReuse()
            // Ensure cell override properly set up to set value to true after prepareForReuse.
            assert(cell.isReadyForConfiguration)
            // Sync selection state with UICollectionView, just like it would be if it were a fresh cell.
            // We must do this since we called prepareForReuse().
            if let indexPathsForSelectedItems = collectionView.indexPathsForSelectedItems,
               !indexPathsForSelectedItems.isEmpty {
                   cell.isSelected = indexPathsForSelectedItems.contains(indexPath)
               }
        }
        
        // Applies a selection reconcilliation update if one was determined during the configuration of the cell
        // We should be both selecting the item in the collection view as well as on the existing cell to ensure
        // that the selection state is synced during cellWillDisplay.
        if let selectionUpdate = configureCellForDisplay(cell, indexPath) {
            switch selectionUpdate {
            case .selected(let indexPath):
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
                cell.isSelected = true
            case .deselected(let indexPath):
                collectionView.deselectItem(at: indexPath, animated: false)
                cell.isSelected = false
            }
        }
            
        cell.isReadyForConfiguration = false
    }
    
    // MARK: - Update collection
        
    fileprivate func updateCollection(_ listChange: ListChange) -> ListChange.FinalChange {
        let didStructureChange = listChange.sectionCounts != self.structure
        
        let isEmptyChange = !didStructureChange && self.structure == [0]
        guard !isEmptyChange else { return .noneExtraneous }
        
        let isFlatList = listChange.sectionCounts.count == 1 && self.structure.count == 1
        let prevStructure = self.structure
        self.structure = listChange.sectionCounts
        
        var last = 0
        var i = 0
        for sectionCount in structure {
            offsetAtStartOfSection[i] = last
            last += sectionCount
            i += 1
        }
        
        // From Apple docs: If the collection view's layout is not up to date before you call performBatchUpdates, a reload may
        // occur. To avoid problems, you should update your data model inside the updates block or ensure the layout is
        // updated before you call performBatchUpdates(_:completion:).
        collectionView.layoutIfNeeded()
        
        var finalChangeApplied: ListChange.FinalChange
        
        if isFlatList && hasPerformedInitialReload && allowDiffUpdates {
            finalChangeApplied = performListChange(listChange, prevStructure: prevStructure)
        } else {
            finalChangeApplied = .reloadAll(reason: !hasPerformedInitialReload ? "Initial load" : "Diffing disabled")
            hasPerformedInitialReload = true
            collectionView.reloadData()
        }
        
        prevListChangeStateId = listChange.newStateId
        
        if !finalChangeApplied.isNoneExtraneous {
            itemUpdateHandler?()
        }
                
        if santiyCheckingEnabled && finalChangeApplied.isSanityCheckHelpful {
            sanityCheckVisibleCells(from: finalChangeApplied)
        }
        
        return finalChangeApplied
    }
    
    var hasPerformedInitialReload = false
    var prevListChangeStateId: UUID? = nil
    
    // Note: performListChange currently only supports flat (only 1 section) structures.
    private func performListChange(_ change: ListChange, prevStructure: [Int]) -> ListChange.FinalChange {
        guard change.hasChanges else {
            if prevStructure != change.sectionCounts {
                assertionFailure("Consistency error: Expected changes in listChange since structure changed from \(prevStructure) to \(change.sectionCounts).")
                collectionView.reloadData()
                return .reloadAllIntegrityFallback
            }
            return .noneExtraneous
        }
                
        switch change.calculateAction(collectionView) {
        case .update(let updates):
            let visibleIndexPaths = Set(collectionView.indexPathsForVisibleItems)
            
            let indexPathsToReload = updates
                .map { IndexPath(item: $0, section: 0) }
                .filter { visibleIndexPaths.contains($0) }
            
            guard !indexPathsToReload.isEmpty else { return .noneExtraneous }
            
            UIView.performWithoutAnimation {
                let selectedIndexPaths = Set<IndexPath>(collectionView.indexPathsForSelectedItems ?? [])
                // Skip expensive cell discard + layout, just update what needs to be updated.
                for indexPath in indexPathsToReload {
                    guard let cell = collectionView.cellForItem(at: indexPath) as? CellType else {
                            assertionFailure()
                            continue
                    }
                    cell.prepareForReuse()
                    let _ = self.configureCellForDisplay(cell, indexPath)
                    // Restore selection state after prepareForReuse.
                    cell.isSelected = selectedIndexPaths.contains(indexPath)
                }
            }
            
            return .update(updates)
            
        case .reloadAll:
            collectionView.reloadData()
            return .reloadAll(reason: "Directly requested")
            
        case .applyDiff(let diff):
            guard diff.hasChanges else { return .noneExtraneous }
            
            /// ListDiff (taken from IGListKit) currently replaces `update` with `insert+delete`  due to issues that can arise
            /// when moving sections & applying updates in the same batch update. This is just a sanity check for future devs.
            /// If a diff only contains updates (eg bulk edit of some sort) then LazyDiff is smart enough to use ListChange.Action.update(IndexSet)
            /// instead.
            assert(diff.diff.updates.isEmpty, "Ensure .forBatchUpdates() has been called on diff before applying")
            
            guard self.prevListChangeStateId == diff.prevStateId else {
                collectionView.reloadData()
                return .reloadAllIntegrityFallback
            }
            
            let expectedItemCount = change.sectionCounts.indices.contains(0)
                ? change.sectionCounts[0]
                : 0
            
            let projectedItemCount = collectionView.numberOfItems(inSection: 0) + diff.delta
            
            guard expectedItemCount == projectedItemCount else {
                assertionFailure("Expected net change of batch to equal \(expectedItemCount) but got \(projectedItemCount)")
                collectionView.reloadData()
                return .reloadAllIntegrityFallback
            }
            
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: 0,
                options: [],
                animations: {
                    self.collectionView.performBatchUpdates(diff: diff.diff)
                },
                completion: { _ in }
            )
                        
            guard self.collectionView.numberOfItems(inSection: 0) == expectedItemCount else {
                assertionFailure("collectionView.numberOfItems did not match expectedItemCount")
                collectionView.reloadData()
                return .reloadAllIntegrityFallback
            }
            
            return .applyDiff(diff)
            
        case .applyLazyDiff:
            fatalError("performListChange: Expected calculateAction() to resolve .applyLazyDiff into either .reloadAll or .applyDiff")
        }
    }
    
    // MARK: - UITableViewDataSource protocol
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return structure.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return structure[section]
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        return collectionView.dequeueReusableCell(withReuseIdentifier: cellIdentifier, for: indexPath) as! CellType
    }
    
    // MARK: - Fallback data source object
    
    // TODO: Expand on this in documentation.
    override public func forwardingTarget(for aSelector: Selector!) -> Any? {
        return dataSource
    }
    
    private var santiyCheckingEnabled: Bool = false
    private var getDiffIdentifier: ((IndexPath) -> AnyHashable?)?
    fileprivate func enableSanityChecking(getDiffIdentifier: @escaping (IndexPath) -> AnyHashable?) {
        self.santiyCheckingEnabled = true
        self.getDiffIdentifier = getDiffIdentifier
    }
    
    private func sanityCheckVisibleCells(from change: ListChange.FinalChange) {
        guard let getDiffIdentifier = getDiffIdentifier else {
            assertionFailure("missing required dependencies for sanity checking")
            return
        }
        
        let mismatchedIndexPaths = collectionView.indexPathsForVisibleItems.filter { indexPath in
            guard let cell = self.collectionView.cellForItem(at: indexPath) else { return false }
            guard let cell = cell as? DiffableCollectionViewCellProtocol else {
                assertionFailure("reconcileCellAtIndexPath can only be used on cells that conform to DiffableCollectionViewCellProtocol")
                return false
            }
            let expectedDiffIdentifier = getDiffIdentifier(indexPath)
            let isMismatched = cell.diffIdentifier != expectedDiffIdentifier
            if isMismatched {
                assertionFailure("Sanity Check: Expected identifier \(String(describing: expectedDiffIdentifier)) at \(indexPath) but got \(cell.diffIdentifier) instead.")
            }
            return isMismatched
        }
        
        // Sanity check failed
        guard !mismatchedIndexPaths.isEmpty else { return }
        
        // Note: There's a small chance that this check could fail due to datasource being updated from
        // a background queue & there just happens to be a pending update. This would be a false-positive.
        assertionFailure("Sanity Check: Mismatched index paths: \(mismatchedIndexPaths) from change: \(change)")
    }
}

public protocol DiffableCollectionViewCellProtocol {
    var diffIdentifier: AnyHashable { get }
}

public enum LazyCollectionViewIntegrityCheckingMode {
    case off
    case on(getDiffIdentifier: (IndexPath) -> AnyHashable?)
}

extension UICollectionView {
    /// Receives `ListChange` input and updates a sectioned
    /// (or flat) collection view. Please note that only .reloadAll is supported for non-flat lists.
    public func bind<CellType>(
        source: LazyDiffCollectionDataSource<CellType>,
        selectionModule: SelectableListModuleProtocol?,
        listChanges: AnyPublisher<ListChange, Never>,
        integrityCheckingMode: LazyCollectionViewIntegrityCheckingMode,
        recordListChange: ((ListChange.FinalChange) -> ())? = nil,
        cancellables: inout [AnyCancellable]
    ) {
        dataSource = source
        
        if case .on(let getDiffIdentifier) = integrityCheckingMode {
            source.enableSanityChecking(getDiffIdentifier: getDiffIdentifier)
        }
                
        listChanges.sink { [weak self, weak source, weak selectionModule] change in
            guard let self = self, let source = source else { return }
            
            if self.dataSource == nil { self.dataSource = source }
            
            let finalChangeApplied = source.updateCollection(change)
            recordListChange?(finalChangeApplied)
            
            if let selectionModule = selectionModule {
                selectionModule.reconcileSelectionAfterCollectionUpdate()
            }
        }
        .store(in: &cancellables)
    }
}

public protocol SelectableListModuleProtocol: AnyObject {
    func reconcileSelectionAfterCollectionUpdate()
}
