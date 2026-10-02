//
//  ContentView.swift
//  RiskDice Watch App
//
//  Created by NA23.Chiao on 2026/10/2.
//

import SceneKit
import SwiftUI

struct ContentView: View {
    /// 場景只建一次。每次 `body` 重算都重建的話，骰子會瞬間彈回起點。
    @StateObject private var model = DiceModel()

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SceneView(
            scene: model.controller.scene,
            options: [.rendersContinuously],
            delegate: model.controller
        )
        .ignoresSafeArea()
        // 點一下螢幕就擲。效果與甩手完全相同。
        // 螢幕剛亮起的那一下不算 —— 判斷在 `DiceModel.tap()`。
        .onTapGesture { model.tap() }
        // 甩手是主要觸發。只在前景時聽；
        // `initial: true` 是因為 app 一打開就在前景，那一次不會有「變化」可以等。
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            model.setForeground(newPhase == .active)
        }
        .accessibilityElement()
        .accessibilityIdentifier("dice")
        .accessibilityLabel("風險骰子")
        .accessibilityValue(statusText)
        .accessibilityAddTraits(.isButton)
    }

    /// 給 VoiceOver 與 UI 測試讀的狀態。**畫面上不顯示** ——
    /// 結果要自己看骰子。
    private var statusText: String {
        switch model.phase {
        case .idle: "待機"
        case .rolling: "丟擲中"
        case .settled(let faceIndex): Icosahedron.isDoom(faceIndex) ? "大凶" : "大吉"
        }
    }
}

#Preview {
    ContentView()
}
