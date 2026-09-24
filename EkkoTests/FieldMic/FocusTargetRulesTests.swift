import XCTest
@testable import Ekko

final class FocusTargetRulesTests: XCTestCase {
    private typealias Traits = FocusTargetRules.Traits

    // MARK: - Editable classification

    func testWritableTextRolesAreEditable() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
            XCTAssertTrue(FocusTargetRules.isEditable(Traits(role: role, isValueSettable: true)), role)
            // A settable selection is enough on its own (some web text areas).
            XCTAssertTrue(FocusTargetRules.isEditable(Traits(role: role, isSelectedTextSettable: true)), role)
        }
        XCTAssertTrue(FocusTargetRules.isEditable(Traits(role: "AXTextField", subrole: "AXSearchField", isValueSettable: true)))
    }

    func testTextRolesNeedNoStringValue() {
        // Unlike groups, a text field counts without its (possibly long) value being copied.
        XCTAssertTrue(FocusTargetRules.isEditable(Traits(role: "AXTextArea", isValueSettable: true, valueIsString: false)))
    }

    func testReadOnlyTextRolesAreNotEditable() {
        // Log views, About windows, non-editable web text areas, pop-up combo boxes.
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
            XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: role)), role)
        }
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: "AXTextField", subrole: "AXSearchField")))
    }

    func testTerminalTextAreaCountsWithoutSettability() {
        // Terminal's view is an AXTextArea without a settable value, but pasting types into the shell.
        XCTAssertTrue(FocusTargetRules.isEditable(Traits(role: "AXTextArea", app: .terminal)))
        XCTAssertTrue(FocusTargetRules.isEditable(Traits(role: "AXTextField", app: .terminal)))
        // Only text roles are relaxed: a terminal's buttons and secure prompts are still excluded.
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: "AXButton", app: .terminal)))
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: "AXGroup", app: .terminal)))
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: "AXTextField", subrole: "AXSecureTextField", app: .terminal)))
    }

    func testChromiumContentEditableCountsWithASettableSelectionRange() {
        // A contenteditable root without a textbox role: AXTextArea, only its selection range settable.
        XCTAssertTrue(FocusTargetRules.isEditable(Traits(role: "AXTextArea", isSelectedTextRangeSettable: true, app: .chromium)))
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: "AXTextArea", app: .chromium)))
        // Elsewhere a selectable read-only NSTextView has a settable range too, so it doesn't count.
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: "AXTextArea", isSelectedTextRangeSettable: true)))
        // Only for text roles.
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: "AXGroup", isSelectedTextRangeSettable: true, app: .chromium)))
    }

    func testAppKinds() {
        for bundleID in [
            "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
            "org.alacritty", "net.kovidgoyal.kitty", "com.github.wez.wezterm", "co.zeit.hyper",
        ] {
            XCTAssertEqual(FocusTargetRules.appKind(bundleID: bundleID, hasElectronFramework: false), .terminal, bundleID)
        }
        // Hyper is an Electron terminal; the terminal rule wins.
        XCTAssertEqual(FocusTargetRules.appKind(bundleID: "co.zeit.hyper", hasElectronFramework: true), .terminal)
        XCTAssertEqual(FocusTargetRules.appKind(bundleID: "com.google.Chrome", hasElectronFramework: false), .chromium)
        XCTAssertEqual(FocusTargetRules.appKind(bundleID: "com.tinyspeck.slackmacgap", hasElectronFramework: true), .chromium)
        XCTAssertEqual(FocusTargetRules.appKind(bundleID: "com.apple.TextEdit", hasElectronFramework: false), .standard)
        XCTAssertEqual(FocusTargetRules.appKind(bundleID: nil, hasElectronFramework: false), .standard)
    }

    func testSecureFieldsAreNeverEditable() {
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: "AXTextField", subrole: "AXSecureTextField")))
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(
            role: "AXTextField", subrole: "AXSecureTextField",
            isValueSettable: true, valueIsString: true, isSelectedTextSettable: true
        )))
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: "AXGroup", subrole: "AXSecureTextFieldSomething", isValueSettable: true, valueIsString: true)))
    }

    func testNonTextControlsAreExcludedEvenWhenSettable() {
        for role in ["AXStaticText", "AXButton", "AXMenuItem", "AXCheckBox", "AXPopUpButton", "AXSlider", "AXLink"] {
            let traits = Traits(role: role, isValueSettable: true, valueIsString: true, isSelectedTextSettable: true)
            XCTAssertFalse(FocusTargetRules.isEditable(traits), role)
        }
    }

    func testCellsNeedASettableStringValue() {
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: "AXCell")))
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: "AXCell", isSelectedTextSettable: true)))
        XCTAssertTrue(FocusTargetRules.isEditable(Traits(role: "AXCell", isValueSettable: true, valueIsString: true)))
    }

    func testContentEditableGroupsAndWebAreas() {
        XCTAssertTrue(FocusTargetRules.isEditable(Traits(role: "AXGroup", isValueSettable: true, valueIsString: true)))
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: "AXGroup", isValueSettable: true, valueIsString: false)))
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: "AXGroup")))
        XCTAssertTrue(FocusTargetRules.isEditable(Traits(role: "AXWebArea", isSelectedTextSettable: true)))
        XCTAssertFalse(FocusTargetRules.isEditable(Traits(role: "AXWebArea")))
    }

    func testRoleDecisionDefersForAmbiguousRoles() {
        XCTAssertNil(FocusTargetRules.roleDecision(role: "AXGroup", subrole: nil, app: .standard))
        XCTAssertNil(FocusTargetRules.roleDecision(role: "AXWebArea", subrole: nil, app: .standard))
        XCTAssertNil(FocusTargetRules.roleDecision(role: nil, subrole: nil, app: .standard))
        XCTAssertEqual(FocusTargetRules.roleDecision(role: "AXButton", subrole: nil, app: .standard), false)
        XCTAssertEqual(FocusTargetRules.roleDecision(role: "AXTextField", subrole: "AXSecureTextField", app: .standard), false)
    }

    func testRoleDecisionForTextRolesDependsOnTheApp() {
        // Outside terminals a text role still needs a settability check.
        XCTAssertNil(FocusTargetRules.roleDecision(role: "AXTextField", subrole: nil, app: .standard))
        XCTAssertNil(FocusTargetRules.roleDecision(role: "AXTextArea", subrole: nil, app: .standard))
        XCTAssertNil(FocusTargetRules.roleDecision(role: "AXTextField", subrole: "AXSearchField", app: .standard))
        XCTAssertEqual(FocusTargetRules.roleDecision(role: "AXTextArea", subrole: nil, app: .terminal), true)
        XCTAssertNil(FocusTargetRules.roleDecision(role: "AXGroup", subrole: nil, app: .terminal))
    }

    func testMultiline() {
        XCTAssertTrue(FocusTargetRules.isMultiline(role: "AXTextArea", frame: CGRect(x: 0, y: 0, width: 200, height: 20)))
        XCTAssertFalse(FocusTargetRules.isMultiline(role: "AXTextField", frame: CGRect(x: 0, y: 0, width: 200, height: 22)))
        XCTAssertFalse(FocusTargetRules.isMultiline(role: "AXTextField", frame: CGRect(x: 0, y: 0, width: 200, height: 44)))
        XCTAssertTrue(FocusTargetRules.isMultiline(role: "AXGroup", frame: CGRect(x: 0, y: 0, width: 200, height: 60)))
    }

    func testManualAccessibilityOnlyForElectronAndChromium() {
        XCTAssertTrue(FocusTargetRules.needsManualAccessibility(bundleID: "com.tinyspeck.slackmacgap", hasElectronFramework: true))
        XCTAssertTrue(FocusTargetRules.needsManualAccessibility(bundleID: "com.hnc.Discord", hasElectronFramework: true))
        XCTAssertTrue(FocusTargetRules.needsManualAccessibility(bundleID: nil, hasElectronFramework: true))
        XCTAssertTrue(FocusTargetRules.needsManualAccessibility(bundleID: "com.google.Chrome", hasElectronFramework: false))
        XCTAssertFalse(FocusTargetRules.needsManualAccessibility(bundleID: "com.apple.Safari", hasElectronFramework: false))
        XCTAssertFalse(FocusTargetRules.needsManualAccessibility(bundleID: nil, hasElectronFramework: false))
    }

    func testElectronTerminalsStillGetManualAccessibility() {
        XCTAssertTrue(FocusTargetRules.needsManualAccessibility(bundleID: "co.zeit.hyper", hasElectronFramework: true))
    }

    func testManualAccessibilityIsNeverForcedOnCodeEditors() {
        // It would switch them into their screen-reader-optimised mode.
        for bundleID in [
            "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.visualstudio.code.oss", "com.vscodium",
            "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "dev.zed.Zed",
        ] {
            XCTAssertFalse(FocusTargetRules.needsManualAccessibility(bundleID: bundleID, hasElectronFramework: true), bundleID)
            XCTAssertFalse(FocusTargetRules.needsManualAccessibility(bundleID: bundleID, hasElectronFramework: false), bundleID)
        }
    }

    // MARK: - AX → AppKit coordinates

    /// Primary display 1728 × 1117 at the AppKit origin.
    private let primaryMaxY: CGFloat = 1117

    func testConversionOnThePrimaryDisplay() {
        let rect = FocusTargetRules.appKitRect(fromAX: CGRect(x: 100, y: 200, width: 300, height: 20), primaryScreenMaxY: primaryMaxY)
        XCTAssertEqual(rect, CGRect(x: 100, y: 897, width: 300, height: 20))
    }

    func testConversionForDisplayAboveAndLeftOfPrimary() {
        // Above/left of the primary, AX coordinates are negative.
        let secondary = CGRect(x: -1920, y: 1117, width: 1920, height: 1080)
        let rect = FocusTargetRules.appKitRect(fromAX: CGRect(x: -1500, y: -800, width: 200, height: 30), primaryScreenMaxY: primaryMaxY)
        XCTAssertEqual(rect, CGRect(x: -1500, y: 1887, width: 200, height: 30))
        XCTAssertTrue(secondary.contains(rect))
    }

    func testConversionForDisplayBelowPrimary() {
        let below = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let rect = FocusTargetRules.appKitRect(fromAX: CGRect(x: 300, y: 1500, width: 200, height: 30), primaryScreenMaxY: primaryMaxY)
        XCTAssertEqual(rect, CGRect(x: 300, y: -413, width: 200, height: 30))
        XCTAssertTrue(below.contains(rect))
    }

    func testTopOfPrimaryMapsToItsMaxY() {
        let rect = FocusTargetRules.appKitRect(fromAX: CGRect(x: 0, y: 0, width: 10, height: 25), primaryScreenMaxY: primaryMaxY)
        XCTAssertEqual(rect.maxY, primaryMaxY)
    }

    // MARK: - Caret validation

    private let element = CGRect(x: 100, y: 100, width: 400, height: 200)

    func testZeroWidthCaretInsideElementIsKept() {
        let caret = CGRect(x: 250, y: 150, width: 0, height: 16)
        XCTAssertEqual(FocusTargetRules.usableCaret(caret, elementFrame: element), caret)
    }

    func testZeroSizeOrMissingCaretIsDiscarded() {
        XCTAssertNil(FocusTargetRules.usableCaret(.zero, elementFrame: element))
        XCTAssertNil(FocusTargetRules.usableCaret(CGRect(x: 250, y: 150, width: 5, height: 0), elementFrame: element))
        XCTAssertNil(FocusTargetRules.usableCaret(nil, elementFrame: element))
        XCTAssertNil(FocusTargetRules.usableCaret(.null, elementFrame: element))
    }

    func testCaretFarOutsideElementIsDiscarded() {
        // Zero-width rects are "empty" to CGRect.contains; make sure they're still range-checked.
        XCTAssertNil(FocusTargetRules.usableCaret(CGRect(x: 900, y: 150, width: 0, height: 16), elementFrame: element))
        XCTAssertNil(FocusTargetRules.usableCaret(CGRect(x: 250, y: 20, width: 0, height: 16), elementFrame: element))
    }

    func testCaretSlightlyOutsideElementIsKept() {
        let caret = CGRect(x: 520, y: 290, width: 0, height: 30)
        XCTAssertEqual(FocusTargetRules.usableCaret(caret, elementFrame: element), caret)
    }

    func testEdges() {
        let glyph = CGRect(x: 10, y: 20, width: 7, height: 16)
        XCTAssertEqual(FocusTargetRules.trailingEdge(of: glyph), CGRect(x: 17, y: 20, width: 0, height: 16))
        XCTAssertEqual(FocusTargetRules.leadingEdge(of: glyph), CGRect(x: 10, y: 20, width: 0, height: 16))
    }
}
