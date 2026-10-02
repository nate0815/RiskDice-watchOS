//
//  RollCoordinator.swift
//  RiskDice Watch App
//
//  擲骰協調：待機／丟擲中／已停下 三個狀態，以及「什麼時候算停下」的判定。
//
//  ⭐ **純狀態機**，不碰 SceneKit、不碰時鐘、不碰亂數。每一幀由外面餵一筆量測進來，
//     它回答「現在該做什麼」。所以整段判定邏輯測得了，不必開模擬器。
//

import simd

nonisolated struct RollCoordinator {

    // MARK: - 狀態與動作

    enum Phase: Equatable {
        /// 待機：app 剛打開，還沒擲過。
        case idle
        /// 丟擲中：骰子在動，或者停了但還讀不出來。
        case rolling
        /// 已停下，朝上的是第 `faceIndex` 面。
        case settled(faceIndex: Int)
    }

    /// 這一幀之後，展演那一邊該做的事。
    enum Action: Equatable {
        /// 再推一把（骰子靜止了但讀不出來）。
        case nudge
        /// 整個重丟一次：回到場內、重新抽朝向。
        case rethrow
        /// 停下了，結果是第 `faceIndex` 面。
        case settled(faceIndex: Int)
    }

    /// 一幀的量測。
    struct Sample {
        /// 線速率（場景單位／秒）。
        var speed: Float
        /// 轉速（弧度／秒）。
        var spinSpeed: Float
        /// 骰子的朝向。
        var orientation: simd_quatf
        /// 骰子是不是跑到場外了（`Arena.isOutOfBounds`）。
        var isOutOfBounds: Bool
    }

    // MARK: - 數值（全部是工作值）

    /// **工作值。** 只在模擬器上看過，實機上要重新確認 ——
    /// 尤其是 `stillSeconds`：太短會在骰子還在晃的時候就判定，太長則「停了卻還沒震」。
    struct Tuning: Equatable {
        /// 線速率低於這個值才算「沒在動」。
        var maxStillSpeed: Float = 0.5
        /// 轉速低於這個值才算「沒在轉」。
        var maxStillSpinSpeed: Float = 0.35
        /// 連續靜止多久才判定停下。
        var stillSeconds: Float = 0.3
        /// 同一次丟擲最多推幾把；再讀不出來就整個重丟。
        var maxNudges: Int = 3
        /// 丟出去這麼久還沒停，視為卡住，整個重丟。
        var maxRollSeconds: Float = 10
        /// 單幀時間的上限。app 被暫停再回來時那一幀會很長，不能整段算成「靜止時間」。
        var maxDeltaSeconds: Float = 0.1
    }

    let tuning: Tuning

    init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    private(set) var phase: Phase = .idle

    /// 這次丟擲已經過了多久（含重丟之前的時間）。只在 `.rolling` 時有意義。
    private(set) var rollSeconds: Float = 0
    /// 這次丟擲被推了幾把。
    private(set) var nudgeCount = 0
    /// 這次丟擲被整個重丟了幾次。
    private(set) var rethrowCount = 0

    private var stillSeconds: Float = 0
    /// 距離上一次丟出（或重丟）過了多久 —— 卡住的判定用這個，不是 `rollSeconds`。
    private var secondsSinceThrow: Float = 0
    private var nudgesSinceThrow = 0

    // MARK: - 輸入

    /// 使用者要擲骰（甩手或點擊）。
    ///
    /// - Returns: 接受的話是 `true`，呼叫端要把骰子丟出去；
    ///   骰子還在動的話是 `false`，**忽略、不打斷、不排隊**。
    mutating func requestRoll() -> Bool {
        if phase == .rolling { return false }

        phase = .rolling
        rollSeconds = 0
        nudgeCount = 0
        rethrowCount = 0
        stillSeconds = 0
        secondsSinceThrow = 0
        nudgesSinceThrow = 0
        return true
    }

    /// 丟到一半被打斷了（螢幕暗掉、app 離開前景），現在回來了。
    ///
    /// 這隻錶沒有永遠顯示：甩手的動作常被系統判定成「手腕放下」，螢幕在丟出後一秒內就關掉，
    /// 物理跟著停在半空中。回來時如果只是接著跑完剩下的那一小段，看起來像「骰子自己動了一下」。
    /// 所以整個重新丟一次，讓人看得到完整的丟擲（把錶轉回來看 → 骰子在彈）。
    ///
    /// ⚠️⚠️ **條件只有「是不是丟擲中」，不看朝向、不看結果**。
    /// 已經停下的不會重丟 —— 那個結果已經定了。
    ///
    /// - Returns: 正在丟擲中是 `true`，呼叫端要把骰子重新丟出去；否則是 `false`，什麼都不做。
    mutating func restartInterruptedRoll() -> Bool {
        guard phase == .rolling else { return false }

        rollSeconds = 0
        nudgeCount = 0
        rethrowCount = 0
        stillSeconds = 0
        secondsSinceThrow = 0
        nudgesSinceThrow = 0
        return true
    }

    /// 餵一幀的量測。
    ///
    /// ⚠️⚠️ **這裡的每一個分支都不可以看「是哪一面」。**
    /// 可以看的只有：讀不讀得出來、動不動、在不在場內、過了多久。
    /// 一旦出現「這一面就重丟」之類的條件，大凶的機率就不再是 1/20，
    /// 而且完全沒有症狀。
    mutating func step(_ sample: Sample, deltaSeconds: Float) -> Action? {
        let dt = min(max(deltaSeconds, 0), tuning.maxDeltaSeconds)

        switch phase {
        case .settled:
            // 停下之後骰子留在原地，直到下一次擲骰。
            return nil

        case .idle:
            // 還沒擲過。骰子掉到場外的話把它放回來，但不算一次擲骰、也不報結果。
            return sample.isOutOfBounds ? .rethrow : nil

        case .rolling:
            rollSeconds += dt
            secondsSinceThrow += dt

            if sample.isOutOfBounds || secondsSinceThrow > tuning.maxRollSeconds {
                return rethrow()
            }

            let isStill = sample.speed < tuning.maxStillSpeed && sample.spinSpeed < tuning.maxStillSpinSpeed
            guard isStill else {
                stillSeconds = 0
                return nil
            }

            stillSeconds += dt
            guard stillSeconds >= tuning.stillSeconds else { return nil }

            switch DieRoll.read(orientation: sample.orientation) {
            case .face(let faceIndex):
                phase = .settled(faceIndex: faceIndex)
                return .settled(faceIndex: faceIndex)

            case .unreadable:
                // 斜靠或立著 —— 不算停下，要繼續滾到能判讀為止。
                stillSeconds = 0
                if nudgesSinceThrow >= tuning.maxNudges {
                    return rethrow()
                }
                nudgeCount += 1
                nudgesSinceThrow += 1
                return .nudge
            }
        }
    }

    private mutating func rethrow() -> Action {
        rethrowCount += 1
        stillSeconds = 0
        secondsSinceThrow = 0
        nudgesSinceThrow = 0
        return .rethrow
    }
}
