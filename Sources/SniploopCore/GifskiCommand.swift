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
