//
//  DebugOptions.swift
//  RiskDice Watch App
//
//  驗證用的開關，從啟動參數讀。**Release 組態下全部是關的，而且關不開** ——
//  這些不是產品行為，也不會改變機率
//  （測試需要的話用測試手段解決，不該變成產品行為）。
//
//  用法（模擬器）：
//      xcrun simctl launch <SIM> com.nate0815.RiskDice.watchkitapp -autoRoll 200 -autoRollPause 2 -numberedFaces
//

import Foundation

nonisolated enum DebugOptions {

    /// 啟動後自動連續擲幾次。每次停下後隔一小段時間自己再擲。
    ///
    /// 用來在模擬器上量統計：各面次數、停下花多久、推了幾把、重丟幾次。
    /// 它走的是跟點擊**完全相同**的那條路（`DiceController.requestRoll`）。
    static let autoRollCount: Int = {
        #if DEBUG
        return max(0, UserDefaults.standard.integer(forKey: "autoRoll"))
        #else
        return 0
        #endif
    }()

    /// 自動連擲時，停下之後隔多久再擲（秒）。拉長就有時間對每一次的結果截圖。
    static let autoRollPauseSeconds: Double = {
        #if DEBUG
        let value = UserDefaults.standard.double(forKey: "autoRollPause")
        return value > 0 ? value : 0.4
        #else
        return 0.4
        #endif
    }()

    /// 啟動時把骰子放在場地外面，用來驗「出界 → 放回場內」那條路真的接得起來。
    static let startOutside: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-startOutside")
        #else
        return false
        #endif
    }()

    /// 甩手門檻（g）的臨時覆寫。沒給就用 `ShakeDetector.Tuning` 的預設值。
    ///
    /// 在實機上調門檻時用：不必重新建置，換個啟動參數重開就好。
    ///     xcrun devicectl device process launch --device <手錶> --terminate-existing \
    ///       com.nate0815.RiskDice.watchkitapp -shakeG 1.5 -shakeHits 2 -shakeLog
    static let shakeThresholdG: Double? = {
        #if DEBUG
        let value = UserDefaults.standard.double(forKey: "shakeG")
        return value > 0 ? value : nil
        #else
        return nil
        #endif
    }()

    /// 甩手要湊滿幾「下」的臨時覆寫。同上。
    static let shakeRequiredHits: Int? = {
        #if DEBUG
        let value = UserDefaults.standard.integer(forKey: "shakeHits")
        return value > 0 ? value : nil
        #else
        return nil
        #endif
    }()

    /// 把動作資料的峰值與擲骰的每一步印到標準輸出（`devicectl … launch --console` 讀得到）。
    static let shakeLog: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-shakeLog")
        #else
        return false
        #endif
    }()

    private static let traceStart = ProcessInfo.processInfo.systemUptime

    /// 印一行帶時間的追蹤訊息（秒，從 app 啟動算起）。只有 `-shakeLog` 開著才印。
    ///
    /// 用來在實機上看事情的**先後順序**：甩了、丟出、螢幕暗了、回來了、停下 —— 各在第幾秒。
    /// 標準輸出不是終端機時是整塊緩衝的，所以每一行都自己沖出去。
    static func trace(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard shakeLog else { return }
        let seconds = ProcessInfo.processInfo.systemUptime - traceStart
        print(String(format: "[%7.2f] ", seconds) + message())
        fflush(stdout)
        #endif
    }

    /// 骰面改畫面編號，用來逐一比對「程式讀出的面」與「畫面上朝上的面」。
    static let numberedFaces: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-numberedFaces")
        #else
        return false
        #endif
    }()
}
