//
//  ShakeDetector.swift
//  RiskDice Watch App
//
//  甩手偵測的判定。
//
//  ⭐ **純函式**：不碰 CoreMotion、不碰時鐘。每筆動作資料由外面餵進來，它回答「這一筆算不算甩」。
//     所以判定邏輯測得了，不必有手錶（模擬器沒有加速度計）。
//     它**只送出「擲」這件事**，不知道骰子的存在 —— 調門檻時只動這個檔。
//

import Foundation

nonisolated struct ShakeDetector {

    // MARK: - 數值（全部是工作值）

    /// **工作值，還沒在實機上調過。** 定案值要等下面這個判準在實機上過關
    /// （刻意甩 20 次至少觸發 18 次；走路 2 分鐘＋抬腕看錶 10 次誤觸 0 次）。
    struct Tuning: Equatable {
        /// 加速度超過這個值才算「一下」。單位是 g，量的是**扣掉重力之後**的加速度大小。
        ///
        /// 太低：走路擺手、抬腕看錶會誤觸。太高：要甩到手痠。
        ///
        /// 2026-10-02 實機：原本 1.8，輕輕晃沒反應。追蹤記錄裡沒判定到的輕晃峰值在 1.6～2.6 g，
        /// 而不是在甩的時候（拿著、抬腕、轉回來看）每半秒的最大值都在 1.2 g 以下。取在兩者之間。
        /// ⚠️ 還沒有走路的資料。
        var thresholdG: Double = 1.3
        /// 要在 `windowSeconds` 之內湊滿幾「下」才判定為甩。
        ///
        /// 設成 1 的話，手錶敲到桌子那種單一筆的尖峰也會觸發。
        var requiredHits: Int = 2
        /// 湊「下」的時間窗。
        var windowSeconds: TimeInterval = 0.25
        /// 判定一次之後，這段時間內不再判定。
        ///
        /// 一次甩手是好幾下來回，沒有這段會連續觸發。骰子還在動時的觸發本來就會被
        /// `RollCoordinator` 忽略，這裡擋的是「同一次甩手被算成好幾次」。
        var cooldownSeconds: TimeInterval = 1.0
    }

    let tuning: Tuning

    init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    // MARK: - 狀態

    /// 時間窗內超過門檻的那幾筆的時間。
    private var hitTimes: [TimeInterval] = []
    private var lastTriggerTime: TimeInterval?
    private var lastSampleTime: TimeInterval?

    // MARK: - 判定

    /// 餵一筆動作資料。回傳 `true` 表示「這一筆判定為甩」。
    ///
    /// - Parameters:
    ///   - magnitudeG: 扣掉重力之後的加速度大小（g）。
    ///   - time: 這筆資料的時間（秒）。只要單調遞增就好，起點是什麼都可以。
    mutating func ingest(magnitudeG: Double, at time: TimeInterval) -> Bool {
        // 時間倒退：動作更新被停掉再重開，時間軸換了。先前累積的不能沿用。
        if let last = lastSampleTime, time < last { reset() }
        lastSampleTime = time

        if let last = lastTriggerTime, time - last < tuning.cooldownSeconds {
            return false
        }

        hitTimes.removeAll { time - $0 > tuning.windowSeconds }

        guard magnitudeG >= tuning.thresholdG else { return false }
        hitTimes.append(time)

        guard hitTimes.count >= tuning.requiredHits else { return false }
        hitTimes.removeAll()
        lastTriggerTime = time
        return true
    }

    /// 忘掉累積到一半的東西。停掉動作更新時呼叫 ——
    /// 不然回到前景後的第一筆，會跟離開前的最後一筆湊成一次「甩」。
    mutating func reset() {
        hitTimes.removeAll()
        lastTriggerTime = nil
        lastSampleTime = nil
    }
}
