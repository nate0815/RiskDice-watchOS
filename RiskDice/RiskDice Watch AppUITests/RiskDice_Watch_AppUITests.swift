//
//  RiskDice_Watch_AppUITests.swift
//  RiskDice Watch AppUITests
//
//  整條路的驗證：點一下 → 骰子被丟出去 → 停下 → 讀出結果。
//  判定邏輯本身由單元測試負責；這裡驗的是**點擊真的接得到、真的會停**。
//

import XCTest

final class RiskDice_Watch_AppUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private var dice: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "dice").firstMatch
    }

    private func waitForValue(_ values: Set<String>, timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = dice.value as? String, values.contains(value) { return value }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return nil
    }

    @MainActor
    func testLaunchShowsTheDieWaiting() throws {
        XCTAssertTrue(dice.waitForExistence(timeout: 10))
        XCTAssertEqual(dice.value as? String, "待機")
    }

    /// 點一下螢幕就擲。
    @MainActor
    func testTapThrowsTheDieAndItSettles() throws {
        XCTAssertTrue(dice.waitForExistence(timeout: 10))

        dice.tap()
        XCTAssertNotNil(waitForValue(["丟擲中"], timeout: 2), "點了之後沒有進入丟擲中")
        XCTAssertNotNil(waitForValue(["大吉", "大凶"], timeout: 15), "丟出去之後沒有停下")
    }

    /// 停下之後再點，同一顆骰子再被丟出去。連做幾次，每次都要停得下來。
    @MainActor
    func testCanRollAgainAfterSettling() throws {
        XCTAssertTrue(dice.waitForExistence(timeout: 10))

        for round in 1...4 {
            dice.tap()
            XCTAssertNotNil(waitForValue(["丟擲中"], timeout: 2), "第 \(round) 次：點了沒有反應")
            XCTAssertNotNil(waitForValue(["大吉", "大凶"], timeout: 15), "第 \(round) 次：沒有停下")
        }
    }

    /// 骰子還在動時又觸發 → 忽略。
    @MainActor
    func testTapWhileRollingDoesNotBreakTheRoll() throws {
        XCTAssertTrue(dice.waitForExistence(timeout: 10))

        dice.tap()
        XCTAssertNotNil(waitForValue(["丟擲中"], timeout: 2))
        dice.tap()
        dice.tap()
        XCTAssertNotNil(waitForValue(["大吉", "大凶"], timeout: 15), "丟擲中連點之後停不下來")
    }
}
