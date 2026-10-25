// Calls ../../../greeter.pep's functions through `import Greeter`, the Swift
// wrappers `--lib swift-package` generates over CGreeter.xcframework.
import Greeter
import XCTest

final class GreeterCheckTests: XCTestCase {
    func testCallsPepper() {
        XCTAssertEqual(greet("SwiftPM"), "Hello, SwiftPM, from Pepper")
        // A string crosses as UTF-8.
        XCTAssertEqual(greet("caf\u{e9} \u{1F336}"), "Hello, caf\u{e9} \u{1F336}, from Pepper")
        XCTAssertEqual(fibonacci(50), 12586269025)
        XCTAssertEqual(countWords("Pepper runs on iOS"), 4)
        XCTAssertTrue(isEven(10))
        XCTAssertEqual(half(2.5), 1.25)
    }

    func testHandlesOwnAReference() {
        let tally = tallyNew()
        XCTAssertEqual(tallyAdd(tally, 3), 3)
        XCTAssertEqual(tallyAdd(tally, 4), 7)
    }
}
