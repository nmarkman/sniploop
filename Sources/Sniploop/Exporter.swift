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
