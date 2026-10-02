# RiskDice

[English](README.md) | **繁體中文**

**Apple Watch 上的風險骰子：打開 app、甩一下手腕，一顆二十面骰像真的被丟出去一樣彈跳、滾動、停下 —— 19 面「大吉」、1 面「大凶」。**

> 這是一個**非官方的粉絲作品**。骰子的設計概念（二十面、19 吉 1 凶、黑底白紅字）出自
> 冨樫義博《HUNTER×HUNTER》貪婪之島篇的「風險骰子」，相關權利屬於原作者與出版社。
> 本專案與他們沒有任何關係，不營利，也沒有使用任何原作的圖像或素材 ——
> 骰面文字與 app 圖示都是程式畫出來的。

> 📦 **這個 repo 是一份分享用的快照，不會持續維護。** issue 與 PR 不一定有人回，歡迎直接 fork 去改。

---

## 它做什麼

- **甩手腕**或**點一下螢幕**，骰子被丟出去。兩種觸發效果完全相同。
- 骰子直接在錶面這塊空間裡活動：**沒有骰盤、沒有箱子**，螢幕的四邊就是看不見的邊界，撞到會彈回來。
- 停下之後自己看朝上的是哪一面。字不一定是正的 —— 跟真的骰子一樣，停成什麼方向就是什麼方向。
- 結果**真的是物理模擬算出來的**，不是先抽亂數再演一段動畫。各面機率仍然精確是 1/20（見下面的說明）。
- 不保存任何東西：沒有紀錄、沒有統計、沒有保底。

### 目前的狀態

| 項目 | 狀態 |
|---|---|
| 二十面骰、骰面貼圖、物理丟擲、讀出朝上的面 | 完成 |
| 點擊擲骰、甩手擲骰、丟出時的震動 | 完成 |
| 在實體手錶上跑（Apple Watch SE 第 1 代、watchOS 10.6） | 跑得順 |
| 甩手的判定門檻 | **工作值** —— 輕甩會觸發，但還沒用走路時的資料驗過誤觸 |
| 停下時的震動、大凶的特別演出、丟擲手感的細調 | 還沒做 |

---

## 怎麼跑起來

### 需要什麼

- 一台 Mac 與 Xcode（含 watchOS 平台支援）。專案是用 Xcode 27 建的
- 模擬器就能跑；要裝到實機的話，另外需要 Apple Watch（watchOS 10.6 以上）、與它配對的 iPhone、一個 Apple ID（免費的就可以）
- 不需要任何第三方套件

### 先改兩個設定

專案裡的簽署資訊已經清空，Bundle Identifier 還是原作者的。只跑模擬器可以不管；要裝到實機，
請在 Xcode 的 **Signing & Capabilities** 裡，對每一個 target：

1. **Team** 選你自己的
2. **Bundle Identifier** 的 `com.nate0815` 換成你自己的前綴
   （Watch App 的 `WKCompanionAppBundleIdentifier` 要跟著改成一致的值）

下面指令裡的 `com.nate0815.RiskDice.watchkitapp` 也要跟著換。

### 在模擬器上跑

在 Xcode 裡開 `RiskDice/RiskDice.xcodeproj`，scheme 選 **RiskDice Watch App**，
執行目標選任一個 Apple Watch 模擬器，按 ▶︎。

或者用指令（`<SIM>` 換成 `xcrun simctl list devices | grep Watch` 裡任一個模擬器的 UDID）：

```bash
xcodebuild -project RiskDice/RiskDice.xcodeproj -scheme "RiskDice Watch App" \
  -destination "platform=watchOS Simulator,id=<SIM>" build
xcrun simctl boot <SIM>
xcrun simctl install <SIM> ~/Library/Developer/Xcode/DerivedData/RiskDice-*/Build/Products/Debug-watchsimulator/RiskDice\ Watch\ App.app
xcrun simctl launch <SIM> com.nate0815.RiskDice.watchkitapp
```

**看到什麼算跑起來了**：從正上方往下看，深灰色的底上有一顆黑色二十面骰靜止著。
點一下螢幕，骰子被丟出去、撞到螢幕邊緣彈回來、滾一兩秒後停下。

> ⚠️ **甩手與震動在模擬器上測不了**（沒有加速度計、沒有實體震動），模擬器上用點擊擲骰。
>
> ⚠️ Xcode 按 ▶︎ 有時會卡在啟動轉圈（除錯器的問題，不是 app）。
> 卡住就按 ■ 停止，直接在模擬器裡點 app 圖示開啟。

### 在實體手錶上跑

手錶要先跟這台 Mac 的 Xcode 配對過（`xcrun devicectl list devices` 列得出手錶）。

用 Xcode 直接對手錶按 ▶︎ 就可以。如果手錶一直停在 `connecting`、或安裝時控制通道逾時，
下面這個配置是實際走得通的：

1. iPhone 開個人熱點，**開「最大化相容性」**（手錶只支援 2.4GHz 的 Wi-Fi）
2. Mac 與手錶都連上那個熱點
3. **到 iPhone 的「設定」裡關掉藍牙**（控制中心那顆不算）—— 藍牙開著，手錶會把 Wi-Fi 放掉，Mac 就連不到它
4. 手錶解鎖、保持亮著
5. `xcrun devicectl list devices` 看到手錶的狀態是 `connected` 才往下

```bash
W=<手錶的 UDID>
xcodebuild -project RiskDice/RiskDice.xcodeproj -scheme "RiskDice Watch App" \
  -destination "platform=watchOS,id=$W" -allowProvisioningUpdates build
xcrun devicectl device install app --device $W \
  ~/Library/Developer/Xcode/DerivedData/RiskDice-*/Build/Products/Debug-watchos/RiskDice\ Watch\ App.app
xcrun devicectl device process launch --device $W com.nate0815.RiskDice.watchkitapp
```

> ⚠️ 用免費 Apple ID 簽署的話，裝上去的 app 約 7 天後失效，要重裝。
>
> 螢幕暗著時點一下只會把螢幕點亮，不會擲；亮起之後才接受甩手或點擊。

**手錶連不上、配對不起來、裝不上去** → [手錶連不上 Mac 時的 Q&A](TROUBLESHOOTING.zh-TW.md)。

### 跑測試

```bash
xcodebuild test -project RiskDice/RiskDice.xcodeproj -scheme "RiskDice Watch App" \
  -destination "platform=watchOS Simulator,id=<SIM>"
```

---

## 程式怎麼組的

所有程式都在 `RiskDice/RiskDice Watch App/`。切法的原則是：**會決定機率與判定的邏輯全部寫成純函式**，
不碰 SceneKit、不碰時鐘、不碰感測器，所以不必開模擬器就測得了。

| 檔案 | 做什麼 | 純函式？ |
|---|---|---|
| `Icosahedron.swift` | 正二十面體的幾何（SceneKit 沒有內建，自己算） | ✓ |
| `DieRoll.swift` | 抽均勻隨機的初始朝向；讀出停下後朝上的是哪一面 | ✓ |
| `DieThrow.swift` | 一次丟擲的初始速度與旋轉 | ✓ |
| `Arena.swift` | 骰子活動的空間：邊界在哪、離邊界多遠 | ✓ |
| `RollCoordinator.swift` | 待機／丟擲中／已停下 的狀態機，以及「什麼時候算停下」 | ✓ |
| `ShakeDetector.swift` | 「這一筆動作資料算不算甩手」的判定。調門檻只動這個檔 | ✓ |
| `WakeGuard.swift` | 螢幕剛亮起的那一下不算擲骰 | ✓ |
| `DieFaceTexture.swift` | 用系統字型在程式裡畫出骰面貼圖，零外部素材 | |
| `DiceScene.swift` | SceneKit 場景：骰子、隱形邊界、鏡頭 | |
| `DiceController.swift` | 把狀態機接到 SceneKit：每一幀量骰子、照狀態機說的去丟／推／重丟 | |
| `ShakeMonitor.swift` | 把 CoreMotion 的資料餵給 `ShakeDetector` | |
| `DebugOptions.swift` | 驗證用的啟動參數（自動連丟、骰面顯示編號…）。Release 組態下全部關閉 | |
| `ContentView.swift`、`RiskDiceApp.swift` | SwiftUI 進入點 | |

其他：

- `RiskDice/RiskDice/` —— iPhone 端的空殼 app。它沒有任何功能，唯一的作用是把 watch app 送上手錶
- `RiskDice/RiskDice Watch AppTests/`、`RiskDice Watch AppUITests/` —— 單元測試與介面測試
- `tools/make-app-icon.swift` —— 畫 app 圖示的腳本：`swift tools/make-app-icon.swift <輸出的 png 路徑>`

---

## 機率為什麼是精確的 1/20

直覺上「物理模擬決定結果」好像保證不了均勻，其實可以，靠的是對稱性：

正二十面體轉到任何一面朝上，形狀都跟原來完全重合。所以只要丟出前骰子的**初始朝向是均勻隨機的**
（所有朝向機會均等，而且跟丟出的位置、力道、旋轉各自獨立），那麼「第 3 面最後朝上」與
「第 17 面最後朝上」的機率必然相同 —— 把骰子上的編號按某個對稱轉法換一換，整個物理過程一模一樣，
只是標籤換了。二十個面機率相同、加起來是 1，所以各是 1/20。
物理引擎內部怎麼算碰撞、參數怎麼調，都不影響這個結論。

這帶來兩條不能違反的約束：

1. **初始朝向必須從均勻分布抽**（`DieRoll.uniformRandomOrientation`，Shoemake 的方法）。
   不能是「上次停下的朝向再加一點擾動」，也不能「三個軸各抽一個均勻角度」。
2. **重丟的條件不能看結果**。骰子停在無法判讀的狀態（斜靠在邊界上、立在稜上）時可以再推一把或重丟，
   但「這次是大凶所以重丟」之類的處理會直接破壞機率。

也因此，程式裡**不存在一個可以調的「大凶機率」**。

---

## 想改的話，先知道這些

下面這些約束被破壞之後**程式還是能跑，也不會有任何錯誤訊息**，只是已經壞了。都是實際踩過的。

| 約束 | 破壞後的症狀 |
|---|---|
| **場景單位不是公尺**（`DiceScene.unitsPerMetre`），骰子在場景裡不能小於約 1 個單位。SceneKit 的物理引擎對太小的物體會失常 | 骰子直接穿過地面消失，畫面上只剩一片底 |
| **重力刻意不是物理正確值**（`DiceScene.gravityMagnitude`）。照「9.8 × 尺度」去設會太大，每個時間步都穿透碰撞邊界 | 骰子緩慢地自己「爬」到牆角，永遠停不下來。很容易誤判成阻尼不夠 |
| **相機 `zNear` 要配合場景尺度** | 畫面全黑 |
| **邊界要順著鏡頭的視線往內傾斜**，在鏡頭的位置收成一點（`Arena.apexY` 必須等於鏡頭高度）。鏡頭是透視的，骰子彈得越高，投影到畫面上越往外 | 骰子彈在空中時被螢幕邊緣切掉一半；靜止時完全正常，截圖看不出來 |
| **場景與狀態機只能在算圖執行緒上碰**。主執行緒只能呼叫 `DiceController.requestRoll()` 舉旗子，由下一幀處理 | 骰子偶爾瞬移、力道偶爾被吃掉、偶爾連丟兩次。偶發、無法重現 |
| **`Icosahedron.doomFaceIndex` 只能對應一個面**；初始朝向要均勻、重丟不看結果（見上一節） | 機率悄悄跑掉，要丟幾百次做統計才看得出來 |

---

## 授權

程式碼以 [MIT License](LICENSE) 釋出 —— 歡迎自由 fork、修改、拿去用。

授權只涵蓋這個 repo 裡的程式碼與它產生的圖像。《HUNTER×HUNTER》及其中的設定屬於原權利人，不在授權範圍內。
