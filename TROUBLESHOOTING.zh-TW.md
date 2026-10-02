# 手錶連不上 Mac 時的 Q&A

[English](TROUBLESHOOTING.md) | **繁體中文**

把 app 裝到實體 Apple Watch 的過程中實際遇到的問題與走通的解法。
環境是 Apple Watch SE 第 1 代（watchOS 10.6）、Xcode 27、免費 Apple ID。
別的機型或版本不一定完全一樣，標「不確定」的地方是真的沒有單獨驗過。

**先記住一件事：配對與裝 app 要的條件相反。**

| 你要做的事 | iPhone 的藍牙 | 靠什麼連 |
|---|---|---|
| 讓 Xcode 認得手錶（配對） | **開** | iPhone 用 USB 接 Mac，手錶經由 iPhone 被發現 |
| 把 app 裝上手錶 | **關** | Mac 與手錶在同一個 2.4GHz Wi-Fi 上 |

---

## Q1. Xcode 完全看不到手錶，手錶上也找不到「開發者模式」

**現象**

- iPhone 一切正常，但手錶不出現在 `xcrun devicectl list devices`，也不在 Xcode 的 Manage Run Destinations 裡
- 手錶的 設定 → 隱私權與安全性 滑到最底，沒有「開發者模式」這一項
- 重開手錶、重開 iPhone 都沒用

**原因**

「開發者模式」這個選項要等 Xcode 看到手錶之後才會出現。而在某些 Wi-Fi 上（我遇到的是家用 Wi-Fi），
Mac 就是找不到手錶 —— 手錶自己顯示已連線，但 Mac 那一側看不到它。確切原因不明。

**解法：用 iPhone 的個人熱點，讓 Mac 和手錶都連上去。**

1. iPhone 開個人熱點，並打開「最大化相容性」
2. Mac 連那個熱點（`ipconfig getifaddr en0` 會是 `172.20.10.x`）
3. 手錶也連那個熱點
4. `xcrun devicectl list devices` 這時應該列得出手錶
5. 手錶的 設定 → 隱私權與安全性 會出現「開發者模式」—— 打開，依指示重開機
6. 重開後手錶的狀態變成 `available (paired)`

> 過程中不要把 Mac 切回原本的 Wi-Fi。
>
> Xcode 27 把「Devices and Simulators」改名成 **Manage Run Destinations**（⇧⌘2），照舊名稱在選單裡找不到。

---

## Q2. 手錶已經配對，但狀態一直在 `available (paired)` 與 `connecting` 之間跳，裝不上去

**現象**

- `xcrun devicectl list devices` 列得出手錶，但從來不會變成 `connected`
- Xcode 按 ▶︎ 裝實機失敗：`CoreDeviceError Code 4`
- 指令安裝失敗：`Bluetooth connection to the device was invalidated before tunnel could be created`
- 手錶 ping 得到，看起來像「連得上但不穩」

**原因**

錯誤訊息裡的「Bluetooth」是誤導。裝 app 的資料只走 **Wi-Fi**，而**配對的 iPhone 在藍牙範圍內時，
手錶會優先走藍牙、把 Wi-Fi 放掉**（系統為了省電的設計）。所以 Mac 找得到手錶，卻連不過去。

另一個常見成因：Mac 在 5GHz 的 Wi-Fi 上，而舊款手錶只支援 2.4GHz，兩者其實不在同一個網路。

**解法**

1. iPhone 開個人熱點，**開「最大化相容性」**（讓熱點走 2.4GHz）
2. Mac 與手錶都連上那個熱點
3. **到 iPhone 的「設定」裡關掉藍牙** —— 控制中心那顆只是暫時斷線，不算
4. 手錶解鎖、保持亮著、放在 Mac 旁邊
5. `xcrun devicectl list devices` 看到手錶是 **`connected`** 才動手裝

建置與安裝的指令在 [README](README.zh-TW.md)「在實體手錶上跑」。

想知道它卡在哪一步，看系統記錄，不要先亂改設定：

```bash
/usr/bin/log show --last 3m --style compact --predicate 'process == "remotepairingd" AND (eventMessage CONTAINS "tunnel bringup attempt" OR eventMessage CONTAINS "on-demand bonjour")'
```

| 記錄裡看到 | 代表什麼 |
|---|---|
| `Received timeout for browsing for on-demand bonjour advert` | Mac 與手錶不在同一個網路上，或手錶根本不在 Wi-Fi 上 |
| `Control channel connection timed out while in state preparing` | 找到手錶了但連不過去 —— 手錶把 Wi-Fi 放掉了，去關 iPhone 的藍牙 |

> 連上之後，手錶閒置太久或離 Mac 太遠還是會斷。要它醒著、在旁邊才接得回來。
>
> 不確定的地方：走通時 iPhone 的 USB 是接著 Mac 的，拔掉行不行沒有單獨測過。

---

## Q3. 剛裝完馬上啟動，回 `A connection to this device could not be established`

**原因**

手錶上如果有同一個 app 正在跑，安裝會先把它關掉，連線跟著斷十幾秒。

**解法**

等 `xcrun devicectl list devices` 裡的手錶回到 `connected` 再啟動。

---

## Q4. 在 Xcode 裡對手錶按了解除配對，之後配不回來

**先說結論：能不按就不要按。** 上面 Q2 的連線問題跟配對無關，解除再重配修不好它，只會多出這一題。

**現象**

- 手錶從 `xcrun devicectl list devices` 裡整個消失
- `xcrun devicectl manage pair --device <手錶的 UDID>` 回 `The specified device was not found`
- iPhone 用 USB 接上 Mac，手錶上卻不跳「信任這部電腦」

**原因**

沒配對的手錶不是靠自己被發現的，而是**經由接著 USB 的 iPhone**。所以 iPhone 要能用藍牙連到手錶才行。
另外配對是兩段式的：按了信任之後，Mac 不會自己接著完成，要等手錶再被發現一次。

**解法**（實際走通的順序）

1. iPhone 的**藍牙開著**，確認它連著手錶
2. **重開手錶**，開機後解鎖，然後**把手錶的 Wi-Fi 關掉**（設定 → Wi-Fi）
3. iPhone 解鎖，**用 USB 接上 Mac**（已經接著就拔掉重插）
4. 手錶跳「信任這部電腦」→ 點信任
5. **USB 再拔掉重插一次** —— 這次不會再跳提示，幾秒後 `xcrun devicectl list devices` 重新列出手錶
6. **把手錶的 Wi-Fi 開回來**，之後裝 app 要用（回到 Q2）

每一步之後可以這樣看它卡在哪：

```bash
/usr/bin/log show --last 3m --style compact --predicate 'process == "remotepairingd" AND (eventMessage CONTAINS "proxied device" OR eventMessage CONTAINS "bootstrap" OR eventMessage CONTAINS "kAMD" OR eventMessage CONTAINS "Pairing completed")'
```

| 記錄裡看到 | 意思 | 該做什麼 |
|---|---|---|
| USB 接上了但沒有 `proxied device` | iPhone 連不到手錶 | 開 iPhone 的藍牙 |
| `kAMDUserDeniedPairingError` | 手錶沒跳提示就回絕了 | 第 2 步 |
| `kAMDPasswordProtectedError` | 手錶鎖著 | 解鎖手錶（離開手腕它會自己上鎖） |
| `kAMDPairingDialogResponsePendingError` | 提示已顯示，等人按 | 點信任，然後 USB 重插 |
| `Pairing completed` | 成功 | —— |

> 不確定的地方：第 2 步裡到底是「重開」還是「關 Wi-Fi」起作用，兩個是同一輪做的，分不出來。

---

## Q5. 模擬器上甩手沒反應、也不會震動

正常。模擬器沒有加速度計，也沒有實體震動，這兩樣只能在實機上測。模擬器上用**點擊**擲骰，效果與甩手相同。

## Q6. Xcode 按 ▶︎ 卡在啟動轉圈

是除錯器的問題，不是 app。按 ■ 停止，直接在模擬器或手錶上點 app 圖示開啟。

## Q7. app 裝得上、也能用，幾個小時後卻從手錶上消失

**現象**

- 用 Mac 直接裝到手錶（`xcrun devicectl device install app`），當下能開、能擲。
- 幾個小時後手錶上的 app 不見了。沒有錯誤訊息，也沒有「已過期」的提示。
- 不是免費 Apple ID 的七天期限：那個的症狀是打不開，不是整個消失。

**原因**（推論，沒有記錄可以佐證）

watch target 宣告了伴隨的 iOS app（`WKCompanionAppBundleIdentifier`），卻**沒有標成可以獨立執行**。
系統因此把它當成依附 iPhone app 的手錶 app。從 Mac 直接安裝只會把 app 放上手錶，iPhone 上並沒有伴隨 app。
之後 iPhone 的藍牙開回來、兩台裝置重新同步，手錶上那份依附型的 app 在手機上找不到對應的 app，就被移除了。

修正之前兩邊都查過：手錶的 app 清單是空的，iPhone 上也沒有伴隨 app。

**解法**

把 watch target 標成可獨立執行，Debug 與 Release 兩個組態都要加。Xcode 的
「Watch App with New Companion iOS App」範本**不會**幫你加：

```
INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = YES;
```

這個 repo 已經加好了。要確認它有進到建置出來的 app 裡：

```bash
plutil -p ~/Library/Developer/Xcode/DerivedData/RiskDice-*/Build/Products/Debug-watchos/RiskDice\ Watch\ App.app/Info.plist | grep -i -E "Independent|Companion"
```

應該同時看到 `WKRunsIndependentlyOfCompanionApp => true` 與 `WKCompanionAppBundleIdentifier`。

> 不確定：加上這個設定之後，藍牙開回來幾分鐘 app 還在。**幾個小時後**還在不在，寫這一段的時候還沒確認 ——
> 而原本的消失是隔了幾個小時才發現的。

