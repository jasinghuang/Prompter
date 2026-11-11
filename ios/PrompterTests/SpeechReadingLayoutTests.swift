import XCTest
import UIKit
@testable import Prompter

final class SpeechReadingLayoutTests: XCTestCase {
    func testLeadKeepsConfirmedTextAboveAnchorWithoutEnteringTopControls() {
        for size in [CGSize(width: 402, height: 874), CGSize(width: 874, height: 402)] {
            for lineHeight: CGFloat in [54, 96, 144] {
                let safeTop: CGFloat = size.height > size.width ? 62 : 0
                let anchor = SpeechReadingLayout.anchor(in: size, voice: true)
                let lead = SpeechReadingLayout.lead(in: size, lineHeight: lineHeight, safeTop: safeTop)
                XCTAssertGreaterThan(lead, 0)
                XCTAssertLessThanOrEqual(lead, lineHeight)
                XCTAssertGreaterThanOrEqual(anchor - lead - lineHeight / 2, safeTop + 68 - 0.1)
            }
        }
        XCTAssertEqual(SpeechReadingLayout.anchor(in: CGSize(width: 402, height: 874), voice: true), 874 / 3, accuracy: 0.01)
        XCTAssertEqual(SpeechReadingLayout.anchor(in: CGSize(width: 874, height: 402), voice: true), 201)
    }
}
