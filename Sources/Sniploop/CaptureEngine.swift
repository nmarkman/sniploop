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
