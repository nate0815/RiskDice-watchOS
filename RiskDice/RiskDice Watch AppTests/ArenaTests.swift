//
//  ArenaTests.swift
//  RiskDice Watch AppTests
//
//  場地範圍：在不在裡面、拉回裡面是哪裡。
//

import Testing
import simd
@testable import RiskDice_Watch_App

struct ArenaTests {

    private let arena = Arena(halfWidth: 3, halfDepth: 4, cornerCut: 1, ceilingY: 8, apexY: 16)

    @Test("場地中央在場內")
    func centreIsInside() {
        #expect(!arena.isOutOfBounds(SIMD3<Float>(0, 1, 0), tolerance: 0.5))
        #expect(arena.clearance(at: SIMD3<Float>(0, 1, 0)) == 1)      // 最近的是地面
    }

    @Test("超出任何一道邊界都算出界", arguments: [
        SIMD3<Float>(4, 1, 0), SIMD3<Float>(-4, 1, 0),      // 左右
        SIMD3<Float>(0, 1, 5), SIMD3<Float>(0, 1, -5),      // 上下
        SIMD3<Float>(0, -1, 0),                             // 穿過地面
        SIMD3<Float>(0, 9, 0),                              // 穿過天花板
        SIMD3<Float>(2.9, 0.5, 3.9), SIMD3<Float>(-2.9, 0.5, -3.9),   // 被切掉的角
    ])
    func outsideIsOutOfBounds(position: SIMD3<Float>) {
        #expect(arena.isOutOfBounds(position, tolerance: 0.5))
    }

    /// 邊界順著鏡頭的視線往內傾斜：同一個水平位置，在地面上還在場內，彈高了就出界。
    @Test("越高的地方場地越窄")
    func arenaNarrowsWithHeight() {
        #expect(!arena.isOutOfBounds(SIMD3<Float>(2.5, 0.5, 0), tolerance: 0))
        #expect(arena.isOutOfBounds(SIMD3<Float>(2.5, 7, 0), tolerance: 0))

        // 半高的地方，場地剛好是地面的一半寬（邊界在 apexY 收成一點）。
        let halfway = SIMD3<Float>(1.5, 8, 0)
        #expect(abs(arena.depthInside(arena.sides[0], at: halfway)) < 1e-4)
    }

    @Test("邊界上的點深度是零，法線朝外又稍微朝上")
    func sideGeometryIsConsistent() {
        for side in arena.sides {
            let onGround = side.direction * side.distance
            let apex = SIMD3<Float>(0, arena.apexY, 0)
            #expect(abs(arena.depthInside(side, at: onGround)) < 1e-4)
            #expect(abs(arena.depthInside(side, at: apex)) < 1e-4)

            let normal = arena.outwardNormal(of: side)
            #expect(abs(simd_length(normal) - 1) < 1e-4)
            #expect(simd_dot(normal, side.direction) > 0)
            #expect(normal.y > 0)
            // 沿著法線往內走 1，深度就是 1。
            #expect(abs(arena.depthInside(side, at: onGround - normal) - 1) < 1e-4)
        }
    }

    @Test("貼著邊界、只超出一點點不算出界")
    func toleranceAbsorbsSmallPenetration() {
        // 求解器瞬間的穿透不該被當成出界，否則正常碰撞也會觸發重丟。
        #expect(!arena.isOutOfBounds(SIMD3<Float>(3.2, 0.5, 0), tolerance: 0.5))
        #expect(!arena.isOutOfBounds(SIMD3<Float>(0, -0.2, 0), tolerance: 0.5))
    }

    @Test("場內的點拉回來還是原地")
    func clampLeavesInsidePointsAlone() {
        let point = SIMD3<Float>(0.5, 2, -1)
        #expect(arena.clampedInside(point, margin: 1) == point)
    }

    /// 重丟時的保證：換了朝向之後，骰子不會插進任何一道邊界。
    @Test("拉回來的點離每一道邊界至少一個 margin")
    func clampedPointKeepsItsMargin() {
        let margin: Float = 1.1
        var generator = SeededGenerator(seed: 11)

        for _ in 0..<2_000 {
            let wild = SIMD3<Float>(
                Float.random(in: -20...20, using: &generator),
                Float.random(in: -20...20, using: &generator),
                Float.random(in: -20...20, using: &generator)
            )
            let p = arena.clampedInside(wild, margin: margin)
            #expect(arena.clearance(at: p) >= margin - 1e-3, "點 \(wild) 拉回 \(p)，離邊界只有 \(arena.clearance(at: p))")
        }
    }

    @Test("已經在場內的點只會被移動到剛好夠遠")
    func clampMovesAsLittleAsNeeded() {
        // 貼著右邊界的點：只往左移，z 與 y 不變。
        let p = arena.clampedInside(SIMD3<Float>(2.9, 1.5, 0.3), margin: 1.1)
        #expect(p.y == 1.5 && abs(p.z - 0.3) < 1e-5)
        #expect(p.x < 2.9)
        #expect(abs(arena.clearance(at: p) - 1.1) < 1e-3)
    }
}

// MARK: - 場景的尺寸

struct DiceSceneSizingTests {

    /// 幾種實際的錶面比例（寬 ÷ 高）：40mm、44mm、Series 12、Ultra。
    private static let aspects: [Float] = [162.0 / 197, 184.0 / 224, 208.0 / 248, 205.0 / 251]

    /// 骰子小於約 1 個單位時，物理引擎會讓它直接穿過地面消失，
    /// 而且沒有任何錯誤訊息。
    @Test("骰子在場景裡不小於 1 個單位")
    func dieIsNotTooSmallForThePhysicsEngine() {
        #expect(DiceScene.dieRadius >= 1)
    }

    @Test("場地的形狀跟著錶面的比例走", arguments: aspects)
    func arenaMatchesScreenAspect(aspect: Float) {
        let arena = DiceScene.arena(aspect: aspect)
        #expect(abs(arena.halfWidth / arena.halfDepth - aspect) < 1e-4)
    }

    @Test("場地裝得下骰子，而且有地方彈", arguments: aspects)
    func arenaHasRoomForTheDie(aspect: Float) {
        let arena = DiceScene.arena(aspect: aspect)
        // 至少兩顆骰子寬，否則沒有「丟出去」的空間。
        #expect(arena.halfWidth >= DiceScene.dieRadius * 2)
        // 天花板要高過一次正常丟擲的最高點（最大上拋速率、重力 120 → 約 6 個單位）。
        #expect(arena.ceilingY > DiceScene.dieRadius * 4)
        // 四個角切掉之後中間還有路。
        #expect(arena.cornerCut < arena.halfWidth)
        // 邊界在鏡頭的位置收成一點，天花板要在那之下。
        #expect(arena.ceilingY < arena.apexY)
        // 骰子貼著天花板時，場地還是比骰子寬（不會被斜面夾住）。
        let top = SIMD3<Float>(0, arena.ceilingY - DiceScene.dieRadius, 0)
        #expect(arena.clearance(at: top) >= DiceScene.dieRadius - 1e-3)
    }
}
