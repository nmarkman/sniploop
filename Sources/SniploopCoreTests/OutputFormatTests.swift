import SniploopCore

func runOutputFormatTests() {
    T.ok(OutputFormat.gif.producesGIF && !OutputFormat.gif.producesMP4, "gif produces gif only")
    T.ok(!OutputFormat.mp4.producesGIF && OutputFormat.mp4.producesMP4, "mp4 produces mp4 only")
    T.ok(OutputFormat.both.producesGIF && OutputFormat.both.producesMP4, "both produces both")
    T.eq(Settings.defaults.defaultFormat, OutputFormat.gif, "default format is gif")
}
