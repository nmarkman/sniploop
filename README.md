# Sniploop

A fast, native macOS region GIF recorder. Press a hotkey, drag a rectangle anywhere on screen, record what happens in that region in the background, and it drops a high-quality GIF (or MP4) on your Desktop. The target feeling is the macOS screenshot tool (Cmd-Shift-4), but for short animations.

> Status: **working v1 foundation.** The full capture loop is implemented and usable daily. The in-app editor (trim/crop/fps) and distribution polish are the next milestones. See [Roadmap](#roadmap).

## What works today

- **Global hotkey** to start a capture: Hyper (Cmd-Ctrl-Opt-Shift) + G. A Caps-Lock-as-Hyper binding (Raycast/Karabiner) sends the same chord. No Accessibility permission required (Carbon `RegisterEventHotKey`).
- **URL trigger**: `open sniploop://capture` (wire it to Raycast/Shortcuts/Automator).
- **Region selector**: dim overlay + crosshair, a glowing selection box, live dimensions. On release the box stays so you can re-drag or fine-tune; press Enter to record, or hold **Shift** on release to record instantly. High-contrast HUD chips so the hints stay readable on any background.
- **Persistent recording border**: a red frame stays around the region while recording, drawn just outside the captured area so it never appears in the output.
- **Background capture** via ScreenCaptureKit, streamed straight to a temp H.264 `.mov` (flat memory, any duration).
- **Keyboard-driven stop**: while recording, **Enter** stops and exports, **Esc** cancels. A floating Stop/Cancel control with a timer is also there.
- **Export**: GIF via bundled [gifski](https://gif.ski) (best-in-class quality), MP4 via AVFoundation. Choose which in Settings.
- **Output**: saves to your chosen folder (default Desktop), reveals in Finder, and copies the GIF to the clipboard.
- **Settings** (menu bar -> Settings…, or Cmd-,): output format (GIF / MP4 / GIF + MP4), frame rate, destination folder, show-cursor. Persisted via `UserDefaults`.
- Menu-bar app (no Dock icon).

## Requirements

- macOS 14 (Sonoma) or later.
- Apple Swift toolchain. **Xcode is not required** (CommandLineTools is enough): `xcode-select --install`.
- [gifski](https://gif.ski) for GIF export: `brew install gifski`. It is copied into the app bundle at build time.

## Build and run

```bash
brew install gifski          # one time, for GIF export
./build.sh                   # builds the SwiftPM executable into Sniploop.app
open Sniploop.app
```

On first run, grant **Screen Recording** when prompted (System Settings -> Privacy & Security -> Screen Recording), then relaunch once. ScreenCaptureKit only picks up the grant after an app restart.

### Stable code signing (so the Screen Recording grant survives rebuilds)

macOS ties the Screen Recording grant to the app's code signature. Ad-hoc signing mints a new identity every build, which invalidates the grant. `build.sh` therefore signs with a stable self-signed identity named **Sniploop Dev** if it exists, and falls back to ad-hoc otherwise.

Create the identity once (no Xcode needed):

```bash
cd /tmp
cat > sniploop-cert.cnf <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = Sniploop Dev
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout sniploop.key -out sniploop.crt -config sniploop-cert.cnf
security import sniploop.key -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -A
security import sniploop.crt -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -A
rm -f sniploop.key sniploop.crt sniploop-cert.cnf
```

It reports `CSSMERR_TP_NOT_TRUSTED` (expected for self-signed); codesign still uses it, and TCC keys on the stable designated requirement, so the grant persists across rebuilds. Real distribution to others will use Developer ID + notarization instead (see Roadmap / M4).

## Architecture

The design is what makes the app testable: all real logic lives in a pure library, and the GUI/system code is a thin shell over it.

- **`Sources/SniploopCore/`**: pure, dependency-free, fully unit-tested logic:
  - `CaptureGeometry` (selection rect -> ScreenCaptureKit sourceRect + output pixel size)
  - `EditSpec` (trim/crop/scale/fps model + output-size math)
  - `FrameTiming` (fps sample times for frame extraction)
  - `GifskiCommand` (builds the gifski argument vector)
  - `OutputNaming` (timestamped filenames)
  - `OutputFormat` (GIF / MP4 / Both)
  - `URLTrigger` (parses `sniploop://` URLs)
  - `SelectionMachine` (the drag / confirm / quick-mode state machine)
  - `Settings` (+ `SettingsManager` with an injectable store)
- **`Sources/Sniploop/`**: AppKit / ScreenCaptureKit / AVFoundation glue (not unit-tested; verified by running the app):
  - `AppController` (orchestrates the whole flow), `MenuBarController`, `GlobalHotKey` (Carbon),
    `OverlayWindow`/`OverlayView` (selector), `RecordingBorder`, `RecordingControl`,
    `CaptureEngine` (SCStream -> AVAssetWriter), `Exporter` (gifski + AVFoundation),
    `Output` (save/reveal/clipboard), `SettingsWindowController`, `UserDefaultsSettingsStore`.

Data flow: `Trigger -> RegionSelector -> CaptureEngine (temp .mov) -> Exporter (EditSpec) -> Output`.

## Tests

This project does **not** use XCTest. XCTest and the `Testing` framework ship inside Xcode, which is not installed here, so tests are a small stdlib assertion harness run as an executable:

```bash
swift run SniploopCoreTests     # exit 0 = all green, non-zero = a failure printed
```

`Sources/SniploopCoreTests/TestHarness.swift` defines `T.ok` / `T.eq` / `T.close` / `T.finish`. Each `*Tests.swift` exposes a `run<Name>Tests()` function that `main.swift` calls. The core was built strictly red/green (write a failing check, see it fail, implement, see `ALL PASSED`).

## Roadmap

`docs/PRD.md` is the product spec, `docs/build-plan.md` is the phased plan, and `docs/superpowers/plans/` holds the detailed task plans. High level:

- **M0 to M2 (done, this codebase):** SwiftPM foundation, tested core, capture -> gifski GIF + MP4 -> save loop, plus settings (format/fps/destination), the persistent recording border, and keyboard stop/cancel.
- **M3, Editor (next):** trim in/out, in-editor fps and crop/resize, AVPlayer preview, a "what you see is what you export" pipeline, keyboard shortcuts + cheatsheet, choose-format-per-capture, estimated file size. The `Exporter` already accepts crop/scale via `EditSpec`; M3 fills in the crop path and the editor UI.
- **M4, Polish + distribution:** rebindable-hotkey UI, multi-display capture, last-region recall, launch-at-login, Developer ID signing + notarization, and a public-release README. A `sniploop.app` landing page is post-v1.
- **Backlog:** annotations, WebP/APNG, capture history, system audio/webcam.

Known current simplifications: exports use an identity `EditSpec` (full clip, source size, fps from Settings) since the editor is M3; capture is single-display (the display the drag starts on).

## License

Sniploop is licensed under **GPL-3.0** (see `LICENSE`). It bundles the gifski binary, which is licensed AGPL-3.0; gifski is invoked as a separate executable and its source is at https://github.com/ImageOptim/gifski.
