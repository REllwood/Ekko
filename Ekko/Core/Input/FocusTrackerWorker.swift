import ApplicationServices
import Foundation

/// Makes every Accessibility call for `FocusTracker` on one private serial queue, so AX messaging
/// (blocking IPC to another app) never runs on the main thread, where Ekko's keyboard event tap
/// lives. Owns the `AXObserver` and the facts cached about the focused element.
///
/// All stored state is confined to `queue`: the methods below only enqueue work and return
/// straight away, and reads report back on the main actor.
final class FocusTrackerWorker: @unchecked Sendable {
    struct App {
        let pid: pid_t
        let bundleID: String?
        let bundleURL: URL?
    }

    struct ReadRequest {
        /// For converting AX rects to AppKit; read from `NSScreen` on the main thread.
        var primaryScreenMaxY: CGFloat = 0
        var windowFrameIsStale = false
        var forgetFocusedElement = false
        /// Try again to register for notifications if that failed so far.
        var retryObserver = false
    }

    /// Carries an `AXUIElement` to the main actor; AX element references are immutable CF objects.
    struct ReadResult: @unchecked Sendable {
        enum Outcome: Equatable {
            case target(EditableTarget)
            case noTarget
            /// The app did not answer in time.
            case busy
        }

        var outcome: Outcome
        /// The focused element while it is editable, to match notifications against.
        var editableElement: AXUIElement?
        /// Its character count changed since the previous read: typing, in apps that post no
        /// value-changed notifications.
        var textChanged = false
    }

    private struct AttachedApp {
        let pid: pid_t
        let bundleID: String?
        let element: AXUIElement
        let kind: FocusTargetRules.AppKind
    }

    /// Facts about the focused element that don't change while it keeps focus.
    private struct FocusedElement {
        let element: AXUIElement
        let role: String?
        let isEditable: Bool
        var characterCount: Int?
        var windowFrame: CGRect?
        var windowFrameIsStale = true
    }

    /// Registered on the application element. Element destruction is watched per focused element.
    private static let appNotifications = [
        kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification,
        kAXSelectedTextChangedNotification, kAXValueChangedNotification,
        kAXWindowMovedNotification, kAXWindowResizedNotification,
    ]
    private static let maxObserverAttempts = 10
    private static let manualAccessibilityAttribute = "AXManualAccessibility" as CFString

    private let queue = DispatchQueue(label: "com.rhysellwood.ekko.focus-tracker", qos: .userInitiated)
    private let callback: AXObserverCallback
    /// Passed to every notification callback (the tracker, unretained).
    private let refcon: UnsafeMutableRawPointer

    // Confined to `queue`.
    private var app: AttachedApp?
    private var focused: FocusedElement?
    private var observer: AXObserver?
    private var observedElement: AXUIElement?
    private var observerAttempts = 0
    private var manualAccessibilityChecked: Set<pid_t> = []
    /// Apps Ekko switched AXManualAccessibility on in, to switch back off when tracking stops.
    private var manualAccessibilityEnabled: Set<pid_t> = []

    /// Notification callbacks are delivered on the main run loop.
    init(callback: AXObserverCallback, refcon: UnsafeMutableRawPointer) {
        self.callback = callback
        self.refcon = refcon
    }

    // MARK: - Commands

    func attach(_ app: App) {
        queue.async { self.performAttach(app) }
    }

    func detach() {
        queue.async { self.performDetach() }
    }

    /// The process is gone; its pid may be reused.
    func forget(pid: pid_t) {
        queue.async {
            self.manualAccessibilityChecked.remove(pid)
            self.manualAccessibilityEnabled.remove(pid)
        }
    }

    /// Runs after every command queued before it. `completion` runs on the main actor.
    func read(_ request: ReadRequest, completion: @escaping @MainActor (ReadResult) -> Void) {
        queue.async {
            let result = self.performRead(request)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(result) }
            }
        }
    }

    /// Detaches and switches AXManualAccessibility back off wherever Ekko switched it on. With a
    /// timeout, waits up to that long for it (when Ekko is quitting and won't get another chance).
    func shutDown(waitingUpTo timeout: TimeInterval? = nil) {
        let work = DispatchWorkItem {
            self.performDetach()
            self.revertManualAccessibility()
        }
        queue.async(execute: work)
        if let timeout, work.wait(timeout: .now() + timeout) == .timedOut {
            Log.input.info("Focus tracker cleanup did not finish before quitting")
        }
    }

    // MARK: - Attaching

    private func performAttach(_ info: App) {
        performDetach()
        let element = AXUIElementCreateApplication(info.pid)
        AXUIElementSetMessagingTimeout(element, FocusElementReader.messagingTimeout)
        let hasElectron = info.bundleURL.map {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
        } ?? false
        app = AttachedApp(
            pid: info.pid,
            bundleID: info.bundleID,
            element: element,
            kind: FocusTargetRules.appKind(bundleID: info.bundleID, hasElectronFramework: hasElectron)
        )
        enableManualAccessibilityIfNeeded(info, hasElectron: hasElectron, element: element)
        installObserver()
    }

    private func performDetach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedElement = nil
        observerAttempts = 0
        app = nil
        focused = nil
    }

    /// Registering is messaging too (it can time out on a busy app), hence on this queue.
    private func installObserver() {
        guard let app, observer == nil, observerAttempts < Self.maxObserverAttempts else { return }
        observerAttempts += 1
        var created: AXObserver?
        guard AXObserverCreate(app.pid, callback, &created) == .success, let created else { return }
        var registered = 0
        for name in Self.appNotifications {
            let result = AXObserverAddNotification(created, app.element, name as CFString, refcon)
            if result == .success || result == .notificationAlreadyRegistered { registered += 1 }
            // Busy or not ready yet: don't wait on the rest, the poll retries.
            if result == .cannotComplete { break }
        }
        guard registered > 0 else { return }
        // CFRunLoop is thread-safe. The callbacks only schedule reads, so they stay cheap on main.
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
    }

    private func watchDestruction(of element: AXUIElement?) {
        guard let observer else { return }
        if let old = observedElement {
            AXObserverRemoveNotification(observer, old, kAXUIElementDestroyedNotification as CFString)
            observedElement = nil
        }
        guard let element else { return }
        if AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon) == .success {
            observedElement = element
        }
    }

    // MARK: - Manual accessibility

    /// Electron and Chromium only build their web accessibility tree once an assistive app asks.
    /// AXEnhancedUserInterface is deliberately not used: it breaks window animations in some apps.
    private func enableManualAccessibilityIfNeeded(_ info: App, hasElectron: Bool, element: AXUIElement) {
        guard manualAccessibilityChecked.insert(info.pid).inserted else { return }
        guard FocusTargetRules.needsManualAccessibility(bundleID: info.bundleID, hasElectronFramework: hasElectron) else { return }
        let result = AXUIElementSetAttributeValue(element, Self.manualAccessibilityAttribute, kCFBooleanTrue)
        // Remembered even when the app reports an error: some Electron builds apply it anyway.
        if result != .invalidUIElement { manualAccessibilityEnabled.insert(info.pid) }
        Log.input.debug("AXManualAccessibility on for \(info.bundleID ?? "?", privacy: .public): \(result.rawValue)")
    }

    private func revertManualAccessibility() {
        for pid in manualAccessibilityEnabled {
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, FocusElementReader.messagingTimeout)
            let result = AXUIElementSetAttributeValue(element, Self.manualAccessibilityAttribute, kCFBooleanFalse)
            // Without Accessibility, or while the app is hung, keep it and retry on the next stop.
            if result != .apiDisabled, result != .cannotComplete { manualAccessibilityEnabled.remove(pid) }
            Log.input.debug("AXManualAccessibility off for pid \(pid): \(result.rawValue)")
        }
        manualAccessibilityChecked.removeAll()
    }

    // MARK: - Reading the focused element

    private func performRead(_ request: ReadRequest) -> ReadResult {
        guard let app else { return ReadResult(outcome: .noTarget) }
        if request.retryObserver, observer == nil { installObserver() }
        if request.forgetFocusedElement { focused = nil }
        if request.windowFrameIsStale { focused?.windowFrameIsStale = true }

        let element: AXUIElement
        switch FocusElementReader.focusedElement(of: app.element) {
        case .value(let focusedElement):
            element = focusedElement
        case .busy:
            return ReadResult(outcome: .busy)
        case .missing, .gone:
            focused = nil
            return ReadResult(outcome: .noTarget)
        }
        if !(focused.map { CFEqual($0.element, element) } ?? false) {
            switch FocusElementReader.classify(element, app: app.kind) {
            case .value(let classification):
                focused = FocusedElement(element: element, role: classification.role, isEditable: classification.isEditable)
                watchDestruction(of: classification.isEditable ? element : nil)
            case .busy:
                return ReadResult(outcome: .busy)
            case .missing, .gone:
                focused = nil
                return ReadResult(outcome: .noTarget)
            }
        }
        guard var current = focused, current.isEditable else { return ReadResult(outcome: .noTarget) }

        switch FocusElementReader.frame(of: element) {
        case .value(let axFrame):
            let convert = { FocusTargetRules.appKitRect(fromAX: $0, primaryScreenMaxY: request.primaryScreenMaxY) }
            let target = makeTarget(&current, axFrame: axFrame, app: app, convert: convert)
            let textChanged = updateCharacterCount(&current)
            focused = current
            return ReadResult(outcome: .target(target), editableElement: element, textChanged: textChanged)
        case .busy:
            return ReadResult(outcome: .busy)
        case .gone:
            focused = nil
            return ReadResult(outcome: .noTarget)
        case .missing:
            return ReadResult(outcome: .noTarget, editableElement: element)
        }
    }

    private func makeTarget(
        _ current: inout FocusedElement,
        axFrame: CGRect,
        app: AttachedApp,
        convert: (CGRect) -> CGRect
    ) -> EditableTarget {
        let frame = convert(axFrame)
        let isMultiline = FocusTargetRules.isMultiline(role: current.role, frame: frame)
        // Only multi-line placement uses the caret, so single-line fields skip those AX calls.
        let caret = isMultiline
            ? FocusElementReader.caretRect(of: current.element, elementFrame: axFrame).map(convert)
            : nil
        if current.windowFrameIsStale {
            current.windowFrame = FocusElementReader.windowFrame(of: current.element, app: app.element).map(convert)
            current.windowFrameIsStale = false
        }
        return EditableTarget(
            appPID: app.pid,
            appBundleID: app.bundleID,
            elementFrame: frame,
            caretRect: caret,
            windowFrame: current.windowFrame,
            isMultiline: isMultiline
        )
    }

    /// True when the text length changed since the last read of the same element.
    private func updateCharacterCount(_ current: inout FocusedElement) -> Bool {
        guard let count = FocusElementReader.characterCount(of: current.element) else { return false }
        defer { current.characterCount = count }
        return current.characterCount.map { $0 != count } ?? false
    }
}
