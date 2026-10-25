// A SwiftUI app that calls the Pepper library in ../greeter.pep through the
// Swift wrappers `--bindings swift` writes (greeter.swift, compiled with
// this file), which take and return Swift values.
import Foundation
import SwiftUI

/// Adds 3 and 4 to a Pepper `Tally`, which Swift releases when `tally` goes.
func tallied() -> Int64 {
    let tally = tallyNew()
    _ = tallyAdd(tally, 3)
    return tallyAdd(tally, 4)
}

@main
struct PepperDemoApp: App {
    init() {
        // What build.sh checks: the app reached Pepper at launch.
        print(greet("iOS"))
        print("fibonacci(50) = \(fibonacci(50))")
        print("words: \(countWords("Pepper runs on iOS"))")
        print("even: \(isEven(10)), half: \(half(2.5)), tally: \(tallied())")
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
            Text(greet(name))
                .font(.title2)
            Text("fibonacci(50) = \(fibonacci(50))")
            Text("\(countWords(name)) words")
        }
        .padding()
    }
}
