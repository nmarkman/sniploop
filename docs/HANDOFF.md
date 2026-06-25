# Sniploop Handoff

Start-here doc for a fresh agent (or human) picking up Sniploop with no prior context. Read this first, then `README.md`, then the docs linked below.

## TL;DR

Sniploop is a native macOS region GIF recorder: hotkey, drag an area, it records that region in the background, exports a high-quality GIF (or MP4). The **v1 foundation (milestones M0 to M2) is complete, working, and committed.** The next milestone is the **in-app editor (M3)**: trim / crop / fps with a live preview. Nothing is half-finished or broken; this is a clean stopping point.

## Current state (verified)

- **Local repo:** `~/Desktop/Sniploop`
- **GitHub:** https://github.com/nmarkman/sniploop (public, personal account `nmarkman`, GPL-3.0, default branch `main`)
- **Branch:** all foundation work is on `sniploop-foundation`. `main` sits at the pre-implementation docs.
- **PR:** [#1](https://github.com/nmarkman/sniploop/pull/1) (`sniploop-foundation` -> `main`) is **OPEN and not yet merged**. Merging it is the intended way to land the foundation. It is mergeable with no conflicts.
- **Tests:** `swift run SniploopCoreTests` -> `ALL PASSED (47 checks)`.
- **Build:** `swift build` and `./build.sh` both succeed. The app runs and the full capture loop works.

## Get oriented (read in this order)

1. `README.md`: what works, requirements, build/run, dev signing setup, test harness, architecture, roadmap.
2. `docs/PRD.md`: product spec; the top "Implementation Status" section lists done vs remaining.
3. `docs/build-plan.md`: phased roadmap; the top "Status" banner says which phases are done.
4. `docs/superpowers/plans/2026-06-05-sniploop-foundation.md`: the detailed, task-by-task plan that built M0 to M2 (marked COMPLETED, with the deviations noted).

## Build, test, run

```bash
brew install gifski                 # required for GIF export; build.sh embeds it into the app
swift run SniploopCoreTests         # run the core tests (exit 0 = green)
./build.sh                          # build + assemble + sign Sniploop.app
open Sniploop.app
```

On first run, grant Screen Recording (System Settings -> Privacy & Security -> Screen Recording) and relaunch once.

## Architecture in one screen

- `Sources/SniploopCore/`: pure, dependency-free, fully unit-tested logic (geometry, `EditSpec`, frame timing, gifski argv, output naming, `OutputFormat`, URL parsing, `SelectionMachine`, `Settings`).
- `Sources/Sniploop/`: thin AppKit / ScreenCaptureKit / AVFoundation glue (not unit-tested; verified by running the app). `AppController` orchestrates everything.
- Data flow: `Trigger -> RegionSelector -> CaptureEngine (temp .mov) -> Exporter (EditSpec) -> Output`.

## NON-OBVIOUS THINGS YOU MUST KNOW (landmines)

1. **This machine has CommandLineTools, NOT Xcode.** Two consequences are baked into the design:
   - Tests are a **stdlib assertion harness**, not XCTest (XCTest/`Testing` ship with Xcode). Run with `swift run SniploopCoreTests`. Do not "fix" this back to XCTest unless Xcode gets installed. To add a test: write a `run<Name>Tests()` function using `T.ok`/`T.eq`/`T.close`, and add a call to it in `Sources/SniploopCoreTests/main.swift`.
   - The global hotkey is a **direct Carbon `RegisterEventHotKey`** (`GlobalHotKey.swift`), not the KeyboardShortcuts package (its `#Preview` macro needs Xcode). Sniploop is intentionally **zero-dependency**.
2. **Code signing matters for the Screen Recording grant.** `build.sh` signs with a stable self-signed identity named **`Sniploop Dev`** so the grant survives rebuilds (ad-hoc signing would invalidate it every build). If that identity is missing from the keychain, `build.sh` falls back to ad-hoc and the grant will keep breaking. The README has the one-time command to recreate the identity.
3. **Carbon hotkey dispatch is subtle.** Every `GlobalHotKey` installs a handler on the shared app event target. Each must (a) carry a unique `EventHotKeyID` and (b) return `eventNotHandledErr` when the fired id is not its own, so Carbon keeps dispatching to the other handlers. Getting this wrong caused stop/cancel to cross-fire and discard files. The current `GlobalHotKey.swift` is correct; preserve that pattern if you touch it.
4. **Exports currently use an identity `EditSpec`** (`AppController.handleMaster`): full clip, source size, fps from Settings, no trim/crop. `EditSpec` and `Exporter` already have `cropPixels` / `maxWidth` fields and the GIF/MP4 paths; the editor (M3) just needs to populate a non-identity `EditSpec` and the `Exporter` needs its crop path filled in.
5. **Single-display capture only.** The overlay/capture target the display where the drag starts. Multi-display is M4.
6. **Default output format is GIF** (changed from "always both GIF and MP4"). Configurable in Settings (`OutputFormat`: gif / mp4 / both), persisted via `UserDefaults`.

## What is done (M0 to M2 + post-plan additions)

Global Carbon hotkey (Hyper+G) and `sniploop://capture` URL trigger; region selector with glow, confirm-to-record, Shift quick-mode, re-drag, high-contrast HUD chips; persistent recording border (drawn outside the captured area); ScreenCaptureKit capture to a temp `.mov`; gifski GIF + AVFoundation MP4 export; Settings-driven default output format; save/reveal/clipboard; Settings window (format, fps, destination, show-cursor); keyboard stop/cancel during recording (Return stops + exports, Escape cancels); stable dev signing.

## What is next

**M3: in-app editor (recommended next milestone).** Open an editor window on Stop with the recorded clip loaded (AVPlayer). Add: trim in/out, in-editor fps, crop/resize, a live preview where what you see equals what you export, keyboard shortcuts + a cheatsheet, a choose-format-per-capture export bar, and an estimated output size. The wiring is ready: `Exporter.exportGIF/exportMP4` already take an `EditSpec` with `cropPixels` and `maxWidth`; fill the crop path in `exportGIF` and build the editor UI. This deserves its own plan (use the brainstorming -> writing-plans -> subagent-driven flow, same as the foundation).

**Remaining M4: polish + distribution.** Rebindable-hotkey UI, multi-display capture, last-region recall (the captured rect is already stashed in `AppController.lastSelection`), launch-at-login, Developer ID signing + notarization for sharing, and a public-release README pass. A `sniploop.app` landing page is post-v1 (domain is owned).

**Backlog:** annotations, WebP/APNG, capture history, system audio / webcam.

## Open items / decisions left to the owner

- **PR #1 is not merged.** Decide whether to merge `sniploop-foundation` into `main` (and delete the branch) before starting M3, or keep stacking.
- Real distribution to others still needs Developer ID + notarization (M4); the current self-signed identity is local-dev only.

## Suggested first action for the next session

Merge PR #1 to make `main` the working baseline, then brainstorm + write a plan for M3 (the editor). If you would rather keep iterating on feel first, the app is fully usable as-is.
