# RiskDice

**English** | [繁體中文](README.zh-TW.md)

**A risky die for Apple Watch: open the app, flick your wrist, and a 20-sided die is thrown, bounces, rolls and comes to rest as if it were real — 19 faces read 大吉 (great luck), 1 face reads 大凶 (great misfortune).**

Swift + SwiftUI + SceneKit, Apple frameworks only, no third-party dependencies.

> This is an **unofficial fan project**. The concept of the die (twenty faces, 19 lucky and 1 unlucky,
> black with white and red lettering) comes from the "Risky Dice" in the Greed Island arc of
> *HUNTER×HUNTER* by Yoshihiro Togashi. All rights to that work belong to its author and publisher.
> This project is not affiliated with them, is not for profit, and uses no images or assets from the
> original work — the face lettering and the app icon are drawn by code.

> Code comments and test names are written in Traditional Chinese.

> 📦 **This repository is a snapshot shared as-is. It is archived and no longer maintained.** Issues and pull requests will not be answered — feel free to fork it.

---

## What it does

- **Flick your wrist** or **tap the screen** to throw the die. Both triggers behave identically.
- The die moves in the space of the watch face itself: **no tray, no box**. The four edges of the screen
  are invisible walls, and the die bounces off them.
- When it stops, you read the top face yourself. The lettering is not necessarily upright — like a real
  die, it lands whichever way it lands.
- The result **really is decided by the physics simulation**, not by drawing a random number and then
  playing an animation. Each face still comes up with probability exactly 1/20 (see below).
- Nothing is stored: no history, no statistics, no pity system.

### Current status

| Item | Status |
|---|---|
| Icosahedron, face textures, physics throw, reading the top face | Done |
| Tap to throw, flick to throw, haptic on throw | Done |
| Running on a real watch (Apple Watch SE 1st gen, watchOS 10.6) | Runs smoothly |
| Flick detection threshold | **Working value** — a light flick triggers it, but false triggers while walking have not been measured yet |
| Haptic on landing, a special effect for 大凶, fine-tuning of the throw feel | Not done yet |

---

## Getting it running

### Requirements

- A Mac with Xcode (including watchOS platform support). The project was created with Xcode 27
- The simulator is enough. For a real device you also need an Apple Watch (watchOS 10.6 or later),
  its paired iPhone, and an Apple ID (a free one works)
- No third-party packages

### Change two settings first

The signing team has been cleared from the project, and the bundle identifiers are still the original
author's. You can ignore this for the simulator. To install on a real device, open
**Signing & Capabilities** in Xcode and, for every target:

1. Set **Team** to your own
2. Replace the `com.nate0815` prefix of the **Bundle Identifier** with your own
   (keep the Watch App's `WKCompanionAppBundleIdentifier` consistent with it)

Replace `com.nate0815.RiskDice.watchkitapp` in the commands below accordingly.

### On the simulator

Open `RiskDice/RiskDice.xcodeproj` in Xcode, choose the **RiskDice Watch App** scheme,
pick any Apple Watch simulator as the destination, and press ▶︎.

Or from the command line (`<SIM>` is the UDID of any simulator listed by `xcrun simctl list devices | grep Watch`):

```bash
xcodebuild -project RiskDice/RiskDice.xcodeproj -scheme "RiskDice Watch App" \
  -destination "platform=watchOS Simulator,id=<SIM>" build
xcrun simctl boot <SIM>
xcrun simctl install <SIM> ~/Library/Developer/Xcode/DerivedData/RiskDice-*/Build/Products/Debug-watchsimulator/RiskDice\ Watch\ App.app
xcrun simctl launch <SIM> com.nate0815.RiskDice.watchkitapp
```

**What "it works" looks like**: a top-down view of a black icosahedron resting on a dark grey floor.
Tap the screen and the die is thrown, bounces off the screen edges, and stops after a second or two.

> ⚠️ **Flick detection and haptics cannot be tested on the simulator** (no accelerometer, no haptic
> engine). Use a tap there instead.
>
> ⚠️ Pressing ▶︎ in Xcode sometimes hangs on the launch spinner (a debugger issue, not the app).
> Press ■ and launch the app from its icon in the simulator.

### On a real watch

The watch must already be paired with Xcode on this Mac (`xcrun devicectl list devices` lists it).

Pressing ▶︎ in Xcode with the watch as destination is enough. If the watch stays on `connecting`,
or the install times out on the control channel, this setup is the one that actually worked:

1. Turn on Personal Hotspot on the iPhone with **Maximize Compatibility** enabled (the watch only supports 2.4 GHz Wi-Fi)
2. Connect both the Mac and the watch to that hotspot
3. **Turn Bluetooth off in the iPhone's Settings app** (the Control Centre toggle does not count) —
   with Bluetooth on, the watch drops Wi-Fi and the Mac cannot reach it
4. Keep the watch unlocked and awake
5. Continue only once `xcrun devicectl list devices` shows the watch as `connected`

```bash
W=<UDID of the watch>
xcodebuild -project RiskDice/RiskDice.xcodeproj -scheme "RiskDice Watch App" \
  -destination "platform=watchOS,id=$W" -allowProvisioningUpdates build
xcrun devicectl device install app --device $W \
  ~/Library/Developer/Xcode/DerivedData/RiskDice-*/Build/Products/Debug-watchos/RiskDice\ Watch\ App.app
xcrun devicectl device process launch --device $W com.nate0815.RiskDice.watchkitapp
```

> ⚠️ With a free Apple ID the installed app expires after about 7 days and has to be reinstalled.
>
> Tapping while the screen is dimmed only wakes it and does not throw. Flicks and taps are accepted once the screen is on.

**Watch will not show up, pair or install?** → [Q&A: when the watch will not connect to the Mac](TROUBLESHOOTING.md).

### Running the tests

```bash
xcodebuild test -project RiskDice/RiskDice.xcodeproj -scheme "RiskDice Watch App" \
  -destination "platform=watchOS Simulator,id=<SIM>"
```

---

## How the code is organised

All of the app code lives in `RiskDice/RiskDice Watch App/`. The guiding rule: **everything that decides
probability or judgement is a pure function** — no SceneKit, no clock, no sensors — so it can be
tested without launching a simulator.

| File | What it does | Pure? |
|---|---|---|
| `Icosahedron.swift` | Geometry of the regular icosahedron (SceneKit has no built-in one) | ✓ |
| `DieRoll.swift` | Draws a uniformly random initial orientation; reads which face is up after the die stops | ✓ |
| `DieThrow.swift` | Initial velocity and spin for one throw | ✓ |
| `Arena.swift` | The space the die moves in: where the walls are, how far a point is from them | ✓ |
| `RollCoordinator.swift` | State machine (idle / rolling / settled) and the rule for "when has it stopped" | ✓ |
| `ShakeDetector.swift` | Decides whether a motion sample counts as a flick. Tune the threshold here only | ✓ |
| `WakeGuard.swift` | Ignores the trigger that arrives right as the screen wakes | ✓ |
| `DieFaceTexture.swift` | Draws the face textures in code with the system font — no external assets | |
| `DiceScene.swift` | The SceneKit scene: die, invisible walls, camera | |
| `DiceController.swift` | Connects the state machine to SceneKit: measures the die every frame and throws / nudges / re-throws as told | |
| `ShakeMonitor.swift` | Feeds CoreMotion data into `ShakeDetector` | |
| `DebugOptions.swift` | Launch arguments for verification (auto-roll, numbered faces, …). All off in Release builds | |
| `ContentView.swift`, `RiskDiceApp.swift` | SwiftUI entry point | |

Also:

- `RiskDice/RiskDice/` — an empty iPhone companion app. It has no features; its only job is to carry the watch app onto the watch
- `RiskDice/RiskDice Watch AppTests/`, `RiskDice Watch AppUITests/` — unit tests and UI tests
- `tools/make-app-icon.swift` — the script that draws the app icon: `swift tools/make-app-icon.swift <output png path>`

---

## Why the probability is exactly 1/20

It may seem that letting a physics simulation decide the result cannot guarantee uniformity. It can,
by symmetry.

A regular icosahedron looks identical whichever face is turned up. So as long as the die's **initial
orientation is uniformly random** before each throw (every orientation equally likely, and independent
of the throw's position, force and spin), "face 3 ends up on top" and "face 17 ends up on top" must
have the same probability — relabel the faces by one of the solid's symmetries and the whole physical
process is the same, only the labels differ. Twenty faces with equal probability summing to 1 gives
1/20 each. How the physics engine resolves collisions, and how its parameters are tuned, does not
affect this conclusion.

This imposes two constraints that must not be broken:

1. **The initial orientation must be drawn from the uniform distribution** (`DieRoll.uniformRandomOrientation`,
   Shoemake's method). Not "the last resting orientation plus some jitter", and not "one uniform angle per axis".
2. **The decision to re-throw must not depend on the result.** When the die stops in an unreadable
   state (leaning on a wall, balanced on an edge) it may be nudged or re-thrown, but anything like
   "it came up 大凶, so throw again" directly breaks the probability.

Consequently there is **no tunable "misfortune probability"** anywhere in the code.

---

## Before you change things

When the constraints below are violated, **the app still runs and reports no error** — it is just
quietly broken. Every one of them was hit for real.

| Constraint | Symptom when broken |
|---|---|
| **Scene units are not metres** (`DiceScene.unitsPerMetre`), and the die must not be smaller than about 1 unit in the scene. SceneKit's physics engine misbehaves with very small bodies | The die falls straight through the floor and vanishes, leaving only the floor on screen |
| **Gravity is deliberately not the physically correct value** (`DiceScene.gravityMagnitude`). Setting it to "9.8 × scale" is too large: the die penetrates the collision margin on every time step | The die slowly "crawls" into a corner on its own and never stops. Easily mistaken for insufficient damping |
| **The camera's `zNear` must match the scene scale** | A completely black screen |
| **The walls must lean inwards along the camera's line of sight**, converging to a point at the camera (`Arena.apexY` must equal the camera height). The camera is a perspective one: the higher the die bounces, the further out it projects on screen | Half the die is cut off by the screen edge while it is in the air; perfectly fine at rest, so screenshots do not reveal it |
| **The scene and the state machine may only be touched on the render thread.** The main thread may only call `DiceController.requestRoll()` to raise a flag, handled on the next frame | The die occasionally teleports, a throw occasionally loses its force, or two throws occasionally fire in a row. Intermittent and not reproducible |
| **`Icosahedron.doomFaceIndex` must refer to exactly one face**; the initial orientation must be uniform and re-throws must not depend on the result (see the previous section) | The probability silently drifts; it takes hundreds of throws and statistics to notice |

---

## License

The code is released under the [MIT License](LICENSE) — feel free to fork it, modify it and use it.

The license covers only the code in this repository and the images it generates. *HUNTER×HUNTER* and
its setting belong to their respective rights holders and are not covered.
