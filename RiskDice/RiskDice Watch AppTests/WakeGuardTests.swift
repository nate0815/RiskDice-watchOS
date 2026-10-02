//
//  WakeGuardTests.swift
//  RiskDice Watch AppTests
//
//  螢幕剛亮起的那一下不算擲骰。
//

import Foundation
import Testing
@testable import RiskDice_Watch_App

struct WakeGuardTests {

    @Test("還沒進過前景，什麼觸發都不算")
    func nothingCountsBeforeForeground() {
        let wakeGuard = WakeGuard(guardSeconds: 0.5)
        #expect(wakeGuard.allowsTrigger(at: 0) == false)
        #expect(wakeGuard.allowsTrigger(at: 100) == false)
    }

    @Test("螢幕亮起的那一下不算 —— 喚醒螢幕的點擊就是這個樣子")
    func theWakingTapDoesNotCount() {
        var wakeGuard = WakeGuard(guardSeconds: 0.5)
        wakeGuard.enteredForeground(at: 10.00)
        #expect(wakeGuard.allowsTrigger(at: 10.00) == false)
        // 實機上量到的兩個例子：亮起後 0.02 秒、0.37 秒。
        #expect(wakeGuard.allowsTrigger(at: 10.02) == false)
        #expect(wakeGuard.allowsTrigger(at: 10.37) == false)
    }

    @Test("亮起一段時間之後的觸發才算")
    func triggersCountAfterTheGuard() {
        var wakeGuard = WakeGuard(guardSeconds: 0.5)
        wakeGuard.enteredForeground(at: 10.00)
        #expect(wakeGuard.allowsTrigger(at: 10.49) == false)
        #expect(wakeGuard.allowsTrigger(at: 10.50) == true)
        #expect(wakeGuard.allowsTrigger(at: 30.00) == true)
    }

    @Test("螢幕暗掉之後不算，再亮起時重新計時")
    func leavingAndReturningRestartsTheGuard() {
        var wakeGuard = WakeGuard(guardSeconds: 0.5)
        wakeGuard.enteredForeground(at: 10.00)
        #expect(wakeGuard.allowsTrigger(at: 12.00) == true)

        wakeGuard.leftForeground()
        #expect(wakeGuard.allowsTrigger(at: 12.10) == false)

        wakeGuard.enteredForeground(at: 20.00)
        #expect(wakeGuard.allowsTrigger(at: 20.10) == false)
        #expect(wakeGuard.allowsTrigger(at: 20.60) == true)
    }

    @Test("已經在前景時再收到一次「進前景」，不會把計時重來")
    func repeatedForegroundDoesNotRestartTheGuard() {
        var wakeGuard = WakeGuard(guardSeconds: 0.5)
        wakeGuard.enteredForeground(at: 10.00)
        wakeGuard.enteredForeground(at: 15.00)
        #expect(wakeGuard.allowsTrigger(at: 15.10) == true)
    }

    @Test("預設值就是規格寫的 0.5 秒")
    func defaultMatchesTheSpec() {
        #expect(WakeGuard().guardSeconds == 0.5)
    }
}
