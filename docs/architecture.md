# Architecture

AirSkip uses one Swift app target, `MenuBarApp`, and one test target, `AppTests`.
There are no external dependencies.

```text
src/             Swift source files
  animation/     31 hinge poses × 3 earbud counts
tests/           Parser, device-selection, timing, and persistence checks
assets/          App icons and vector logo
scripts/         Build, installation, and local signing
docs/            Architecture and troubleshooting
Info.plist       App bundle metadata
```

## Runtime

`AppModel` coordinates discovery, key recovery, verification, and playback on
the main run loop. Keychain work runs off the main thread. Normal listening
uses Core Bluetooth scanning; the temporary L2CAP channel is only used during
key recovery. Recovery attempts are limited per device and method, and a denied
Keychain prompt stops further automatic requests for that pair.

`SkipController` pins one peripheral, requires both lid states and explicit
confirmation, and uses system uptime for freshness and repeat timing. A saved
match restores verification without restoring a live signal. The polling timer
runs every 50 ms. An accepted open packet can trigger a press on the next tick;
missed ticks never produce a catch-up burst. Signals expire after three seconds.
Sleep, locking, disabling, and switching devices clear the live signal.

`ChromeKeySender` checks Accessibility permission, the frontmost application,
the focused window title, and the focused UI role. It posts key-down/key-up
pairs only to Chrome's process and rechecks the frontmost process before posting.
It does not activate the browser. Window-title matching does not verify the URL.

The status item uses an AppKit menu hosting SwiftUI controls. AppKit owns menu
tracking so an auto-hidden menu bar stays visible during interaction. Reopening
the app brings up a separate controls window backed by the same model.

## Animation

The app bundles the final transparent 640 × 512 PNGs. `CaseFrameView` caches at
most 40 images with a 48 MiB cost limit. It animates at 60 Hz only during a
transition, eases between poses, and samples the current position before a
reversal. The timer stops when the transition ends or the view leaves its
window. Reduce Motion jumps directly to the target pose. No model generation
or rendering tools are needed to build the app.

## Bluetooth format

Apple manufacturer data is parsed as type/length/value messages. Only `07 11`
case packets with the observed `29 20` model header supply lid readings. The
16-byte payload can arrive decoded by macOS or be decrypted with the selected
pair's 16-byte `MagicAccEncKey` using AES-128 ECB. Reserved fields and battery
ranges must match the supported layout. The `07 19` earbud packet is not used
for lid state because it can be stale outside the case.

The format is reverse-engineered and unauthenticated. Structural checks do not
prove device ownership; physical lid confirmation and peripheral pinning are
still required. Unknown layouts are rejected.

Protocol references:

- [AirPods BLE research](https://github.com/stuffz/airpods/blob/main/docs/ble.md)
- [CAPod key retrieval notes](https://github.com/d4rken-org/capod/wiki/airpod-Keys)
- [Apple Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)

The Swift implementation and bundled artwork are original project assets.
