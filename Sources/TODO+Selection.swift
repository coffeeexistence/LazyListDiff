//
//  TODO+Selection.swift
//  ListDiff
//
//  Created by Rivera, John on 11/22/23.
//  Copyright © 2023 ListDiff. All rights reserved.
//

import Foundation

fileprivate class TODO: SelectableListModuleProtocol {
    private var isSelecting = false
    
    // Selection is difficult & complicated with Lazy Diffing... Implement a generic design in the future.
    public func reconcileSelectionAfterCollectionUpdate() {
//        let collectionViewSelectedItems = collectionView.indexPathsForSelectedItems ?? []
//
//        let shouldReconcile = isSelecting || !collectionViewSelectedItems.isEmpty
//        guard shouldReconcile else { return }
//
//        let prevSelectedIndexPaths = Set<IndexPath>(collectionViewSelectedItems)
//        let newSelectedIndexPaths = Set<IndexPath>(viewModel.selectedIndexPaths.indexPaths)
//
//        let indexPathsToSelect = newSelectedIndexPaths.subtracting(prevSelectedIndexPaths)
//        let indexPathsToDeselect = prevSelectedIndexPaths.subtracting(newSelectedIndexPaths)
//
//        indexPathsToSelect.forEach { collectionView.selectItem(at: $0, animated: false, scrollPosition: []) }
//        indexPathsToDeselect.forEach { collectionView.deselectItem(at: $0, animated: false) }
    }

}
