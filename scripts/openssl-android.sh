#!/usr/bin/env bash
# The static OpenSSL 3 that the tls module links on Android
# (runtime/tls/openssl_android.pep), for each ABI `--target *-android`
# supports.
#
#   bash scripts/openssl-android.sh build <ndk> <output-dir>
#   bash scripts/openssl-android.sh fetch <runtime-dir>
#
# build: downloads OpenSSL's source, checked against its SHA-256, and builds
#   libssl.a and libcrypto.a for each ABI with the NDK's clang, for the
#   oldest API level Pepper supports. Writes <output-dir>/$ARCHIVE, holding
#   <triple>/libssl.a, <triple>/libcrypto.a and OpenSSL's LICENSE.txt, and
#   its .sha256 beside it. The openssl-android workflow publishes both on the
#   `openssl-<version>` release. Needs perl and make (any Linux or macOS).
# fetch: downloads that archive, checks it against its .sha256, and unpacks
#   it into <runtime-dir>/tls/android, where openssl_android.pep's `[Link]`
#   finds the libraries. release-build.sh does this for the toolchain; a
#   checkout runs it once to link Android programs that import tls (or http).
set -euo pipefail

OPENSSL_VERSION=3.5.9
OPENSSL_SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
# DEFAULT_ANDROID_API in tools/compiler/link/platform.pep.
ANDROID_API=30
# Each ABI's triple and OpenSSL's name for it.
ABIS="aarch64-linux-android:android-arm64 x86_64-linux-android:android-x86_64"
ARCHIVE="openssl-$OPENSSL_VERSION-android.tar.gz"
RELEASE_URL="https://github.com/pep-lang/pepper/releases/download/openssl-$OPENSSL_VERSION"

usage() {
  echo "usage: openssl-android.sh build <ndk> <output-dir> | fetch <runtime-dir>" >&2
  exit 2
}

sha256() {
  if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

build() {
  local ndk output prebuilt
  ndk=$(cd "${1:?}" && pwd)
  mkdir -p "${2:?}"
  output=$(cd "$2" && pwd)
  # Global: the EXIT trap runs after this function returns.
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  prebuilt=$(ls -d "$ndk"/toolchains/llvm/prebuilt/*/bin | head -1)
  [ -x "$prebuilt/clang" ] || { echo "no clang in $ndk/toolchains/llvm/prebuilt" >&2; exit 1; }

  curl --fail --location --silent --show-error --retry 3 -o "$work/openssl.tar.gz" \
    "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz"
  [ "$(sha256 "$work/openssl.tar.gz")" = "$OPENSSL_SHA256" ] || { echo "openssl-$OPENSSL_VERSION.tar.gz: checksum mismatch" >&2; exit 1; }

  mkdir -p "$work/out"
  local entry triple target
  for entry in $ABIS; do
    triple=${entry%%:*}
    target=${entry#*:}
    rm -rf "$work/build"
    mkdir "$work/build"
    tar -xzf "$work/openssl.tar.gz" -C "$work/build" --strip-components 1
    # A section per function, so a program's --gc-sections link keeps only
    # what tls reaches. No config file is read (Android has none at
    # OPENSSLDIR), and the trusted roots are loaded by openssl_android.pep.
    (cd "$work/build" \
      && PATH="$prebuilt:$PATH" ANDROID_NDK_ROOT="$ndk" ./Configure "$target" "-D__ANDROID_API__=$ANDROID_API" \
        no-shared no-module no-engine no-tests no-autoload-config \
        -ffunction-sections -fdata-sections \
      && PATH="$prebuilt:$PATH" ANDROID_NDK_ROOT="$ndk" make -j"$(getconf _NPROCESSORS_ONLN)" build_libs)
    mkdir -p "$work/out/$triple"
    cp "$work/build/libssl.a" "$work/build/libcrypto.a" "$work/out/$triple/"
  done
  cp "$work/build/LICENSE.txt" "$work/out/"
  tar -czf "$output/$ARCHIVE" -C "$work/out" .
  (cd "$output" && echo "$(sha256 "$ARCHIVE")  $ARCHIVE" > "$ARCHIVE.sha256")
  ls -l "$output"
}

fetch() {
  local dir
  dir="${1:?}/tls/android"
  # Global: the EXIT trap runs after this function returns.
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  curl --fail --location --silent --show-error --retry 3 -o "$work/$ARCHIVE" "$RELEASE_URL/$ARCHIVE"
  curl --fail --location --silent --show-error --retry 3 -o "$work/$ARCHIVE.sha256" "$RELEASE_URL/$ARCHIVE.sha256"
  [ "$(sha256 "$work/$ARCHIVE")" = "$(cut -d' ' -f1 < "$work/$ARCHIVE.sha256")" ] \
    || { echo "$ARCHIVE: checksum mismatch" >&2; exit 1; }
  rm -rf "$dir"
  mkdir -p "$dir"
  tar -xzf "$work/$ARCHIVE" -C "$dir"
  echo "OpenSSL $OPENSSL_VERSION for Android in $dir"
}

case "${1:-}" in
  build) [ $# = 3 ] || usage; build "$2" "$3" ;;
  fetch) [ $# = 2 ] || usage; fetch "$2" ;;
  *) usage ;;
esac
