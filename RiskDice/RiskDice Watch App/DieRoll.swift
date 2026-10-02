//
//  DieRoll.swift
//  RiskDice Watch App
//
//  擲骰的兩個純粹部分：抽初始朝向、讀出朝上的面。
//
//  ⭐ **這整個檔都是純函式** —— 不碰 SceneKit、不碰畫面、不碰物理引擎。
//     機率的正確性與結果判讀的正確性都在這裡決定，所以它必須單獨測得了。
//

import simd

nonisolated enum DieRoll {

    // MARK: - 初始朝向

    /// 抽一個**均勻分布**的隨機朝向。
    ///
    /// ⚠️⚠️ **這是機率正確性的唯一來源。**
    /// 正二十面體有對稱性：轉到任何一面朝上，形狀都跟原來重合。所以只要初始朝向是均勻的，
    /// 「第 3 面最後朝上」與「第 17 面最後朝上」的機率必然相同 —— 物理引擎內部怎麼算、
    /// 參數怎麼調，都不影響這個結論。完整論證見 README.zh-TW.md「機率為什麼是精確的 1/20」。
    ///
    /// **不可以**改成「上次停下的朝向再加一點擾動」—— 那樣連續兩次的結果會相關，
    /// 而且**不會有任何症狀**，要丟幾百次做統計才看得出來。
    ///
    /// 用的是 Shoemake 的方法：從三個 [0,1) 均勻亂數直接構造均勻分布的單位四元數。
    /// 注意**不能**用「三個軸各抽一個均勻角度」—— 那樣在極區會擠成一團，不是均勻的。
    static func uniformRandomOrientation(using generator: inout some RandomNumberGenerator) -> simd_quatf {
        let u1 = Float.random(in: 0..<1, using: &generator)
        let u2 = Float.random(in: 0..<1, using: &generator)
        let u3 = Float.random(in: 0..<1, using: &generator)

        let r1 = (1 - u1).squareRoot()
        let r2 = u1.squareRoot()
        let t1 = 2 * Float.pi * u2
        let t2 = 2 * Float.pi * u3

        return simd_quatf(ix: r1 * sin(t1), iy: r1 * cos(t1), iz: r2 * sin(t2), r: r2 * cos(t2))
    }

    static func uniformRandomOrientation() -> simd_quatf {
        var generator = SystemRandomNumberGenerator()
        return uniformRandomOrientation(using: &generator)
    }

    // MARK: - 結果判讀

    /// 判讀的結果。
    enum Reading: Equatable {
        /// 讀得出來：第 `faceIndex` 面朝上。
        case face(_ faceIndex: Int)
        /// 讀不出來 —— 骰子沒有平躺在某一面上（斜靠在邊界上、立在稜上）。
        ///
        /// 這種狀態**不算停下**，要繼續滾到能判讀為止。
        case unreadable
    }

    /// 「夠正」的門檻：朝上那一面的法線與正上方的夾角上限。
    ///
    /// 正二十面體相鄰兩面的法線夾角約 41.8°，所以平躺時最接近正上方的那一面
    /// 一定在 20.9° 以內；超過這個角度就表示它是斜靠或立著的。
    /// 取 15° 留了一點餘裕，又不會把真正平躺的狀態誤判成讀不出來。
    ///
    /// **工作值** —— 要在實機上看過斜靠在邊界上的實際情況才能定案。
    static let maxTiltDegrees: Float = 15

    /// 讀出朝上的是哪一面。
    ///
    /// - Parameter orientation: 骰子停下時的朝向。
    /// - Returns: 最接近正上方的那一面；不夠正就是 `.unreadable`。
    ///
    /// ⚠️ **重丟的條件不可以看結果。** `.unreadable` 時可以再推一把或重丟，
    /// 但「這次是大凶所以重丟」會直接破壞 1/20。
    static func read(orientation: simd_quatf) -> Reading {
        let up = SIMD3<Float>(0, 1, 0)

        var bestIndex = 0
        var bestDot = -Float.infinity

        for faceIndex in 0..<Icosahedron.faceCount {
            let worldNormal = orientation.act(Icosahedron.faceNormal(faceIndex))
            let dot = simd_dot(worldNormal, up)
            if dot > bestDot {
                bestDot = dot
                bestIndex = faceIndex
            }
        }

        let maxTiltCosine = cos(maxTiltDegrees * .pi / 180)
        return bestDot >= maxTiltCosine ? .face(bestIndex) : .unreadable
    }

    /// 把骰子轉成「第 `faceIndex` 面正朝上」的朝向。
    ///
    /// 產品不會用到 —— 它存在是為了**測試**：測試要能指定某一面朝上，
    /// 才驗得了二十個面各自朝上時都讀得對。
    /// 不可以靠調高機率來測大凶，這是它的技術版本：
    /// 測試直接指定初始條件，不碰產品行為。
    static func orientation(bringingFaceUp faceIndex: Int) -> simd_quatf {
        let normal = Icosahedron.faceNormal(faceIndex)
        return simd_quatf(from: normal, to: SIMD3<Float>(0, 1, 0))
    }
}
