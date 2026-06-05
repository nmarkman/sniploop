# gifcap Build Plan

Phased plan to take gifcap from validated POC to a daily-driver v1. Each phase ends in something runnable and testable, so the build never goes dark for long. Reference: `docs/PRD.md`.

## Phase 0: Project scaffold

Promote the single-file POC into a maintainable structure without changing behavior yet.

- Convert to a Swift Package executable target (or lightweight Xcode project), one file per component: `App`, `Hotkey`, `RegionSelector`, `CaptureEngine`, `Editor`, `Exporter`, `Output`, `Settings`.
- Move the POC's overlay and capture code into `RegionSelector` and `CaptureEngine` as-is.
- Update `build.sh` to build the package, assemble the `.app`, write `Info.plist`, and ad-hoc sign. Keep a `Resources/` slot for the encoder binary (empty for now).
- **Deliverable:** the existing POC behavior, building from the new structure.
- **Verify:** hotkeyless launch still does drag to GIF (the POC loop) from the new layout.

## Phase 1: Menu-bar shell + global hotkey

- Add `NSStatusItem` menu bar item: New Capture, Settings (stub), Quit.
- Integrate the KeyboardShortcuts package; register a default Shift-Cmd-6 to trigger New Capture. Confirm it works with **no Accessibility permission** (Carbon hotkey).
- App becomes resident (does not quit after one capture).
- **Deliverable:** press the hotkey from anywhere, get the selector; app lives in the menu bar.
- **Verify:** hotkey fires across spaces/apps; menu items work; no Accessibility prompt appears.

## Phase 2: Capture-to-disk core (the pivotal change)

Replace the POC's in-memory CGImage buffer with a disk-backed video master.

- `CaptureEngine`: SCStream sample buffers appended to an `AVAssetWriter` (H.264, 30 fps source) writing a temp `.mov`. Handle SCK idle frames via presentation timestamps so static stretches stay in sync.
- Floating recording control: elapsed timer, Stop, Cancel. Stop finalizes the writer and returns the temp URL; Cancel discards.
- Position the control clear of the captured region.
- For this phase, on Stop just save the raw `.mov` to the output folder and reveal it (editor/export come next).
- **Deliverable:** hotkey to a saved screen-region MP4, unbounded duration, flat memory.
- **Verify:** record 60+ seconds, confirm memory stays flat and the file plays back with the correct region/scale on Retina and on a second display.

## Phase 3: Export pipeline (GIF + MP4)

- `Exporter` with one interface: `(sourceURL, EditSpec) -> outputURL`. For this phase `EditSpec` is identity (no edits yet).
- **MP4 path:** AVFoundation export of the master.
- **GIF path:** `AVAssetImageGenerator` frames at a fixed fps, piped to the bundled encoder.
  - Bundle the encoder binary (gifski primary) in `Resources/`, invoke as a child process, confirm it runs from inside the signed bundle.
- `Output`: save to configured folder, reveal in Finder, and **Copy GIF to clipboard**.
- **Deliverable:** Stop produces a real GIF and an MP4 on demand; clipboard copy works.
- **Verify:** GIF is visibly cleaner and at least ~40 percent smaller than the POC/system-encoder output for the same clip. Paste-test the clipboard GIF into Slack, Notion, Gmail, Jira and record what works (open decision 10.2 in the PRD).

## Phase 4: Editor

- Editor window (SwiftUI + `AVPlayer`) opens on Stop with the master loaded, looping.
- **Trim:** timeline with in/out handles; preview respects the trim.
- **Frame rate:** 10 / 15 / 24 / 30 selector.
- **Crop / resize:** adjustable crop rectangle over a frame, plus output max-width presets (480 / 640 / 800 / original), aspect preserved.
- Build the `AVMutableComposition` / `AVVideoComposition` from the `EditSpec` and feed it to BOTH exports, so preview equals output.
- Best-effort estimated output size.
- Export bar: Copy GIF, Save GIF, Save MP4; remember last action as default.
- **Deliverable:** full capture to edit to export loop.
- **Verify:** trimmed/cropped/fps-reduced exports match the preview exactly for both GIF and MP4.

## Phase 5: Polish, settings, packaging

- Settings window (SwiftUI): hotkey binding, default folder, default export action, default fps, default max width, show-cursor toggle, launch-at-login, Screen Recording permission status + deep link.
- Last-region recall (re-use without re-dragging).
- Permission UX: clear first-run explanation and recovery, no crashes.
- Packaging: finalize `build.sh` to embed and sign the encoder binary; add a documented, flag-gated path to Developer ID + notarization (hardened runtime, `notarytool`) for later sharing.
- Optional stretch: "Recent captures" menu.
- **Deliverable:** v1 Nick would use daily and could hand to someone else with a later notarization flip.
- **Verify:** fresh-machine-style run (or after resetting TCC) walks cleanly through permission, capture, edit, export.

## Sequencing notes

- Phases 0 to 2 are the riskiest plumbing; everything visible depends on the disk-backed capture in Phase 2, so it comes before the editor.
- Phase 3 ships value even without the editor (you already get clean GIFs), so it precedes Phase 4.
- The `EditSpec` interface introduced in Phase 3 (as identity) is what Phase 4 fills in, so the exporter never gets rewritten.

## Out of scope for this plan

Everything in PRD section 12 (annotations, WebP/APNG, history/library, audio/webcam, scheduling, sharing/upload, presets, in-app updates).
