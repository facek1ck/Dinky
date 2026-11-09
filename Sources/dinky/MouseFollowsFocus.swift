import AppKit
import DinkyPrivate

/// Observes actual focus, including same-app window changes and activations which need no Space swipe.
/// A short common-mode timer also catches AX focus settling after WindowServer's notifications.
final class MouseFocus {
    private var policy = MouseFocusPolicy()
    private var timer: Timer?
    private var activationUntil: TimeInterval = 0

    func update(enabled: Bool) {
        policy.reset()
        guard enabled else { timer?.invalidate(); timer = nil; return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func activated() {
        // ActivationFollower gives a new window 250 ms before deciding whether to switch Spaces.
        activationUntil = ProcessInfo.processInfo.systemUptime + 0.35
    }

    private func sample() {
        let state = AppState.shared
        guard let pointer = CGEvent(source: nil)?.location else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let waiting = SpaceSwitcher.shared.switching || now < activationUntil
        if waiting {
            _ = policy.sample(nil, pointer: pointer, now: now,
                              enabled: state.enabled && state.config.mouseFollowsFocus,
                              switching: true, blocked: false)
            return
        }
        let model = state.displays
        let window = frontWindowID(timeout: 0.05)
        let destination = MouseFocusDestination.resolve(displays: model.displays, override: model.focusOverride,
                                                       window: window, windowDisplay: model.display(ofWindow: window),
                                                       windowSpace: dinky_window_space_id(window))
        let blocked = MissionControl.shared.active ||
            CGEventSource.buttonState(.combinedSessionState, button: .left) ||
            CGEventSource.buttonState(.combinedSessionState, button: .right)
        guard let point = policy.sample(destination, pointer: pointer, now: now,
                                        enabled: state.enabled && state.config.mouseFollowsFocus,
                                        switching: waiting, blocked: blocked) else { return }
        // AX can take a moment to answer; do not overwrite a move made while it was answering.
        guard let current = CGEvent(source: nil)?.location,
              hypot(current.x - pointer.x, current.y - pointer.y) < 2,
              dinky_warp_mouse(point) else { return }
        state.parkHover(afterWarpTo: point)
    }
}
