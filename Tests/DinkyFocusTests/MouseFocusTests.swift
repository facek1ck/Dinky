import CoreGraphics
import Testing
@testable import dinky

struct MouseFocusTests {
    private let left = MouseFocusDestination(display: "left", space: 1, window: 10,
                                            frame: CGRect(x: -1600, y: -300, width: 1600, height: 1000))
    private let right = MouseFocusDestination(display: "right", space: 2, window: 20,
                                             frame: CGRect(x: 0, y: 0, width: 2000, height: 1200))
    private let pointer = CGPoint(x: -100, y: 100)

    private func sample(_ policy: inout MouseFocusPolicy, _ target: MouseFocusDestination?, _ now: Double,
                        point: CGPoint? = nil, enabled: Bool = true, switching: Bool = false,
                        blocked: Bool = false) -> CGPoint? {
        policy.sample(target, pointer: point ?? pointer, now: now, enabled: enabled,
                      switching: switching, blocked: blocked)
    }

    @Test func defaultOffAndStartupDoNotWarp() {
        var policy = MouseFocusPolicy()
        #expect(sample(&policy, left, 0, enabled: false) == nil)
        #expect(sample(&policy, right, 1, enabled: false) == nil)
        #expect(sample(&policy, right, 2, enabled: false) == nil)
        #expect(sample(&policy, right, 3) == nil)
        #expect(sample(&policy, right, 4) == nil)
    }

    @Test func crossDisplayFocusSettlesAndWarpsOnlyOnce() {
        var policy = MouseFocusPolicy()
        #expect(sample(&policy, left, 0) == nil)
        #expect(sample(&policy, right, 1) == nil)
        #expect(sample(&policy, right, 1.05) == nil)
        #expect(sample(&policy, right, 1.2) == CGPoint(x: 1000, y: 600))
        #expect(sample(&policy, right, 2) == nil)
    }

    @Test func sameDisplayWindowAndSpaceChangesPreservePointerEvenElsewhere() {
        var policy = MouseFocusPolicy()
        #expect(sample(&policy, right, 0) == nil)
        let next = MouseFocusDestination(display: "right", space: 3, window: 30, frame: right.frame)
        #expect(sample(&policy, next, 1) == nil)
        #expect(sample(&policy, next, 2) == nil)
    }

    @Test func pointerAlreadyOnDestinationIsUntouched() {
        var policy = MouseFocusPolicy()
        #expect(sample(&policy, left, 0) == nil)
        let point = CGPoint(x: 30, y: 80)
        #expect(sample(&policy, right, 1, point: point) == nil)
        #expect(sample(&policy, right, 2, point: point) == nil)
    }

    @Test func visibleWorkspaceAndEmptyMonitorNeedNoSwipe() {
        for window: UInt32 in [0, 20] {
            var policy = MouseFocusPolicy()
            let chosen = MouseFocusDestination(display: "right", space: 2, window: window, frame: right.frame)
            #expect(sample(&policy, left, 0) == nil)
            #expect(sample(&policy, chosen, 1) == nil)
            #expect(sample(&policy, chosen, 2) == CGPoint(x: 1000, y: 600))
        }
    }

    @Test func swipeTemporaryPointerAndRestorationCannotUndoFollow() {
        var policy = MouseFocusPolicy()
        #expect(sample(&policy, left, 0) == nil)
        // The native swipe moves the pointer temporarily, pumping the main run loop.
        #expect(sample(&policy, right, 1, point: CGPoint(x: 1000, y: 600), switching: true) == nil)
        #expect(sample(&policy, right, 2, switching: true) == nil)
        // Restoration precedes landing; settling starts only after the flight ends.
        #expect(sample(&policy, right, 3) == nil)
        #expect(sample(&policy, right, 3.2) == CGPoint(x: 1000, y: 600))
    }

    @Test func activationWaitsForFinalFocusedWindow() {
        var policy = MouseFocusPolicy()
        #expect(sample(&policy, left, 0) == nil)
        #expect(sample(&policy, right, 1, switching: true) == nil)
        #expect(sample(&policy, left, 1.1, switching: true) == nil)
        #expect(sample(&policy, right, 1.4) == nil)
        #expect(sample(&policy, right, 1.6) == CGPoint(x: 1000, y: 600))
    }

    @Test func lateActivationNotificationDoesNotDiscardPendingDisplayChange() {
        var policy = MouseFocusPolicy()
        #expect(sample(&policy, left, 0) == nil)
        #expect(sample(&policy, right, 1) == nil)
        #expect(sample(&policy, right, 1.05, switching: true) == nil)
        #expect(sample(&policy, right, 1.4, switching: true) == nil)
        #expect(sample(&policy, right, 1.5) == nil)
        #expect(sample(&policy, right, 1.7) == CGPoint(x: 1000, y: 600))
        #expect(sample(&policy, right, 2) == nil)
    }

    @Test func transientMissingAXFocusWaitsForAReadableDestination() {
        var policy = MouseFocusPolicy()
        #expect(sample(&policy, left, 0) == nil)
        #expect(sample(&policy, right, 1) == nil)
        #expect(sample(&policy, nil, 1.05) == nil)
        #expect(sample(&policy, nil, 2) == nil)
        #expect(sample(&policy, right, 3) == nil)
        #expect(sample(&policy, right, 3.2) == CGPoint(x: 1000, y: 600))
    }

    @Test func physicalMovementCancelsPendingMoveAndDoesNotRearm() {
        var policy = MouseFocusPolicy()
        #expect(sample(&policy, left, 0) == nil)
        #expect(sample(&policy, right, 1) == nil)
        let moved = CGPoint(x: -150, y: 120)
        #expect(sample(&policy, right, 1.1, point: moved) == nil)
        #expect(sample(&policy, right, 2, point: moved) == nil)
    }

    @Test func movementDuringSwipeOrActivationAlsoCancels() {
        var policy = MouseFocusPolicy()
        #expect(sample(&policy, left, 0) == nil)
        #expect(sample(&policy, right, 1, switching: true) == nil)
        let moved = CGPoint(x: -150, y: 120)
        #expect(sample(&policy, right, 2, point: moved) == nil)
        #expect(sample(&policy, right, 3, point: moved) == nil)
    }

    @Test func rapidRetargetAndNegativeCoordinatesUseFinalDisplay() {
        var policy = MouseFocusPolicy()
        let point = CGPoint(x: 500, y: 500)
        #expect(sample(&policy, right, 0, point: point) == nil)
        #expect(sample(&policy, left, 1, point: point) == nil)
        #expect(sample(&policy, right, 1.05, point: point) == nil)
        #expect(sample(&policy, left, 1.1, point: point) == nil)
        #expect(sample(&policy, left, 1.3, point: point) == CGPoint(x: -800, y: 200))
        #expect(sample(&policy, left, 2, point: point) == nil)
    }

    @Test func dragAndMissionControlCancelMove() {
        var policy = MouseFocusPolicy()
        #expect(sample(&policy, left, 0) == nil)
        #expect(sample(&policy, right, 1, blocked: true) == nil)
        #expect(sample(&policy, right, 2) == nil)
    }
}

struct MouseFocusDestinationTests {
    private func display(_ name: String, _ space: UInt64, x: CGFloat) -> Display {
        Display(uuid: name, id: UInt32(space), frame: CGRect(x: x, y: 0, width: 1000, height: 800),
                isMain: space == 1, spaces: [space, space + 10], userSpaces: [space, space + 10], currentSpaceID: space)
    }

    @Test func actualFocusedWindowWinsForAnAppWithWindowsOnBothDisplays() {
        let main = display("main", 1, x: 0)
        let secondary = display("secondary", 2, x: 1000)
        // The active app also has window 10 on main. AX says window 20 is focused.
        let target = MouseFocusDestination.resolve(displays: [main, secondary], override: nil,
                                                  window: 20, windowDisplay: secondary, windowSpace: 2)
        #expect(target?.display == "secondary")
        #expect(target?.window == 20)
        #expect(target?.frame.midX == 1500)
    }

    @Test func emptyWorkspaceOverrideWinsOverStaleWindowOnAnotherDisplay() {
        let main = display("main", 1, x: 0)
        let secondary = display("secondary", 2, x: 1000)
        let target = MouseFocusDestination.resolve(displays: [main, secondary], override: "secondary",
                                                  window: 10, windowDisplay: main, windowSpace: 1)
        #expect(target?.display == "secondary")
        #expect(target?.window == 0)
        #expect(target?.space == 2)
    }

    @Test func invisibleWindowAndMissingOverrideDoNotPickAnArbitraryDisplay() {
        let main = display("main", 1, x: 0)
        #expect(MouseFocusDestination.resolve(displays: [main], override: nil, window: 10,
                                             windowDisplay: main, windowSpace: 11) == nil)
        #expect(MouseFocusDestination.resolve(displays: [main], override: nil, window: 0,
                                             windowDisplay: nil, windowSpace: 0) == nil)
        #expect(MouseFocusDestination.resolve(displays: [main], override: "disconnected", window: 10,
                                             windowDisplay: main, windowSpace: 1) == nil)
    }
}
