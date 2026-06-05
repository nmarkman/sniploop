# Sniploop Foundation Implementation Plan (Milestones 0 to 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the SwiftPM foundation and a working end-to-end vertical slice: global hotkey or `sniploop://capture` URL triggers a region selector (with confirm/quick-mode), captures the region to a temp video, and exports a high-quality GIF (gifski) and an MP4 (AVFoundation) to the Desktop.

**Architecture:** All real logic lives in a pure `SniploopCore` Swift library and is built strictly red/green with XCTest (`swift test`). The `Sniploop` executable is thin AppKit/ScreenCaptureKit/AVFoundation glue that wires the core into the OS; because that glue cannot be meaningfully unit-tested, each glue task ends in a build-green step plus an explicit manual verification checklist. A `build.sh` wraps the SwiftPM executable into a signed `.app` bundle with the gifski binary embedded.

**Tech Stack:** Swift 6.2 (Swift 5 language mode for lenient concurrency), SwiftPM, XCTest, AppKit, ScreenCaptureKit, AVFoundation, the KeyboardShortcuts package (Carbon hotkeys, no Accessibility permission), and the gifski CLI (bundled).

**Scope note:** This plan covers Milestones M0 to M2 from `docs/build-plan.md`. The editor (M3) and settings UI + distribution (M4) are deliberately out of scope here and will each get their own plan. At the end of this plan the app captures with an *identity* EditSpec (full clip, source fps, no crop): a working capture-to-GIF tool, just without the editing step.

**TDD scope rule:** Tasks that touch `SniploopCore` follow full red/green (write failing test, see it fail, implement, see it pass, commit). Tasks that touch the `Sniploop` executable follow build-green + manual-verify (write code, build, run, verify against a checklist, commit), because their dependencies (screen capture, windows, hotkeys) have no unit-test surface.

**Prerequisites:**
- Xcode command line tools (`swiftc` present, confirmed).
- `brew install gifski` for local dev runs (the export step shells out to it). Tests do not need it.

---

## File Structure

```
Package.swift                         # SwiftPM manifest: SniploopCore lib, Sniploop exe, tests
Sources/
  SniploopCore/                       # PURE, TESTABLE logic (no AppKit/SCK/AVFoundation UI)
    CaptureGeometry.swift             # selection rect -> SCK sourceRect + output pixel size
    EditSpec.swift                    # edit model (trim/crop/scale/fps) + output-size math
    FrameTiming.swift                 # presentation-time -> GIF delays; fps sample times
    GifskiCommand.swift               # build gifski argv from inputs
    OutputNaming.swift                # Capture-<timestamp>.<ext> filename
    URLTrigger.swift                  # parse sniploop:// URLs -> action
    SelectionMachine.swift            # drag/confirm/quick-mode state machine
    Settings.swift                    # settings model + injectable persistence
  Sniploop/                           # THIN GLUE (manual-verify only)
    main.swift                        # NSApplication bootstrap
    AppController.swift               # orchestrates the flow; hotkey + URL handlers
    MenuBarController.swift           # NSStatusItem menu
    OverlayWindow.swift               # borderless per-display selection overlay
    OverlayView.swift                 # crosshair, glow box, drives SelectionMachine
    RecordingControl.swift            # floating Stop/Cancel + timer
    CaptureEngine.swift               # SCStream -> AVAssetWriter temp .mov
    Exporter.swift                    # GIF via gifski, MP4 via AVAssetExportSession
    Output.swift                      # save / reveal / copy-to-clipboard
Tests/
  SniploopCoreTests/
    CaptureGeometryTests.swift
    EditSpecTests.swift
    FrameTimingTests.swift
    GifskiCommandTests.swift
    OutputNamingTests.swift
    URLTriggerTests.swift
    SelectionMachineTests.swift
    SettingsTests.swift
build.sh                              # build exe -> assemble .app -> embed gifski -> sign
```

The single-file POC (`Sniploop.swift`) stays in place until the executable works end to end, then Task 20 deletes it.

---

## Task 1: SwiftPM scaffold and green test harness

**Files:**
- Create: `Package.swift`
- Create: `Sources/SniploopCore/Version.swift`
- Create: `Sources/Sniploop/main.swift`
- Create: `Tests/SniploopCoreTests/VersionTests.swift`
- Modify: `.gitignore`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sniploop",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .target(name: "SniploopCore"),
        .executableTarget(
            name: "Sniploop",
            dependencies: [
                "SniploopCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .testTarget(name: "SniploopCoreTests", dependencies: ["SniploopCore"]),
    ]
)
```

- [ ] **Step 2: Write a trivial core symbol so the library compiles**

`Sources/SniploopCore/Version.swift`:
```swift
public enum Sniploop {
    public static let coreVersion = "0.1.0"
}
```

- [ ] **Step 3: Write a placeholder executable entry point**

`Sources/Sniploop/main.swift`:
```swift
import SniploopCore

print("Sniploop core \(Sniploop.coreVersion)")
```

- [ ] **Step 4: Write the failing test**

`Tests/SniploopCoreTests/VersionTests.swift`:
```swift
import XCTest
@testable import SniploopCore

final class VersionTests: XCTestCase {
    func testCoreVersionIsSet() {
        XCTAssertEqual(Sniploop.coreVersion, "0.1.0")
    }
}
```

- [ ] **Step 5: Run the test, expect green**

Run: `cd ~/Desktop/Sniploop && swift test`
Expected: builds, `VersionTests.testCoreVersionIsSet` PASSES. (This validates the whole SPM + XCTest harness.)

- [ ] **Step 6: Ignore the build dir**

Add `.build/` to `.gitignore` (keep existing entries):
```
.build/
Sniploop.app/
*.gif
*.mov
*.mp4
.DS_Store
```

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests .gitignore
git commit -m "chore: SwiftPM scaffold with SniploopCore lib and green test harness"
```

---

## Task 2: CaptureGeometry (selection -> capture rect math)

**Files:**
- Create: `Sources/SniploopCore/CaptureGeometry.swift`
- Test: `Tests/SniploopCoreTests/CaptureGeometryTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/SniploopCoreTests/CaptureGeometryTests.swift`:
```swift
import XCTest
import CoreGraphics
@testable import SniploopCore

final class CaptureGeometryTests: XCTestCase {
    // AppKit selection is bottom-left origin; SCK sourceRect is top-left origin, in points.
    func testSourceRectFlipsYToTopLeft() {
        let selection = CGRect(x: 100, y: 300, width: 100, height: 100) // bottom-left
        let src = CaptureGeometry.sourceRectTopLeft(selection: selection, displayHeightPoints: 1000)
        // top-left y = 1000 - (300 + 100) = 600
        XCTAssertEqual(src, CGRect(x: 100, y: 600, width: 100, height: 100))
    }

    func testOutputPixelSizeAppliesScale() {
        let selection = CGRect(x: 0, y: 0, width: 640, height: 360)
        let size = CaptureGeometry.outputPixelSize(selection: selection, scale: 2)
        XCTAssertEqual(size.width, 1280)
        XCTAssertEqual(size.height, 720)
    }

    func testOutputPixelSizeRoundsToNearestPixel() {
        let selection = CGRect(x: 0, y: 0, width: 100.4, height: 100.6)
        let size = CaptureGeometry.outputPixelSize(selection: selection, scale: 1)
        XCTAssertEqual(size.width, 100)
        XCTAssertEqual(size.height, 101)
    }
}
```

- [ ] **Step 2: Run, expect failure**

Run: `swift test --filter CaptureGeometryTests`
Expected: FAIL, "cannot find 'CaptureGeometry' in scope".

- [ ] **Step 3: Implement**

`Sources/SniploopCore/CaptureGeometry.swift`:
```swift
import CoreGraphics

public enum CaptureGeometry {
    /// Convert a selection rect in screen points (bottom-left origin, relative to the display's
    /// own frame) into a ScreenCaptureKit `sourceRect` in points with a top-left origin.
    public static func sourceRectTopLeft(selection: CGRect, displayHeightPoints: CGFloat) -> CGRect {
        CGRect(
            x: selection.minX,
            y: displayHeightPoints - selection.maxY,
            width: selection.width,
            height: selection.height
        )
    }

    /// The output frame size in pixels for the captured region at the given backing scale.
    public static func outputPixelSize(selection: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        (
            width: Int((selection.width * scale).rounded()),
            height: Int((selection.height * scale).rounded())
        )
    }
}
```

- [ ] **Step 4: Run, expect green**

Run: `swift test --filter CaptureGeometryTests`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SniploopCore/CaptureGeometry.swift Tests/SniploopCoreTests/CaptureGeometryTests.swift
git commit -m "feat(core): CaptureGeometry sourceRect + output pixel size"
```

---

## Task 3: EditSpec (edit model + output-size math)

**Files:**
- Create: `Sources/SniploopCore/EditSpec.swift`
- Test: `Tests/SniploopCoreTests/EditSpecTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/SniploopCoreTests/EditSpecTests.swift`:
```swift
import XCTest
import CoreGraphics
@testable import SniploopCore

final class EditSpecTests: XCTestCase {
    func testIdentityIsFullLengthNoCropNoResize() {
        let s = EditSpec.identity(duration: 5.0, fps: 15)
        XCTAssertEqual(s.startSeconds, 0)
        XCTAssertEqual(s.endSeconds, 5.0)
        XCTAssertNil(s.cropPixels)
        XCTAssertNil(s.maxWidth)
        XCTAssertEqual(s.fps, 15)
        XCTAssertTrue(s.isTrimOnly)
        XCTAssertEqual(s.durationSeconds, 5.0)
    }

    func testNotTrimOnlyWhenCropped() {
        var s = EditSpec.identity(duration: 5, fps: 15)
        s.cropPixels = CGRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertFalse(s.isTrimOnly)
    }

    func testOutputSizeWithoutMaxWidthIsSource() {
        let s = EditSpec.identity(duration: 5, fps: 15)
        let out = s.outputSize(sourceWidth: 1280, sourceHeight: 720)
        XCTAssertEqual(out.width, 1280)
        XCTAssertEqual(out.height, 720)
    }

    func testOutputSizeScalesDownPreservingAspect() {
        var s = EditSpec.identity(duration: 5, fps: 15)
        s.maxWidth = 640
        let out = s.outputSize(sourceWidth: 1280, sourceHeight: 720)
        XCTAssertEqual(out.width, 640)
        XCTAssertEqual(out.height, 360)
    }

    func testOutputSizeDoesNotUpscale() {
        var s = EditSpec.identity(duration: 5, fps: 15)
        s.maxWidth = 2000
        let out = s.outputSize(sourceWidth: 1280, sourceHeight: 720)
        XCTAssertEqual(out.width, 1280)
        XCTAssertEqual(out.height, 720)
    }

    func testOutputSizeUsesCropAsBase() {
        var s = EditSpec.identity(duration: 5, fps: 15)
        s.cropPixels = CGRect(x: 0, y: 0, width: 800, height: 400)
        s.maxWidth = 400
        let out = s.outputSize(sourceWidth: 1280, sourceHeight: 720)
        XCTAssertEqual(out.width, 400)
        XCTAssertEqual(out.height, 200)
    }
}
```

- [ ] **Step 2: Run, expect failure**

Run: `swift test --filter EditSpecTests`
Expected: FAIL, "cannot find 'EditSpec' in scope".

- [ ] **Step 3: Implement**

`Sources/SniploopCore/EditSpec.swift`:
```swift
import CoreGraphics

public struct EditSpec: Equatable {
    /// Trim window, in seconds, within the master clip.
    public var startSeconds: Double
    public var endSeconds: Double
    /// Crop rectangle in pixels (top-left origin) within the master frame; nil means no crop.
    public var cropPixels: CGRect?
    /// Maximum output width in pixels; nil means keep the base width.
    public var maxWidth: Int?
    /// Output frames per second.
    public var fps: Int

    public init(startSeconds: Double, endSeconds: Double, cropPixels: CGRect? = nil, maxWidth: Int? = nil, fps: Int) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.cropPixels = cropPixels
        self.maxWidth = maxWidth
        self.fps = fps
    }

    public static func identity(duration: Double, fps: Int) -> EditSpec {
        EditSpec(startSeconds: 0, endSeconds: duration, cropPixels: nil, maxWidth: nil, fps: fps)
    }

    public var durationSeconds: Double { max(0, endSeconds - startSeconds) }

    public var isTrimOnly: Bool { cropPixels == nil && maxWidth == nil }

    /// Output pixel size after applying crop (if any) then max-width downscale (aspect preserved, no upscale).
    public func outputSize(sourceWidth: Int, sourceHeight: Int) -> (width: Int, height: Int) {
        let baseW = cropPixels.map { Int($0.width) } ?? sourceWidth
        let baseH = cropPixels.map { Int($0.height) } ?? sourceHeight
        guard let maxW = maxWidth, maxW < baseW, baseW > 0 else {
            return (baseW, baseH)
        }
        let ratio = Double(maxW) / Double(baseW)
        return (maxW, max(1, Int((Double(baseH) * ratio).rounded())))
    }
}
```

- [ ] **Step 4: Run, expect green**

Run: `swift test --filter EditSpecTests`
Expected: 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SniploopCore/EditSpec.swift Tests/SniploopCoreTests/EditSpecTests.swift
git commit -m "feat(core): EditSpec model and output-size math"
```

---

## Task 4: FrameTiming (fps sample times)

**Files:**
- Create: `Sources/SniploopCore/FrameTiming.swift`
- Test: `Tests/SniploopCoreTests/FrameTimingTests.swift`

We sample frames from the recorded `.mov` at evenly spaced times and let gifski apply a uniform `--fps`, so we only need `sampleTimes` here. (Per-frame variable delays are not needed: the recorded clip has a continuous timeline, so sampling at fixed times correctly holds frames through static stretches.)

- [ ] **Step 1: Write the failing tests**

`Tests/SniploopCoreTests/FrameTimingTests.swift`:
```swift
import XCTest
@testable import SniploopCore

final class FrameTimingTests: XCTestCase {
    func testSampleTimesSpacedByFps() {
        let times = FrameTiming.sampleTimes(duration: 1.0, fps: 4)
        XCTAssertEqual(times, [0.0, 0.25, 0.5, 0.75])
    }

    func testSampleTimesZeroDurationIsEmpty() {
        XCTAssertEqual(FrameTiming.sampleTimes(duration: 0, fps: 15), [])
    }

    func testSampleTimesZeroFpsIsEmpty() {
        XCTAssertEqual(FrameTiming.sampleTimes(duration: 5, fps: 0), [])
    }
}
```

- [ ] **Step 2: Run, expect failure**

Run: `swift test --filter FrameTimingTests`
Expected: FAIL, "cannot find 'FrameTiming' in scope".

- [ ] **Step 3: Implement**

`Sources/SniploopCore/FrameTiming.swift`:
```swift
public enum FrameTiming {
    /// Timestamps (seconds from clip start) at which to sample frames for a given output fps.
    public static func sampleTimes(duration: Double, fps: Int) -> [Double] {
        guard duration > 0, fps > 0 else { return [] }
        let interval = 1.0 / Double(fps)
        var times: [Double] = []
        var t = 0.0
        while t < duration {
            times.append(t)
            t += interval
        }
        return times
    }
}
```

- [ ] **Step 4: Run, expect green**

Run: `swift test --filter FrameTimingTests`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SniploopCore/FrameTiming.swift Tests/SniploopCoreTests/FrameTimingTests.swift
git commit -m "feat(core): FrameTiming delays and fps sample times"
```

---

## Task 5: GifskiCommand (build gifski argv)

**Files:**
- Create: `Sources/SniploopCore/GifskiCommand.swift`
- Test: `Tests/SniploopCoreTests/GifskiCommandTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/SniploopCoreTests/GifskiCommandTests.swift`:
```swift
import XCTest
@testable import SniploopCore

final class GifskiCommandTests: XCTestCase {
    func testBuildsFpsQualityOutputAndFrames() {
        let args = GifskiCommand.arguments(
            framePaths: ["/tmp/f/0001.png", "/tmp/f/0002.png"],
            outputPath: "/tmp/out.gif",
            fps: 15, quality: 90, width: nil
        )
        XCTAssertEqual(args, [
            "--fps", "15",
            "--quality", "90",
            "-o", "/tmp/out.gif",
            "/tmp/f/0001.png", "/tmp/f/0002.png",
        ])
    }

    func testIncludesWidthWhenProvided() {
        let args = GifskiCommand.arguments(
            framePaths: ["/tmp/f/0001.png"],
            outputPath: "/tmp/out.gif",
            fps: 10, quality: 80, width: 640
        )
        XCTAssertEqual(args, [
            "--fps", "10",
            "--quality", "80",
            "--width", "640",
            "-o", "/tmp/out.gif",
            "/tmp/f/0001.png",
        ])
    }
}
```

- [ ] **Step 2: Run, expect failure**

Run: `swift test --filter GifskiCommandTests`
Expected: FAIL, "cannot find 'GifskiCommand' in scope".

- [ ] **Step 3: Implement**

`Sources/SniploopCore/GifskiCommand.swift`:
```swift
public enum GifskiCommand {
    /// Argument vector for `gifski` to encode an ordered list of PNG frames into a GIF.
    /// Order matters: flags first, output path, then the frame paths.
    public static func arguments(framePaths: [String], outputPath: String, fps: Int, quality: Int, width: Int?) -> [String] {
        var args = ["--fps", String(fps), "--quality", String(quality)]
        if let width { args += ["--width", String(width)] }
        args += ["-o", outputPath]
        args += framePaths
        return args
    }
}
```

- [ ] **Step 4: Run, expect green**

Run: `swift test --filter GifskiCommandTests`
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SniploopCore/GifskiCommand.swift Tests/SniploopCoreTests/GifskiCommandTests.swift
git commit -m "feat(core): GifskiCommand argv builder"
```

---

## Task 6: OutputNaming (timestamped filename)

**Files:**
- Create: `Sources/SniploopCore/OutputNaming.swift`
- Test: `Tests/SniploopCoreTests/OutputNamingTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/SniploopCoreTests/OutputNamingTests.swift`:
```swift
import XCTest
@testable import SniploopCore

final class OutputNamingTests: XCTestCase {
    func testFilenameFormat() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 5
        comps.hour = 10; comps.minute = 15; comps.second = 30
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: comps)!

        let name = OutputNaming.filename(date: date, ext: "gif", timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(name, "Capture-2026-06-05T10.15.30.gif")
    }

    func testRespectsExtension() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 2
        comps.hour = 3; comps.minute = 4; comps.second = 5
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: comps)!

        let name = OutputNaming.filename(date: date, ext: "mp4", timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(name, "Capture-2026-01-02T03.04.05.mp4")
    }
}
```

- [ ] **Step 2: Run, expect failure**

Run: `swift test --filter OutputNamingTests`
Expected: FAIL, "cannot find 'OutputNaming' in scope".

- [ ] **Step 3: Implement**

`Sources/SniploopCore/OutputNaming.swift`:
```swift
import Foundation

public enum OutputNaming {
    /// Filename like "Capture-2026-06-05T10.15.30.gif".
    public static func filename(date: Date, ext: String, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(format: "%04d-%02d-%02dT%02d.%02d.%02d",
                           c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        return "Capture-\(stamp).\(ext)"
    }
}
```

- [ ] **Step 4: Run, expect green**

Run: `swift test --filter OutputNamingTests`
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SniploopCore/OutputNaming.swift Tests/SniploopCoreTests/OutputNamingTests.swift
git commit -m "feat(core): OutputNaming timestamped filename"
```

---

## Task 7: URLTrigger (parse sniploop:// URLs)

**Files:**
- Create: `Sources/SniploopCore/URLTrigger.swift`
- Test: `Tests/SniploopCoreTests/URLTriggerTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/SniploopCoreTests/URLTriggerTests.swift`:
```swift
import XCTest
@testable import SniploopCore

final class URLTriggerTests: XCTestCase {
    func testCaptureURLMapsToNewCapture() {
        XCTAssertEqual(URLTrigger.action(from: URL(string: "sniploop://capture")!), .newCapture)
    }

    func testWrongSchemeIsNil() {
        XCTAssertNil(URLTrigger.action(from: URL(string: "https://capture")!))
    }

    func testUnknownHostIsNil() {
        XCTAssertNil(URLTrigger.action(from: URL(string: "sniploop://nope")!))
    }
}
```

- [ ] **Step 2: Run, expect failure**

Run: `swift test --filter URLTriggerTests`
Expected: FAIL, "cannot find 'URLTrigger' in scope".

- [ ] **Step 3: Implement**

`Sources/SniploopCore/URLTrigger.swift`:
```swift
import Foundation

public enum TriggerAction: Equatable {
    case newCapture
}

public enum URLTrigger {
    public static func action(from url: URL) -> TriggerAction? {
        guard url.scheme == "sniploop" else { return nil }
        switch url.host {
        case "capture": return .newCapture
        default: return nil
        }
    }
}
```

- [ ] **Step 4: Run, expect green**

Run: `swift test --filter URLTriggerTests`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SniploopCore/URLTrigger.swift Tests/SniploopCoreTests/URLTriggerTests.swift
git commit -m "feat(core): URLTrigger sniploop:// parsing"
```

---

## Task 8: SelectionMachine (drag / confirm / quick-mode)

**Files:**
- Create: `Sources/SniploopCore/SelectionMachine.swift`
- Test: `Tests/SniploopCoreTests/SelectionMachineTests.swift`

This is the state machine behind the capture UX (FB4): confirm-to-record by default, re-drag to redraw, hold-Shift to record instantly.

- [ ] **Step 1: Write the failing tests**

`Tests/SniploopCoreTests/SelectionMachineTests.swift`:
```swift
import XCTest
import CoreGraphics
@testable import SniploopCore

final class SelectionMachineTests: XCTestCase {
    func testDragThenReleaseGoesToConfirming() {
        var m = SelectionMachine()
        m.handle(.dragBegan(CGPoint(x: 0, y: 0)))
        m.handle(.dragChanged(CGRect(x: 0, y: 0, width: 50, height: 40)))
        m.handle(.dragEnded(rect: CGRect(x: 0, y: 0, width: 50, height: 40), quickModifier: false))
        XCTAssertEqual(m.phase, .confirming(CGRect(x: 0, y: 0, width: 50, height: 40)))
    }

    func testConfirmFromConfirmingRecords() {
        var m = SelectionMachine()
        m.handle(.dragBegan(.zero))
        m.handle(.dragEnded(rect: CGRect(x: 0, y: 0, width: 50, height: 40), quickModifier: false))
        m.handle(.confirm)
        XCTAssertEqual(m.phase, .recording(CGRect(x: 0, y: 0, width: 50, height: 40)))
    }

    func testQuickModifierRecordsImmediately() {
        var m = SelectionMachine()
        m.handle(.dragBegan(.zero))
        m.handle(.dragEnded(rect: CGRect(x: 0, y: 0, width: 50, height: 40), quickModifier: true))
        XCTAssertEqual(m.phase, .recording(CGRect(x: 0, y: 0, width: 50, height: 40)))
    }

    func testTinyDragReturnsToIdle() {
        var m = SelectionMachine()
        m.handle(.dragBegan(.zero))
        m.handle(.dragEnded(rect: CGRect(x: 0, y: 0, width: 2, height: 2), quickModifier: false))
        XCTAssertEqual(m.phase, .idle)
    }

    func testReDragFromConfirmingReplacesSelection() {
        var m = SelectionMachine()
        m.handle(.dragBegan(.zero))
        m.handle(.dragEnded(rect: CGRect(x: 0, y: 0, width: 50, height: 40), quickModifier: false))
        // user starts a new drag instead of confirming
        m.handle(.dragBegan(CGPoint(x: 100, y: 100)))
        XCTAssertEqual(m.phase, .dragging(CGRect(x: 100, y: 100, width: 0, height: 0)))
    }

    func testCancelFromAnywhereCancels() {
        var m = SelectionMachine()
        m.handle(.dragBegan(.zero))
        m.handle(.cancel)
        XCTAssertEqual(m.phase, .cancelled)
    }

    func testConfirmFromIdleIsIgnored() {
        var m = SelectionMachine()
        m.handle(.confirm)
        XCTAssertEqual(m.phase, .idle)
    }
}
```

- [ ] **Step 2: Run, expect failure**

Run: `swift test --filter SelectionMachineTests`
Expected: FAIL, "cannot find 'SelectionMachine' in scope".

- [ ] **Step 3: Implement**

`Sources/SniploopCore/SelectionMachine.swift`:
```swift
import CoreGraphics

public enum SelectionPhase: Equatable {
    case idle
    case dragging(CGRect)
    case confirming(CGRect)
    case recording(CGRect)
    case cancelled
}

public enum SelectionEvent: Equatable {
    case dragBegan(CGPoint)
    case dragChanged(CGRect)
    case dragEnded(rect: CGRect, quickModifier: Bool)
    case confirm
    case cancel
}

public struct SelectionMachine {
    public private(set) var phase: SelectionPhase = .idle
    public let minSize: CGFloat

    public init(minSize: CGFloat = 5) {
        self.minSize = minSize
    }

    public mutating func handle(_ event: SelectionEvent) {
        if case .cancel = event {
            phase = .cancelled
            return
        }
        switch (phase, event) {
        case (.idle, .dragBegan(let p)), (.confirming, .dragBegan(let p)):
            phase = .dragging(CGRect(origin: p, size: .zero))
        case (.dragging, .dragChanged(let r)):
            phase = .dragging(r)
        case (.dragging, .dragEnded(let rect, let quick)):
            if rect.width < minSize || rect.height < minSize {
                phase = .idle
            } else {
                phase = quick ? .recording(rect) : .confirming(rect)
            }
        case (.confirming(let r), .confirm):
            phase = .recording(r)
        default:
            break // ignore invalid transitions
        }
    }
}
```

- [ ] **Step 4: Run, expect green**

Run: `swift test --filter SelectionMachineTests`
Expected: 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SniploopCore/SelectionMachine.swift Tests/SniploopCoreTests/SelectionMachineTests.swift
git commit -m "feat(core): SelectionMachine confirm/quick-mode state machine"
```

---

## Task 9: Settings (model + injectable persistence)

**Files:**
- Create: `Sources/SniploopCore/Settings.swift`
- Test: `Tests/SniploopCoreTests/SettingsTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/SniploopCoreTests/SettingsTests.swift`:
```swift
import XCTest
@testable import SniploopCore

private final class MemoryStore: SettingsStore {
    var storage: [String: Data] = [:]
    func data(forKey key: String) -> Data? { storage[key] }
    func set(_ data: Data?, forKey key: String) { storage[key] = data }
}

final class SettingsTests: XCTestCase {
    func testLoadReturnsDefaultsWhenEmpty() {
        let mgr = SettingsManager(store: MemoryStore())
        XCTAssertEqual(mgr.load(), Settings.defaults)
    }

    func testSaveThenLoadRoundTrips() {
        let mgr = SettingsManager(store: MemoryStore())
        var s = Settings.defaults
        s.defaultFPS = 24
        s.defaultMaxWidth = 640
        s.showCursor = false
        mgr.save(s)
        XCTAssertEqual(mgr.load(), s)
    }

    func testDefaultsAreSane() {
        XCTAssertEqual(Settings.defaults.defaultFPS, 15)
        XCTAssertTrue(Settings.defaults.showCursor)
    }
}
```

- [ ] **Step 2: Run, expect failure**

Run: `swift test --filter SettingsTests`
Expected: FAIL, "cannot find 'SettingsManager' in scope".

- [ ] **Step 3: Implement**

`Sources/SniploopCore/Settings.swift`:
```swift
import Foundation

public struct Settings: Codable, Equatable {
    public var destinationFolderPath: String
    public var defaultFPS: Int
    public var defaultMaxWidth: Int?
    public var showCursor: Bool
    public var launchAtLogin: Bool

    public init(destinationFolderPath: String, defaultFPS: Int, defaultMaxWidth: Int?, showCursor: Bool, launchAtLogin: Bool) {
        self.destinationFolderPath = destinationFolderPath
        self.defaultFPS = defaultFPS
        self.defaultMaxWidth = defaultMaxWidth
        self.showCursor = showCursor
        self.launchAtLogin = launchAtLogin
    }

    public static let defaults = Settings(
        destinationFolderPath: NSString(string: "~/Desktop").expandingTildeInPath,
        defaultFPS: 15,
        defaultMaxWidth: 800,
        showCursor: true,
        launchAtLogin: false
    )
}

public protocol SettingsStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

/// UserDefaults conforms to SettingsStore at the call site in the app target.
public final class SettingsManager {
    private let store: SettingsStore
    private let key = "sniploop.settings.v1"

    public init(store: SettingsStore) { self.store = store }

    public func load() -> Settings {
        guard let data = store.data(forKey: key),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else {
            return .defaults
        }
        return s
    }

    public func save(_ settings: Settings) {
        store.set(try? JSONEncoder().encode(settings), forKey: key)
    }
}
```

- [ ] **Step 4: Run, expect green**

Run: `swift test --filter SettingsTests`
Expected: 3 tests PASS.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: all core tests across Tasks 1 to 9 PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SniploopCore/Settings.swift Tests/SniploopCoreTests/SettingsTests.swift
git commit -m "feat(core): Settings model with injectable store"
```

---

> **Glue begins here.** Tasks 10 to 20 build the executable. They cannot be unit-tested, so each ends with a build step and a manual verification checklist instead of red/green. Run the app via the `.app` bundle (Task 10's `build.sh`), not `swift run`, because Screen Recording permission and the URL scheme need the bundle identity.

---

## Task 10: build.sh assembles a signed .app from the SwiftPM exe

**Files:**
- Modify: `build.sh` (replace POC build with SwiftPM-based build)

- [ ] **Step 1: Replace `build.sh`**

```bash
#!/bin/bash
# Builds the SwiftPM executable, wraps it in a .app bundle, embeds gifski, signs ad-hoc.
set -e
cd "$(dirname "$0")"

APP="Sniploop.app"
RES="$APP/Contents/Resources"
BIN_DIR="$APP/Contents/MacOS"
CONFIG="${1:-debug}"   # pass "release" for an optimized build

echo "Building ($CONFIG)..."
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Sniploop"

rm -rf "$APP"
mkdir -p "$BIN_DIR" "$RES"
cp "$BIN" "$BIN_DIR/Sniploop"

# Embed gifski (from Homebrew) so the export step can shell out to it.
if command -v gifski >/dev/null 2>&1; then
    cp "$(command -v gifski)" "$RES/gifski"
else
    echo "WARNING: gifski not found on PATH; GIF export will fail. Run: brew install gifski"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Sniploop</string>
    <key>CFBundleIdentifier</key><string>com.nickmarkman.sniploop</string>
    <key>CFBundleName</key><string>Sniploop</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>com.nickmarkman.sniploop</string>
            <key>CFBundleURLSchemes</key><array><string>sniploop</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$RES/gifski" >/dev/null 2>&1 || true
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
```

- [ ] **Step 2: Build (core glue not present yet, so expect a thin app)**

Run: `cd ~/Desktop/Sniploop && ./build.sh`
Expected: builds `Sniploop.app`. (At this point `main.swift` just prints a line; the app does nothing visible. That is fine.)

- [ ] **Step 3: Commit**

```bash
git add build.sh
git commit -m "build: assemble signed .app from SwiftPM exe, embed gifski, register URL scheme"
```

---

## Task 11: App bootstrap, menu bar, and AppController shell

**Files:**
- Modify: `Sources/Sniploop/main.swift`
- Create: `Sources/Sniploop/AppController.swift`
- Create: `Sources/Sniploop/MenuBarController.swift`

- [ ] **Step 1: Replace `main.swift` with an NSApplication bootstrap**

```swift
import AppKit

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.run()
```

- [ ] **Step 2: Create `MenuBarController.swift`**

```swift
import AppKit

final class MenuBarController {
    private let statusItem: NSStatusItem
    var onNewCapture: (() -> Void)?
    var onQuit: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.dashed.badge.record", accessibilityDescription: "Sniploop")

        let menu = NSMenu()
        let capture = NSMenuItem(title: "New Capture", action: #selector(newCapture), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Sniploop", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func newCapture() { onNewCapture?() }
    @objc private func quit() { onQuit?() }
}
```

- [ ] **Step 3: Create `AppController.swift`**

```swift
import AppKit
import SniploopCore

final class AppController: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mb = MenuBarController()
        mb.onNewCapture = { [weak self] in self?.startCapture() }
        mb.onQuit = { NSApp.terminate(nil) }
        menuBar = mb
    }

    func startCapture() {
        // Wired in later tasks. For now, prove the entry point fires.
        NSLog("Sniploop: startCapture invoked")
    }

    // URL scheme: sniploop://capture
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where URLTrigger.action(from: url) == .newCapture {
            startCapture()
        }
    }
}
```

- [ ] **Step 4: Build and verify**

Run: `./build.sh && open Sniploop.app`
Manual verification:
- A menu bar icon appears (a dashed-rectangle record glyph).
- Clicking it shows "New Capture" and "Quit Sniploop".
- Clicking "New Capture" logs `Sniploop: startCapture invoked` (check with `log stream --predicate 'eventMessage CONTAINS "Sniploop:"'` in another terminal, or Console.app).
- Run `open sniploop://capture` from Terminal; it logs the same line.
- "Quit Sniploop" quits.

- [ ] **Step 5: Commit**

```bash
git add Sources/Sniploop/main.swift Sources/Sniploop/AppController.swift Sources/Sniploop/MenuBarController.swift
git commit -m "feat(app): NSApplication bootstrap, menu bar, URL-scheme + startCapture entry point"
```

---

## Task 12: Global hotkey via KeyboardShortcuts (no Accessibility)

**Files:**
- Modify: `Sources/Sniploop/AppController.swift`

- [ ] **Step 1: Add the shortcut name and registration**

Add to the top of `AppController.swift` (after imports):
```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // Default: Hyper (Cmd-Ctrl-Opt-Shift) + G. A Caps-Lock-as-Hyper setup sends this same chord.
    static let newCapture = Self("newCapture", default: .init(.g, modifiers: [.command, .control, .option, .shift]))
}
```

- [ ] **Step 2: Register the handler in `applicationDidFinishLaunching`**

Add at the end of `applicationDidFinishLaunching`:
```swift
KeyboardShortcuts.onKeyUp(for: .newCapture) { [weak self] in
    self?.startCapture()
}
```

- [ ] **Step 3: Build and verify**

Run: `./build.sh && open Sniploop.app`
Manual verification:
- Press the Hyper+G chord (Cmd-Ctrl-Opt-Shift-G) from any app; `startCapture invoked` logs.
- Critically: **no Accessibility permission prompt appears** (Carbon hotkeys do not need it). Confirm Sniploop is absent from System Settings > Privacy & Security > Accessibility.

- [ ] **Step 4: Commit**

```bash
git add Sources/Sniploop/AppController.swift
git commit -m "feat(app): global Hyper-chord hotkey via KeyboardShortcuts"
```

---

## Task 13: Region overlay window (single display, crosshair + dim)

**Files:**
- Create: `Sources/Sniploop/OverlayWindow.swift`
- Create: `Sources/Sniploop/OverlayView.swift`
- Modify: `Sources/Sniploop/AppController.swift`

This task ports the proven POC overlay into the new structure but drives it with `SelectionMachine` and adds the glow.

- [ ] **Step 1: Create `OverlayWindow.swift`**

```swift
import AppKit

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

- [ ] **Step 2: Create `OverlayView.swift`**

```swift
import AppKit
import SniploopCore

final class OverlayView: NSView {
    /// Called with the selected rect (view/screen points, bottom-left) when recording should start.
    var onRecord: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var machine = SelectionMachine()
    private var dragOrigin: NSPoint?
    private var currentRect: NSRect?

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        dragOrigin = p
        currentRect = NSRect(origin: p, size: .zero)
        machine.handle(.dragBegan(p))
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        guard let o = dragOrigin else { return }
        let p = convert(e.locationInWindow, from: nil)
        let r = NSRect(x: min(o.x, p.x), y: min(o.y, p.y), width: abs(p.x - o.x), height: abs(p.y - o.y))
        currentRect = r
        machine.handle(.dragChanged(r))
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        guard let r = currentRect else { return }
        let quick = e.modifierFlags.contains(.shift)
        machine.handle(.dragEnded(rect: r, quickModifier: quick))
        evaluate()
    }

    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 53: machine.handle(.cancel); evaluate()        // Esc
        case 36, 76: machine.handle(.confirm); evaluate()   // Return / keypad Enter
        default: break
        }
    }

    private func evaluate() {
        switch machine.phase {
        case .recording(let r): onRecord?(r)
        case .cancelled: onCancel?()
        case .idle: currentRect = nil; needsDisplay = true   // tiny drag reset
        default: needsDisplay = true                         // confirming: keep box + glow
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()

        let hint = "Drag to select   ·   Enter to record   ·   hold Shift to record instantly   ·   Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let hs = hint.size(withAttributes: attrs)
        hint.draw(at: NSPoint(x: bounds.midX - hs.width / 2, y: bounds.maxY - 60), withAttributes: attrs)

        guard let r = currentRect, r.width > 0, r.height > 0 else { return }
        if let ctx = NSGraphicsContext.current?.cgContext { ctx.clear(r) }   // see-through hole

        let confirming: Bool = { if case .confirming = machine.phase { return true }; return false }()
        let stroke = confirming ? NSColor.systemBlue : NSColor.white

        if confirming, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 14, color: NSColor.systemBlue.withAlphaComponent(0.9).cgColor)
            stroke.setStroke()
            let path = NSBezierPath(rect: r); path.lineWidth = 2; path.stroke()
            ctx.restoreGState()
        } else {
            stroke.setStroke()
            let path = NSBezierPath(rect: r); path.lineWidth = 1.5; path.stroke()
        }

        let label = "\(Int(r.width)) × \(Int(r.height))"
        let lattrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        label.draw(at: NSPoint(x: r.minX + 2, y: r.maxY + 4), withAttributes: lattrs)
    }
}
```

- [ ] **Step 3: Wire it into `AppController.startCapture()`**

Replace the placeholder `startCapture()` body and add a property:
```swift
    private var overlay: OverlayWindow?
    private var captureScreen: NSScreen?

    func startCapture() {
        guard overlay == nil, let screen = NSScreen.main else { return }
        captureScreen = screen

        let win = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.setFrame(screen.frame, display: true)

        let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onRecord = { [weak self] rect in self?.beginRecording(selection: rect) }
        view.onCancel = { [weak self] in self?.dismissOverlay() }
        win.contentView = view

        overlay = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(view)
    }

    private func dismissOverlay() {
        overlay?.orderOut(nil)
        overlay = nil
    }

    private func beginRecording(selection: NSRect) {
        dismissOverlay()
        NSLog("Sniploop: beginRecording rect=\(NSStringFromRect(selection))")
    }
```

- [ ] **Step 4: Build and verify**

Run: `./build.sh && open Sniploop.app`
Manual verification:
- Trigger via hotkey or menu: the screen dims with a crosshair and the hint text.
- Dragging draws a see-through white box with a live `W × H` label.
- On release (no Shift), the box turns blue with a glow and stays. Pressing Esc dismisses; starting a new drag replaces the box; pressing Enter logs `beginRecording`.
- Dragging with Shift held logs `beginRecording` immediately on release.
- A tiny click (no real drag) clears back to just the dim overlay.

- [ ] **Step 5: Commit**

```bash
git add Sources/Sniploop/OverlayWindow.swift Sources/Sniploop/OverlayView.swift Sources/Sniploop/AppController.swift
git commit -m "feat(app): selection overlay with glow, driven by SelectionMachine"
```

---

## Task 14: CaptureEngine (SCStream region -> temp .mov)

**Files:**
- Create: `Sources/Sniploop/CaptureEngine.swift`

- [ ] **Step 1: Create `CaptureEngine.swift`**

```swift
import AppKit
import ScreenCaptureKit
import AVFoundation
import SniploopCore

/// Captures a screen region to a temp H.264 .mov via ScreenCaptureKit + AVAssetWriter.
final class CaptureEngine: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var startedSession = false
    private let queue = DispatchQueue(label: "sniploop.capture")
    private(set) var outputURL: URL?

    /// `selection` is in points, bottom-left origin, relative to `screen`'s own frame.
    func start(screen: NSScreen, selection: NSRect, showsCursor: Bool) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw NSError(domain: "Sniploop", code: 1, userInfo: [NSLocalizedDescriptionKey: "No capturable display found"])
        }

        let scale = screen.backingScaleFactor
        let sourceRect = CaptureGeometry.sourceRectTopLeft(selection: selection, displayHeightPoints: screen.frame.height)
        let pixel = CaptureGeometry.outputPixelSize(selection: selection, scale: scale)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sniploop-\(UUID().uuidString).mov")
        let w = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixel.width,
            AVVideoHeightKey: pixel.height,
        ])
        videoIn.expectsMediaDataInRealTime = true
        w.add(videoIn)
        writer = w
        input = videoIn
        outputURL = url

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = pixel.width
        config.height = pixel.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 6
        config.showsCursor = showsCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let s = SCStream(filter: filter, configuration: config, delegate: nil)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
    }

    func stop() async -> URL? {
        if let s = stream { try? await s.stopCapture() }
        stream = nil
        input?.markAsFinished()
        await writer?.finishWriting()
        return outputURL
    }

    func cancel() async {
        if let s = stream { try? await s.stopCapture() }
        stream = nil
        input?.markAsFinished()
        await writer?.finishWriting()
        if let url = outputURL { try? FileManager.default.removeItem(at: url) }
        outputURL = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let writer, let input else { return }

        // Only complete frames.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let statusRaw = info[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete else { return }

        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            startedSession = true
        }
        guard writer.status == .writing, startedSession, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }
}
```

- [ ] **Step 2: Build (compile-only check)**

Run: `swift build`
Expected: compiles. (Behavior is verified in Task 16 once Stop is wired.)

- [ ] **Step 3: Commit**

```bash
git add Sources/Sniploop/CaptureEngine.swift
git commit -m "feat(app): CaptureEngine streams a region to a temp .mov"
```

---

## Task 15: RecordingControl (floating Stop / Cancel + timer)

**Files:**
- Create: `Sources/Sniploop/RecordingControl.swift`

- [ ] **Step 1: Create `RecordingControl.swift`**

```swift
import AppKit

final class RecordingControl: NSObject {
    private let window: NSWindow
    private let timeLabel: NSTextField
    private let started = Date()
    private var timer: Timer?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?

    /// `region` is in global screen points (bottom-left origin).
    init(near region: NSRect, on screen: NSScreen) {
        let size = NSSize(width: 184, height: 40)
        var origin = NSPoint(x: region.minX, y: region.maxY + 10)
        if origin.y + size.height > screen.frame.maxY - 6 { origin.y = region.minY - size.height - 10 }
        origin.x = max(screen.frame.minX + 6, min(origin.x, screen.frame.maxX - size.width - 6))
        origin.y = max(screen.frame.minY + 6, origin.y)

        window = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 10
        bg.layer?.masksToBounds = true

        timeLabel = NSTextField(labelWithString: "0:00")
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timeLabel.textColor = .white

        super.init()

        let stop = NSButton(title: "Stop", target: self, action: #selector(stopTapped))
        stop.bezelStyle = .rounded
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded

        let stack = NSStackView(views: [timeLabel, stop, cancel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        stack.frame = NSRect(origin: .zero, size: size)
        stack.autoresizingMask = [.width, .height]
        bg.addSubview(stack)
        window.contentView = bg

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func show() { window.orderFrontRegardless() }
    func close() { timer?.invalidate(); window.orderOut(nil) }

    private func tick() {
        let s = Int(Date().timeIntervalSince(started))
        timeLabel.stringValue = String(format: "%d:%02d", s / 60, s % 60)
    }

    @objc private func stopTapped() { onStop?() }
    @objc private func cancelTapped() { onCancel?() }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: compiles.

- [ ] **Step 3: Commit**

```bash
git add Sources/Sniploop/RecordingControl.swift
git commit -m "feat(app): floating recording control with Stop/Cancel and timer"
```

---

## Task 16: Wire capture + recording control into the flow

**Files:**
- Modify: `Sources/Sniploop/AppController.swift`

- [ ] **Step 1: Add capture state and replace `beginRecording`**

Add properties:
```swift
    private let capture = CaptureEngine()
    private var recordingControl: RecordingControl?
    private var lastSelection: NSRect = .zero
```

Replace `beginRecording(selection:)`:
```swift
    private func beginRecording(selection: NSRect) {
        guard let screen = captureScreen else { return }
        dismissOverlay()
        lastSelection = selection

        let global = NSRect(x: selection.minX + screen.frame.minX,
                            y: selection.minY + screen.frame.minY,
                            width: selection.width, height: selection.height)
        let control = RecordingControl(near: global, on: screen)
        control.onStop = { [weak self] in self?.finishRecording() }
        control.onCancel = { [weak self] in self?.cancelRecording() }
        control.show()
        recordingControl = control

        Task {
            do {
                try await capture.start(screen: screen, selection: selection, showsCursor: true)
            } catch {
                await MainActor.run { self.failCapture(error) }
            }
        }
    }

    private func finishRecording() {
        recordingControl?.close()
        recordingControl = nil
        Task {
            let url = await capture.stop()
            await MainActor.run {
                if let url { NSLog("Sniploop: master saved at \(url.path)") }
                self.handleMaster(url)
            }
        }
    }

    private func cancelRecording() {
        recordingControl?.close()
        recordingControl = nil
        Task { await capture.cancel() }
    }

    private func handleMaster(_ url: URL?) {
        // Exporter wired in Task 17. For now, reveal the raw master to prove capture works.
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func failCapture(_ error: Error) {
        recordingControl?.close()
        recordingControl = nil
        let a = NSAlert()
        a.messageText = "Can't record the screen"
        a.informativeText = "Sniploop needs Screen Recording permission.\n\nEnable Sniploop under System Settings > Privacy & Security > Screen Recording, then try again.\n\n(\(error.localizedDescription))"
        a.addButton(withTitle: "Open Settings")
        a.addButton(withTitle: "OK")
        if a.runModal() == .alertFirstButtonReturn,
           let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(u)
        }
    }
```

- [ ] **Step 2: Build and verify the full capture path**

Run: `./build.sh && open Sniploop.app`
Manual verification (grant Screen Recording on first prompt, relaunch if needed):
- Trigger, drag a region, press Enter (or Shift-release for quick mode).
- The Stop/Cancel pill appears with a running timer, positioned clear of the region.
- Do something on screen, click Stop. Finder opens revealing a `.mov` in the temp dir that plays back showing exactly the selected region at the correct scale.
- Repeat and click Cancel mid-recording: no file is revealed, and the temp file is removed.
- Record for 60+ seconds and confirm Activity Monitor shows flat memory for Sniploop (disk-backed writer, not in-memory frames).

- [ ] **Step 3: Commit**

```bash
git add Sources/Sniploop/AppController.swift
git commit -m "feat(app): wire capture + recording control; reveal raw master"
```

---

## Task 17: Exporter (GIF via gifski, MP4 via AVFoundation)

**Files:**
- Create: `Sources/Sniploop/Exporter.swift`

- [ ] **Step 1: Create `Exporter.swift`**

```swift
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import SniploopCore

enum ExportError: Error { case gifskiMissing, frameExtractionFailed, gifskiFailed(Int32), mp4Failed }

final class Exporter {
    private let gifskiURL: URL?

    init(gifskiURL: URL? = Bundle.main.url(forResource: "gifski", withExtension: nil)) {
        self.gifskiURL = gifskiURL
    }

    /// Export a GIF from the master using the EditSpec. Identity spec = whole clip, source size.
    func exportGIF(master: URL, spec: EditSpec, quality: Int = 90) async throws -> URL {
        guard let gifskiURL else { throw ExportError.gifskiMissing }

        let asset = AVURLAsset(url: master)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        // (crop is deferred to the editor plan; with an identity spec there is no crop.)

        let times = FrameTiming.sampleTimes(duration: spec.durationSeconds, fps: spec.fps)
            .map { CMTime(seconds: spec.startSeconds + $0, preferredTimescale: 600) }

        let framesDir = FileManager.default.temporaryDirectory.appendingPathComponent("sniploop-frames-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: framesDir) }

        var framePaths: [String] = []
        for (i, t) in times.enumerated() {
            let cg = try await gen.image(at: t).image
            let path = framesDir.appendingPathComponent(String(format: "%05d.png", i))
            guard let dest = CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw ExportError.frameExtractionFailed
            }
            CGImageDestinationAddImage(dest, cg, nil)
            guard CGImageDestinationFinalize(dest) else { throw ExportError.frameExtractionFailed }
            framePaths.append(path.path)
        }
        guard !framePaths.isEmpty else { throw ExportError.frameExtractionFailed }

        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("sniploop-out-\(UUID().uuidString).gif")
        let args = GifskiCommand.arguments(framePaths: framePaths, outputPath: outURL.path, fps: spec.fps, quality: quality, width: spec.maxWidth)

        let proc = Process()
        proc.executableURL = gifskiURL
        proc.arguments = args
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw ExportError.gifskiFailed(proc.terminationStatus) }
        return outURL
    }

    /// Export an MP4 from the master using the EditSpec (identity = passthrough of the whole clip).
    func exportMP4(master: URL, spec: EditSpec) async throws -> URL {
        let asset = AVURLAsset(url: master)
        let preset = spec.isTrimOnly ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw ExportError.mp4Failed }
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("sniploop-out-\(UUID().uuidString).mp4")
        session.outputURL = outURL
        session.outputFileType = .mp4
        let start = CMTime(seconds: spec.startSeconds, preferredTimescale: 600)
        let dur = CMTime(seconds: spec.durationSeconds, preferredTimescale: 600)
        session.timeRange = CMTimeRange(start: start, duration: dur)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }
        guard session.status == .completed else { throw ExportError.mp4Failed }
        return outURL
    }
}
```

Note: crop/scale beyond `maxWidth` (passed to gifski via `--width`) is intentionally deferred to the editor plan. With an identity spec, `cropPixels` is nil and `maxWidth` is nil, so this exports the full clip at source size, which is the goal for this slice.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: compiles.

- [ ] **Step 3: Commit**

```bash
git add Sources/Sniploop/Exporter.swift
git commit -m "feat(app): Exporter (gifski GIF + AVFoundation MP4) over an EditSpec"
```

---

## Task 18: Output (save / reveal / clipboard) and export-on-stop

**Files:**
- Create: `Sources/Sniploop/Output.swift`
- Modify: `Sources/Sniploop/AppController.swift`

- [ ] **Step 1: Create `Output.swift`**

```swift
import AppKit
import SniploopCore

enum Output {
    /// Move a produced file into the destination folder under a timestamped name; returns the final URL.
    static func save(_ produced: URL, toFolder folder: String, ext: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSString(string: folder).expandingTildeInPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(OutputNaming.filename(date: Date(), ext: ext))
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: produced, to: dest)
        return dest
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Put an animated GIF on the pasteboard (data + a file URL for apps that prefer files).
    static func copyGIFToClipboard(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")
        if let data = try? Data(contentsOf: url) {
            pb.setData(data, forType: gifType)
        }
        pb.writeObjects([url as NSURL])
    }
}
```

- [ ] **Step 2: Replace `handleMaster` in `AppController` to export and save**

Add a property:
```swift
    private let exporter = Exporter()
```

Replace `handleMaster(_:)`:
```swift
    private func handleMaster(_ url: URL?) {
        guard let master = url else { return }
        Task {
            do {
                let movDuration = try await AVURLAsset(url: master).load(.duration).seconds
                let spec = EditSpec.identity(duration: movDuration, fps: 15)

                let gif = try await exporter.exportGIF(master: master, spec: spec)
                let savedGIF = try Output.save(gif, toFolder: Settings.defaults.destinationFolderPath, ext: "gif")

                await MainActor.run {
                    Output.copyGIFToClipboard(savedGIF)
                    Output.reveal(savedGIF)
                    NSLog("Sniploop: GIF saved + copied at \(savedGIF.path)")
                }
                try? FileManager.default.removeItem(at: master)
            } catch {
                await MainActor.run {
                    let a = NSAlert()
                    a.messageText = "Export failed"
                    a.informativeText = "\(error)"
                    a.runModal()
                }
            }
        }
    }
```

Add `import AVFoundation` at the top of `AppController.swift` if not present.

- [ ] **Step 3: Build and verify the full slice**

Run: `brew install gifski` (if not already), then `./build.sh && open Sniploop.app`
Manual verification:
- Trigger, select, record a few seconds with on-screen motion, Stop.
- A `Capture-<timestamp>.gif` appears on the Desktop and Finder reveals it. It plays as an animation, visibly cleaner than the POC's system-encoder GIF.
- Paste (Cmd-V) into Slack, Notion, Gmail, and a Jira comment. Record which render the animation vs a static frame (open decision 1 in the PRD).
- Confirm the temp `.mov` and temp frame dir are gone after export.

- [ ] **Step 4: Commit**

```bash
git add Sources/Sniploop/Output.swift Sources/Sniploop/AppController.swift
git commit -m "feat(app): export GIF on stop, save to Desktop, reveal, copy to clipboard"
```

---

## Task 19: Add MP4 save alongside GIF

**Files:**
- Modify: `Sources/Sniploop/AppController.swift`

For this slice, also produce the MP4 so both outputs exist (the editor plan will let the user choose; here we save both to prove the pipeline).

- [ ] **Step 1: Extend `handleMaster` to also export + save MP4**

Inside the `do` block in `handleMaster`, after the GIF save and before removing the master, add:
```swift
                let mp4 = try await exporter.exportMP4(master: master, spec: spec)
                let savedMP4 = try Output.save(mp4, toFolder: Settings.defaults.destinationFolderPath, ext: "mp4")
                await MainActor.run { NSLog("Sniploop: MP4 saved at \(savedMP4.path)") }
```

- [ ] **Step 2: Build and verify**

Run: `./build.sh && open Sniploop.app`
Manual verification:
- After a capture, both `Capture-<timestamp>.gif` and `Capture-<timestamp>.mp4` are on the Desktop.
- The MP4 plays in QuickTime and matches the captured region; it is much smaller than the GIF.

- [ ] **Step 3: Commit**

```bash
git add Sources/Sniploop/AppController.swift
git commit -m "feat(app): also export and save MP4 for each capture"
```

---

## Task 20: Retire the POC and finalize the slice

**Files:**
- Delete: `Sniploop.swift` (the single-file POC)

- [ ] **Step 1: Remove the POC source**

```bash
git rm Sniploop.swift
```

- [ ] **Step 2: Full verification pass**

Run: `swift test && ./build.sh && open Sniploop.app`
Manual verification:
- All `SniploopCore` tests pass.
- Cold path works end to end: Hyper+G (and `open sniploop://capture`) → dim overlay → drag → blue glow box → Enter (or Shift quick mode) → Stop pill → GIF + MP4 on Desktop, GIF on clipboard, Finder reveals the GIF.
- Esc cancels the overlay; Cancel discards a recording with no files left behind.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: retire single-file POC; foundation slice complete"
```

---

## Self-Review Notes (for the executor)

- **Run `swift test` after every core task.** The whole point of the architecture is that the core stays green continuously.
- **Build via `./build.sh` and run `Sniploop.app`, never `swift run`,** for any task that touches capture, hotkeys, or the URL scheme. TCC and URL registration need the bundle identity.
- **First capture will prompt for Screen Recording.** Grant it, then relaunch. If a rebuild changes signing identity, macOS may re-prompt.
- **gifski must be on PATH at build time** so `build.sh` can embed it. `brew install gifski`.

## What this plan deliberately leaves for follow-on plans

- **M3 (editor):** trim/fps/crop UI, applying a non-identity `EditSpec` (the Exporter already accepts crop/scale fields; the editor plan fills the crop path in `exportGIF` and adds an `AVVideoComposition` for preview), keyboard shortcuts + cheatsheet, choose-your-export bar, estimated size.
- **M4 (settings + distribution):** Settings window backed by `SettingsManager` (swap `Settings.defaults` for loaded settings throughout `AppController`), `UserDefaults: SettingsStore` conformance, last-region recall using `lastSelection`, launch-at-login, multi-display overlay, GPL-3.0 LICENSE + README, Developer ID + notarization in `build.sh`.
