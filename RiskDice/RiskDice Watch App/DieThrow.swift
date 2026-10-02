//
//  DieThrow.swift
//  RiskDice Watch App
//
//  一次丟擲的初始條件：速度與旋轉。純函式，不碰 SceneKit。
//
//  ⚠️ **這裡不抽朝向。** 朝向由 `DieRoll.uniformRandomOrientation` 抽，
//     而且那是機率正確性的唯一來源。
//     這個檔抽的東西**不可以依賴骰子目前哪一面朝上** —— 一旦依賴，
//     「二十面對稱所以各面 1/20」的論證就不成立了。
//

import simd

nonisolated enum DieThrow {

    /// 骰子被丟出去那一瞬間的運動狀態（場景單位，見 `DiceScene.unitsPerMetre`）。
    struct Launch: Equatable {
        /// 線速度。y 是離開錶面朝向使用者的方向。
        var velocity: SIMD3<Float>
        /// 旋轉軸（單位向量）。
        var spinAxis: SIMD3<Float>
        /// 轉速（弧度／秒）。
        var spinSpeed: Float
    }

    // MARK: - 數值（全部是工作值）

    /// **工作值，全部都還沒上過實機。** 手感還沒調，而且必須在實機上調。
    /// 目前的值只保證「模擬器上看起來像被丟出去、
    /// 會撞到邊、大約兩三秒停下」。
    enum Tuning {
        /// 沿著錶面方向的速率範圍（場景單位／秒）。
        static let horizontalSpeed: ClosedRange<Float> = 24...42
        /// 往使用者方向彈起的速率範圍。配合 `DiceScene.gravityMagnitude`，
        /// 最高點大約離地 3–6 個單位，離天花板還有一段。
        static let upwardSpeed: ClosedRange<Float> = 28...38
        /// 轉速範圍（弧度／秒）。
        static let spinSpeed: ClosedRange<Float> = 18...34

        /// 「再推一把」的力道 —— 只要夠讓斜靠的骰子倒下來就好，不是重丟。
        static let nudgeUpwardSpeed: ClosedRange<Float> = 9...13
        static let nudgeTowardCentreSpeed: Float = 5
        static let nudgeSpinSpeed: ClosedRange<Float> = 5...9
    }

    // MARK: - 抽初始條件

    /// 抽一次丟擲的速度與旋轉。每次都不同。
    static func randomLaunch(using generator: inout some RandomNumberGenerator) -> Launch {
        let heading = Float.random(in: 0..<(2 * .pi), using: &generator)
        let horizontal = Float.random(in: Tuning.horizontalSpeed, using: &generator)
        let upward = Float.random(in: Tuning.upwardSpeed, using: &generator)

        return Launch(
            velocity: SIMD3<Float>(cos(heading) * horizontal, upward, sin(heading) * horizontal),
            spinAxis: randomUnitVector(using: &generator),
            spinSpeed: Float.random(in: Tuning.spinSpeed, using: &generator)
        )
    }

    /// 骰子停在讀不出來的狀態時，再推它一把。
    ///
    /// - Parameter position: 骰子目前的位置。推的方向朝場地中心 —— 讀不出來多半是因為
    ///   斜靠在邊上，往中心推才倒得下來。
    ///
    /// ⚠️ 輸入**只有位置**，沒有朝向也沒有判讀結果，這是刻意的：
    ///    「依結果決定怎麼推」會破壞機率。
    static func randomNudge(
        from position: SIMD3<Float>,
        using generator: inout some RandomNumberGenerator
    ) -> Launch {
        let toCentre = SIMD3<Float>(-position.x, 0, -position.z)
        let distance = simd_length(toCentre)
        let direction = distance > 1e-3 ? toCentre / distance : SIMD3<Float>(0, 0, 0)

        var velocity = direction * Tuning.nudgeTowardCentreSpeed
        velocity.y = Float.random(in: Tuning.nudgeUpwardSpeed, using: &generator)

        return Launch(
            velocity: velocity,
            spinAxis: randomUnitVector(using: &generator),
            spinSpeed: Float.random(in: Tuning.nudgeSpinSpeed, using: &generator)
        )
    }

    /// 球面上均勻分布的單位向量。
    ///
    /// 用 Archimedes 的方法：z 均勻、經度均勻。**不能**用「三個分量各抽一個再正規化」——
    /// 那樣會往立方體的角擠。
    static func randomUnitVector(using generator: inout some RandomNumberGenerator) -> SIMD3<Float> {
        let z = Float.random(in: -1...1, using: &generator)
        let longitude = Float.random(in: 0..<(2 * .pi), using: &generator)
        let r = max(0, 1 - z * z).squareRoot()
        return SIMD3<Float>(r * cos(longitude), r * sin(longitude), z)
    }
}
