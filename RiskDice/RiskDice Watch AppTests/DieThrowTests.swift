//
//  DieThrowTests.swift
//  RiskDice Watch AppTests
//
//  丟擲的初始條件：速度與旋轉。
//

import Testing
import simd
@testable import RiskDice_Watch_App

struct DieThrowTests {

    @Test("丟出的速度與轉速都落在設定的範圍內")
    func launchStaysWithinTuning() {
        var generator = SeededGenerator(seed: 3)
        for _ in 0..<2_000 {
            let launch = DieThrow.randomLaunch(using: &generator)
            let horizontal = simd_length(SIMD2<Float>(launch.velocity.x, launch.velocity.z))

            #expect(DieThrow.Tuning.horizontalSpeed.contains(horizontal.rounded(toPlaces: 3)))
            #expect(DieThrow.Tuning.upwardSpeed.contains(launch.velocity.y))
            #expect(DieThrow.Tuning.spinSpeed.contains(launch.spinSpeed))
            #expect(abs(simd_length(launch.spinAxis) - 1) < 1e-4)
        }
    }

    /// 骰子一定是往上（朝使用者）丟的 —— 往下丟會直接砸在地面上，看不出「丟出去」。
    @Test("丟出的方向一定離開地面")
    func launchGoesUp() {
        #expect(DieThrow.Tuning.upwardSpeed.lowerBound > 0)
        #expect(DieThrow.Tuning.nudgeUpwardSpeed.lowerBound > 0)
    }

    /// 每次丟出的力道、方向、旋轉都不同。
    @Test("丟出的方向涵蓋四面八方")
    func launchHeadingCoversAllQuadrants() {
        var generator = SeededGenerator(seed: 5)
        var quadrants = [0, 0, 0, 0]
        for _ in 0..<4_000 {
            let v = DieThrow.randomLaunch(using: &generator).velocity
            quadrants[(v.x >= 0 ? 0 : 1) + (v.z >= 0 ? 0 : 2)] += 1
        }
        for count in quadrants {
            #expect(count > 850 && count < 1_150, "四個象限的次數 = \(quadrants)")
        }
    }

    @Test("連續兩次丟出的初始條件不一樣")
    func consecutiveLaunchesDiffer() {
        var generator = SeededGenerator(seed: 9)
        var previous = DieThrow.randomLaunch(using: &generator)
        for _ in 0..<500 {
            let current = DieThrow.randomLaunch(using: &generator)
            #expect(current != previous)
            previous = current
        }
    }

    @Test("旋轉軸在球面上均勻分布")
    func spinAxisIsUniformOnTheSphere() {
        var generator = SeededGenerator(seed: 21)
        var sum = SIMD3<Float>(0, 0, 0)
        var sumOfSquares = SIMD3<Float>(0, 0, 0)
        let trials = 20_000

        for _ in 0..<trials {
            let axis = DieThrow.randomUnitVector(using: &generator)
            #expect(abs(simd_length(axis) - 1) < 1e-4)
            sum += axis
            sumOfSquares += axis * axis
        }

        // 均勻的話：每個分量的平均是 0、平方的平均是 1/3。
        // 「三個分量各抽一個再正規化」那種寫法會讓平方的平均偏離 1/3。
        let mean = sum / Float(trials)
        let meanSquare = sumOfSquares / Float(trials)
        for component in 0..<3 {
            #expect(abs(mean[component]) < 0.02, "平均 = \(mean)")
            #expect(abs(meanSquare[component] - 1.0 / 3) < 0.01, "平方的平均 = \(meanSquare)")
        }
    }

    @Test("再推一把的方向朝場地中心，而且往上")
    func nudgePushesTowardCentre() {
        var generator = SeededGenerator(seed: 13)
        let position = SIMD3<Float>(2.5, 0.9, -3)
        let nudge = DieThrow.randomNudge(from: position, using: &generator)

        let horizontal = SIMD3<Float>(nudge.velocity.x, 0, nudge.velocity.z)
        let toCentre = simd_normalize(SIMD3<Float>(-position.x, 0, -position.z))
        #expect(simd_dot(simd_normalize(horizontal), toCentre) > 0.999)
        #expect(abs(simd_length(horizontal) - DieThrow.Tuning.nudgeTowardCentreSpeed) < 1e-3)
        #expect(DieThrow.Tuning.nudgeUpwardSpeed.contains(nudge.velocity.y))
    }

    @Test("骰子正好在場地中心時，再推一把不會算出 NaN")
    func nudgeAtCentreIsFinite() {
        var generator = SeededGenerator(seed: 17)
        let nudge = DieThrow.randomNudge(from: SIMD3<Float>(0, 0.9, 0), using: &generator)
        #expect(nudge.velocity.x == 0 && nudge.velocity.z == 0)
        #expect(nudge.velocity.y.isFinite && nudge.velocity.y > 0)
    }

    /// 推一把比丟一次輕 —— 它只是讓斜靠的骰子倒下來，不是重丟。
    @Test("再推一把的力道比丟出小")
    func nudgeIsGentlerThanLaunch() {
        #expect(DieThrow.Tuning.nudgeUpwardSpeed.upperBound < DieThrow.Tuning.upwardSpeed.lowerBound)
        #expect(DieThrow.Tuning.nudgeSpinSpeed.upperBound < DieThrow.Tuning.spinSpeed.lowerBound)
    }
}

private extension Float {
    /// 浮點誤差會讓「剛好在範圍邊界」的值多出一點點，比對前先捨到小數第 n 位。
    func rounded(toPlaces places: Int) -> Float {
        let scale = Float(pow(10, Double(places)))
        return (self * scale).rounded() / scale
    }
}
