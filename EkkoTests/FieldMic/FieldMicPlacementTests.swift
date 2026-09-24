import XCTest
@testable import Ekko

/// AppKit coordinates throughout (y up). A 1440 × 900 display with a 25 pt menu bar.
final class FieldMicPlacementTests: XCTestCase {
    private let button = CGSize(width: 26, height: 26)
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    private func origin(
        element: CGRect,
        caret: CGRect? = nil,
        window: CGRect? = nil,
        multiline: Bool = false,
        visibleFrame: CGRect? = nil
    ) -> CGPoint? {
        FieldMicPlacement.buttonOrigin(
            elementFrame: element,
            caretRect: caret,
            windowFrame: window,
            isMultiline: multiline,
            visibleFrame: visibleFrame ?? visible,
            buttonSize: button
        )
    }

    // MARK: - Single-line fields

    func testSingleLineSitsJustOutsideTrailingEdgeVerticallyCentred() {
        let result = origin(
            element: CGRect(x: 100, y: 500, width: 200, height: 22),
            window: CGRect(x: 50, y: 300, width: 800, height: 500)
        )
        // x = maxX 300 + 6; y = midY 511 - 13.
        XCTAssertEqual(result, CGPoint(x: 306, y: 498))
    }

    func testSingleLineNearScreenRightEdgeFlipsInside() {
        let result = origin(element: CGRect(x: 1300, y: 500, width: 130, height: 22))
        // Outside would end at 1462 > 1440, so inside: 1430 - 6 - 26.
        XCTAssertEqual(result, CGPoint(x: 1398, y: 498))
    }

    func testSingleLineFlipsInsideWhenOutsideWouldLeaveTheWindow() {
        let result = origin(
            element: CGRect(x: 400, y: 500, width: 290, height: 22),
            window: CGRect(x: 100, y: 300, width: 600, height: 400)
        )
        // Outside would end at 722, past the window's 700.
        XCTAssertEqual(result, CGPoint(x: 658, y: 498))
    }

    func testSingleLinePartlyOffScreenStaysFullyOnScreen() {
        // Hangs off the right and the top of the visible frame.
        let result = origin(element: CGRect(x: 1380, y: 860, width: 200, height: 22))
        // Trailing edge is cut off, so inside the visible part (1440 - 6 - 26); y clamped to 875 - 26.
        XCTAssertEqual(result, CGPoint(x: 1408, y: 849))
    }

    func testSingleLineHangingOffTheLeftStillUsesTrailingEdge() {
        let result = origin(element: CGRect(x: -100, y: 400, width: 300, height: 22))
        XCTAssertEqual(result, CGPoint(x: 206, y: 398))
    }

    func testElementEntirelyOffScreenHasNoPlacement() {
        XCTAssertNil(origin(element: CGRect(x: 2000, y: 400, width: 200, height: 22)))
    }

    func testZeroSizeElementHasNoPlacement() {
        XCTAssertNil(origin(element: CGRect(x: 100, y: 100, width: 0, height: 22)))
    }

    func testWindowThatDoesNotOverlapTheElementIsIgnored() {
        // e.g. a field in a popover whose AX window is the parent window.
        let result = origin(
            element: CGRect(x: 100, y: 500, width: 200, height: 22),
            window: CGRect(x: 800, y: 100, width: 300, height: 200)
        )
        XCTAssertEqual(result, CGPoint(x: 306, y: 498))
    }

    // MARK: - Multi-line text

    func testTextAreaSitsInTheTrailingMarginOnTheCaretLine() {
        let result = origin(
            element: CGRect(x: 100, y: 100, width: 600, height: 400),
            caret: CGRect(x: 300, y: 350, width: 0, height: 16),
            multiline: true
        )
        // x = element maxX 700 - 8 - 26; y = caret midY 358 - 13. Never on top of the text after the caret.
        XCTAssertEqual(result, CGPoint(x: 666, y: 345))
    }

    func testCaretAtEndOfLongLineStaysInsideTheElement() {
        let result = origin(
            element: CGRect(x: 100, y: 100, width: 600, height: 400),
            caret: CGRect(x: 690, y: 350, width: 0, height: 16),
            multiline: true
        )
        XCTAssertEqual(result, CGPoint(x: 666, y: 345))
    }

    func testTextAreaWithoutCaretUsesBottomTrailingCorner() {
        let result = origin(element: CGRect(x: 100, y: 100, width: 600, height: 400), multiline: true)
        XCTAssertEqual(result, CGPoint(x: 666, y: 108))
    }

    func testScrolledDocumentUsesOnlyThePartInsideTheWindow() {
        // A TextEdit-style text view is as tall as the document, far beyond its window.
        let element = CGRect(x: 100, y: -1000, width: 600, height: 1600)
        let window = CGRect(x: 80, y: 80, width: 640, height: 540)
        XCTAssertEqual(
            origin(element: element, window: window, multiline: true),
            CGPoint(x: 666, y: 88)
        )
        // A caret scrolled out of view falls back to the corner of what's visible.
        XCTAssertEqual(
            origin(element: element, caret: CGRect(x: 300, y: -500, width: 0, height: 16), window: window, multiline: true),
            CGPoint(x: 666, y: 88)
        )
        XCTAssertEqual(
            origin(element: element, caret: CGRect(x: 300, y: 400, width: 0, height: 16), window: window, multiline: true),
            CGPoint(x: 666, y: 395)
        )
    }

    func testLargeElementUsesCaretRuleEvenWhenNotFlaggedMultiline() {
        let editor = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(
            origin(element: editor, caret: CGRect(x: 500, y: 400, width: 0, height: 18), window: editor),
            CGPoint(x: 1406, y: 396)
        )
        XCTAssertEqual(origin(element: editor, window: editor), CGPoint(x: 1406, y: 8))
    }

    func testMultilineBottomPartlyOffScreenUsesVisibleCorner() {
        let result = origin(element: CGRect(x: 100, y: -300, width: 600, height: 500), multiline: true)
        // Visible part is y 0…200.
        XCTAssertEqual(result, CGPoint(x: 666, y: 8))
    }

    func testPlacementOnSecondaryDisplayAboveAndLeftOfPrimary() {
        let secondaryVisible = CGRect(x: -1920, y: 1117, width: 1920, height: 1055)
        let result = origin(
            element: CGRect(x: -1500, y: 1887, width: 200, height: 30),
            visibleFrame: secondaryVisible
        )
        XCTAssertEqual(result, CGPoint(x: -1294, y: 1889))
    }

    // MARK: - Screen choice

    private let primary = FieldMicPlacement.Screen(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1085)
    )
    private let aboveLeft = FieldMicPlacement.Screen(
        frame: CGRect(x: -1920, y: 1117, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: 1117, width: 1920, height: 1055)
    )

    private func target(_ element: CGRect, caret: CGRect? = nil, window: CGRect? = nil, multiline: Bool = false) -> EditableTarget {
        EditableTarget(appPID: 1, appBundleID: nil, elementFrame: element, caretRect: caret, windowFrame: window, isMultiline: multiline)
    }

    func testScreenIsTheOneContainingTheElement() {
        let screens = [primary, aboveLeft]
        XCTAssertEqual(FieldMicPlacement.screen(for: target(CGRect(x: -1500, y: 1887, width: 200, height: 30)), in: screens), aboveLeft)
        XCTAssertEqual(FieldMicPlacement.screen(for: target(CGRect(x: 100, y: 500, width: 200, height: 22)), in: screens), primary)
    }

    func testScreenFollowsTheCaretInMultilineText() {
        // A text area spanning both displays with the caret on the upper one.
        let element = CGRect(x: -200, y: 900, width: 600, height: 400)
        let caret = CGRect(x: -100, y: 1200, width: 0, height: 16)
        XCTAssertEqual(FieldMicPlacement.screen(for: target(element, caret: caret, multiline: true), in: [primary, aboveLeft]), aboveLeft)
    }

    func testScreenFallsBackToLargestOverlap() {
        let right = FieldMicPlacement.Screen(
            frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1728, y: 0, width: 1920, height: 1055)
        )
        // Centre (1750, 1100) falls in the gap above the shorter right-hand display.
        let element = CGRect(x: 1700, y: 1090, width: 100, height: 20)
        XCTAssertEqual(FieldMicPlacement.screen(for: target(element), in: [primary, right]), primary)
    }

    func testNoScreenForAnElementOffEveryDisplay() {
        XCTAssertNil(FieldMicPlacement.screen(for: target(CGRect(x: 5000, y: 5000, width: 100, height: 20)), in: [primary, aboveLeft]))
    }

    func testClampPrefersLowerBoundWhenRangeIsInverted() {
        XCTAssertEqual(FieldMicPlacement.clamp(50, 10, 5), 10)
        XCTAssertEqual(FieldMicPlacement.clamp(50, 10, 40), 40)
        XCTAssertEqual(FieldMicPlacement.clamp(0, 10, 40), 10)
    }
}
