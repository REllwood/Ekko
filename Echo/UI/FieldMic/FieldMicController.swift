import AppKit
import Observation
import SwiftUI

/// Shows a small clickable mic beside the focused text field in any app.
///
/// Visible when `settings.showFieldMic`, Accessibility is granted and `FocusTracker` reports an
/// editable target. While a dictation is running (however it started) the mic stays at its last
/// position even if focus info flickers, so it can always be clicked to stop.
@MainActor
final class FieldMicController {
    private let container: AppContainer
    private let model = FieldMicModel()
    private var panel: FieldMicPanel?
    private var isStarted = false
    /// Bumped on every start so a stale observation callback can't re-arm a second loop.
    private var generation = 0
    /// Whether the mic should be on screen; the panel may still be fading out when false.
    private var isShown = false
    private var panelFrame: NSRect?
    private var hideTask: Task<Void, Never>?
    private var wasDictationVisible = false
    private var dictationEndedAt: TimeInterval = 0

    /// Focus often disappears for a moment while it moves between fields.
    static let hideGrace: TimeInterval = 0.15
    static let fadeDuration: TimeInterval = 0.12
    static let moveDuration: TimeInterval = 0.12
    /// Moves longer than this jump instead of gliding.
    static let jumpDistance: CGFloat = 200
    /// Text changes this soon after a dictation are Echo's own insertion, not typing.
    static let insertionQuietPeriod: TimeInterval = 1.0

    init(container: AppContainer) {
        self.container = container
    }

    /// Begins observing `settings.showFieldMic`, permissions, focus and dictation state.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        generation += 1
        observe(generation: generation)
        sync()
        Log.ui.info("Field mic controller started")
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        generation += 1
        hide(animated: false)
        container.focusTracker.stop()
        Log.ui.info("Field mic controller stopped")
    }

    // MARK: - Observation

    private func observe(generation: Int) {
        withObservationTracking {
            _ = container.settings.showFieldMic
            _ = container.permissions.accessibility
            _ = container.focusTracker.isRunning
            _ = container.focusTracker.target
            _ = container.focusTracker.isUserTyping
            _ = container.dictation.state
            _ = model.isHovering
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted, self.generation == generation else { return }
                self.sync()
                self.observe(generation: generation)
            }
        }
    }

    #if DEBUG
    /// Debug-only (`--demo-field-mic`): pretend this field has focus, without Accessibility.
    static var debugTarget: EditableTarget?
    #endif

    private func sync() {
        #if DEBUG
        if let debugTarget = Self.debugTarget {
            _ = show(at: debugTarget)
            return
        }
        #endif
        let settings = container.settings
        let tracker = container.focusTracker
        let wantsTracking = settings.showFieldMic && container.permissions.accessibility == .granted
        if wantsTracking, !tracker.isRunning {
            tracker.start()
        } else if !wantsTracking, tracker.isRunning {
            tracker.stop()
        }

        let state = container.dictation.state
        let dictationVisible = Self.keepsMicVisible(state)
        if wasDictationVisible, !dictationVisible { dictationEndedAt = Self.now }
        wasDictationVisible = dictationVisible

        guard settings.showFieldMic, tracker.isRunning else {
            hide(animated: true)
            return
        }
        if let target = tracker.target, show(at: target) {
            cancelHide()
        } else if dictationVisible, isShown {
            cancelHide()
        } else {
            scheduleHide()
        }
        updateDimming(state: state)
    }

    /// States in which the mic holds its place: it is the stop button, then shows the outcome.
    private static func keepsMicVisible(_ state: DictationState) -> Bool {
        if case .failed = state { return true }
        return state.isActive
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func updateDimming(state: DictationState) {
        let insertedRecently = Self.now - dictationEndedAt < Self.insertionQuietPeriod
        let dim = container.focusTracker.isUserTyping && state == .idle && !model.isHovering && !insertedRecently
        if model.isDimmed != dim { model.isDimmed = dim }
    }

    // MARK: - Showing and hiding

    /// Places the mic for `target`. Returns false when no part of the element is on screen.
    private func show(at target: EditableTarget) -> Bool {
        guard let frame = Self.panelFrame(for: target) else { return false }
        let panel = existingPanel()
        if isShown {
            move(panel, to: frame)
        } else {
            appear(panel, at: frame)
        }
        return true
    }

    /// Where the panel goes for `target`, or nil when no part of the element is on screen
    /// (scrolled away, or its window moved off every display).
    private static func panelFrame(for target: EditableTarget) -> NSRect? {
        let screens = NSScreen.screens.map { FieldMicPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let buttonSize = CGSize(width: FieldMicView.diameter, height: FieldMicView.diameter)
        guard let screen = FieldMicPlacement.screen(for: target, in: screens),
              let origin = FieldMicPlacement.buttonOrigin(for: target, on: screen, buttonSize: buttonSize) else {
            return nil
        }
        return NSRect(
            x: (origin.x - FieldMicView.margin).rounded(),
            y: (origin.y - FieldMicView.margin).rounded(),
            width: FieldMicView.panelSize.width,
            height: FieldMicView.panelSize.height
        )
    }

    private func appear(_ panel: FieldMicPanel, at frame: NSRect) {
        installContentIfNeeded(in: panel)
        isShown = true
        panelFrame = frame
        panel.setFrame(frame, display: false)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 1
        }
        Log.ui.debug("Field mic shown")
    }

    private func move(_ panel: FieldMicPanel, to frame: NSRect) {
        guard let current = panelFrame else {
            panelFrame = frame
            panel.setFrame(frame, display: true)
            return
        }
        guard current != frame else { return }
        panelFrame = frame
        let distance = hypot(frame.minX - current.minX, frame.minY - current.minY)
        if distance > Self.jumpDistance || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.moveDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    private func scheduleHide() {
        guard isShown, hideTask == nil else { return }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.hideGrace * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.hideTask = nil
            // Hide unless the mic can be placed again (not merely "a target exists": the field may
            // have scrolled out of view) or a dictation is holding it in place.
            let dictationVisible = Self.keepsMicVisible(self.container.dictation.state)
            let placeable = self.container.focusTracker.target.flatMap(Self.panelFrame(for:)) != nil
            if !placeable, !dictationVisible {
                self.hide(animated: true)
            }
        }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    private func hide(animated: Bool) {
        cancelHide()
        guard isShown else { return }
        isShown = false
        panelFrame = nil
        model.isHovering = false
        model.isPressed = false
        model.isDimmed = false
        guard let panel else { return }
        guard animated else {
            finishHide()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishHide() }
        })
    }

    /// Orders the panel out once faded, unless it was asked back in the meantime. Dropping the
    /// hosting view stops SwiftUI from observing dictation state while nothing is on screen.
    private func finishHide() {
        guard !isShown, let panel else { return }
        panel.orderOut(nil)
        panel.contentView = nil
        Log.ui.debug("Field mic hidden")
    }

    // MARK: - Panel

    private func existingPanel() -> FieldMicPanel {
        if let panel { return panel }
        let created = FieldMicPanel(size: FieldMicView.panelSize)
        panel = created
        return created
    }

    private func installContentIfNeeded(in panel: FieldMicPanel) {
        guard !(panel.contentView is FieldMicHostingView) else { return }
        let view = FieldMicView(container: container, model: model) { [weak self] in
            self?.toggleDictation()
        }
        let hosting = FieldMicHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: FieldMicView.panelSize)
        hosting.hitRadius = FieldMicView.diameter / 2 + 2
        hosting.onHover = { [weak self] hovering in self?.model.isHovering = hovering }
        hosting.onPress = { [weak self] pressed in self?.model.isPressed = pressed }
        hosting.onClick = { [weak self] in self?.toggleDictation() }
        panel.contentView = hosting
    }

    /// Start when idle, stop-and-transcribe when listening. The panel never takes focus, so the
    /// text field that was focused before the click is still where the transcript lands.
    private func toggleDictation() {
        Log.ui.info("Field mic clicked")
        container.dictation.toggle()
    }
}
