//
//  LazyCollectionCell.swift
//  ListDiff
//
//  Created by Rivera, John on 11/22/23.
//  Copyright © 2023 ListDiff. All rights reserved.
//

import UIKit

public class LazyCollectionCell: UICollectionViewCell {
    public var isReadyForConfiguration: Bool = true
    
    // This should be overridden, make sure to always call super()
    override public func prepareForReuse() {
        isReadyForConfiguration = true
        super.prepareForReuse()
    }
}
