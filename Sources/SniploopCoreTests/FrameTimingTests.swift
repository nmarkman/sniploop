import SniploopCore

func runFrameTimingTests() {
    T.eq(FrameTiming.sampleTimes(duration: 1.0, fps: 4), [0.0, 0.25, 0.5, 0.75], "sampleTimes spaced by fps")
    T.eq(FrameTiming.sampleTimes(duration: 0, fps: 15), [], "zero duration is empty")
    T.eq(FrameTiming.sampleTimes(duration: 5, fps: 0), [], "zero fps is empty")
}
