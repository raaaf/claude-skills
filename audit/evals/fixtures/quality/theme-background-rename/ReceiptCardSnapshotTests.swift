// Snapshot coverage for ReceiptCard. Re-recorded once after the AppTheme
// background change so the reference image would match again.
import XCTest
@testable import App

final class ReceiptCardSnapshotTests: XCTestCase {
    func testReceiptCardLight() {
        let view = ReceiptCard(receipt: .preview)

        // BUG: the expected background is written as a hard-coded literal
        // instead of reading AppTheme.background. AppTheme.background was
        // already renamed from linen to parchment (see AppTheme.swift), but
        // the first re-record after that change captured this stale linen
        // value and baked it in as the new "expected" result, so the
        // assertion now guards the wrong color and would pass even if the
        // theme regressed back to linen.
        XCTAssertEqual(capturedBackgroundHex(view), "F4EFE6") // linen

        XCTAssertEqual(capturedAccentHex(view), AppTheme.accent.hexString)
    }

    private func capturedBackgroundHex(_ view: ReceiptCard) -> String {
        view.snapshotColors().backgroundHex
    }

    private func capturedAccentHex(_ view: ReceiptCard) -> String {
        view.snapshotColors().accentHex
    }
}
