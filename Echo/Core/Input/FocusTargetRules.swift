import ApplicationServices
import CoreGraphics

/// Pure rules behind `FocusTracker`: which focused elements count as "somewhere text can be
/// written", and how AX geometry maps to AppKit. No AX calls, so all of it is unit tested.
enum FocusTargetRules {
    /// How an app's text views report that they can be written to.
    enum AppKind: Equatable {
        case standard
        /// Terminal emulators: the text view is read-only to Accessibility, but pasting types into
        /// the shell.
        case terminal
        /// Chromium browsers and Electron apps: a contenteditable text area only reports a settable
        /// selection range (Chromium never makes AXSelectedText settable).
        case chromium
    }

    /// What the classifier needs to know about an element.
    struct Traits: Equatable {
        var role: String?
        var subrole: String?
        var isValueSettable = false
        var valueIsString = false
        var isSelectedTextSettable = false
        var isSelectedTextRangeSettable = false
        var app = AppKind.standard
    }

    static let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, kAXSearchFieldSubrole]
    static let nonTextRoles: Set<String> = [
        kAXStaticTextRole, kAXButtonRole, kAXMenuItemRole, kAXMenuBarItemRole, kAXMenuButtonRole,
        kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole, kAXSliderRole, kAXImageRole, "AXLink",
    ]
    /// Chromium browsers, like Electron apps, only expose web content once an assistive app asks.
    static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser", "com.operasoftware.Opera",
    ]
    /// Electron code editors switch into their screen-reader mode when AXManualAccessibility is set,
    /// so they are never forced into it.
    static let codeEditorBundleIDs: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.visualstudio.code.oss", "com.vscodium",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf", "dev.zed.Zed",
    ]
    /// Terminal emulators: their text view is read-only to Accessibility, but pasting types into the shell.
    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "org.alacritty", "net.kovidgoyal.kitty", "com.github.wez.wezterm", "co.zeit.hyper",
    ]
    /// Taller than this and a field is treated as multi-line.
    static let multilineHeight: CGFloat = 44
    /// A caret rect further than this outside its element is garbage.
    static let caretTolerance: CGFloat = 40

    // MARK: - Classification

    static func isSecure(role: String?, subrole: String?) -> Bool {
        subrole == kAXSecureTextFieldSubrole
            || subrole?.contains("Secure") == true
            || role?.contains("Secure") == true
    }

    static func isTextRole(role: String?, subrole: String?) -> Bool {
        role.map { textRoles.contains($0) } == true || subrole == kAXSearchFieldSubrole
    }

    static func appKind(bundleID: String?, hasElectronFramework: Bool) -> AppKind {
        if let bundleID, terminalBundleIDs.contains(bundleID) { return .terminal }
        if isChromium(bundleID: bundleID, hasElectronFramework: hasElectronFramework) { return .chromium }
        return .standard
    }

    /// true/false when the role (and, for terminals, the app) alone decides; nil when settability
    /// has to be checked.
    static func roleDecision(role: String?, subrole: String?, app: AppKind) -> Bool? {
        if isSecure(role: role, subrole: subrole) { return false }
        if isTextRole(role: role, subrole: subrole) { return app == .terminal ? true : nil }
        if let role, nonTextRoles.contains(role) { return false }
        return nil
    }

    static func isEditable(_ traits: Traits) -> Bool {
        if let decision = roleDecision(role: traits.role, subrole: traits.subrole, app: traits.app) {
            return decision
        }
        // Read-only text views (logs, About boxes, static web text areas) share the text roles.
        if isTextRole(role: traits.role, subrole: traits.subrole) {
            return traits.isValueSettable || traits.isSelectedTextSettable
                || (traits.app == .chromium && traits.isSelectedTextRangeSettable)
        }
        let hasSettableText = traits.isValueSettable && traits.valueIsString
        if traits.role == kAXCellRole { return hasSettableText }
        // contenteditable in Safari/Chrome can surface as AXGroup/AXWebArea with a settable value.
        return hasSettableText || traits.isSelectedTextSettable
    }

    static func isMultiline(role: String?, frame: CGRect) -> Bool {
        role == kAXTextAreaRole || frame.height > multilineHeight
    }

    /// Electron terminals (Hyper) need it too: without it their input textarea isn't exposed.
    static func needsManualAccessibility(bundleID: String?, hasElectronFramework: Bool) -> Bool {
        if let bundleID, codeEditorBundleIDs.contains(bundleID) { return false }
        return isChromium(bundleID: bundleID, hasElectronFramework: hasElectronFramework)
    }

    private static func isChromium(bundleID: String?, hasElectronFramework: Bool) -> Bool {
        hasElectronFramework || bundleID.map { chromiumBundleIDs.contains($0) } == true
    }

    // MARK: - Geometry

    /// AX rects have their origin at the top-left of the primary display with y growing down;
    /// AppKit's origin is the primary display's bottom-left with y growing up.
    static func appKitRect(fromAX rect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenMaxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Keeps a caret rect only when it has a height and sits within `caretTolerance` of the element.
    /// Compared by edges: `CGRect.contains` treats zero-width rects as empty and accepts them anywhere.
    static func usableCaret(_ rect: CGRect?, elementFrame: CGRect) -> CGRect? {
        guard let rect, !rect.isNull, !rect.isInfinite, rect.height > 0 else { return nil }
        let bounds = elementFrame.insetBy(dx: -caretTolerance, dy: -caretTolerance)
        guard rect.minX >= bounds.minX, rect.maxX <= bounds.maxX,
              rect.minY >= bounds.minY, rect.maxY <= bounds.maxY else { return nil }
        return rect
    }

    static func trailingEdge(of rect: CGRect) -> CGRect {
        CGRect(x: rect.maxX, y: rect.minY, width: 0, height: rect.height)
    }

    static func leadingEdge(of rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY, width: 0, height: rect.height)
    }
}
