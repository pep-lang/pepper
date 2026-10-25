// Calls ../../../greeter.pep's functions through `import Greeter`, the module
// map in Greeter.xcframework.
import Foundation
import Greeter
import XCTest

final class GreeterCheckTests: XCTestCase {
    func testCallsPepper() {
        let result = "SwiftPM".withCString { greet($0, strlen($0)) }!
        defer { pepper_string_free(result) }
        XCTAssertEqual(String(cString: result), "Hello, SwiftPM, from Pepper")
        XCTAssertEqual(fibonacci(50), 12586269025)
        XCTAssertEqual("Pepper runs on iOS".withCString { count_words($0, strlen($0)) }, 4)
    }
}
