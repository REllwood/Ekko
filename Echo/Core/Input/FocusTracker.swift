import AppKit
import ApplicationServices
import Foundation

/// The text field that currently has keyboard focus in the frontmost app, in AppKit global
/// coordinates (origin bottom-left of the primary display). Fixed contract.
struct EditableTarget: Equatable, Sendable {
    var appPID: pid_t
    var appBundleID: String?
    /// Frame of the focused editable element.
    var elementFrame: CGRect
    /// Frame of the insertion point / selection, when the app reports it.
    var caretRect: CGRect?
    /// Frame of the window that contains the element, when known.
    var windowFrame: CGRect?
    /// Text areas (multi-line) vs. single-line fields; drives mic placement.
    var isMultiline: Bool
}

/// Follows keyboard focus across apps with the Accessibility API and publishes the focused
/// editable text element, if any.
///
/// Notifications from an `AXObserver` on the frontmost app drive refreshes; a 0.5 s poll covers
/// apps that don't post them. Every AX call runs on `FocusTrackerWorker`'s serial queue, never on
/// the main thread, which also runs Echo's keyboard event tap. This side only decides when to read
/// (`FocusRefreshPolicy`: one read in flight, ≤ 30 Hz, ≤ 8 Hz while typing) and publishes results.
@Observable
@MainActor
final class FocusTracker {
    /// nil when nothing editable has focus, tracking is off, or Accessibility is not granted.
    private(set) var target: EditableTarget?
    private(set) var isRunning = false
    /// True while the focused field's text keeps changing (typing, or Echo inserting). Clears about
    /// `typingWindow` after the last change.
    private(set) var isUserTyping = false

    static let pollInterval: TimeInterval = 0.5
    static let typingWindow: TimeInterval = 0.8
    /// How long quitting Echo waits for AXManualAccessibility to be switched back off.
    private static let quitCleanupWait: TimeInterval = 1

    @ObservationIgnored private lazy var worker = FocusTrackerWorker(
        callback: focusTrackerCallback,
        refcon: Unmanaged.passUnretained(self).toOpaque()
    )
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var policy = FocusRefreshPolicy()
    @ObservationIgnored private var scheduledRead: DispatchWorkItem?
    /// What the next read must redo, gathered from notifications and polls.
    @ObservationIgnored private var nextRead = FocusTrackerWorker.ReadRequest()
    /// Bumped whenever the attached app changes, so a read that finishes late is dropped.
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var attachedPID: pid_t?
    /// The focused editable element as of the last read, to match notifications against.
    @ObservationIgnored private var focusedElement: AXUIElement?
    @ObservationIgnored private var lastTypingAt: TimeInterval = 0
    @ObservationIgnored private var busyUntil: TimeInterval = 0
    @ObservationIgnored private var busyStrikes = 0

    init() {}

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: - Lifecycle

    /// Starts following focus. Safe to call repeatedly; does nothing without Accessibility trust.
    func start() {
        guard AXIsProcessTrusted() else {
            if isRunning { stop() }
            return
        }
        guard !isRunning else { return }
        isRunning = true

        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.didActivateApplicationNotification, on: workspace) { tracker, note in
            tracker.attach(to: note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        observe(NSWorkspace.didTerminateApplicationNotification, on: workspace) { tracker, note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            tracker.applicationTerminated(app?.processIdentifier)
        }
        observe(NSApplication.willTerminateNotification, on: .default) { tracker, _ in
            tracker.shutDown(waitingUpTo: Self.quitCleanupWait)
        }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollTick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        attach(to: NSWorkspace.shared.frontmostApplication)
        Log.input.info("Focus tracking started")
    }

    /// Stops following focus and switches AXManualAccessibility back off in the apps Echo set it in.
    func stop() {
        shutDown(waitingUpTo: nil)
    }

    private func shutDown(waitingUpTo cleanupWait: TimeInterval?) {
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
        pollTimer?.invalidate()
        pollTimer = nil
        cancelScheduledRead()
        resetFocusState()
        if isRunning {
            isRunning = false
            worker.shutDown(waitingUpTo: cleanupWait)
            Log.input.info("Focus tracking stopped")
        }
        if isUserTyping { isUserTyping = false }
        publish(nil)
    }

    private func observe(
        _ name: Notification.Name,
        on center: NotificationCenter,
        _ handler: @escaping @MainActor (FocusTracker, Notification) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self, note)
            }
        }
        observers.append((center, token))
    }

    // MARK: - Following the frontmost app

    private func attach(to runningApp: NSRunningApplication?) {
        resetFocusState()
        publish(nil)
        guard isRunning else { return }
        guard let runningApp, !runningApp.isTerminated, runningApp.processIdentifier > 0,
              runningApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            worker.detach()
            return
        }
        attachedPID = runningApp.processIdentifier
        worker.attach(.init(
            pid: runningApp.processIdentifier,
            bundleID: runningApp.bundleIdentifier,
            bundleURL: runningApp.bundleURL
        ))
        requestRefresh(.prompt)
    }

    private func applicationTerminated(_ pid: pid_t?) {
        guard let pid else { return }
        worker.forget(pid: pid)
        guard attachedPID == pid else { return }
        resetFocusState()
        worker.detach()
        publish(nil)
    }

    /// Forgets everything about the attached app; reads still in flight are dropped on arrival.
    private func resetFocusState() {
        epoch += 1
        attachedPID = nil
        focusedElement = nil
        nextRead = FocusTrackerWorker.ReadRequest()
        busyUntil = 0
        busyStrikes = 0
    }

    // MARK: - Events

    fileprivate func handle(notification: String, element: AXUIElement) {
        guard isRunning else { return }
        let response = FocusRefreshPolicy.response(
            to: notification,
            isFocusedElement: focusedElement.map { CFEqual($0, element) } ?? false,
            focusedIsMultiline: target?.isMultiline ?? false
        )
        if response.focusedElementDestroyed {
            focusedElement = nil
            nextRead.forgetFocusedElement = true
            publish(nil)
        }
        if response.windowFrameIsStale { nextRead.windowFrameIsStale = true }
        if response.notesTyping { noteTyping() }
        if let urgency = response.refresh { requestRefresh(urgency) }
    }

    private func pollTick() {
        guard isRunning else { return }
        if isUserTyping, Self.now - lastTypingAt > Self.typingWindow { isUserTyping = false }
        nextRead.windowFrameIsStale = true
        nextRead.retryObserver = true
        requestRefresh(.prompt)
    }

    private func noteTyping() {
        lastTypingAt = Self.now
        if !isUserTyping { isUserTyping = true }
    }

    // MARK: - Reading

    private func requestRefresh(_ urgency: FocusRefreshPolicy.Urgency) {
        guard isRunning, let time = policy.request(urgency, now: Self.now) else { return }
        scheduledRead?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.scheduledReadFired() }
        }
        scheduledRead = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, time - Self.now), execute: item)
    }

    private func cancelScheduledRead() {
        scheduledRead?.cancel()
        scheduledRead = nil
        policy.clearSchedule()
    }

    private func scheduledReadFired() {
        scheduledRead = nil
        policy.clearSchedule()
        // While backing off from a busy app, the next poll asks again.
        guard isRunning, Self.now >= busyUntil else { return }

        var request = nextRead
        request.primaryScreenMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        nextRead = FocusTrackerWorker.ReadRequest()
        policy.readStarted(now: Self.now)
        let epoch = self.epoch
        worker.read(request) { [weak self] result in
            self?.readFinished(result, epoch: epoch)
        }
    }

    private func readFinished(_ result: FocusTrackerWorker.ReadResult, epoch: Int) {
        let followUp = policy.readFinished()
        if isRunning, epoch == self.epoch { apply(result) }
        if let followUp { requestRefresh(followUp) }
    }

    private func apply(_ result: FocusTrackerWorker.ReadResult) {
        switch result.outcome {
        case .busy:
            backOff()
            return
        case .noTarget:
            publish(nil)
        case .target(let newTarget):
            publish(newTarget)
        }
        busyStrikes = 0
        focusedElement = result.editableElement
        if result.textChanged { noteTyping() }
    }

    private func backOff() {
        busyStrikes += 1
        busyUntil = Self.now + min(Double(busyStrikes), 5)
        if busyStrikes >= 3 { publish(nil) }
    }

    private func publish(_ newTarget: EditableTarget?) {
        guard newTarget != target else { return }
        target = newTarget
    }
}

/// AXObserver callback. The observer's run-loop source lives on the main run loop, so this runs
/// on the main thread; `refcon` is the (unretained, app-lifetime) tracker.
private func focusTrackerCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated {
        tracker.handle(notification: name, element: element)
    }
}
