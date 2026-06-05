import CoreGraphics

public enum SelectionPhase: Equatable {
    case idle
    case dragging(CGRect)
    case confirming(CGRect)
    case recording(CGRect)
    case cancelled
}

public enum SelectionEvent: Equatable {
    case dragBegan(CGPoint)
    case dragChanged(CGRect)
    case dragEnded(rect: CGRect, quickModifier: Bool)
    case confirm
    case cancel
}

public struct SelectionMachine {
    public private(set) var phase: SelectionPhase = .idle
    public let minSize: CGFloat

    public init(minSize: CGFloat = 5) {
        self.minSize = minSize
    }

    public mutating func handle(_ event: SelectionEvent) {
        if case .cancel = event {
            phase = .cancelled
            return
        }
        switch (phase, event) {
        case (.idle, .dragBegan(let p)), (.confirming, .dragBegan(let p)):
            phase = .dragging(CGRect(origin: p, size: .zero))
        case (.dragging, .dragChanged(let r)):
            phase = .dragging(r)
        case (.dragging, .dragEnded(let rect, let quick)):
            if rect.width < minSize || rect.height < minSize {
                phase = .idle
            } else {
                phase = quick ? .recording(rect) : .confirming(rect)
            }
        case (.confirming(let r), .confirm):
            phase = .recording(r)
        default:
            break // ignore invalid transitions
        }
    }
}
