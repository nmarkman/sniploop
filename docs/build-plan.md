# Sniploop Build Plan

Phased plan to take Sniploop from validated POC to a daily-driver v1. Each phase ends in something runnable and testable, so the build never goes dark for long. Reference: `docs/PRD.md`.

## Phase 0: Project scaffold

Promote the single-file POC into a maintainable structure without changing behavior yet.

- Convert to a Swift Package executable target (or lightweight Xcode project), one file per component: `App`, `Hotkey`, `RegionSelector`, `CaptureEngine`, `Editor`, `Exporter`, `Output`, `Settings`.
- Move the POC's overlay and capture code into `RegionSelector` and `CaptureEngine` as-is.
- Update `build.sh` to build the package, assemble the `.app`, write `Info.plist`, and ad-hoc sign. Keep a `Resources/` slot for the encoder binary (empty for now).
- **Deliverable:** the existing POC behavior, building from the new structure.
- **Verify:** hotkeyless launch still does drag to GIF (the POC loop) from the new layout.

## Phase 1: Menu-bar shell + triggers (hotkey + URL scheme)

- Add `NSStatusItem` menu bar item: New Capture, Settings (stub), Quit.
- Integrate the KeyboardShortcuts package; register a default Hyper-chord hotkey to trigger New Capture. Confirm the picker accepts multi-modifier Hyper chords (Caps-Lock-as-Hyper bindings work as a normal chord) and that it works with **no Accessibility permission** (Carbon hotkey).
- Register the `sniploop://capture` URL scheme (`CFBundleURLTypes` in `Info.plist`) and handle it so Raycast / Shortcuts / Automator can trigger a capture.
- App becomes resident (does not quit after one capture).
- **Deliverable:** trigger the selector from the hotkey AND from `open sniploop://capture`; app lives in the menu bar.
- **Verify:** hotkey fires across spaces/apps; the URL trigger works from Terminal and Raycast; menu items work; no Accessibility prompt appears.

## Phase 2: Capture-to-disk core (the pivotal change)

Replace the POC's in-memory CGImage buffer with a disk-backed video master.

- `CaptureEngine`: SCStream sample buffers appended to an `AVAssetWriter` (H.264, 30 fps source) writing a temp `.mov`. Handle SCK idle frames via presentation timestamps so static stretches stay in sync.
- **Selector UX upgrade:** add a glow/highlight around the selection box; make it confirm-to-record by default (box persists on release; re-drag to redraw, drag to move/resize, Enter or click Record to start), with a held-Shift quick mode that records instantly on release.
- Floating recording control: elapsed timer, Stop, Cancel. Stop finalizes the writer and returns the temp URL; Cancel discards.
- Position the control clear of the captured region (and keep the selection glow out of the recorded frame).
- For this phase, on Stop just save the raw `.mov` to the output folder and reveal it (editor/export come next).
- **Deliverable:** hotkey to a saved screen-region MP4, unbounded duration, flat memory, with the confirm/quick-mode selector.
- **Verify:** record 60+ seconds, confirm memory stays flat and the file plays back with the correct region/scale on Retina and on a second display; confirm re-drag, move/resize, and Shift quick mode all behave; confirm no glow appears in the output.

## Phase 3: Export pipeline (GIF + MP4)

- `Exporter` with one interface: `(masterURL, EditSpec) -> outputURL`. For this phase `EditSpec` is identity (no edits yet).
- Bundle the **gifski** binary in `Resources/`, invoke as a child process, confirm it runs from inside the signed bundle.
- **GIF path:** extract frames at the chosen output fps via `AVAssetImageGenerator`, pipe to gifski; delete temp frames after encode.
- **MP4 path:** native AVFoundation (`AVAssetExportSession`, H.264).
- `Output`: save to configured folder, reveal in Finder, and **Copy GIF to clipboard**.
- **Deliverable:** Stop produces a real GIF and an MP4 on demand; clipboard copy works.
- **Verify:** GIF is visibly cleaner and at least ~40 percent smaller than the POC/system-encoder output for the same clip. Paste-test the clipboard GIF into Slack, Notion, Gmail, Jira and record what works (open decision 1 in the PRD).

## Phase 4: Editor

- Editor window (SwiftUI + `AVPlayer`) opens on Stop with the master loaded, looping.
- **Trim:** timeline with in/out handles; preview respects the trim.
- **Frame rate:** 10 / 15 / 24 / 30 selector.
- **Crop / resize:** adjustable crop rectangle over a frame, plus output max-width presets (480 / 640 / 800 / original), aspect preserved.
- Build the `AVMutableComposition` / `AVVideoComposition` from the `EditSpec` for live preview; the same `EditSpec` drives the exporter (gifski for GIF, AVFoundation for MP4), so preview matches output.
- Best-effort estimated output size.
- Export bar: Copy GIF, Save GIF, Save MP4; remember last action as default.
- **Keyboard shortcuts** on all primary actions (play/pause, set in/out, change fps, Copy GIF, Save GIF, Save MP4) plus an in-app **cheatsheet** (press `?`).
- **Deliverable:** full capture to edit to export loop, keyboard-driven.
- **Verify:** trimmed/cropped/fps-reduced exports match the preview for both GIF and MP4; every primary action has a working shortcut and appears in the cheatsheet.

## Phase 5: Polish, settings, distribution

- Settings window (SwiftUI): hotkey binding (Hyper chords), **default destination folder**, default export action, default fps, default max width, **quick-mode modifier**, show-cursor toggle, launch-at-login, Screen Recording permission status + deep link.
- Last-region recall (re-use without re-dragging).
- Permission UX: clear first-run explanation and recovery, no crashes.
- Packaging: finalize `build.sh` to embed and sign the gifski binary; add a documented, flag-gated path to Developer ID + notarization (hardened runtime, `notarytool`, including the embedded gifski) for sharing.
- Distribution: add a `LICENSE` (GPL-3.0) plus gifski's AGPL notice + source link, and a `README` with macOS install instructions; prep the public GitHub repo. (sniploop.app landing page is post-v1.)
- Optional stretch: "Recent captures" menu.
- **Deliverable:** v1 Nick would use daily and a coworker could install from the repo with a later notarization flip.
- **Verify:** fresh-machine-style run (or after resetting TCC) walks cleanly through permission, capture, edit, export, following only the README.

## Sequencing notes

- Phases 0 to 2 are the riskiest plumbing; everything visible depends on the disk-backed capture in Phase 2, so it comes before the editor.
- Phase 3 ships value even without the editor (you already get clean GIFs), so it precedes Phase 4.
- The `EditSpec` interface introduced in Phase 3 (as identity) is what Phase 4 fills in, so the exporter never gets rewritten.

## Out of scope for this plan

Everything in PRD section 12 (annotations, WebP/APNG, history/library, audio/webcam, scheduling, sharing/upload, presets, in-app updates).
