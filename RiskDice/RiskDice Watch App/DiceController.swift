//
//  DiceController.swift
//  RiskDice Watch App
//
//  把 `RollCoordinator`（純狀態機）接到 SceneKit 上：每一幀量骰子、餵給狀態機、
//  照它說的去丟／推／重丟。丟擲展演可抽換的那一塊。
//

import Combine
import Foundation
import SceneKit
import WatchKit
import os

/// ⚠️ **執行緒**：`renderer(_:didSimulatePhysicsAtTime:)` 跑在 SceneKit 的算圖執行緒上，
/// 不是主執行緒。所有碰場景與狀態機的程式都只在那個回呼裡跑；
/// 主執行緒只做一件事 —— `requestRoll()` 舉一面旗子，由下一幀來處理。
/// 這樣骰子的位置、速度不會在物理算到一半時被改掉。
nonisolated final class DiceController: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {

    let scene: SCNScene
    let arena: Arena

    /// 狀態變了就呼叫（在算圖執行緒上）。丟出時的觸覺回饋接在這裡（`DiceModel.phaseDidChange`）。
    var onPhaseChange: (@Sendable (RollCoordinator.Phase) -> Void)?

    private let die: SCNNode
    private let body: SCNPhysicsBody
    private let log = Logger(subsystem: "com.nate0815.RiskDice", category: "roll")

    private let lock = NSLock()
    private var isRollRequested = false
    private var didReturnToForeground = false

    // 以下只在算圖執行緒上讀寫。
    private var coordinator = RollCoordinator()
    private var generator = SystemRandomNumberGenerator()
    private var lastTime: TimeInterval?
    private var rollNumber = 0
    private var autoRollsRemaining = DebugOptions.autoRollCount
    private var nextAutoRollTime: TimeInterval?

    /// - Parameter aspect: 畫面的寬 ÷ 高。
    init(aspect: Float) {
        scene = DiceScene.make(aspect: aspect)
        arena = DiceScene.arena(aspect: aspect)

        guard
            let die = scene.rootNode.childNode(withName: DiceScene.dieNodeName, recursively: true),
            let body = die.physicsBody
        else {
            preconditionFailure("場景裡找不到骰子 —— DiceScene.make 與 dieNodeName 對不上")
        }
        self.die = die
        self.body = body
        super.init()

        // 待機時骰子的朝向也用均勻分布抽：每次打開 app 看到的不會是同一面。
        die.simdOrientation = DieRoll.uniformRandomOrientation(using: &generator)

        if DebugOptions.startOutside {
            die.simdPosition = SIMD3<Float>(arena.halfWidth * 2.5, DiceScene.dieRadius * 2, 0)
        }
    }

    // MARK: - 輸入（主執行緒）

    /// 要求擲骰。甩手與點擊都走這裡，效果完全相同。
    /// 骰子還在動的話會被忽略 —— 那個判斷在 `RollCoordinator.requestRoll()`。
    func requestRoll() {
        lock.lock()
        isRollRequested = true
        lock.unlock()
    }

    private func takeRollRequest() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let requested = isRollRequested
        isRollRequested = false
        return requested
    }

    /// app 回到前景了（螢幕重新亮起來）。丟到一半被打斷的話，下一幀會整個重新丟一次 ——
    /// 判斷在 `RollCoordinator.restartInterruptedRoll()`。跟 `requestRoll()` 一樣只舉旗子。
    func noteReturnedToForeground() {
        lock.lock()
        didReturnToForeground = true
        lock.unlock()
    }

    private func takeForegroundReturn() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let returned = didReturnToForeground
        didReturnToForeground = false
        return returned
    }

    // MARK: - 每一幀（算圖執行緒）

    func renderer(_ renderer: any SCNSceneRenderer, didSimulatePhysicsAtTime time: TimeInterval) {
        let delta = Float(time - (lastTime ?? time))
        lastTime = time

        if let autoTime = nextAutoRollTime, time >= autoTime {
            nextAutoRollTime = nil
            requestRoll()
        } else if rollNumber == 0, autoRollsRemaining > 0, nextAutoRollTime == nil {
            nextAutoRollTime = time + 1.5      // 啟動後先讓骰子落定
        }

        let position = die.presentation.simdPosition

        // 丟到一半螢幕暗了、現在回來：從頭完整丟一次，不是接著跑完剩下那一小段。
        // 不呼叫 `onPhaseChange` —— 狀態沒變（還是丟擲中），丟出的那一下震動已經震過了。
        if takeForegroundReturn(), coordinator.restartInterruptedRoll() {
            log.info("replay #\(self.rollNumber, privacy: .public) (interrupted)")
            DebugOptions.trace("replay #\(rollNumber) (was interrupted)")
            launch(from: position)
            return
        }

        if takeRollRequest(), coordinator.requestRoll() {
            rollNumber += 1
            log.info("throw #\(self.rollNumber, privacy: .public)")
            DebugOptions.trace("throw #\(rollNumber)")
            launch(from: position)
            onPhaseChange?(coordinator.phase)
            return
        }

        let sample = RollCoordinator.Sample(
            speed: simd_length(simd_float3(body.velocity)),
            spinSpeed: abs(body.angularVelocity.w),
            orientation: die.presentation.simdOrientation,
            isOutOfBounds: arena.isOutOfBounds(position, tolerance: DiceScene.dieRadius * 0.5)
        )

        switch coordinator.step(sample, deltaSeconds: delta) {
        case nil:
            break

        case .nudge:
            log.info("nudge #\(self.rollNumber, privacy: .public) (unreadable)")
            apply(DieThrow.randomNudge(from: position, using: &generator))

        case .rethrow:
            log.info("rethrow #\(self.rollNumber, privacy: .public) outOfBounds=\(sample.isOutOfBounds, privacy: .public)")
            // 出界的話從場地中央重來；只是卡住的話從原地重丟。
            let origin = sample.isOutOfBounds ? SIMD3<Float>(0, 0, 0) : position
            launch(from: origin)

        case .settled(let faceIndex):
            let c = coordinator
            log.info("""
                settled #\(self.rollNumber, privacy: .public) \
                face=\(faceIndex, privacy: .public) \
                doom=\(Icosahedron.isDoom(faceIndex), privacy: .public) \
                seconds=\(c.rollSeconds, format: .fixed(precision: 2), privacy: .public) \
                nudges=\(c.nudgeCount, privacy: .public) \
                rethrows=\(c.rethrowCount, privacy: .public) \
                x=\(position.x, format: .fixed(precision: 2), privacy: .public) \
                z=\(position.z, format: .fixed(precision: 2), privacy: .public)
                """)
            DebugOptions.trace(String(
                format: "settled #%d face=%d doom=%@ seconds=%.2f nudges=%d rethrows=%d",
                rollNumber, faceIndex, Icosahedron.isDoom(faceIndex) ? "yes" : "no",
                c.rollSeconds, c.nudgeCount, c.rethrowCount
            ))
            onPhaseChange?(coordinator.phase)

            if autoRollsRemaining > 0 {
                autoRollsRemaining -= 1
                if autoRollsRemaining > 0 { nextAutoRollTime = time + DebugOptions.autoRollPauseSeconds }
            }
        }
    }

    // MARK: - 動骰子

    /// 把骰子丟出去。
    ///
    /// ⚠️⚠️ **朝向一定是重新抽的，不是沿用停下時的朝向** —— 那是各面 1/20 的唯一來源。
    /// 所以這裡沒有「沿用朝向」的選項。
    /// 位置則沿用骰子現在的位置：同一顆骰子從它停著的地方被丟出去。
    private func launch(from position: SIMD3<Float>) {
        // 換了朝向之後，骰子的角可能伸到原本沒碰到的牆裡。
        // 離每道邊界至少一個外接球半徑，任何朝向都不會穿牆。
        die.simdPosition = arena.clampedInside(position, margin: DiceScene.dieRadius * 1.05)
        die.simdOrientation = DieRoll.uniformRandomOrientation(using: &generator)
        // 直接改 node 的位置與朝向之後，要叫物理引擎重新讀一次，否則它會沿用舊的。
        body.resetTransform()
        apply(DieThrow.randomLaunch(using: &generator))
    }

    private func apply(_ launch: DieThrow.Launch) {
        body.clearAllForces()
        body.velocity = SCNVector3(launch.velocity)
        body.angularVelocity = SCNVector4(launch.spinAxis.x, launch.spinAxis.y, launch.spinAxis.z, launch.spinSpeed)
    }
}

// MARK: - 給 SwiftUI 的那一面

/// 畫面那一側拿到的東西：場景、控制器、目前的狀態。主執行緒上用。
@MainActor
final class DiceModel: ObservableObject {

    let controller: DiceController

    @Published private(set) var phase: RollCoordinator.Phase = .idle

    private let shakeMonitor = ShakeMonitor()
    private var wakeGuard = WakeGuard()

    init() {
        // 畫面是滿版的（`ignoresSafeArea`），所以場地的形狀就是螢幕的形狀。
        let bounds = WKInterfaceDevice.current().screenBounds
        controller = DiceController(aspect: Float(bounds.width / bounds.height))

        controller.onPhaseChange = { [weak self] phase in
            Task { @MainActor [weak self] in self?.phaseDidChange(to: phase) }
        }
        // 甩手與點擊走同一條路，效果完全相同。
        // 甩手那一邊的「剛亮起不算」在 `ShakeMonitor.start(armDelay:)` 裡擋掉了。
        shakeMonitor.onShake = { [weak self] in self?.roll() }
    }

    /// 使用者點了螢幕。
    ///
    /// 螢幕暗著時點它是要把螢幕點亮，那一下不擲。
    /// 系統會把喚醒的那一下照樣送進來，所以要自己擋。
    func tap() {
        guard wakeGuard.allowsTrigger(at: ProcessInfo.processInfo.systemUptime) else {
            DebugOptions.trace("tap ignored (screen just woke)")
            return
        }
        DebugOptions.trace("tap")
        roll()
    }

    private func roll() {
        controller.requestRoll()
    }

    /// app 在不在前景。只有在前景時才聽甩手 ——
    /// 不在前景不擲，也不白白耗電。
    func setForeground(_ isForeground: Bool) {
        DebugOptions.trace(isForeground ? "foreground" : "left foreground")
        if isForeground {
            wakeGuard.enteredForeground(at: ProcessInfo.processInfo.systemUptime)
            // 丟到一半被螢幕暗掉打斷的話，回來時完整重丟一次。
            controller.noteReturnedToForeground()
            shakeMonitor.start(armDelay: wakeGuard.guardSeconds)
        } else {
            wakeGuard.leftForeground()
            shakeMonitor.stop()
        }
    }

    private func phaseDidChange(to newPhase: RollCoordinator.Phase) {
        phase = newPhase
        // 丟出的那一下震動。
        //
        // 掛在「狀態變成丟擲中」上，而不是掛在甩手或點擊上：骰子還在動時的觸發會被
        // `RollCoordinator` 忽略，那種時候不該震 —— 震了但骰子沒動，比沒反應更怪。
        // 重丟（`.rethrow`）不會經過這裡，所以一次丟擲只震一下。
        if case .rolling = newPhase {
            WKInterfaceDevice.current().play(Self.throwHaptic)
        }
    }

    /// **工作值。** `.click` 在手腕正在動的時候幾乎感覺不到，所以用比較實的這一種。
    /// 停下時的震動（大吉／大凶要分得出來）還沒做。
    private static let throwHaptic: WKHapticType = .start
}
