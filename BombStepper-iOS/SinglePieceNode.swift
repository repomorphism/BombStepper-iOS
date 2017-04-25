//
//  SinglePieceNode.swift
//  BombStepper-iOS
//
//  Created by Paul on 4/25/17.
//  Copyright © 2017 Mathemusician.net. All rights reserved.
//

import SpriteKit


final class SinglePieceNode: SKTileMapNode {

    fileprivate let tileWidth: CGFloat

    /// When creating multiple of this guy, may want to skip generating
    /// the same tile groups by taking from one already generated
    fileprivate(set) var blockTileGroupMap: BlockTileGroupMap
    
    init(tileWidth: CGFloat, blockTileGroupMap: BlockTileGroupMap = [:]) {
        self.tileWidth = tileWidth
        self.blockTileGroupMap = (!blockTileGroupMap.isEmpty) ? blockTileGroupMap : SinglePieceNode.generateTileGroupMap(tileWidth: tileWidth)
        
        let tileSet = SKTileSet(tileGroups: Array(self.blockTileGroupMap.values))
        let size = CGSize(width: tileWidth, height: tileWidth)
        
        super.init(tileSet: tileSet, columns: 4, rows: 2, tileSize: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ tetromino: Tetromino) {
        fill(with: nil)
        let tileGroup = blockTileGroupMap[Block.BlockType.active(tetromino)]
        let piece = Piece(type: tetromino, x: 1, y: 0)
        for block in piece.blocks {
            setTileGroup(tileGroup, forColumn: block.x, row: block.y)
        }
    }
}


extension SinglePieceNode {
    class func generateTileGroupMap(tileWidth: CGFloat) -> BlockTileGroupMap {
        var map = BlockTileGroupMap()
        for type in Tetromino.allCases.map({ Block.BlockType.active($0) }) {
            map[type] = type.tileGroup(tileWidth: tileWidth)
        }
        return map
    }
}

