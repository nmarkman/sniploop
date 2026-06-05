# Sniploop PRD

Working name: **Sniploop**. A fast, native macOS region GIF recorder. Status: POC validated, building v1.

## 1. Summary

Sniploop lets you press a hotkey, drag a rectangle anywhere on screen, record what happens in that region in the background, then trim and export it as a high-quality GIF or MP4. The target feeling is the macOS screenshot tool (Cmd-Shift-4), but for short animations instead of stills.

## 2. Problem and motivation

Capturing a quick GIF on a Mac today means reaching for Giphy Capture, which feels dated and slow, or heavier tools (Kap, CleanShot) that carry more UI than the job needs. There is no equivalent of the instant, muscle-memory region selector that the built-in screenshot tool provides. The job to be done: *"show someone a 5-second interaction without recording my whole screen or fiddling with an app."*

This is a personal daily-driver tool first. It should be fast enough that reaching for it never feels like a decision.

## 3. Goals and success criteria

- **Speed to capture:** hotkey to recording in under one second, with zero clicks beyond the drag.
- **No-friction stop:** a single obvious control stops recording. No hunting.
- **Quality output:** GIFs that look clean and are meaningfully smaller than the system encoder produces.
- **Useful editor:** trim dead frames, adjust crop, and pick frame rate before export, in a window that opens instantly.
- **Reliability:** captures the right region at the right scale on Retina and across multiple displays, every time.
- **It earns daily use:** the bar for success is Nick replacing Giphy Capture entirely.

## 4. Non-goals (v1)

- Annotations (arrows, text, highlights). Deferred to backlog.
- WebP / APNG export. GIF and MP4 only.
- Audio capture, webcam bubble, scheduled/timed capture.
- Cloud upload, share links, or any account/login.
- Capture history/library browser (a lightweight "recent" menu is a stretch goal, not a requirement).
- Windows/cross-platform. macOS only.

## 5. Primary user and use cases

Single primary user (Nick), power user, comfortable granting permissions. Representative captures:

- A UI interaction in a web app to drop into Slack or a Jira ticket.
- A short product behavior to paste into a doc or send a teammate.
- A bug repro to attach to a ticket.

Common thread: small region, a few seconds, shared immediately into another tool.

## 6. Happy-path flow

1. Press the global hotkey (default proposal: Shift-Cmd-6, rebindable).
2. Screen dims with a crosshair across all displays. Drag a rectangle. (Last region is remembered and can be re-used.)
3. On mouse-up the overlay disappears and recording starts immediately. A compact floating control shows elapsed time, a Stop button, and a Cancel.
4. Do the thing. Click Stop (or press Return; Esc cancels and discards).
5. The editor window opens with the clip loaded: scrub, set trim in/out, optionally tweak crop and frame rate and output width.
6. Choose export: **Copy GIF to clipboard**, **Save GIF**, or **Save MP4**. Default action is one click.
7. File lands in the configured folder (default Desktop) and is revealed in Finder; clipboard option puts it straight on the pasteboard for immediate paste.

## 7. Functional requirements (v1)

### 7.1 Menu-bar app and hotkey
- Resident menu-bar app (`LSUIElement`, no Dock icon). Menu bar item with: New Capture, Settings, Quit, and (stretch) Recent captures.
- Global hotkey to trigger capture, rebindable in Settings.
- **No Accessibility permission required.** Use a Carbon `RegisterEventHotKey`-based hotkey (via the KeyboardShortcuts package), which is global without the Accessibility grant that `NSEvent` global monitors need.
- Optional launch-at-login.

### 7.2 Region selector
- Dim overlay with crosshair across **all connected displays**.
- Live dimension readout while dragging.
- See-through selection rectangle (as in the POC).
- Remember and offer the last-used region (re-use without re-dragging).
- Esc cancels.
- (Stretch) After drawing, allow drag-to-move and edge handles to fine-tune before confirming.

### 7.3 Capture engine
- Record the selected region via ScreenCaptureKit.
- **Stream straight to a temp video file** (`AVAssetWriter`, H.264, in the system temp dir) rather than buffering frames in memory. This is the source of truth for both exports and removes any duration cap.
- Capture frame rate target 30 fps source (output fps chosen later in the editor).
- Cursor visible in capture (toggle in Settings, default on).
- Floating recording control: elapsed timer, Stop, Cancel. Positioned clear of the captured region so it never appears in the output.

### 7.4 Editor
Opens with the temp clip loaded. `AVPlayer` preview plus a timeline.
- **Trim:** set in/out points by dragging timeline handles; preview reflects the trim.
- **Frame rate:** choose output fps (10 / 15 / 24 / 30), with a hint of the resulting size/smoothness tradeoff.
- **Crop / resize:** adjust the crop rectangle over a representative frame, and set an output max width (e.g. 480 / 640 / 800 / original) to control file size. Aspect ratio preserved by default.
- Loop preview playback.
- Show estimated output file size before export (best-effort).

### 7.5 Export
- **GIF:** high quality via a bundled encoder (see 9.4). Two-step internally: render the trimmed/cropped/scaled clip, then encode to GIF.
- **MP4:** H.264 export of the trimmed/cropped/scaled clip via AVFoundation.
- Actions: Copy GIF to clipboard, Save GIF, Save MP4. Remember last-used action as the default.
- Output naming `Capture-<timestamp>.<ext>`; configurable destination folder (default Desktop); reveal in Finder on save.

### 7.6 Settings
Hotkey binding, default output folder, default export action, default/last fps, default max width, show-cursor toggle, launch-at-login, and a Screen Recording permission status row with a button to open the relevant System Settings pane.

### 7.7 Permissions and first run
- Requires Screen Recording. Detect missing permission, explain it plainly, and deep-link to System Settings. Recover gracefully (no crash, clear retry path).
- No Accessibility, Camera, or Microphone permissions in v1.

## 8. Quality bar and performance targets

- Hotkey to crosshair: visually immediate (< ~250 ms).
- Mouse-up to recording active: < ~500 ms.
- A 5-second, 600x400 capture at 15 fps exports to GIF in a couple seconds and lands well under the file sizes the system encoder produces for the same clip (target: at least ~40 percent smaller at equal or better visual quality).
- Correct region and scale on Retina and on a secondary display.
- No frames of the recording control or overlay in the output.

## 9. Technical architecture

### 9.1 Components and data flow
```
Hotkey (Carbon)  ->  RegionSelector (overlay per display)  ->  selected rect
       -> CaptureEngine (SCStream -> AVAssetWriter -> temp .mov)
       -> Editor (AVPlayer + AVMutableComposition: trim/crop/scale/fps)
       -> Exporter
            ├─ MP4: AVAssetExportSession over the composition
            └─ GIF: AVAssetImageGenerator frames -> bundled encoder -> .gif
       -> Output (save to folder / reveal / copy to clipboard)
```
Each unit has one job and a narrow interface: the selector returns a rect + target display; the capture engine returns a temp file URL; the editor returns an edit spec (in/out, crop, scale, fps); the exporter consumes an edit spec + source URL and produces a file URL.

### 9.2 Capture pipeline
SCStream delivers sample buffers on a background queue, appended to an `AVAssetWriter` input (H.264, 30 fps source). Writing to disk keeps memory flat regardless of duration and yields an MP4-quality master that both exports derive from.

### 9.3 Editor pipeline
Build an `AVMutableComposition` / `AVVideoComposition` from the master applying trim (time range), crop (transform/region), and scale. The same composition feeds both the MP4 export and the GIF frame extraction, so what you preview is what you export.

### 9.4 Encoders
- **MP4 and all trim/crop/scale: native AVFoundation.** No third-party binary.
- **GIF: one bundled binary.** Extract frames from the edited composition at the chosen fps via `AVAssetImageGenerator`, then encode to GIF.
  - Primary candidate: **gifski** (excellent perceptual quality, small files). Licensing caveat: gifski is AGPL-3.0 (or commercial). Fine for personal/local use and for an open-source build; a concern if a closed binary is later distributed to others. See open decision 10.1.
  - Alternative: **ffmpeg** `palettegen`/`paletteuse` (two-pass, `dither=sierra2_4a`). Near-gifski quality, and an LGPL ffmpeg build avoids the AGPL question. Heavier binary but also could replace AVFoundation for MP4/scale if we ever want one tool.
- Bundled binary lives in `Contents/Resources` and is invoked as a child process. It must be signed and (for later notarization) built with the hardened runtime.

### 9.5 Project structure and build
- Promote from the single-file POC to a small Swift Package (executable target) or lightweight Xcode project, organized by the components in 9.1 (one file per unit).
- A build script assembles the `.app`, embeds the encoder binary, writes `Info.plist`, and signs.
- SwiftUI for Settings and Editor windows; AppKit for the overlay and floating control (they need precise window/level control SwiftUI does not give cleanly).

### 9.6 Signing and distribution
- **Now:** ad-hoc signing, local install. Re-grant permissions if identity changes between builds.
- **Later (shareable):** Developer ID signing + notarization (`codesign --options runtime`, `notarytool`), including the embedded encoder binary. Structure the build script so this is a flag flip, not a refactor. Requires an Apple Developer account ($99/yr) when the time comes.

## 10. Open decisions and risks

1. **GIF encoder licensing (gifski AGPL vs ffmpeg LGPL).** Lean gifski for v1 quality since use is local; revisit before distributing to others. Low effort to swap because the exporter isolates this behind one interface.
2. **Clipboard GIF fidelity.** macOS clipboard handling of animated GIFs is inconsistent across destination apps; some paste a static frame. Validate against Slack, Notion, Gmail, Jira early and document what works; fall back to "save then drag" if a target app misbehaves.
3. **Multi-display capture.** Overlay spans all displays, but a single capture is one region on one display in v1. A selection dragged across the seam between displays is out of scope (clamp to the display where the drag started).
4. **ScreenCaptureKit idle frames.** SCK only emits frames on change. Writing to AVAssetWriter needs sane timestamps so static stretches do not desync; handle via presentation timestamps from the sample buffers.
5. **Large-region performance.** Full-display-sized regions at 30 fps are heavier; the disk-writing pipeline mitigates memory, but encode time and file size grow. Output max-width default helps.
6. **Hotkey conflicts.** Default Shift-Cmd-6 may collide with user macros; rebindable from first run.

## 11. Milestones

Detailed phasing in `docs/build-plan.md`. High level:

- **M1 Capture-to-disk core:** menu bar + hotkey, multi-display overlay, SCK-to-AVAssetWriter, floating control, save raw MP4. (Replaces the POC's in-memory path.)
- **M2 Export pipeline:** GIF via bundled encoder + MP4 export, output handling and clipboard.
- **M3 Editor:** trim, fps, crop/resize, size estimate, what-you-see-is-what-you-export.
- **M4 Polish and settings:** Settings window, launch-at-login, last-region recall, permission UX, packaging/sign script with a notarization-ready path.

## 12. Backlog (post-v1)

Annotations; WebP/APNG; capture history/library; system-audio and webcam; timed/scheduled capture; share/upload; export presets; in-app updates; drag-out-to-app from the editor.
