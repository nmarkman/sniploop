# Sniploop PRD

Working name: **Sniploop**. A fast, native macOS region GIF recorder. Status: POC validated, building v1.

## 1. Summary

Sniploop lets you press a hotkey, drag a rectangle anywhere on screen, record what happens in that region in the background, then trim and export it as a high-quality GIF or MP4. The target feeling is the macOS screenshot tool (Cmd-Shift-4), but for short animations instead of stills.

## 2. Problem and motivation

Capturing a quick GIF on a Mac today means reaching for Giphy Capture, which feels dated and slow, or heavier tools (Kap, CleanShot) that carry more UI than the job needs. There is no equivalent of the instant, muscle-memory region selector that the built-in screenshot tool provides. The job to be done: *"show someone a 5-second interaction without recording my whole screen or fiddling with an app."*

This is a personal daily-driver tool first, but it is built to share: v1 ships from a public GitHub repo so coworkers can install it, with a landing page at sniploop.app later. It should be fast enough that reaching for it never feels like a decision.

## 3. Goals and success criteria

- **Speed to capture:** from hotkey to recording in about a second. A held-modifier quick mode records the instant you release the drag; the default flow adds a single confirm keystroke so you can nail the region.
- **No-friction stop:** a single obvious control stops recording. No hunting.
- **Quality output:** GIFs that look clean and are meaningfully smaller than the system encoder produces.
- **Useful editor:** trim dead frames, adjust crop, and pick frame rate before export, in a window that opens instantly, with keyboard shortcuts on every primary action.
- **Reliability:** captures the right region at the right scale on Retina and across multiple displays, every time.
- **It earns daily use:** the bar for success is Nick replacing Giphy Capture entirely, and a coworker installing it from the repo without help.

## 4. Non-goals (v1)

- Annotations (arrows, text, highlights). Deferred to backlog.
- WebP / APNG export. GIF and MP4 only.
- Audio capture, webcam bubble, scheduled/timed capture.
- Cloud upload, share links, or any account/login.
- A hosted web/landing page at sniploop.app. Planned, but post-v1; v1 distributes via the GitHub repo.
- Capture history/library browser (a lightweight "recent" menu is a stretch goal, not a requirement).
- Windows/cross-platform. macOS only.

## 5. Users and use cases

Primary user is Nick (power user, comfortable granting permissions). Secondary audience is coworkers who install from the public repo. Representative captures:

- A UI interaction in a web app to drop into Slack or a Jira ticket.
- A short product behavior to paste into a doc or send a teammate.
- A bug repro to attach to a ticket.

Common thread: small region, a few seconds, shared immediately into another tool.

## 6. Happy-path flow

1. Trigger a capture: press the global hotkey (default proposal: a Hyper chord such as Caps-Lock-as-Hyper + G, rebindable), or fire it from Raycast / Shortcuts / Automator via the `sniploop://capture` URL.
2. Screen dims with a crosshair across all displays. Drag a rectangle.
3. On release, the selection stays as a glowing box. Re-drag to draw a fresh one, or drag the box / its edges to fine-tune, then press Enter (or click Record) to start. **Holding Shift as you release skips the confirm and records instantly.** (Last region is remembered and can be re-used.)
4. Recording runs in the background with a compact floating control: elapsed time, Stop, Cancel. Click Stop (or press Return); Esc cancels and discards.
5. The editor opens with the clip loaded: scrub, set trim in/out, optionally tweak crop, frame rate, and output width. Primary actions have keyboard shortcuts, discoverable via an in-app cheatsheet (press `?`).
6. Export: **Copy GIF to clipboard**, **Save GIF**, or **Save MP4**, each with a shortcut. The default action is one key or click.
7. File lands in your configured destination folder (default Desktop) and is revealed in Finder; the clipboard option puts it straight on the pasteboard for immediate paste.

## 7. Functional requirements (v1)

### 7.1 Menu-bar app, hotkey, and triggers
- Resident menu-bar app (`LSUIElement`, no Dock icon). Menu bar item with: New Capture, Settings, Quit, and (stretch) Recent captures.
- Global hotkey to trigger capture, rebindable in Settings. The picker accepts multi-modifier Hyper chords, so a Caps-Lock-as-Hyper binding (set up via Raycast or Karabiner) works as an ordinary chord.
- **URL scheme `sniploop://capture`** so Raycast, Shortcuts, Automator, or any launcher can trigger a capture without using the in-app hotkey.
- **No Accessibility permission required.** Use a Carbon `RegisterEventHotKey`-based hotkey (implemented directly, no third-party dependency), which is global without the Accessibility grant that `NSEvent` global monitors need.
- Optional launch-at-login.

### 7.2 Region selector
- Dim overlay with crosshair across **all connected displays**.
- Live dimension readout while dragging.
- See-through selection rectangle with a subtle **glow/highlight** around the boundary so the captured area is unmistakable.
- **Confirm-to-record by default:** on release the glowing box persists. Re-drag anywhere to draw a new box, drag the box to move it, or drag its edges/handles to resize, then press Enter (or click Record) to start.
- **Quick mode:** holding a modifier (proposed: Shift) on release records instantly, skipping the confirm.
- Remember and offer the last-used region (re-use without re-dragging).
- Esc cancels.

### 7.3 Capture engine
- Record the selected region via ScreenCaptureKit.
- **Stream straight to a temp video file** (`AVAssetWriter`, H.264, in the system temp dir) rather than buffering frames in memory. This is the source of truth (the "master") for both exports and removes any duration cap.
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
- **Keyboard shortcuts on all primary actions** (play/pause, set in/out, change fps, Copy GIF, Save GIF, Save MP4), plus an in-app **shortcut cheatsheet** (press `?`) so the shortcuts are discoverable.

### 7.5 Export
- **GIF:** high quality via the bundled gifski engine (see 9.4). Driven by the editor's EditSpec (trim/crop/scale/fps).
- **MP4:** H.264 via native AVFoundation, from the same EditSpec, so it matches the GIF and the preview.
- Actions: Copy GIF to clipboard, Save GIF, Save MP4, each with a keyboard shortcut. Remember last-used action as the default.
- Output naming `Capture-<timestamp>.<ext>`; destination folder from Settings (default Desktop); reveal in Finder on save.

### 7.6 Settings
- Hotkey binding (accepts Hyper chords).
- **Default destination folder for saved files.**
- Default export action, default/last fps, default max width.
- Quick-mode modifier (the key that records instantly on release).
- Show-cursor toggle, launch-at-login.
- Screen Recording permission status row with a button to open the relevant System Settings pane.

### 7.7 Permissions and first run
- Requires Screen Recording. Detect missing permission, explain it plainly, and deep-link to System Settings. Recover gracefully (no crash, clear retry path).
- No Accessibility, Camera, or Microphone permissions in v1.

## 8. Quality bar and performance targets

- Hotkey to crosshair: visually immediate (< ~250 ms).
- Quick mode: modifier-release to recording active < ~500 ms. Confirm mode adds one keystroke, no extra latency.
- A 5-second, 600x400 capture at 15 fps exports to GIF in a couple seconds and lands well under the file sizes the system encoder produces for the same clip (target: at least ~40 percent smaller at equal or better visual quality).
- Correct region and scale on Retina and on a secondary display.
- No frames of the recording control, overlay, or selection glow in the output.

## 9. Technical architecture

### 9.1 Components and data flow
```
Trigger (hotkey / sniploop:// URL)
       -> RegionSelector (overlay per display; glow + confirm-or-quick-mode)  -> selected rect
       -> CaptureEngine (SCStream -> AVAssetWriter -> temp .mov master)
       -> Editor (AVPlayer + AVMutableComposition: trim/crop/scale/fps preview)
       -> Exporter (over the editor composition + EditSpec)
            ├─ GIF: AVAssetImageGenerator frames (at output fps) -> bundled gifski -> .gif
            └─ MP4: AVAssetExportSession (H.264)
       -> Output (save to destination / reveal in Finder / copy to clipboard)
```
Each unit has one job and a narrow interface: the selector returns a rect + target display; the capture engine returns the master file URL; the editor returns an EditSpec (in/out, crop, scale, fps); the exporter consumes an EditSpec + master URL and produces a file URL.

### 9.2 Capture pipeline
SCStream delivers sample buffers on a background queue, appended to an `AVAssetWriter` input (H.264, 30 fps source). Writing to disk keeps memory flat regardless of duration and yields an MP4-quality master that both exports derive from.

### 9.3 Editor pipeline
Build an `AVMutableComposition` / `AVVideoComposition` from the master to drive live preview of the EditSpec (trim time range, crop region, scale). The preview approximates the export; GIF palette/dither effects only appear in the exported file.

### 9.4 Export engine
- **GIF: bundled gifski**, the highest-quality GIF encoder available (libimagequant quantizer with animation-aware palette and dithering). Extract frames from the edited composition at the chosen output fps via `AVAssetImageGenerator`, pipe them to gifski, which writes the `.gif`. Cleaner gradients and smaller files than the system encoder or a single global-palette approach. Chosen for quality; the GPL/AGPL licensing is a non-issue for a free, open-source app (see 9.6).
- **MP4: native AVFoundation** (`AVAssetExportSession` over the same composition, H.264). No third-party binary needed for MP4.
- Both formats render from the same composition and EditSpec, so GIF and MP4 always match each other and the editor preview.
- gifski lives in `Contents/Resources`, invoked as a child process; signed, and built with the hardened runtime for later notarization. It is a separate program under its own AGPL-3.0 license (see 9.6).

### 9.5 Project structure and build
- Promote from the single-file POC to a small Swift Package (executable target) or lightweight Xcode project, organized by the components in 9.1 (one file per unit).
- A build script assembles the `.app`, embeds the gifski binary, writes `Info.plist`, registers the `sniploop://` URL scheme, and signs.
- Ship a `LICENSE` (GPL-3.0) and a `README` with macOS install instructions, including gifski's AGPL license text and a link to its source.
- SwiftUI for Settings and Editor windows; AppKit for the overlay and floating control (they need precise window/level control SwiftUI does not give cleanly).

### 9.6 Licensing and distribution
- **Project license: GPL-3.0.** Sniploop is free and open-source, so copyleft costs nothing here, and it lets us bundle gifski for the best GIF quality. (Sniploop is a desktop app, so AGPL's network-use clause is irrelevant; GPL-3.0 is the natural fit. Donations / a tip jar are fully compatible with GPL.)
- **gifski compliance:** gifski is invoked as a separate bundled binary under its own AGPL-3.0 license. We satisfy it by including gifski's license text and a link to its source, which the public repo does by default. The trade we accept: Sniploop cannot later become a closed-source paid product. That is not a goal.
- **v1 distribution:** public GitHub repository with a README walking a Mac user through download, granting Screen Recording, and optional launch-at-login.
- **Signing:** ad-hoc for the earliest local builds; **Developer ID + notarization** (`codesign --options runtime`, `notarytool`, including the embedded gifski) before sharing widely, so coworkers install without Gatekeeper warnings. Structured as a build-script flag, not a refactor. Requires an Apple Developer account ($99/yr) at that point.
- **Later (post-v1):** a landing/download page at **sniploop.app** (domain already registered) to promote and distribute the app.
- **Reversibility:** the exporter sits behind one interface, so swapping gifski for ffmpeg (and relicensing permissively) later is a contained change if plans ever shift toward a closed/commercial build.

## 10. Open decisions and risks

1. **Clipboard GIF fidelity.** macOS clipboard handling of animated GIFs is inconsistent across destination apps; some paste a static frame. Validate against Slack, Notion, Gmail, Jira early and document what works; fall back to "save then drag" if a target app misbehaves.
2. **Multi-display capture.** Overlay spans all displays, but a single capture is one region on one display in v1 (confirmed out of scope). A selection dragged across the seam between displays clamps to the display where the drag started.
3. **gifski frame extraction.** gifski encodes from extracted frames, so a long or large capture produces many temp frames. Mitigate by extracting at the chosen output fps (not the 30 fps source) and deleting temp frames after encode; the output max-width default also caps frame size. Watch peak disk/memory on long clips.
4. **ScreenCaptureKit idle frames.** SCK only emits frames on change. Writing to AVAssetWriter needs sane timestamps so static stretches do not desync; handle via presentation timestamps from the sample buffers.
5. **Large-region performance.** Full-display-sized regions at 30 fps are heavier; the disk-writing pipeline mitigates memory, but encode time and file size grow. Output max-width default helps.
6. **Hotkey conflicts.** Default Hyper chord may collide with user macros; rebindable from first run, and the `sniploop://capture` URL is an always-available alternative trigger.
7. **Notarizing embedded gifski.** The bundled binary adds a signing/notarization step; budget for it before wide distribution.

## 11. Milestones

Detailed phasing in `docs/build-plan.md`. High level:

- **M1 Capture-to-disk core:** menu bar + hotkey + `sniploop://` URL, multi-display overlay with glow and confirm/quick-mode selection, SCK-to-AVAssetWriter, floating control, save raw MP4. (Replaces the POC's in-memory path.)
- **M2 Export pipeline:** GIF via bundled gifski, MP4 via AVFoundation, output handling and clipboard.
- **M3 Editor:** trim, fps, crop/resize, size estimate, action shortcuts + cheatsheet, what-you-see-is-what-you-export.
- **M4 Polish, settings, distribution:** Settings (default destination, quick-mode modifier, launch-at-login, permission UX), last-region recall, GPL-3.0 LICENSE + README, packaging/sign script with a notarization-ready path.

## 12. Backlog (post-v1)

Annotations; WebP/APNG; capture history/library; system-audio and webcam; timed/scheduled capture; share/upload; export presets; in-app updates; drag-out-to-app from the editor; a sniploop.app landing and download page.
