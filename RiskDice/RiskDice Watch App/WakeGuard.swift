//
//  WakeGuard.swift
//  RiskDice Watch App
//
//  螢幕剛亮起時的那一下不算擲骰。
//
//  螢幕暗著時用手指點它，那一下是要把螢幕點亮，不是要擲。但系統會把那一下照樣送進 app ——
//  實機上量到螢幕亮起後 0.02 秒、0.37 秒就丟出去的例子。把錶轉回來看的那個動作也一樣，
//  不該被當成甩手。
//
//  ⭐ **純函式**：時間由外面給，不碰時鐘。
//

import Foundation

nonisolated struct WakeGuard {

    /// **工作值**。螢幕亮起後這段時間內的觸發不算。
    ///
    /// 太短擋不住喚醒的那一下；太長會覺得「點了沒反應」。
    static let defaultGuardSeconds: TimeInterval = 0.5

    let guardSeconds: TimeInterval

    /// 這一次是什麼時候回到前景的。不在前景時是 `nil`。
    private var foregroundSince: TimeInterval?

    init(guardSeconds: TimeInterval = WakeGuard.defaultGuardSeconds) {
        self.guardSeconds = guardSeconds
    }

    /// app 回到前景了（螢幕亮起來）。已經在前景的話不重新計時。
    mutating func enteredForeground(at time: TimeInterval) {
        if foregroundSince == nil { foregroundSince = time }
    }

    /// app 離開前景了（螢幕暗掉）。
    mutating func leftForeground() {
        foregroundSince = nil
    }

    /// 這個時間點的觸發算不算。
    ///
    /// 不在前景 → 不算（app 不在前景不擲）。
    /// 剛回到前景、還在 `guardSeconds` 之內 → 不算。
    func allowsTrigger(at time: TimeInterval) -> Bool {
        guard let since = foregroundSince else { return false }
        return time - since >= guardSeconds
    }
}
