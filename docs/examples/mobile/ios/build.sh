#!/usr/bin/env bash
# Build the prototype iOS app and run it in the simulator (#375):
#
#   bash build.sh <pep-build> <output-dir> [<simulator-udid>]
#
# Builds ../greeter.pep as a static library for the simulator, compiles
# PepperDemo.swift against it with greeter.h as the bridging header, and
# bundles PepperDemo.app. With a booted simulator's UDID, installs the app,
# launches it, and checks what it printed. It also links the app for a
# device (arm64-apple-ios), unsigned, to show the device build links.
set -euo pipefail

compiler=${1:?usage: build.sh <pep-build> <output-dir> [<simulator-udid>]}
out=${2:?usage: build.sh <pep-build> <output-dir> [<simulator-udid>]}
device=${3:-}
here=$(cd "$(dirname "$0")" && pwd)

build() {
  local platform=$1 pepper_triple=$2 swift_triple=$3 dir=$4
  local sdk
  sdk=$(xcrun --sdk "$platform" --show-sdk-path)
  rm -rf "$dir"
  mkdir -p "$dir/PepperDemo.app"
  "$compiler" --target "$pepper_triple" --sysroot "$sdk" --lib static "$here/../greeter.pep" \
    -o "$dir/libgreeter.a" --build "$dir/build"
  xcrun --sdk "$platform" swiftc -target "$swift_triple" -sdk "$sdk" -parse-as-library -O \
    -import-objc-header "$dir/greeter.h" "$here/PepperDemo.swift" \
    -L "$dir" -lgreeter -o "$dir/PepperDemo.app/PepperDemo"
  cp "$here/Info.plist" "$dir/PepperDemo.app/Info.plist"
}

build iphoneos aarch64-apple-ios arm64-apple-ios15.0 "$out/device"
echo "device build: $(lipo -info "$out/device/PepperDemo.app/PepperDemo")"

build iphonesimulator aarch64-apple-ios-simulator arm64-apple-ios15.0-simulator "$out/simulator"
app="$out/simulator/PepperDemo.app"
codesign --force --sign - "$app"
[ -n "$device" ] || exit 0

xcrun simctl install "$device" "$app"
xcrun simctl launch --terminate-running-process --stdout="$out/stdout.txt" "$device" dev.pepper.demo
expected="Hello, iOS, from Pepper"
waited=0
until grep -q "$expected" "$out/stdout.txt" 2>/dev/null; do
  sleep 1
  waited=$((waited + 1))
  if [ "$waited" -ge 60 ]; then
    echo "the app did not print '$expected'; it printed:"
    cat "$out/stdout.txt" 2>/dev/null || true
    xcrun simctl uninstall "$device" dev.pepper.demo || true
    exit 1
  fi
done
cat "$out/stdout.txt"
grep -q "fibonacci(50) = 12586269025" "$out/stdout.txt"
grep -q "words: 4" "$out/stdout.txt"
xcrun simctl io "$device" screenshot "$out/screenshot.png" || true
xcrun simctl terminate "$device" dev.pepper.demo || true
xcrun simctl uninstall "$device" dev.pepper.demo
echo "ios app: ok"
