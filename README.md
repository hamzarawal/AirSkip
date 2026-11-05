# AirSkip

<img src="assets/app-icon.png" alt="AirSkip app icon" width="96">

Use your AirPods case as a YouTube fast-forward remote on macOS. Open the
lid to repeat the right-arrow key; close it to stop. Set the repeat delay from
0.15 to 2 seconds.

AirSkip runs in the menu bar and works with **YouTube in Google Chrome**.
It is experimental: lid detection uses an undocumented Bluetooth format.
**Tested only on AirPods Pro 3 (firmware 9A348).** Other cases may work if they
use the same packet layout, or may need code changes. Model headers are not
restricted to Pro 3; compatibility with other cases has not been verified.

## Install from source

You need macOS 13 or later and Swift 5.9 or later from Xcode or the Xcode
command-line tools. Check with `swift --version`. If the tools are missing, run
`xcode-select --install` and finish the installer first.

```sh
git clone https://github.com/hamzarawal/AirSkip.git
cd AirSkip
bash scripts/build.sh --install
open "$HOME/Applications/AirSkip.app"
```

The script builds an optimized app for your Mac and installs it in
`~/Applications`. It needs no third-party packages, Blender, or paid Apple
developer account. To build without installing, run `bash scripts/build.sh`;
the app will be in `dist/AirSkip.app`.

If exactly one Apple signing certificate is available, the build uses it.
Otherwise, with no certificate, it signs the app locally (ad hoc). A changed
ad hoc build may require removing and re-adding AirSkip in Accessibility
Settings. See [signing and updates](docs/troubleshooting.md#signing-and-updates)
if you have multiple certificates or want a consistent signing identity.

## Set up

1. Pair your AirPods with this Mac and open AirSkip.
2. Allow Bluetooth access. Open and close the case, check that the animation
   follows it, then click **The lid matches**. Check with the earbuds out too.
3. Click **Open Accessibility Settings** and allow AirSkip under
   **Privacy & Security → Accessibility**. Use **+** to add the installed app
   if it is missing.
4. Enable AirSkip. Bring YouTube in Chrome to the front, click the video player,
   and close AirSkip's controls. Open the lid to skip; close it to stop.

The app starts disabled and remembers your verified case. Closing its window
keeps it running in the menu bar. Open the app again to bring back the controls
if the menu bar icon is hidden. Disabling AirSkip stops listening. Sleep and
screen locking disable it too; enable it again when ready.

## Limits and privacy

- Chrome must be frontmost and its focused window title must contain `YouTube`.
  This checks the title, not the URL. Focused text fields block arrow presses.
- Bluetooth delivery adds latency. A missing closing broadcast can allow
  skipping until the signal expires, up to three seconds after the last packet.
  The repeat-delay slider changes key timing, not Bluetooth latency.
- The case stays pinned to one Bluetooth peripheral. If its identity changes,
  use **Troubleshoot → Find case again** and repeat the lid match.
- Keys stay in macOS Keychain. Device choices and repeat delay stay in local
  preferences. AirSkip has no network service, telemetry, or browser extension.
- The animation uses 93 bundled PNG frames, supports either direction, and
  respects Reduce Motion. There is no runtime 3D renderer.

If the lid is not detected, use **Troubleshoot** in the app. Automatic setup
tries a saved key, the selected pair's macOS pairing key, and then one current-key
request to connected earbuds when needed. macOS may ask for Keychain access.
See [troubleshooting](docs/troubleshooting.md) for manual recovery.

## Development

```sh
swift test
bash scripts/build.sh
```

Open `Package.swift` in Xcode, or edit the Swift sources directly. See
[CONTRIBUTING.md](CONTRIBUTING.md) for validation and
[architecture](docs/architecture.md) for the source layout and Bluetooth format.
