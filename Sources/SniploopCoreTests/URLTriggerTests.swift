import Foundation
import SniploopCore

func runURLTriggerTests() {
    T.ok(URLTrigger.action(from: URL(string: "sniploop://capture")!) == .newCapture, "capture URL maps to newCapture")
    T.ok(URLTrigger.action(from: URL(string: "https://capture")!) == nil, "wrong scheme is nil")
    T.ok(URLTrigger.action(from: URL(string: "sniploop://nope")!) == nil, "unknown host is nil")
}
