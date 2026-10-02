//
//  ShakeMonitor.swift
//  RiskDice Watch App
//
//  把 CoreMotion 接到 `ShakeDetector`（純判定）上。這個檔只負責「拿到動作資料」，
//  「算不算甩」的規則全部在 `ShakeDetector`。
//
//  ⚠️ 模擬器沒有加速度計：`isDeviceMotionAvailable` 是 false，`start()` 什麼都不做。
//     甩手只能在實機上驗。
//

import CoreMotion
import Foundation

final class ShakeMonitor {

    /// 判定為甩的那一刻呼叫（主執行緒）。
    var onShake: (() -> Void)?

    private let manager = CMMotionManager()
    private var detector: ShakeDetector
    private var armDelay: TimeInterval = 0
    private var firstSampleTime: TimeInterval?

    /// 每秒取樣幾次。甩手的一下大約 40–100 毫秒，50 Hz 能取到兩筆以上。
    private static let sampleRate: Double = 50

    // 以下只給 `DebugOptions.shakeLog` 用。
    private var peakG: Double = 0
    private var peakWindowStart: TimeInterval = 0
    /// 最近半秒的每一筆（時間、加速度大小、重力方向），離開前景時整段印出來。
    private var recentSamples: [(time: TimeInterval, magnitudeG: Double, gravity: CMAcceleration)] = []

    init() {
        var tuning = ShakeDetector.Tuning()
        if let threshold = DebugOptions.shakeThresholdG { tuning.thresholdG = threshold }
        if let hits = DebugOptions.shakeRequiredHits { tuning.requiredHits = hits }
        detector = ShakeDetector(tuning: tuning)
    }

    var isRunning: Bool { manager.isDeviceMotionActive }

    /// 開始聽。已經在聽、或這台裝置沒有動作感測器，就什麼都不做。
    ///
    /// - Parameter armDelay: 開始之後這段時間內的動作不拿去判定（`WakeGuard`）——
    ///   把錶轉回來看的那個動作不該被當成甩手。這段時間的資料**根本不餵給 `ShakeDetector`**，
    ///   而不是判定了再丟掉：判定了再丟掉的話，偵測器會進入冷卻，接下來真的在甩反而沒反應。
    func start(armDelay: TimeInterval) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        detector.reset()
        self.armDelay = armDelay
        firstSampleTime = nil
        // 追蹤用的峰值也要歸零，否則重新開始後印出來的第一筆是離開前景之前的舊數字。
        peakG = 0
        peakWindowStart = 0
        recentSamples.removeAll()
        manager.deviceMotionUpdateInterval = 1 / Self.sampleRate
        // 交給主佇列：一秒 50 筆、每筆只算一個平方根，不值得另開執行緒，
        // 而且 `onShake` 的下游（`DiceModel.roll`）本來就要在主執行緒上。
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.handle(motion)
        }
    }

    /// 停止聽。app 不在前景時不擲，也不白白耗電。
    func stop() {
        guard manager.isDeviceMotionActive else { return }
        traceRecentSamples()
        manager.stopDeviceMotionUpdates()
        detector.reset()
    }

    /// 驗證用：螢幕被關的那一刻，往回半秒手錶是什麼姿勢、動得多大。
    /// 每 0.1 秒取一筆印出來，用來看系統是被什麼動作判定成「手腕放下」的。
    private func traceRecentSamples() {
        guard DebugOptions.shakeLog, let last = recentSamples.last else { return }
        var nextTime = last.time - 0.5
        var parts: [String] = []
        for sample in recentSamples where sample.time >= nextTime {
            parts.append(String(
                format: "%+.1fs %.1fg (%.1f,%.1f,%.1f)",
                sample.time - last.time, sample.magnitudeG,
                sample.gravity.x, sample.gravity.y, sample.gravity.z
            ))
            nextTime = sample.time + 0.1
        }
        let maxG = recentSamples.map(\.magnitudeG).max() ?? 0
        DebugOptions.trace(String(format: "before leave: max %.1fg | ", maxG) + parts.joined(separator: " | "))
        recentSamples.removeAll()
    }

    private func handle(_ motion: CMDeviceMotion) {
        // `userAcceleration` 已經扣掉重力：手錶靜止時接近 0，不管它朝哪個方向。
        let a = motion.userAcceleration
        let magnitudeG = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()

        // 用第一筆資料的時間當起點，不拿系統時鐘來比 —— 兩邊的時間基準不保證一樣。
        let startTime = firstSampleTime ?? motion.timestamp
        firstSampleTime = startTime
        let isArmed = motion.timestamp - startTime >= armDelay

        let isShake = isArmed && detector.ingest(magnitudeG: magnitudeG, at: motion.timestamp)
        logIfRequested(magnitudeG: magnitudeG, motion: motion, isShake: isShake)
        if isShake { onShake?() }
    }

    /// 驗證用：每半秒印一次這段時間的最大加速度與手錶的朝向，判定為甩時另外印一行。
    /// 從 Mac 用 `devicectl device process launch --console` 讀得到，調門檻時用量的不用猜的。
    ///
    /// 朝向印的是重力在手錶座標裡的方向：螢幕朝正上方時 z 接近 −1，螢幕轉開、朝外或朝下時 z 往 0 與正值走。
    /// 用來看「螢幕暗掉的那一刻手錶是什麼姿勢」。
    private func logIfRequested(magnitudeG: Double, motion: CMDeviceMotion, isShake: Bool) {
        guard DebugOptions.shakeLog else { return }
        let time = motion.timestamp
        peakG = max(peakG, magnitudeG)
        recentSamples.append((time, magnitudeG, motion.gravity))
        recentSamples.removeAll { time - $0.time > 0.6 }
        if isShake {
            DebugOptions.trace(String(format: "SHAKE g=%.2f", magnitudeG))
        }
        if peakWindowStart == 0 { peakWindowStart = time }
        if time - peakWindowStart >= 0.5 {
            // 靜止時的小數字不印，否則整個畫面都是雜訊。
            if peakG >= 0.3 {
                let g = motion.gravity
                DebugOptions.trace(String(format: "peak g=%.2f grav=(%.1f,%.1f,%.1f)", peakG, g.x, g.y, g.z))
            }
            peakG = 0
            peakWindowStart = time
        }
    }
}
