import CoreGraphics
import SniploopCore

func runSelectionMachineTests() {
    // drag then release (no quick) -> confirming
    var m = SelectionMachine()
    m.handle(.dragBegan(CGPoint(x: 0, y: 0)))
    m.handle(.dragChanged(CGRect(x: 0, y: 0, width: 50, height: 40)))
    m.handle(.dragEnded(rect: CGRect(x: 0, y: 0, width: 50, height: 40), quickModifier: false))
    T.ok(m.phase == .confirming(CGRect(x: 0, y: 0, width: 50, height: 40)), "drag+release -> confirming")

    // confirm from confirming -> recording
    var m2 = SelectionMachine()
    m2.handle(.dragBegan(.zero))
    m2.handle(.dragEnded(rect: CGRect(x: 0, y: 0, width: 50, height: 40), quickModifier: false))
    m2.handle(.confirm)
    T.ok(m2.phase == .recording(CGRect(x: 0, y: 0, width: 50, height: 40)), "confirm -> recording")

    // quick modifier -> records immediately
    var m3 = SelectionMachine()
    m3.handle(.dragBegan(.zero))
    m3.handle(.dragEnded(rect: CGRect(x: 0, y: 0, width: 50, height: 40), quickModifier: true))
    T.ok(m3.phase == .recording(CGRect(x: 0, y: 0, width: 50, height: 40)), "quick modifier -> recording")

    // tiny drag -> idle
    var m4 = SelectionMachine()
    m4.handle(.dragBegan(.zero))
    m4.handle(.dragEnded(rect: CGRect(x: 0, y: 0, width: 2, height: 2), quickModifier: false))
    T.ok(m4.phase == .idle, "tiny drag -> idle")

    // re-drag from confirming replaces selection
    var m5 = SelectionMachine()
    m5.handle(.dragBegan(.zero))
    m5.handle(.dragEnded(rect: CGRect(x: 0, y: 0, width: 50, height: 40), quickModifier: false))
    m5.handle(.dragBegan(CGPoint(x: 100, y: 100)))
    T.ok(m5.phase == .dragging(CGRect(x: 100, y: 100, width: 0, height: 0)), "re-drag replaces")

    // cancel from anywhere
    var m6 = SelectionMachine()
    m6.handle(.dragBegan(.zero))
    m6.handle(.cancel)
    T.ok(m6.phase == .cancelled, "cancel -> cancelled")

    // confirm from idle ignored
    var m7 = SelectionMachine()
    m7.handle(.confirm)
    T.ok(m7.phase == .idle, "confirm from idle ignored")
}
