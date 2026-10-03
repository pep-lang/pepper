// A SwiftUI app that calls the Pepper library in ../greeter.pep through its
// generated C header (greeter.h, passed to swiftc as the bridging header).
import Foundation
import SwiftUI

/// Calls Pepper's `greet`: a Swift String goes in as UTF-8 bytes and their
/// count, and the C string that comes back is copied, then freed with
/// `pepper_string_free`.
func pepperGreeting(_ name: String) -> String {
    let result = name.withCString { greet($0, strlen($0)) }!
    defer { pepper_string_free(result) }
    return String(cString: result)
}

func pepperWordCount(_ text: String) -> Int {
    Int(text.withCString { count_words($0, strlen($0)) })
}

@main
struct PepperDemoApp: App {
    init() {
        // What build.sh checks: the app reached Pepper at launch.
        print(pepperGreeting("iOS"))
        print("fibonacci(50) = \(fibonacci(50))")
        print("words: \(pepperWordCount("Pepper runs on iOS"))")
        fflush(stdout)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var name = "iOS"

    var body: some View {
        VStack(spacing: 16) {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            Text(pepperGreeting(name))
                .font(.title2)
            Text("fibonacci(50) = \(fibonacci(50))")
            Text("\(pepperWordCount(name)) words")
        }
        .padding()
    }
}
