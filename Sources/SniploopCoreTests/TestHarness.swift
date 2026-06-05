import Foundation

/// Minimal stdlib-only test harness. XCTest and the Testing framework are unavailable
/// under CommandLineTools (they ship with Xcode), so tests are plain functions that call
/// these check helpers. The runner exits 0 when every check passed (green) and 1 when any
/// check failed (red), which gives a real red/green TDD signal via `swift run SniploopCoreTests`.
enum T {
    static var failures = 0
    static var checks = 0

    static func ok(_ condition: Bool, _ message: String, file: StaticString = #fileID, line: UInt = #line) {
        checks += 1
        if !condition {
            failures += 1
            print("FAIL [\(file):\(line)] \(message)")
        }
    }

    static func eq<V: Equatable>(_ a: V, _ b: V, _ label: String = "", file: StaticString = #fileID, line: UInt = #line) {
        ok(a == b, label.isEmpty ? "\(a) != \(b)" : "\(label): \(a) != \(b)", file: file, line: line)
    }

    static func close(_ a: Double, _ b: Double, _ tol: Double = 1e-9, _ label: String = "", file: StaticString = #fileID, line: UInt = #line) {
        ok(abs(a - b) <= tol, label.isEmpty ? "\(a) not within \(tol) of \(b)" : "\(label): \(a) vs \(b)", file: file, line: line)
    }

    static func finish() -> Never {
        if failures == 0 {
            print("ALL PASSED (\(checks) checks)")
            exit(0)
        }
        print("\(failures) FAILURE(S) of \(checks) checks")
        exit(1)
    }
}
