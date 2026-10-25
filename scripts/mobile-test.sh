#!/usr/bin/env bash
# Build Pepper programs for iOS and Android and run them in the iOS simulator
# and the Android emulator, on a Mac with Xcode and the Android SDK.
#
#   bash scripts/mobile-test.sh <compiler> <output-dir> [ios|android|all] [example-prefix...]
#
# <compiler> is a built pep-build. Each documentation example (docs/examples/,
# a `name.pep` or a folder with `main.pep`) whose name starts with one of the
# prefixes (all of them when none is given) is built for each platform, run
# there, and must exit 0, as tools/pep-doc/examples_test.pep requires on the
# desktop.
# Then the prototype apps in docs/examples/mobile/ are built and run: an iOS
# app calling a Pepper library from Swift in the simulator, and an Android app
# calling it through JNI in the emulator.
#
# On iOS, scripts/mobile/tls_check.pep also checks the tls module and HTTPS:
# against `openssl s_server` on this Mac (Homebrew's openssl@3, else the
# system's), with a test CA made for the run (its header lists the checks).
# Setting PEPPER_MOBILE_TLS_URL also fetches that public URL through the
# system's roots; by default nothing leaves the Mac.
#
# iOS: the simulator SDK comes from `xcrun`, and the programs run in a
# booted iPhone simulator through `xcrun simctl spawn`. The first available
# iPhone is booted for the run and shut down after, unless it was already
# running.
#
# Android: the NDK, `adb` and the emulator come from the Android SDK
# (`ANDROID_HOME`, default ~/Library/Android/sdk). The emulator starts
# headless and read-only from the first AVD (or `PEPPER_ANDROID_AVD`), so the
# AVD is left as it was, and stops after the run. Programs are pushed to
# /data/local/tmp and run with `adb shell`.
set -euo pipefail

compiler=${1:?usage: mobile-test.sh <compiler> <output-dir> [ios|android|all] [prefix...]}
out=${2:?usage: mobile-test.sh <compiler> <output-dir> [ios|android|all] [prefix...]}
platforms=${3:-all}
shift 3 2>/dev/null || shift $#
prefixes=("$@")

[ "$(uname -s)" = Darwin ] || { echo "mobile-test.sh runs on a Mac" >&2; exit 1; }
repo_root=$(cd "$(dirname "$0")/.." && pwd)
compiler=$(cd "$(dirname "$compiler")" && pwd)/$(basename "$compiler")
mkdir -p "$out"
out=$(cd "$out" && pwd)

# Examples that need what an app sandbox or an Android shell does not give a
# program: starting other programs (iOS forbids it; Android has no `ls`-style
# tools these examples call at the same paths), and a Unix socket file. On
# iOS a socket's path is at most 104 bytes, and the simulator's temporary
# folder (inside ~/Library/Developer/CoreSimulator) leaves too few for the
# example's name, as an app container's does on a device. On Android,
# SELinux lets an app create socket files in its own data folder but not the
# `adb shell` user anywhere it can write (bind fails with EACCES).
NOT_ON_MOBILE="processes- platform-declarations networking-unix"

# The examples to run on `$1` (ios or android): "<name> <entry>" lines.
examples() {
  for path in "$repo_root"/docs/examples/*; do
    name=$(basename "$path" .pep)
    if [ -d "$path" ]; then
      [ -f "$path/main.pep" ] || continue
      entry="$path/main.pep"
    else
      case "$path" in *.pep) entry="$path" ;; *) continue ;; esac
    fi
    skip=0
    for prefix in $NOT_ON_MOBILE; do
      case "$name" in "$prefix"*) skip=1 ;; esac
    done
    [ "$skip" = 0 ] || continue
    if [ "${#prefixes[@]}" -gt 0 ]; then
      match=0
      for prefix in "${prefixes[@]}"; do
        case "$name" in "$prefix"*) match=1 ;; esac
      done
      [ "$match" = 1 ] || continue
    fi
    echo "$name $entry"
  done
}

# Build every example for `$3` (ios or android) with the triple `$1` into
# `$2`, eight at a time. Prints one line
# per failure; the build logs stay in `$2/<name>.log`.
build_all() {
  local triple=$1 dir=$2
  mkdir -p "$dir"
  examples "$3" | xargs -P 8 -n 2 sh -c '
    "$0" --target "$1" "$4" -o "$2/$3" --build "$2/build-$3" > "$2/$3.log" 2>&1 || echo "build failed: $3"
  ' "$compiler" "$triple" "$dir" 2>/dev/null || true
}

# A TLS server on this Mac for the phone's checks, in `$1`: a test CA, a
# certificate for localhost and 127.0.0.1 that it issued (valid for 30 days,
# with the serverAuth usage iOS requires), and `openssl s_server -www`, which
# answers `GET /` and chooses http/1.1 through ALPN. Sets tls_pid.
TLS_PORT=18443
# Under `if`, `set -e` is off, so each step returns on failure itself.
start_tls_server() {
  local dir=$1 openssl
  openssl="$(brew --prefix openssl@3 2>/dev/null || true)/bin/openssl"
  [ -x "$openssl" ] || openssl=openssl
  mkdir -p "$dir"
  printf '%s\n' basicConstraints=critical,CA:TRUE keyUsage=critical,keyCertSign,cRLSign > "$dir/ca.ext"
  printf '%s\n' basicConstraints=CA:FALSE keyUsage=critical,digitalSignature extendedKeyUsage=serverAuth \
    subjectAltName=DNS:localhost,IP:127.0.0.1 > "$dir/server.ext"
  "$openssl" ecparam -name prime256v1 -genkey -noout -out "$dir/ca-key.pem" || return 1
  "$openssl" req -new -key "$dir/ca-key.pem" -subj "/CN=Pepper test CA" -out "$dir/ca.csr" || return 1
  "$openssl" x509 -req -in "$dir/ca.csr" -signkey "$dir/ca-key.pem" -days 30 -extfile "$dir/ca.ext" -out "$dir/ca.pem" || return 1
  "$openssl" ecparam -name prime256v1 -genkey -noout -out "$dir/key.pem" || return 1
  "$openssl" req -new -key "$dir/key.pem" -subj "/CN=localhost" -out "$dir/server.csr" || return 1
  "$openssl" x509 -req -in "$dir/server.csr" -CA "$dir/ca.pem" -CAkey "$dir/ca-key.pem" -CAcreateserial -days 30 \
    -extfile "$dir/server.ext" -out "$dir/server.pem" || return 1
  "$openssl" s_server -4 -accept "$TLS_PORT" -cert "$dir/server.pem" -key "$dir/key.pem" -alpn http/1.1 -www \
    < /dev/null > "$dir/server.log" 2>&1 &
  tls_pid=$!
  local waited=0
  until nc -z 127.0.0.1 "$TLS_PORT" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    [ "$waited" -lt 30 ] || { echo "the TLS server did not start"; cat "$dir/server.log"; return 1; }
  done
}

failures=0
report() {
  echo "FAIL $1"
  failures=$((failures + 1))
}

run_ios() {
  echo "=== iOS simulator"
  local sdk device booted_here=0
  sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
  export PEPPER_SYSROOT_AARCH64_APPLE_IOS_SIMULATOR=$sdk
  device=$(xcrun simctl list devices available | sed -nE 's/^ +iPhone[^(]* \(([0-9A-F-]{36})\) \((Booted|Shutdown)\).*/\1 \2/p' | head -1)
  [ -n "$device" ] || { echo "no iPhone simulator available" >&2; return 1; }
  if [ "${device#* }" != Booted ]; then
    xcrun simctl boot "${device% *}"
    booted_here=1
  fi
  device=${device% *}
  xcrun simctl bootstatus "$device" -b > /dev/null

  local dir="$out/ios"
  build_all aarch64-apple-ios-simulator "$dir" ios
  local count=0
  while read -r name entry; do
    count=$((count + 1))
    if [ ! -x "$dir/$name" ]; then
      report "ios $name (build)"
      sed 's/^/    /' "$dir/$name.log" | head -20
      continue
    fi
    # stdin from /dev/null: the loop reads the examples from its own.
    if ! (cd "$dir" && xcrun simctl spawn "$device" "$dir/$name" < /dev/null > "$dir/$name.out" 2>&1); then
      report "ios $name (run)"
      sed 's/^/    /' "$dir/$name.out" | head -20
    fi
  done < <(examples ios)
  echo "ios: ran $count examples"

  # TLS through Security.framework, against a server on this Mac (and a
  # public host only when PEPPER_MOBILE_TLS_URL names one).
  local tls_dir="$out/ios-tls" tls_args
  if start_tls_server "$tls_dir"; then
    tls_args=("$tls_dir/ca.pem" localhost "$TLS_PORT")
    [ -z "${PEPPER_MOBILE_TLS_URL-}" ] || tls_args+=("$PEPPER_MOBILE_TLS_URL")
    if ! "$compiler" --target aarch64-apple-ios-simulator "$repo_root/scripts/mobile/tls_check.pep" -o "$dir/tls_check" \
      --build "$dir/build-tls_check" > "$dir/tls_check.log" 2>&1; then
      report "ios tls_check (build)"
      sed 's/^/    /' "$dir/tls_check.log" | head -20
    # Bounded (macOS has no `timeout`): a TLS read that waits forever would
    # otherwise hold the job until its own limit.
    elif ! perl -e 'alarm shift; exec @ARGV' 300 xcrun simctl spawn "$device" "$dir/tls_check" "${tls_args[@]}" < /dev/null; then
      report "ios tls_check (run)"
    fi
  else
    report "ios tls server"
  fi
  kill "${tls_pid:-}" 2>/dev/null || true

  # The device build links too (nothing runs it here).
  "$compiler" --target aarch64-apple-ios "$repo_root/docs/examples/hello.pep" -o "$dir/hello-device" \
    --sysroot "$(xcrun --sdk iphoneos --show-sdk-path)" --build "$dir/build-device" || report "ios device link"

  if [ -d "$repo_root/docs/examples/mobile/ios" ]; then
    bash "$repo_root/docs/examples/mobile/ios/build.sh" "$compiler" "$out/ios-app" "$device" || report "ios app"
  fi

  if [ "$booted_here" = 1 ]; then
    xcrun simctl shutdown "$device" || true
  fi
}

run_android() {
  echo "=== Android emulator"
  export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
  local adb="$ANDROID_HOME/platform-tools/adb" emulator="$ANDROID_HOME/emulator/emulator"
  local avd=${PEPPER_ANDROID_AVD:-$("$emulator" -list-avds | head -1)}
  [ -n "$avd" ] || { echo "no Android virtual device" >&2; return 1; }
  local port=5584 serial=emulator-5584

  # Start it first: it boots while the examples build.
  "$emulator" -avd "$avd" -port "$port" -no-window -no-audio -no-boot-anim -read-only -no-snapshot \
    > "$out/emulator.log" 2>&1 &
  local emulator_pid=$!
  trap 'kill "$emulator_pid" 2>/dev/null || true' EXIT

  local dir="$out/android"
  build_all aarch64-linux-android "$dir" android

  "$adb" -s "$serial" wait-for-device
  local waited=0
  until [ "$("$adb" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do
    sleep 2
    waited=$((waited + 2))
    [ "$waited" -lt 300 ] || { echo "the emulator did not boot"; cat "$out/emulator.log"; return 1; }
  done
  "$adb" -s "$serial" shell mkdir -p /data/local/tmp/pepper

  local count=0
  while read -r name entry; do
    count=$((count + 1))
    if [ ! -f "$dir/$name" ]; then
      report "android $name (build)"
      sed 's/^/    /' "$dir/$name.log" | head -20
      continue
    fi
    "$adb" -s "$serial" push "$dir/$name" "/data/local/tmp/pepper/$name" < /dev/null > /dev/null
    # stdin from /dev/null: adb would read the rest of the example list.
    if ! "$adb" -s "$serial" shell "cd /data/local/tmp/pepper && chmod 755 ./$name && ./$name" < /dev/null > "$dir/$name.out" 2>&1; then
      report "android $name (run)"
      sed 's/^/    /' "$dir/$name.out" | head -20
    fi
  done < <(examples android)
  echo "android: ran $count examples"

  if [ -d "$repo_root/docs/examples/mobile/android" ]; then
    bash "$repo_root/docs/examples/mobile/android/build.sh" "$compiler" "$out/android-app" "$serial" || report "android app"
  fi

  "$adb" -s "$serial" emu kill > /dev/null 2>&1 || true
  wait "$emulator_pid" 2>/dev/null || true
  trap - EXIT
}

case "$platforms" in
  ios) run_ios ;;
  android) run_android ;;
  all) run_ios; run_android ;;
  *) echo "unknown platform '$platforms' (expected ios, android or all)" >&2; exit 1 ;;
esac

echo "failures: $failures"
[ "$failures" = 0 ]
