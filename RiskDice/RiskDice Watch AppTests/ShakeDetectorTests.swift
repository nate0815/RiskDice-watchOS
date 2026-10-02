//
//  ShakeDetectorTests.swift
//  RiskDice Watch AppTests
//
//  甩手判定的規則。**只驗規則本身**（幾下、多近、冷卻多久）；
//  門檻的數字對不對要在實機上驗，這裡驗不了。
//

import Foundation
import Testing
@testable import RiskDice_Watch_App

struct ShakeDetectorTests {

    /// 測試用的固定數值 —— 不跟著預設的工作值跑，調門檻時這些測試不必改。
    private let tuning = ShakeDetector.Tuning(
        thresholdG: 2.0,
        requiredHits: 2,
        windowSeconds: 0.25,
        cooldownSeconds: 1.0
    )

    /// 50 Hz 的取樣間隔。
    private let dt: TimeInterval = 0.02

    @Test("時間窗內湊滿兩下才判定為甩")
    func triggersOnSecondHitInsideWindow() {
        var detector = ShakeDetector(tuning: tuning)
        #expect(detector.ingest(magnitudeG: 2.5, at: 0.00) == false)
        #expect(detector.ingest(magnitudeG: 2.5, at: 0.02) == true)
    }

    @Test("單獨一筆尖峰不算 —— 手錶敲到桌子就是這個樣子")
    func singleSpikeDoesNotTrigger() {
        var detector = ShakeDetector(tuning: tuning)
        #expect(detector.ingest(magnitudeG: 6.0, at: 0.00) == false)
        for step in 1...100 {
            #expect(detector.ingest(magnitudeG: 0.1, at: Double(step) * dt) == false)
        }
    }

    @Test("兩下隔太遠不算同一次甩")
    func hitsOutsideWindowDoNotCombine() {
        var detector = ShakeDetector(tuning: tuning)
        #expect(detector.ingest(magnitudeG: 2.5, at: 0.00) == false)
        #expect(detector.ingest(magnitudeG: 0.1, at: 0.15) == false)
        #expect(detector.ingest(magnitudeG: 2.5, at: 0.30) == false)
    }

    @Test("剛好等於門檻算一下，差一點點不算")
    func thresholdIsInclusive() {
        var atThreshold = ShakeDetector(tuning: tuning)
        _ = atThreshold.ingest(magnitudeG: 2.0, at: 0.00)
        #expect(atThreshold.ingest(magnitudeG: 2.0, at: 0.02) == true)

        var justBelow = ShakeDetector(tuning: tuning)
        _ = justBelow.ingest(magnitudeG: 1.99, at: 0.00)
        #expect(justBelow.ingest(magnitudeG: 1.99, at: 0.02) == false)
    }

    @Test("一次甩手來回好幾下，只算一次")
    func oneShakeGestureTriggersOnce() {
        var detector = ShakeDetector(tuning: tuning)
        var triggers = 0
        // 0.6 秒內一直在門檻之上。
        for step in 0..<30 where detector.ingest(magnitudeG: 3.0, at: Double(step) * dt) {
            triggers += 1
        }
        #expect(triggers == 1)
    }

    @Test("冷卻時間過了之後可以再甩一次")
    func triggersAgainAfterCooldown() {
        var detector = ShakeDetector(tuning: tuning)
        _ = detector.ingest(magnitudeG: 2.5, at: 0.00)
        #expect(detector.ingest(magnitudeG: 2.5, at: 0.02) == true)

        // 冷卻中：再大力也不算，而且不會偷偷累積。
        #expect(detector.ingest(magnitudeG: 5.0, at: 0.50) == false)
        #expect(detector.ingest(magnitudeG: 5.0, at: 0.52) == false)

        // 冷卻結束（上一次判定在 0.02，冷卻 1 秒）。
        #expect(detector.ingest(magnitudeG: 2.5, at: 1.10) == false)
        #expect(detector.ingest(magnitudeG: 2.5, at: 1.12) == true)
    }

    @Test("冷卻期間的那幾下不會留到冷卻結束後湊數")
    func hitsDuringCooldownAreNotCarriedOver() {
        var detector = ShakeDetector(tuning: tuning)
        _ = detector.ingest(magnitudeG: 2.5, at: 0.00)
        #expect(detector.ingest(magnitudeG: 2.5, at: 0.02) == true)

        // 冷卻的最後一刻有一下；冷卻一結束又來一下。兩下相隔在時間窗內，
        // 但前一下是在冷卻期間，不該算數。
        #expect(detector.ingest(magnitudeG: 2.5, at: 1.00) == false)
        #expect(detector.ingest(magnitudeG: 2.5, at: 1.03) == false)
        #expect(detector.ingest(magnitudeG: 2.5, at: 1.05) == true)
    }

    @Test("低於門檻的動作再久也不觸發 —— 走路擺手是這個樣子")
    func sustainedMotionBelowThresholdNeverTriggers() {
        var detector = ShakeDetector(tuning: tuning)
        // 兩分鐘，2 Hz 的擺動，峰值 1.2 g。
        for step in 0..<6000 {
            let time = Double(step) * dt
            let magnitude = 1.2 * abs(sin(2 * .pi * 2 * time))
            #expect(detector.ingest(magnitudeG: magnitude, at: time) == false)
        }
    }

    @Test("reset 之後，先前累積的那一下不算")
    func resetForgetsPendingHits() {
        var detector = ShakeDetector(tuning: tuning)
        _ = detector.ingest(magnitudeG: 2.5, at: 0.00)
        detector.reset()
        #expect(detector.ingest(magnitudeG: 2.5, at: 0.02) == false)
    }

    @Test("時間倒退（動作更新重開）時不沿用舊的累積與冷卻")
    func timeGoingBackwardsResets() {
        var detector = ShakeDetector(tuning: tuning)
        _ = detector.ingest(magnitudeG: 2.5, at: 100.00)
        #expect(detector.ingest(magnitudeG: 2.5, at: 100.02) == true)

        // 時間軸換了。舊的冷卻不該擋住新的判定。
        #expect(detector.ingest(magnitudeG: 2.5, at: 5.00) == false)
        #expect(detector.ingest(magnitudeG: 2.5, at: 5.02) == true)
    }

    @Test("要求三下時，兩下不夠")
    func respectsRequiredHits() {
        var strict = tuning
        strict.requiredHits = 3
        var detector = ShakeDetector(tuning: strict)
        #expect(detector.ingest(magnitudeG: 2.5, at: 0.00) == false)
        #expect(detector.ingest(magnitudeG: 2.5, at: 0.02) == false)
        #expect(detector.ingest(magnitudeG: 2.5, at: 0.04) == true)
    }
}
