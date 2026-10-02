# Q&A: when the watch will not connect to the Mac

**English** | [繁體中文](TROUBLESHOOTING.zh-TW.md)

Problems actually hit while installing the app on a real Apple Watch, and the fixes that worked.
The setup was an Apple Watch SE (1st generation, watchOS 10.6), Xcode 27 and a free Apple ID.
Other models and versions may differ, and anything marked "not sure" was genuinely never tested in isolation.

**One thing to remember first: pairing and installing need opposite conditions.**

| What you are doing | iPhone Bluetooth | How the connection is made |
|---|---|---|
| Getting Xcode to recognise the watch (pairing) | **On** | iPhone plugged into the Mac over USB; the watch is discovered through the iPhone |
| Installing the app on the watch | **Off** | Mac and watch on the same 2.4 GHz Wi-Fi network |

---

## Q1. Xcode cannot see the watch at all, and the watch has no "Developer Mode" option

**Symptoms**

- The iPhone is fine, but the watch does not appear in `xcrun devicectl list devices` or in Xcode's Manage Run Destinations
- On the watch, Settings → Privacy & Security has no "Developer Mode" entry at the bottom
- Restarting the watch and the iPhone does not help

**Cause**

The "Developer Mode" option only appears after Xcode has seen the watch. And on some Wi-Fi networks
(a home network, in my case) the Mac simply cannot find the watch — the watch says it is connected,
but it is invisible from the Mac. The exact reason is unknown.

**Fix: put both the Mac and the watch on the iPhone's Personal Hotspot.**

1. Turn on Personal Hotspot on the iPhone, with "Maximize Compatibility" enabled
2. Connect the Mac to that hotspot (`ipconfig getifaddr en0` should show `172.20.10.x`)
3. Connect the watch to that hotspot too
4. `xcrun devicectl list devices` should now list the watch
5. Settings → Privacy & Security on the watch now shows "Developer Mode" — turn it on and restart as prompted
6. After the restart the watch shows as `available (paired)`

> Do not switch the Mac back to its usual Wi-Fi during this.
>
> Xcode 27 renamed "Devices and Simulators" to **Manage Run Destinations** (⇧⌘2); you will not find it under the old name.

---

## Q2. The watch is paired, but keeps flipping between `available (paired)` and `connecting`, and installs fail

**Symptoms**

- `xcrun devicectl list devices` lists the watch, but it never becomes `connected`
- Running from Xcode fails with `CoreDeviceError Code 4`
- Installing from the command line fails with `Bluetooth connection to the device was invalidated before tunnel could be created`
- The watch answers ping, so it looks "connected but flaky"

**Cause**

The word "Bluetooth" in that error is misleading. The install data travels over **Wi-Fi** only, and
**when the paired iPhone is within Bluetooth range, the watch prefers Bluetooth and drops Wi-Fi**
(a power-saving design). So the Mac can find the watch but cannot connect to it.

Another common cause: the Mac is on 5 GHz Wi-Fi while an older watch only supports 2.4 GHz, so they
are not really on the same network.

**Fix**

1. Turn on Personal Hotspot on the iPhone with **Maximize Compatibility** enabled (this makes the hotspot use 2.4 GHz)
2. Connect both the Mac and the watch to that hotspot
3. **Turn Bluetooth off in the iPhone's Settings app** — the Control Centre toggle only disconnects temporarily and does not count
4. Keep the watch unlocked, awake and next to the Mac
5. Install only once `xcrun devicectl list devices` shows the watch as **`connected`**

The build and install commands are in the [README](README.md), under "On a real watch".

To find out which step it is stuck on, read the system log before changing settings at random:

```bash
/usr/bin/log show --last 3m --style compact --predicate 'process == "remotepairingd" AND (eventMessage CONTAINS "tunnel bringup attempt" OR eventMessage CONTAINS "on-demand bonjour")'
```

| Log line | What it means |
|---|---|
| `Received timeout for browsing for on-demand bonjour advert` | The Mac and the watch are not on the same network, or the watch is not on Wi-Fi at all |
| `Control channel connection timed out while in state preparing` | The watch was found but cannot be reached — it dropped Wi-Fi; turn off Bluetooth on the iPhone |

> Even once connected, the link drops if the watch sits idle for long or moves away from the Mac.
> It has to be awake and nearby to reconnect.
>
> Not sure: the iPhone was plugged into the Mac over USB when this worked. Whether it still works unplugged was never tested separately.

---

## Q3. Launching right after installing returns `A connection to this device could not be established`

**Cause**

If the same app is already running on the watch, installing terminates it first and the connection
drops for ten seconds or so.

**Fix**

Wait until the watch is back to `connected` in `xcrun devicectl list devices`, then launch.

---

## Q4. I unpaired the watch in Xcode and now it will not pair again

**The short version: do not unpair unless you have to.** The connection problem in Q2 has nothing to
do with pairing; unpairing and re-pairing does not fix it and only adds this problem on top.

**Symptoms**

- The watch disappears from `xcrun devicectl list devices` entirely
- `xcrun devicectl manage pair --device <watch UDID>` returns `The specified device was not found`
- With the iPhone plugged into the Mac over USB, the watch never shows "Trust This Computer"

**Cause**

An unpaired watch is not discovered on its own; it is discovered **through the iPhone connected over
USB**. So the iPhone must be able to reach the watch over Bluetooth. Pairing is also a two-stage
process: after you tap Trust, the Mac does not finish by itself — it waits for the watch to be
discovered once more.

**Fix** (the sequence that actually worked)

1. Keep **Bluetooth on** on the iPhone and check that it is connected to the watch
2. **Restart the watch**, unlock it, then **turn the watch's Wi-Fi off** (Settings → Wi-Fi)
3. Unlock the iPhone and **plug it into the Mac over USB** (if already plugged in, unplug and replug)
4. The watch shows "Trust This Computer" → tap Trust
5. **Unplug and replug the USB cable once more** — no prompt this time; a few seconds later `xcrun devicectl list devices` lists the watch again
6. **Turn the watch's Wi-Fi back on** — you need it to install the app (back to Q2)

After each step you can check where it is stuck:

```bash
/usr/bin/log show --last 3m --style compact --predicate 'process == "remotepairingd" AND (eventMessage CONTAINS "proxied device" OR eventMessage CONTAINS "bootstrap" OR eventMessage CONTAINS "kAMD" OR eventMessage CONTAINS "Pairing completed")'
```

| Log line | Meaning | What to do |
|---|---|---|
| USB plugged in but no `proxied device` | The iPhone cannot reach the watch | Turn on Bluetooth on the iPhone |
| `kAMDUserDeniedPairingError` | The watch refused without showing a prompt | Step 2 |
| `kAMDPasswordProtectedError` | The watch is locked | Unlock it (it locks itself when off the wrist) |
| `kAMDPairingDialogResponsePendingError` | The prompt is showing and waiting for a tap | Tap Trust, then replug the USB cable |
| `Pairing completed` | Success | — |

> Not sure: whether it is the restart or turning Wi-Fi off in step 2 that does the trick. Both were done in the same round.

---

## Q5. On the simulator, flicking does nothing and there is no haptic

That is expected. The simulator has no accelerometer and no haptic engine, so both can only be tested
on a real watch. On the simulator, **tap** to throw; it behaves the same as a flick.

## Q6. Pressing ▶︎ in Xcode hangs on the launch spinner

A debugger issue, not the app. Press ■ and open the app from its icon on the simulator or the watch.
