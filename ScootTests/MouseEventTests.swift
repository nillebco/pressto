import XCTest
import Cocoa

final class MouseEventTests: XCTestCase {
    func testRepeatedTargetedClicksKeepCoordinatesAndSingleClickState() throws {
        // Different positions model successive permission prompts and monitors.
        for point in [CGPoint(x: 412, y: 911), CGPoint(x: -600, y: 200)] {
            for _ in 0..<3 {
                for kind in [Mouse.Event.down, .up] {
                    let event = try XCTUnwrap(Mouse.targetedClickEvent(button: .left, event: kind, location: point))
                    XCTAssertEqual(event.location, point)
                    XCTAssertEqual(event.type, Mouse.Button.left.cgEventType(for: kind))
                    XCTAssertEqual(event.flags, [])
                    XCTAssertEqual(event.getIntegerValueField(.mouseEventClickState), 1)
                }
            }
        }
    }
}
