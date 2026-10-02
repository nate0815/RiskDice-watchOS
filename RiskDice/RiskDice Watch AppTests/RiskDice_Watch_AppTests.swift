//
//  RiskDice_Watch_AppTests.swift
//  RiskDice Watch AppTests
//
//  Created by NA23.Chiao on 2026/10/2.
//

import Testing
import simd
@testable import RiskDice_Watch_App

// MARK: - 骰子的幾何

struct IcosahedronTests {

    @Test("二十個面")
    func faceCount() {
        #expect(Icosahedron.faceCount == 20)
    }

    @Test("恰好一面是大凶")
    func exactlyOneDoomFace() {
        let doomCount = (0..<Icosahedron.faceCount).count { Icosahedron.isDoom($0) }
        #expect(doomCount == 1, "大凶必須恰好一面 —— 多一面機率就悄悄變成 2/20，而且看不出來")
    }

    @Test("每個面的法線都是單位向量")
    func faceNormalsAreUnitVectors() {
        for faceIndex in 0..<Icosahedron.faceCount {
            let length = simd_length(Icosahedron.faceNormal(faceIndex))
            #expect(abs(length - 1) < 1e-4, "第 \(faceIndex) 面的法線長度是 \(length)")
        }
    }

    @Test("二十個面的法線兩兩不同")
    func faceNormalsAreDistinct() {
        for a in 0..<Icosahedron.faceCount {
            for b in (a + 1)..<Icosahedron.faceCount {
                let dot = simd_dot(Icosahedron.faceNormal(a), Icosahedron.faceNormal(b))
                #expect(dot < 0.99, "第 \(a) 面與第 \(b) 面的法線幾乎重合（dot = \(dot)）")
            }
        }
    }

    /// 正二十面體的面是成對相反的：每一面都有一個方向完全相反的對面。
    @Test("每個面都有一個正對面")
    func everyFaceHasAnOpposite() {
        for a in 0..<Icosahedron.faceCount {
            let hasOpposite = (0..<Icosahedron.faceCount).contains { b in
                b != a && simd_dot(Icosahedron.faceNormal(a), Icosahedron.faceNormal(b)) < -0.99
            }
            #expect(hasOpposite, "第 \(a) 面找不到正對面 —— 幾何或索引表有錯")
        }
    }
}

// MARK: - 結果判讀

struct DieReadingTests {

    @Test("二十個面各自朝上時都讀得對", arguments: 0..<Icosahedron.faceCount)
    func readsEachFaceWhenItIsUp(faceIndex: Int) {
        let orientation = DieRoll.orientation(bringingFaceUp: faceIndex)
        #expect(DieRoll.read(orientation: orientation) == .face(faceIndex))
    }

    @Test("稍微傾斜仍然讀得出同一面", arguments: 0..<Icosahedron.faceCount)
    func toleratesSmallTilt(faceIndex: Int) {
        let base = DieRoll.orientation(bringingFaceUp: faceIndex)
        // 門檻是 15°，用 10° 測 —— 要在容許範圍內但不是剛好貼著邊界。
        let tilt = simd_quatf(angle: 10 * .pi / 180, axis: SIMD3<Float>(1, 0, 0))
        #expect(DieRoll.read(orientation: tilt * base) == .face(faceIndex))
    }

    @Test("立在稜上讀不出來")
    func edgeOnIsUnreadable() {
        // 把兩個相鄰面的中間轉到正上方 —— 那就是「立在稜上」。
        let a = Icosahedron.faceNormal(0)
        let b = (1..<Icosahedron.faceCount)
            .map { (index: $0, dot: simd_dot(a, Icosahedron.faceNormal($0))) }
            .filter { $0.dot < 0.99 }
            .max { $0.dot < $1.dot }!                 // 跟第 0 面夾角最小的，就是相鄰面
        let between = simd_normalize(a + Icosahedron.faceNormal(b.index))

        let orientation = simd_quatf(from: between, to: SIMD3<Float>(0, 1, 0))
        #expect(DieRoll.read(orientation: orientation) == .unreadable)
    }

    @Test("判讀不依賴繞上下軸的旋轉", arguments: 0..<Icosahedron.faceCount)
    func readingIsInvariantToYawn(faceIndex: Int) {
        // 字不一定是正的，所以繞 Y 軸怎麼轉都該讀到同一面。
        let base = DieRoll.orientation(bringingFaceUp: faceIndex)
        for degrees in stride(from: 0, to: 360, by: 37) {
            let yaw = simd_quatf(angle: Float(degrees) * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
            #expect(DieRoll.read(orientation: yaw * base) == .face(faceIndex),
                    "第 \(faceIndex) 面轉 \(degrees)° 之後讀錯了")
        }
    }
}

// MARK: - 初始朝向的均勻性

struct UniformOrientationTests {

    @Test("抽出來的是單位四元數")
    func producesUnitQuaternions() {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<2_000 {
            let q = DieRoll.uniformRandomOrientation(using: &generator)
            #expect(abs(simd_length(q.vector) - 1) < 1e-4)
        }
    }

    /// 均勻的朝向 → 二十個面朝上的次數應該接近相等。
    ///
    /// 這一條是 1/20 的直接驗證。它測的是**初始朝向**的均勻性，不是物理模擬的結果 ——
    /// 物理那一段靠對稱性論證，測不了。
    @Test("二十個面朝上的機率接近相等")
    func faceDistributionIsUniform() {
        var generator = SeededGenerator(seed: 2026)
        let trials = 40_000
        var counts = [Int](repeating: 0, count: Icosahedron.faceCount)

        for _ in 0..<trials {
            let q = DieRoll.uniformRandomOrientation(using: &generator)
            // 不走 read(_:) —— 那會把傾斜的濾掉。這裡要的是「最接近上方的是哪一面」。
            var best = 0
            var bestDot = -Float.infinity
            for faceIndex in 0..<Icosahedron.faceCount {
                let dot = simd_dot(q.act(Icosahedron.faceNormal(faceIndex)), SIMD3<Float>(0, 1, 0))
                if dot > bestDot { bestDot = dot; best = faceIndex }
            }
            counts[best] += 1
        }

        let expected = Double(trials) / Double(Icosahedron.faceCount)
        // 卡方檢定，19 自由度。臨界值 43.82 對應 p = 0.001 ——
        // 門檻放寬是刻意的：這個測試要抓的是「分布明顯歪掉」，不是雜訊。
        let chiSquare = counts.reduce(0.0) { sum, count in
            let diff = Double(count) - expected
            return sum + diff * diff / expected
        }
        #expect(chiSquare < 43.82, "卡方 = \(chiSquare)，各面次數 = \(counts)")
    }

    @Test("連續兩次抽出來的朝向不相關")
    func consecutiveOrientationsAreIndependent() {
        // 防的是「拿上次的朝向加一點擾動」那種實作 —— 它會讓連續兩次高度相關，
        // 而且不會有任何症狀。見 DieRoll.uniformRandomOrientation 的註解。
        var generator = SeededGenerator(seed: 7)
        var previous = DieRoll.uniformRandomOrientation(using: &generator)
        var totalAbsDot = 0.0
        let trials = 5_000

        for _ in 0..<trials {
            let current = DieRoll.uniformRandomOrientation(using: &generator)
            totalAbsDot += Double(abs(simd_dot(previous.vector, current.vector)))
            previous = current
        }

        // 四維單位向量兩兩的 |內積| 期望值約 0.375。擾動式實作會接近 1。
        let mean = totalAbsDot / Double(trials)
        #expect(mean < 0.5, "連續兩次朝向的平均 |內積| = \(mean)，太高表示兩次是相關的")
    }
}
