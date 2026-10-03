#!/usr/bin/env bash
# CI-only: pack this host's system libraries into a system root another
# host links against with `--target <triple> --sysroot <dir>` (the
# cross-link jobs in ci.yml).
#
#   bash scripts/ci-export-sysroot.sh <output.tar.gz>
#
# Linux packs glibc's startup objects and libraries and GCC's libgcc, at the
# paths clang looks for them in a sysroot. macOS packs the SDK's library
# stubs (`.tbd`) and its SDKSettings, which name the deployment target; the
# headers stay behind, since a Pepper program links only. Either is a few
# megabytes, small enough to hand between jobs as an artifact every run.
#
# Symbolic links are copied as the files they name: the archive is unpacked
# on Windows too, where Git's tar cannot make them.
set -euo pipefail

output=${1:?usage: ci-export-sysroot.sh <output.tar.gz>}
output=$(cd "$(dirname "$output")" && pwd)/$(basename "$output")
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

case "$(uname -s)" in
  Linux)
    multiarch=$(gcc -print-multiarch 2>/dev/null || echo "$(uname -m)-linux-gnu")
    gcc_dir=$(dirname "$(gcc -print-libgcc-file-name)")
    root="$staging/linux"
    # Each file at its own path, and at the path the linker scripts
    # (libc.so, libm.so) name: Ubuntu's /lib is a link to /usr/lib.
    copy() {
      local file
      for file in "$@"; do
        [ -e "$file" ] || continue
        mkdir -p "$root$(dirname "$file")"
        cp -L "$file" "$root$file"
      done
    }
    for dir in "/usr/lib/$multiarch" "/lib/$multiarch"; do
      copy "$dir"/{crt1.o,Scrt1.o,crti.o,crtn.o} \
        "$dir"/{libc,libm,libmvec,libpthread,libdl,librt}.so* \
        "$dir"/libc_nonshared.a "$dir"/ld-linux-*.so.* \
        "$dir"/libgcc_s.so*
    done
    copy /lib64/ld-linux-*.so.* /lib/ld-linux-*.so.*
    copy "$gcc_dir"/{crtbegin,crtbeginS,crtbeginT,crtend,crtendS}.o \
      "$gcc_dir"/{libgcc.a,libgcc_eh.a,libgcc_s.so}
    ;;
  Darwin)
    # No AppleDouble (`._`) files for extended attributes in the archive.
    export COPYFILE_DISABLE=1
    sdk=$(xcrun --sdk macosx --show-sdk-path)
    root="$staging/MacOSX.sdk"
    mkdir -p "$root"
    # usr/lib holds libSystem and its re-exports; Swift's stubs are not
    # needed and are most of its size.
    (cd "$sdk" && tar -c -h --exclude usr/lib/swift SDKSettings.json SDKSettings.plist usr/lib) | tar -x -C "$root"
    ;;
  *)
    echo "ci-export-sysroot.sh: no system root to export from $(uname -s)" >&2
    exit 1
    ;;
esac

tar -czf "$output" -C "$staging" "$(basename "$root")"
echo "wrote $output ($(du -k "$output" | cut -f1) KB)" >&2
