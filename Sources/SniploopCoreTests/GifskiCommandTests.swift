import SniploopCore

func runGifskiCommandTests() {
    T.eq(GifskiCommand.arguments(framePaths: ["/tmp/f/0001.png", "/tmp/f/0002.png"],
                                 outputPath: "/tmp/out.gif", fps: 15, quality: 90, width: nil),
         ["--fps", "15", "--quality", "90", "-o", "/tmp/out.gif", "/tmp/f/0001.png", "/tmp/f/0002.png"],
         "builds fps/quality/output/frames, no width")

    T.eq(GifskiCommand.arguments(framePaths: ["/tmp/f/0001.png"],
                                 outputPath: "/tmp/out.gif", fps: 10, quality: 80, width: 640),
         ["--fps", "10", "--quality", "80", "--width", "640", "-o", "/tmp/out.gif", "/tmp/f/0001.png"],
         "includes width when provided")
}
