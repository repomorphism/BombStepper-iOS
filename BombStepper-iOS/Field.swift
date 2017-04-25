//
//  Field.swift
//  BombStepper-iOS
//
//  Created by Paul on 4/22/17.
//  Copyright © 2017 Mathemusician.net. All rights reserved.
//

import Foundation


/// Field does work on a separate queue, so delegate might want to dispatch back to main
protocol FieldDelegate: class {
    func updateField(blocks: [Block])
    func fieldActivePieceDidTouchBottom(touching: Bool)
    func fieldActivePieceDidLock()
}


/**
 A field is a model of what is presently on the playfield.  It handles the logic
 of how the playing piece behave on the field, reports how field changes at the
 individual blocks level, and handles things like piece locking, line clears, 
 and top out. The field size is 40 x 10, twice as high as the visible part.
 Only changes in the visible half is reported.  For soft drop lock timing,
 call update for each scene tick.
 */
final class Field {


    enum StartPieceResult {
        case success
        case stillHasActivePiece
        case toppedOut
    }


    weak var delegate: FieldDelegate?

    // Data for the whole 40 x 10 field
    fileprivate var allBlocks: [Block.BlockType]
    // Changes are keyed by their index, so multiple changes on same place is overridden
    fileprivate var unreportedChanges: [Int : (newBlock: Block, oldType:Block.BlockType)] = [:]
    // Put most operations on a serial queue to make access on the two properties above atomic
    fileprivate let queue = DispatchQueue(label: "net.mathemusician.BombStepper.Field")

    fileprivate var activePiece: Piece? {
        didSet { updateActivePiece(current: activePiece, previous: oldValue) }
    }

    fileprivate var ghostPiece: Piece?

    fileprivate var hideGhost = false
    fileprivate var dasFrames = 1
    fileprivate var dasFrameCounter = 0
    fileprivate var softDropFrames = 1
    fileprivate var softDropFrameCounter = 0
    // TODO: Move soft drop logic out

    init(delegate: FieldDelegate? = nil) {
        self.delegate = delegate
        allBlocks = Array<Block.BlockType>(repeating: Block.BlockType.blank, count: 10 * 40)
    }

}


extension Field: SettingsNotificationTarget {
    func settingsDidUpdate(_ settings: SettingsManager) {
        dasFrames      = settings.dasFrames
        softDropFrames = settings.softDropFrames
        hideGhost      = settings.hideGhost
    }
}


extension Field {

    
    // WISHLIST: gravity setting

    
    /// Top out is reported here
    @discardableResult
    func startPiece(type: Tetromino) -> StartPieceResult {
        var result: StartPieceResult = .success
        queue.sync {
            guard activePiece == nil else {
                result = .stillHasActivePiece
                return
            }

            let piece = Piece(type: type, x: 4, y: 20)

            guard !pieceIsObstructed(piece) else {
                result = .toppedOut
                return
            }

            defer {
                self.activePiece = piece
                reportChanges()
            }
        }
        return result
    }

    func process(input: Button) {
        queue.async { self.processAsync(input: input) }
    }

    func process(das: XDirection) {
        queue.async { self.processAsync(das: das) }
    }

    func shift(_ offset: Offset) {
        queue.async { self.shiftAsync(offset) }
    }

    func reset() {
        (0 ..< allBlocks.count).forEach { allBlocks[$0] = .blank }
        activePiece = nil
        ghostPiece = nil
        unreportedChanges.removeAll()
    }

}


private extension Field {

    func updateActivePiece(current: Piece?, previous: Piece?) {
        previous?.blocks.forEach(clearBlock)
        ghostPiece?.blocks.forEach(clearBlock)

        ghostPiece = hideGhost ? nil : current.map(positionedGhost)
        ghostPiece?.blocks.forEach(setBlock)
        current?.blocks.forEach(setBlock)
    }

    func processAsync(input: Button) {
        guard activePiece != nil else { return }
        switch input {
        case .moveLeft: moveActivePiece((x: -1, y: 0))
        case .moveRight: moveActivePiece((x: 1, y: 0))
        case .hardDrop: hardDrop()
        case .softDrop: softDrop()
        case .hold: break
        case .rotateLeft: rotateLeft()
        case .rotateRight: rotateRight()
        case .none: break
        }
        reportChanges()
    }

    func processAsync(das: XDirection) {
        dasFrameCounter += 1
        guard dasFrameCounter >= dasFrames else { return }
        dasFrameCounter = 0

        if moveActivePiece(das.offset), dasFrames == 0 {
            while moveActivePiece(das.offset) { }
        }

        reportChanges()
    }

    func shiftAsync(_ offset: Offset) {
        for _ in 0 ..< abs(offset.x) {
            if !moveActivePiece((x: (offset.x > 0 ? 1 : -1), y: 0)) { break }
        }
        for _ in 0 ..< abs(offset.y) {
            if !moveActivePiece((x: 0, y: (offset.y > 0 ? 1 : -1))) { break }
        }
        reportChanges()
    }

}


private extension Field {
    
    func positionedGhost(for piece: Piece) -> Piece{
        var ghost = piece.ghost
        while !pieceIsObstructed(ghost) { ghost.y -= 1 }
        ghost.y += 1
        return ghost
    }

    func softDrop()  {
        softDropFrameCounter += 1
        guard softDropFrameCounter >= softDropFrames else { return }
        softDropFrameCounter = 0

        if moveActivePiece((x: 0, y: -1)), softDropFrames == 0 {
            while moveActivePiece((x: 0, y: -1)) { }
        }
    }

    func hardDrop() {
        while moveActivePiece((x: 0, y: -1)) { }
        lockDown()
    }
    
    func lockDown() {
        guard let piece = activePiece else { return }
        activePiece = nil
        piece.blocks.forEach { block in
            guard case .active(let t) = block.type else { return }
            let lockedBlock = Block(type: .locked(t), x: block.x, y: block.y)
            setBlock(lockedBlock)
        }

        clearCompletedLines()

        // TODO: may be "topped out" by locking completely outside of visible field
        // logically may be easiest to place an obstruction at the starting place

        self.delegate?.fieldActivePieceDidLock()
    }

    // Temporary.  May be more complicated (e.g. bombs)
    func clearCompletedLines() {
        var clearedLinesCount = 0
        for y in 0 ..< 24 {
            let currentLine = allBlocks[(y * 10) ..< ((y + 1) * 10)]
            if !currentLine.contains(where: { type in
                if case .locked = type { return false }
                return true
            }) {
                clearedLinesCount += 1
            }
            else if clearedLinesCount > 0 { // Shift this incomplete line down by the number of lines cleared so far
                for (index, type) in currentLine.enumerated() {
                    let block = Block(type: type, x: index % 10, y: y - clearedLinesCount)
                    setBlock(block)
                }
            }
        }
    }

    // Returns whether move was successful
    // Remember to manually reportChanges()
    @discardableResult
    func moveActivePiece(_ offset: Offset) -> Bool {
        guard var piece = activePiece else { return false }


        // TODO: lock timing
        // check if touching something below right after a move or rotate
        

        piece.x += offset.x
        piece.y += offset.y
        let canMove = !pieceIsObstructed(piece)
        if canMove { activePiece = piece }
        return canMove
    }

    func rotateRight() {
        activePiece.map { rotateToFirstAvailablePosition(in: $0.kickCandidatesForRotatingRight()) }
    }

    func rotateLeft() {
        activePiece.map { rotateToFirstAvailablePosition(in: $0.kickCandidatesForRotatingLeft()) }
    }

    private func rotateToFirstAvailablePosition(in candidates: [Piece]) {
        if let piece = candidates.first(where: { !pieceIsObstructed($0) }) {
            activePiece = piece
        }
    }

    // Rules for free space: within 10 x 40, either blank or is active piece's space
    // because this is used to check if active piece can move
    func pieceIsObstructed(_ piece: Piece) -> Bool {
        for block in piece.blocks {
            if !(0 ..< 10 ~= block.x) { return true }
            if !(0 ..< 40 ~= block.y) { return true }
            if case .locked = allBlocks[block.x + block.y * 10] { return true }
        }
        return false
    }
}


private extension Field {

    func setBlock(_ block: Block) {
        setBlock(block, clear: false)
    }

    func clearBlock(_ block: Block) {
        setBlock(block, clear: true)
    }

    private func setBlock(_ block: Block, clear: Bool) {
        let i = block.x + block.y * 10
        let type = clear ? .blank : block.type

        guard allBlocks[i] != type else { return }
        let previousType = allBlocks[i]
        allBlocks[i] = type

        guard i < 10 * 20 else { return }

        // Change changeset as smartly as possible
        let newBlock = clear ? Block(type: .blank, x: block.x, y: block.y) : block

        if let (_, oldType) = unreportedChanges[i] {
            if type == oldType {
                unreportedChanges.removeValue(forKey: i)
            }
            else {
                unreportedChanges[i] = (newBlock: newBlock, oldType: oldType)
            }
        }
        else {
            unreportedChanges[i] = (newBlock: newBlock, oldType: previousType)
        }
    }

    func reportChanges() {
        guard !unreportedChanges.isEmpty else { return }

        let blocks = unreportedChanges.map { $0.value.newBlock }
        unreportedChanges.removeAll(keepingCapacity: true)

        self.delegate?.updateField(blocks: blocks)
    }

}





