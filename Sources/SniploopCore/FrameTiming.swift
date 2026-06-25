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
