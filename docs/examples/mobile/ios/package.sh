#!/usr/bin/env bash
# Build ../greeter.pep as a Swift package and call it from Swift tests in the
# simulator, through SwiftPM:
#
#   bash package.sh <pep-build> <output-dir> <simulator-udid>
#
# `pep-build --lib swift-package` writes <output-dir>/Greeter (Package.swift
# and Greeter.xcframework); package/, whose tests `import Greeter`, is copied
# beside it and tested with `xcodebuild test` on the booted simulator.
set -euo pipefail

compiler=${1:?usage: package.sh <pep-build> <output-dir> <simulator-udid>}
out=${2:?usage: package.sh <pep-build> <output-dir> <simulator-udid>}
device=${3:?usage: package.sh <pep-build> <output-dir> <simulator-udid>}
here=$(cd "$(dirname "$0")" && pwd)

rm -rf "$out"
mkdir -p "$out"
"$compiler" --lib swift-package "$here/../greeter.pep" -o "$out/Greeter" --build "$out/build"
cp -R "$here/package" "$out/GreeterCheck"
cd "$out/GreeterCheck"
# Xcode names a package's schemes itself: take the one it lists.
scheme=$(xcodebuild -list | sed -n '/Schemes:/{n;s/^ *//;p;}')
xcodebuild test -scheme "$scheme" -destination "id=$device" -derivedDataPath "$out/derived" -quiet
echo "ios swift package: ok"
