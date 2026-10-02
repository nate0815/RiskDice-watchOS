//
//  RollCoordinatorTests.swift
//  RiskDice Watch AppTests
//
//  擲骰協調：什麼時候接受擲骰、什麼時候算停下、讀不出來與出界怎麼處理。
//

import Testing
import simd
@testable import RiskDice_Watch_App

struct RollCoordinatorTests {

    // MARK: - 測試用的量測

    private static let frame: Float = 1.0 / 60

    private static func moving(faceUp faceIndex: Int = 3) -> RollCoordinator.Sample {
        .init(speed: 12, spinSpeed: 9, orientation: DieRoll.orientation(bringingFaceUp: faceIndex), isOutOfBounds: false)
    }

    private static func still(faceUp faceIndex: Int) -> RollCoordinator.Sample {
        .init(speed: 0, spinSpeed: 0, orientation: DieRoll.orientation(bringingFaceUp: faceIndex), isOutOfBounds: false)
    }

    /// 靜止，但立在稜上 —— 讀不出來。`towardFace` 決定是立在哪一條稜上。
    private static func stillOnEdge(nearFace faceIndex: Int = 0) -> RollCoordinator.Sample {
        let a = Icosahedron.faceNormal(faceIndex)
        let neighbour = (0..<Icosahedron.faceCount)
            .filter { $0 != faceIndex }
            .max { simd_dot(a, Icosahedron.faceNormal($0)) < simd_dot(a, Icosahedron.faceNormal($1)) }!
        let between = simd_normalize(a + Icosahedron.faceNormal(neighbour))
        return .init(
            speed: 0,
            spinSpeed: 0,
            orientation: simd_quatf(from: between, to: SIMD3<Float>(0, 1, 0)),
            isOutOfBounds: false
        )
    }

    private static func outOfBounds() -> RollCoordinator.Sample {
        .init(speed: 30, spinSpeed: 5, orientation: DieRoll.orientation(bringingFaceUp: 3), isOutOfBounds: true)
    }

    /// 連續餵同一筆量測，回傳第一個出現的動作（沒有就是 nil）。
    private static func feed(
        _ coordinator: inout RollCoordinator,
        _ sample: RollCoordinator.Sample,
        seconds: Float
    ) -> RollCoordinator.Action? {
        var elapsed: Float = 0
        while elapsed < seconds {
            if let action = coordinator.step(sample, deltaSeconds: frame) { return action }
            elapsed += frame
        }
        return nil
    }

    private static func rolling() -> RollCoordinator {
        var coordinator = RollCoordinator()
        _ = coordinator.requestRoll()
        return coordinator
    }

    // MARK: - 接受與忽略擲骰

    @Test("一開始是待機")
    func startsIdle() {
        #expect(RollCoordinator().phase == .idle)
    }

    @Test("待機時擲骰會被接受")
    func acceptsRollWhenIdle() {
        var coordinator = RollCoordinator()
        let accepted = coordinator.requestRoll()
        #expect(accepted)
        #expect(coordinator.phase == .rolling)
    }

    /// 骰子還在動時又觸發 → 忽略，不打斷、不排隊。
    @Test("骰子還在動時再擲會被忽略，而且不影響這一次")
    func ignoresRollWhileRolling() {
        var coordinator = Self.rolling()
        _ = Self.feed(&coordinator, Self.moving(), seconds: 0.5)
        let secondsBefore = coordinator.rollSeconds

        let accepted = coordinator.requestRoll()
        #expect(!accepted)
        #expect(coordinator.phase == .rolling)
        #expect(coordinator.rollSeconds == secondsBefore, "被忽略的擲骰不可以把計時歸零")

        // 沒有排隊：這一次停下之後不會自己再擲一次。
        #expect(Self.feed(&coordinator, Self.still(faceUp: 5), seconds: 1) == .settled(faceIndex: 5))
        #expect(coordinator.phase == .settled(faceIndex: 5))
    }

    @Test("停下之後可以再擲")
    func acceptsRollAfterSettling() {
        var coordinator = Self.rolling()
        _ = Self.feed(&coordinator, Self.still(faceUp: 2), seconds: 1)
        #expect(coordinator.phase == .settled(faceIndex: 2))

        let accepted = coordinator.requestRoll()
        #expect(accepted)
        #expect(coordinator.phase == .rolling)
        #expect(coordinator.rollSeconds == 0)
        #expect(coordinator.nudgeCount == 0)
        #expect(coordinator.rethrowCount == 0)
    }

    // MARK: - 停下的判定

    @Test("還在動就不算停下")
    func doesNotSettleWhileMoving() {
        var coordinator = Self.rolling()
        #expect(Self.feed(&coordinator, Self.moving(), seconds: 3) == nil)
        #expect(coordinator.phase == .rolling)
    }

    @Test("只有線速度或只有轉速降下來都不算停下")
    func needsBothSpeedsBelowThreshold() {
        var sliding = Self.still(faceUp: 4)
        sliding.speed = 5
        var spinning = Self.still(faceUp: 4)
        spinning.spinSpeed = 5

        var coordinator = Self.rolling()
        #expect(Self.feed(&coordinator, sliding, seconds: 2) == nil)
        #expect(Self.feed(&coordinator, spinning, seconds: 2) == nil)
    }

    @Test("靜止的時間不夠長不算停下")
    func needsToStayStill() {
        var coordinator = Self.rolling()
        let almost = coordinator.tuning.stillSeconds * 0.8
        #expect(Self.feed(&coordinator, Self.still(faceUp: 7), seconds: almost) == nil)
        #expect(coordinator.phase == .rolling)
    }

    /// 骰子在最高點、或兩次彈跳之間會有一瞬間幾乎不動 —— 那不是停下。
    @Test("中途又動起來的話，靜止時間重新算")
    func movementResetsTheStillTimer() {
        var coordinator = Self.rolling()
        let almost = coordinator.tuning.stillSeconds * 0.8

        for _ in 0..<5 {
            #expect(Self.feed(&coordinator, Self.still(faceUp: 7), seconds: almost) == nil)
            let action = coordinator.step(Self.moving(), deltaSeconds: Self.frame)
            #expect(action == nil)
        }
        #expect(coordinator.phase == .rolling)
    }

    @Test("靜止夠久就停下，結果是朝上的那一面", arguments: 0..<Icosahedron.faceCount)
    func settlesOnTheFaceThatIsUp(faceIndex: Int) {
        var coordinator = Self.rolling()
        _ = Self.feed(&coordinator, Self.moving(), seconds: 1)

        #expect(Self.feed(&coordinator, Self.still(faceUp: faceIndex), seconds: 1) == .settled(faceIndex: faceIndex))
        #expect(coordinator.phase == .settled(faceIndex: faceIndex))
    }

    /// 停下後骰子留在原地，直到下一次擲骰。
    @Test("停下之後不再發出任何動作")
    func staysSettled() {
        var coordinator = Self.rolling()
        _ = Self.feed(&coordinator, Self.still(faceUp: 6), seconds: 1)

        #expect(Self.feed(&coordinator, Self.moving(), seconds: 1) == nil)
        #expect(Self.feed(&coordinator, Self.stillOnEdge(), seconds: 1) == nil)
        #expect(Self.feed(&coordinator, Self.outOfBounds(), seconds: 1) == nil)
        #expect(coordinator.phase == .settled(faceIndex: 6))
    }

    @Test("很長的一幀不會被整段算成靜止時間")
    func clampsLongFrames() {
        // app 被暫停再回來時，那一幀的時間差可能是好幾秒。
        var coordinator = Self.rolling()
        let action = coordinator.step(Self.still(faceUp: 1), deltaSeconds: 30)
        #expect(action == nil)
        #expect(coordinator.phase == .rolling)
        #expect(coordinator.rollSeconds <= coordinator.tuning.maxDeltaSeconds)
    }

    // MARK: - 讀不出來

    /// 看不出哪面朝上的狀態不算停下，要繼續滾到能判讀為止。
    @Test("靜止但讀不出來 → 再推一把，不算停下")
    func nudgesWhenUnreadable() {
        var coordinator = Self.rolling()
        #expect(Self.feed(&coordinator, Self.stillOnEdge(), seconds: 1) == .nudge)
        #expect(coordinator.phase == .rolling)
        #expect(coordinator.nudgeCount == 1)
    }

    @Test("推了還是讀不出來，推到上限就整個重丟")
    func rethrowsAfterTooManyNudges() {
        var coordinator = Self.rolling()
        let limit = coordinator.tuning.maxNudges

        for _ in 0..<limit {
            #expect(Self.feed(&coordinator, Self.stillOnEdge(), seconds: 1) == .nudge)
        }
        #expect(Self.feed(&coordinator, Self.stillOnEdge(), seconds: 1) == .rethrow)
        #expect(coordinator.phase == .rolling)
        #expect(coordinator.nudgeCount == limit)
        #expect(coordinator.rethrowCount == 1)

        // 重丟之後推的次數重新算。
        #expect(Self.feed(&coordinator, Self.stillOnEdge(), seconds: 1) == .nudge)
    }

    @Test("推一把之後骰子倒下來，照常停下")
    func settlesAfterANudge() {
        var coordinator = Self.rolling()
        #expect(Self.feed(&coordinator, Self.stillOnEdge(), seconds: 1) == .nudge)
        _ = Self.feed(&coordinator, Self.moving(), seconds: 0.4)
        #expect(Self.feed(&coordinator, Self.still(faceUp: 9), seconds: 1) == .settled(faceIndex: 9))
    }

    // MARK: - 出界與卡住

    @Test("丟擲中出界 → 立刻重丟")
    func rethrowsWhenOutOfBounds() {
        var coordinator = Self.rolling()
        let action = coordinator.step(Self.outOfBounds(), deltaSeconds: Self.frame)
        #expect(action == .rethrow)
        #expect(coordinator.phase == .rolling)
        #expect(coordinator.rethrowCount == 1)
    }

    @Test("待機時出界 → 放回場內，但不算一次擲骰")
    func recoversWhenOutOfBoundsWhileIdle() {
        var coordinator = RollCoordinator()
        let action = coordinator.step(Self.outOfBounds(), deltaSeconds: Self.frame)
        #expect(action == .rethrow)
        #expect(coordinator.phase == .idle)
    }

    @Test("待機時骰子落定不會報出結果")
    func idleNeverReportsAResult() {
        var coordinator = RollCoordinator()
        #expect(Self.feed(&coordinator, Self.still(faceUp: 0), seconds: 2) == nil)
        #expect(coordinator.phase == .idle)
    }

    @Test("一直停不下來 → 視為卡住，重丟")
    func rethrowsWhenStuck() {
        var coordinator = Self.rolling()
        let limit = coordinator.tuning.maxRollSeconds

        #expect(Self.feed(&coordinator, Self.moving(), seconds: limit - 0.5) == nil)
        #expect(Self.feed(&coordinator, Self.moving(), seconds: 1) == .rethrow)
        // 重丟之後重新計時，不會下一幀又重丟。
        #expect(Self.feed(&coordinator, Self.moving(), seconds: limit - 0.5) == nil)
    }

    // MARK: - 不變式：處理方式不可以依結果而定

    /// 重丟的條件不可以看結果。
    ///
    /// 同一段劇本（動 → 立在稜上 → 動 → 平躺），換二十個不同的面去跑，
    /// 每一面得到的動作序列必須**完全一樣**（除了最後報出的面編號）。
    /// 如果有人加了「大凶就再推一把」之類的條件，大凶那一面的序列就會跟別人不同。
    // MARK: - 丟到一半被打斷

    @Test("丟擲中被打斷，回來時整個重丟")
    func restartsWhenInterruptedWhileRolling() {
        var coordinator = Self.rolling()
        _ = Self.feed(&coordinator, Self.moving(), seconds: 0.8)

        #expect(coordinator.restartInterruptedRoll() == true)
        #expect(coordinator.phase == .rolling)
        #expect(coordinator.rollSeconds == 0)
    }

    @Test("待機或已停下時回來，什麼都不做 —— 停下的結果已經定了，不可以重丟")
    func doesNotRestartWhenNotRolling() {
        var idle = RollCoordinator()
        #expect(idle.restartInterruptedRoll() == false)
        #expect(idle.phase == .idle)

        var settled = Self.rolling()
        _ = Self.feed(&settled, Self.still(faceUp: 7), seconds: 1)
        #expect(settled.phase == .settled(faceIndex: 7))
        #expect(settled.restartInterruptedRoll() == false)
        #expect(settled.phase == .settled(faceIndex: 7))
    }

    @Test("重丟之後靜止時間重新算，不會沿用打斷前累積的")
    func restartClearsTheStillTimer() {
        var coordinator = Self.rolling()
        // 差一點點就要判定停下了。
        let almost = coordinator.tuning.stillSeconds - Self.frame * 2
        #expect(Self.feed(&coordinator, Self.still(faceUp: 4), seconds: almost) == nil)

        #expect(coordinator.restartInterruptedRoll() == true)

        // 沿用舊累積的話，再兩幀就會停下。
        #expect(Self.feed(&coordinator, Self.still(faceUp: 4), seconds: Self.frame * 4) == nil)
        #expect(coordinator.phase == .rolling)
    }

    @Test("重丟的條件不看朝上的是哪一面", arguments: 0..<Icosahedron.faceCount)
    func restartDoesNotDependOnTheFace(faceIndex: Int) {
        var coordinator = Self.rolling()
        // 靜止在某一面上，但還沒久到判定停下。
        _ = Self.feed(&coordinator, Self.still(faceUp: faceIndex), seconds: Self.frame * 3)
        #expect(coordinator.restartInterruptedRoll() == true)
    }

    @Test("二十個面走過完全相同的處理流程")
    func handlingDoesNotDependOnTheFace() {
        func script(for faceIndex: Int) -> [String] {
            var coordinator = Self.rolling()
            var actions: [String] = []

            func record(_ sample: RollCoordinator.Sample, seconds: Float) {
                var elapsed: Float = 0
                while elapsed < seconds {
                    switch coordinator.step(sample, deltaSeconds: Self.frame) {
                    case nil: break
                    case .nudge: actions.append("nudge")
                    case .rethrow: actions.append("rethrow")
                    case .settled: actions.append("settled")
                    }
                    elapsed += Self.frame
                }
            }

            record(Self.moving(faceUp: faceIndex), seconds: 0.8)
            record(Self.stillOnEdge(nearFace: faceIndex), seconds: 0.5)
            record(Self.moving(faceUp: faceIndex), seconds: 0.3)
            record(Self.still(faceUp: faceIndex), seconds: 2)
            actions.append("nudges=\(coordinator.nudgeCount) rethrows=\(coordinator.rethrowCount)")
            actions.append("phase=\(coordinator.phase == .settled(faceIndex: faceIndex))")
            return actions
        }

        let reference = script(for: 1)
        #expect(reference.contains("settled"))
        for faceIndex in 0..<Icosahedron.faceCount {
            #expect(script(for: faceIndex) == reference, "第 \(faceIndex) 面的處理流程跟別的面不一樣")
        }
    }
}
