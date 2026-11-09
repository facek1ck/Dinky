import CoreGraphics
import Foundation

/// A settled focus destination. Identity includes the window and Space so changes on one display also
/// cancel an older pending move. Empty workspaces use the display model's explicit focus override.
struct MouseFocusDestination: Equatable {
    let display: String
    let space: UInt64
    let window: UInt32
    let frame: CGRect

    static func resolve(displays: [Display], override: String?, window: UInt32,
                        windowDisplay: Display?, windowSpace: UInt64) -> Self? {
        if let override, let display = displays.first(where: { $0.uuid == override }) {
            return Self(display: display.uuid, space: display.currentSpaceID, window: 0, frame: display.frame)
        }
        guard override == nil, window != 0, let display = windowDisplay,
              windowSpace == display.currentSpaceID else { return nil }
        return Self(display: display.uuid, space: display.currentSpaceID, window: window, frame: display.frame)
    }
}

/// Pure settling policy; the app supplies actual AX focus, CG coordinates and swipe state.
struct MouseFocusPolicy {
    private var initialized = false
    private var previous: MouseFocusDestination?
    private var lastDisplay: String?
    private var lastPointer: CGPoint?
    private var waitingPointer: CGPoint?
    private var pending: (target: MouseFocusDestination, point: CGPoint, since: TimeInterval)?

    mutating func reset() { self = MouseFocusPolicy() }

    mutating func sample(_ target: MouseFocusDestination?, pointer: CGPoint, now: TimeInterval,
                         enabled: Bool, switching: Bool, blocked: Bool) -> CGPoint? {
        guard enabled else { reset(); return nil }
        // Native swipes pump the main run loop while the pointer is temporarily on their display.
        // Never sample that temporary placement or warp before the restoration has completed.
        guard !switching else {
            if waitingPointer == nil { waitingPointer = lastPointer ?? pointer }
            pending?.since = now
            return nil
        }
        let wasWaiting = waitingPointer != nil
        let movedWhileWaiting = waitingPointer.map { hypot(pointer.x - $0.x, pointer.y - $0.y) >= 2 } ?? false
        waitingPointer = nil
        lastPointer = pointer
        guard initialized else {
            initialized = true
            previous = target
            lastDisplay = target?.display
            return nil
        }
        if target != previous {
            previous = target
            if let target {
                if target.display != lastDisplay || pending != nil { pending = (target, pointer, now) }
                lastDisplay = target.display
            } else if pending != nil {
                // AX can briefly have no focused window during a transition. Keep the candidate,
                // but require another full settle interval after focus becomes readable again.
                pending?.since = now
            }
        }
        if wasWaiting { pending?.since = now }
        if movedWhileWaiting { pending = nil }
        guard let candidate = pending else { return nil }
        guard !blocked, hypot(pointer.x - candidate.point.x, pointer.y - candidate.point.y) < 2 else {
            pending = nil
            return nil
        }
        guard target != nil, now - candidate.since >= 0.1 else { return nil }
        pending = nil
        guard !candidate.target.frame.contains(pointer) else { return nil }
        return CGPoint(x: candidate.target.frame.midX, y: candidate.target.frame.midY)
    }
}
