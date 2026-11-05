# Contributing

Use Swift 5.9 or later on macOS. Open `Package.swift` in Xcode or use the CLI:

```sh
bash -n scripts/build.sh scripts/sign-app.sh
swift test
bash scripts/build.sh
open dist/AirSkip.app
```

The build produces an optimized app with bundled icons and all animation frames.
Run the syntax checks, regression suite, and app build locally before pushing
changes.

Swift files live directly in `src/`; regression checks live in `tests/`. Add
regression coverage for changes to decoding, device selection,
verification, or timing. Use synthetic packet data and keys. Never commit real
keys, device identifiers, Bluetooth captures, or signing credentials.

For another case layout, follow [the decoder extension steps](docs/architecture.md#adding-another-case-layout).

For changes to the app, check the affected paths on a Mac:

- Verify the lid with both earbuds in, one in, and both out. Confirm a saved
  match survives relaunch and another case cannot drive it.
- Enable with YouTube focused in Chrome, open and close the case, then check
  that disabling, focus loss, signal expiry, sleep, and locking stop key presses.
- Check animation reversal and Reduce Motion. Confirm the transition timer
  stops when the view is detached or the animation finishes.
- With automatic menu bar hiding on, move into and out of the controls without
  clicking. Check scrolling, the repeat-delay slider, and manual key entry.
  Repeat on a full-screen Space or another display when available.

Unit checks cover parsing and state transitions. Bluetooth reception, macOS
permission prompts, and Chrome keyboard handling require hardware validation.

The checked-in icons and animation frames are sufficient for a clean build.
Local asset tools belong in the ignored `tooling/` directory.

Downloaded app releases need a separate Developer ID signing, hardened-runtime,
and notarization process. The local build script is for source installations;
an ad hoc signature is not a notarized release.

Contributions are licensed under the project's [MIT license](LICENSE).
