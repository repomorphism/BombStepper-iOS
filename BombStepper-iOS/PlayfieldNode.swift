//
//  PlayfieldNode.swift
//  BombStepper-iOS
//
//  Created by Paul on 4/21/17.
//  Copyright © 2017 Mathemusician.net. All rights reserved.
//

import SpriteKit


private let outerFrameWidth = 4
private let innerFrameWidth = 1


private typealias BlockTileGroupMap = [Block.BlockType : SKTileGroup]


final class PlayfieldNode: SKNode {

    let sceneSize: CGSize
    private let blockWidth: CGFloat

    private let tileMapNode: SKTileMapNode
    private let cropNode: SKCropNode
    private let outerFrameNode: SKShapeNode
    private let innerFrameNode: SKShapeNode
    private var blockTileGroupMap: BlockTileGroupMap
    private let settingManager: SettingManager
    private var ghostOpacity: CGFloat {
        didSet {
            guard ghostOpacity != oldValue else { return }
            updateTileSet(ghostOpacity: ghostOpacity)
        }
    }


    init(sceneSize: CGSize) {
        self.sceneSize = sceneSize
        blockWidth = CGFloat((Int(sceneSize.height) - outerFrameWidth * 2)/20)
        blockTileGroupMap = PlayfieldNode.createTileGroupMap(tileWidth: blockWidth, ghostOpacity: Alpha.ghostDefault)
        (tileMapNode, innerFrameNode, outerFrameNode, cropNode) = PlayfieldNode.createNodes(blockWidth: blockWidth)
        settingManager = SettingManager()
        ghostOpacity = Alpha.ghostDefault

        super.init()

        cropNode.addChild(tileMapNode)
        [outerFrameNode, innerFrameNode, cropNode].forEach(addChild)

        settingManager.updateSettingsAction = { [weak self] settings in
            DispatchQueue.main.async { self?.ghostOpacity = CGFloat(settings.ghostOpacity) }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func fadeIn() {
        [outerFrameNode, innerFrameNode, tileMapNode].forEach { $0.alpha = 0 }
        self.alpha = 1
        tileMapNode.run(.fadeIn(withDuration: 1))
        innerFrameNode.run(.sequence([.wait(forDuration: 0.5),
                                      .fadeIn(withDuration: 1)]))
        outerFrameNode.run(.sequence([.wait(forDuration: 1),
                                      .fadeIn(withDuration: 1)]))
    }

//    func clearField() { tileMapNode.fill(with: nil) }

    func place(blocks: [Block], automapping: Bool = true)  {
        DispatchQueue.main.async {
            if !automapping {
                // TODO: do a copy at top lines
                self.tileMapNode.enableAutomapping = false
                self.tileMapNode.enableAutomapping = true
            }
            
            blocks.forEach {
                
                // TODO: layer field on top of static background, blanks don't draw
                
                // TODO: layer field on top of static background, blanks don't draw
                
                if case .blank = $0.type {
                    self.tileMapNode.setTileGroup(nil, forColumn: $0.x, row: $0.y)
                }
                else {
                    self.tileMapNode.setTileGroup(self.tileGroup(for: $0.type), forColumn: $0.x, row: $0.y)
                }
            }
        }
        
    }

    private func tileGroup(for t: Block.BlockType) -> SKTileGroup {
        return blockTileGroupMap[t]!
    }

    private func updateTileSet(ghostOpacity: CGFloat) {
        // Note: I don't know why changing the tile set causes it to behave correctly,
        // i.e. immediately re-render with the new set without a place() call
        // Seems magical esp. the ghost piece now has a new image, but maybe it
        // has a way of identifying the tile groups as being the same?
        // To help it does that I'll set group names
        blockTileGroupMap = PlayfieldNode.createTileGroupMap(tileWidth: blockWidth, ghostOpacity: ghostOpacity)
        tileMapNode.tileSet = SKTileSet(tileGroups: Array(blockTileGroupMap.values))
    }

}


private extension PlayfieldNode {

    class func createTileGroupMap(tileWidth: CGFloat, ghostOpacity: CGFloat) -> BlockTileGroupMap {

        var map = BlockTileGroupMap()

        let allAdjacencies = allAdjacencyOptionSets()

        Block.BlockType.allCases.forEach { type in
            let tileGroup: SKTileGroup
            switch type {
            case .blank:
                let image = type.defaultImage(side: tileWidth)
                let texture = SKTexture(image: image)
                let tileDefinition = SKTileDefinition(texture: texture)
                tileGroup = SKTileGroup(tileDefinition: tileDefinition)
            case .ghost(let t):
                let image = type.ghostImage(side: tileWidth, tetromino: t, alpha: ghostOpacity)
                let texture = SKTexture(image: image)
                let tileDefinition = SKTileDefinition(texture: texture)
                tileGroup = SKTileGroup(tileDefinition: tileDefinition)
            case .active, .locked:
                let rules: [SKTileGroupRule] = allAdjacencies.map { adjacency in
                    let image = type.defaultImage(side: tileWidth, adjacency: adjacency)
                    let texture = SKTexture(image: image)
                    let definition = SKTileDefinition(texture: texture)
//                    definition.userData = ["adjacency" : adjacency]
                    
                    return SKTileGroupRule(adjacency: adjacency, tileDefinitions: [definition])
                }
                tileGroup = SKTileGroup(rules: rules)
            }
            tileGroup.name = type.name
            map[type] = tileGroup
        }

        return map
    }

    class func createNodes(blockWidth: CGFloat) -> (tileMap: SKTileMapNode, innerFrame: SKShapeNode, outerFrame: SKShapeNode, cropNode: SKCropNode) {

        // The tile map has 4 extra rows on top for auxiliary rendering, and is masked out.
        // Normal field update should happen in the lower 20 rows only.
        // Tile set is set after getting user settings back.
        let tileSize = CGSize(width: blockWidth, height: blockWidth)
        let tileMapNode = SKTileMapNode(tileSet: SKTileSet(tileGroups: []), columns: 10, rows: 24, tileSize: tileSize)
        tileMapNode.position.y = blockWidth * 2

        let fieldRect = CGRect(x: -blockWidth * 5, y: -blockWidth * 10,
                               width: blockWidth * 10, height: blockWidth * 20)
        let innerFrameRect = fieldRect.insetBy(dx: -CGFloat(innerFrameWidth), dy: -CGFloat(innerFrameWidth))
        let outerFrameRect = fieldRect.insetBy(dx: -CGFloat(outerFrameWidth), dy: -CGFloat(outerFrameWidth))

        let innerFrameNode = SKShapeNode(rect: innerFrameRect, cornerRadius: 2)
        innerFrameNode.fillColor = .playfieldBorder
        innerFrameNode.lineWidth = 0
        innerFrameNode.zPosition = ZPosition.playfieldInnerFrame

        let outerFrameNode = SKShapeNode(rect: outerFrameRect, cornerRadius: 4)
        outerFrameNode.fillColor = .playfieldOuterFrame
        outerFrameNode.lineWidth = 0
        outerFrameNode.zPosition = ZPosition.playfieldOuterFrame

        let maskNode = SKShapeNode(rect: fieldRect)
        maskNode.fillColor = #colorLiteral(red: 0.168627451, green: 0.168627451, blue: 0.168627451, alpha: 1)
        maskNode.lineWidth = 0
        let cropNode = SKCropNode()
        cropNode.maskNode = maskNode

        return (tileMap: tileMapNode, innerFrame: innerFrameNode, outerFrame: outerFrameNode, cropNode: cropNode)
    }

}


private func allAdjacencyOptionSets() -> [SKTileAdjacencyMask] {
    let none: SKTileAdjacencyMask = []
    var sets = [none]

    for adjacency in [SKTileAdjacencyMask.adjacencyUp, .adjacencyDown, .adjacencyLeft, .adjacencyRight] {
        sets = sets + sets.map {
            var new = $0
            new.insert(adjacency)
            return new
        }
    }

    return sets
}













