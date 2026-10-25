// swift-tools-version:5.5
// A package whose tests call the Pepper library through SwiftPM:
// ../package.sh copies it beside `Greeter`, the package that
// `pep-build --lib swift-package` writes, and runs them in the simulator.
import PackageDescription

let package = Package(
    name: "GreeterCheck",
    platforms: [.iOS(.v15)],
    dependencies: [.package(path: "../Greeter")],
    targets: [
        .testTarget(name: "GreeterCheckTests", dependencies: [.product(name: "Greeter", package: "Greeter")]),
    ]
)
