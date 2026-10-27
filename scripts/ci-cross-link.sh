#!/usr/bin/env bash
# CI-only: the cross-link smoke test (the cross-link jobs in ci.yml).
#
#   bash scripts/ci-cross-link.sh build <compiler> <output-dir>
#   bash scripts/ci-cross-link.sh run <artifacts-dir>
#
# `build` runs on each host: it builds the examples below for the host, runs
# them and keeps what they print in <output-dir>/expected/, then builds them
# for the other two operating systems (`--target`, with the system roots
# ci-provision-cross.sh set up) into <output-dir>/<os>/. So too the project
# `native-script`, whose build script, built for the host, compiles C for the
# target (pep-package's test a_build_script_runs_on_the_host_and_compiles_c_for_the_target),
# and `native-table`, whose `[native]` table compiles C for the target
# (a_projects_native_table_builds_after_its_script_and_for_the_target).
#
# `run` runs on each host after every `build`: <artifacts-dir> holds each
# host's <output-dir> in a folder of its own. It runs every program built for
# this host's operating system elsewhere and compares what it prints with what
# this host's own build printed.
set -euo pipefail

EXAMPLES="hello interpolation-format maps-sorted json-structs threads-basics simd-basics"
PROGRAMS="$EXAMPLES native-script native-table"

# The runners: x86_64 Linux and Windows, and an arm64 Mac. (A function, not
# an associative array: macOS ships bash 3.2.)
triple() {
  case "$1" in
    linux) echo x86_64-unknown-linux-gnu ;;
    macos) echo aarch64-apple-darwin ;;
    windows) echo x86_64-pc-windows-msvc ;;
  esac
}

case "$(uname -s)" in
  Linux) host=linux ;;
  Darwin) host=macos ;;
  MINGW*|MSYS*|CYGWIN*) host=windows ;;
  *) echo "unsupported host: $(uname -s)" >&2; exit 1 ;;
esac

executable() { if [ "$1" = windows ]; then echo "$2.exe"; else echo "$2"; fi; }

repo_root=$(cd "$(dirname "$0")/.." && pwd)

case "${1:-}" in
  build)
    compiler=${2:?usage: ci-cross-link.sh build <compiler> <output-dir>}
    out=${3:?usage: ci-cross-link.sh build <compiler> <output-dir>}
    rm -rf "$out"
    mkdir -p "$out/expected" "$out/native"
    out=$(cd "$out" && pwd)
    for example in $EXAMPLES; do
      source="$repo_root/docs/examples/$example.pep"
      native="$out/native/$(executable "$host" "$example")"
      "$compiler" "$source" -o "$native" --build "$out/native/build"
      "$native" > "$out/expected/$example.txt"
      for os in linux macos windows; do
        [ "$os" != "$host" ] || continue
        mkdir -p "$out/$os"
        "$compiler" --target "$(triple "$os")" "$source" -o "$out/$os/$(executable "$os" "$example")" --build "$out/$os/build"
      done
    done
    # The project native-script, from the test's files.
    project="$out/native-script"
    testdata="$repo_root/tools/pep-package/testdata"
    mkdir -p "$project/c"
    printf '[package]\nname = "app"\n' > "$project/pep.toml"
    cp "$testdata/native_main.pep.txt" "$project/main.pep"
    cp "$testdata/native_build.pep.txt" "$project/build.pep"
    cp "$testdata/native_add.c" "$project/c/add.c"
    compiler_path=$(cd "$(dirname "$compiler")" && pwd)/$(basename "$compiler")
    native="$out/native/$(executable "$host" native-script)"
    (cd "$project" && "$compiler_path" -o "$native")
    "$native" > "$out/expected/native-script.txt"
    for os in linux macos windows; do
      [ "$os" != "$host" ] || continue
      (cd "$project" && "$compiler_path" --target "$(triple "$os")" -o "$out/$os/$(executable "$os" native-script)")
    done
    rm -rf "$project"
    # The project native-table: the same C, compiled for the target by its
    # `[native]` table, with a define that a target condition chooses.
    project="$out/native-table"
    mkdir -p "$project/c"
    printf '[package]\nname = "app"\n\n[native]\nsources = ["c/*.c"]\n\n[target.%s.native]\ndefines = ["NATIVE_WINDOWS"]\n' "'OS(Windows)'" > "$project/pep.toml"
    cp "$testdata/native_main.pep.txt" "$project/main.pep"
    printf '#ifdef NATIVE_WINDOWS\nint native_add(int a, int b) { return a + b + 100; }\n#else\nint native_add(int a, int b) { return a + b; }\n#endif\n' > "$project/c/add.c"
    native="$out/native/$(executable "$host" native-table)"
    (cd "$project" && "$compiler_path" -o "$native")
    "$native" > "$out/expected/native-table.txt"
    for os in linux macos windows; do
      [ "$os" != "$host" ] || continue
      (cd "$project" && "$compiler_path" --target "$(triple "$os")" -o "$out/$os/$(executable "$os" native-table)")
    done
    rm -rf "$project"
    # The objects stay, so `run` can compare what two hosts compiled for
    # the same target when a program fails.
    rm -rf "$out/native"
    ;;
  run)
    artifacts=${2:?usage: ci-cross-link.sh run <artifacts-dir>}
    expected="$artifacts/cross-from-$host"
    [ -d "$expected/expected" ] || { echo "no output from this host's build in $artifacts" >&2; exit 1; }
    # Every program runs, so one run reports every pair that fails.
    count=0
    failures=0
    for from in "$artifacts"/cross-from-*; do
      [ "$from" != "$expected" ] || continue
      [ -d "$from/$host" ] || { echo "$(basename "$from") built nothing for $host" >&2; exit 1; }
      for example in $PROGRAMS; do
        program="$from/$host/$(executable "$host" "$example")"
        chmod +x "$program"
        count=$((count + 1))
        status=0
        "$program" > "$program.txt" || status=$?
        if [ "$status" = 0 ] && diff "$expected/expected/$example.txt" "$program.txt"; then
          continue
        fi
        failures=$((failures + 1))
        echo "::error::$(basename "$from")/$host/$example failed (exit status $status)"
        # What the failure is about, while the program is at hand.
        file "$program" || true
        if [ "$host" = linux ]; then
          readelf -lW "$program" | grep -E 'interpreter|LOAD|Type' || true
          # Static constructors: lld runs `.init_array`, never `.ctors`.
          readelf -SW "$program" | grep -E 'init_array|ctors|\.init|\.fini' || true
          readelf -dW "$program" | grep -E 'INIT|FINI|NEEDED' || true
          for object in "$from/$host/build/$example.o" "$from/$host/build/$example.units"/*.o; do
            echo "$object: $(readelf -SW "$object" | grep -oE '\.(init_array|ctors)[^ ]*' | tr '\n' ' ')"
          done
          command -v gdb > /dev/null || sudo apt-get install -y --no-install-recommends gdb > /dev/null || true
          gdb -batch -ex run -ex bt -ex 'x/6i $pc' "$program" 2>&1 | tail -25 || true
        fi
      done
    done
    # Code two other hosts compiled for this OS should be identical: the
    # compiler is deterministic (the bytes differ in the source paths each
    # embeds). Name the objects whose disassembly differs.
    others=$(for from in "$artifacts"/cross-from-*; do [ "$from" = "$expected" ] || echo "$from"; done)
    first=$(echo "$others" | head -1)
    second=$(echo "$others" | sed -n 2p)
    if [ "$failures" -gt 0 ] && [ -n "$second" ]; then
      (cd "$first/$host/build" && find . -name '*.o' | sort) | while read -r object; do
        lines=$(diff <(objdump -dr --no-show-raw-insn "$first/$host/build/$object" | tail -n +3) \
          <(objdump -dr --no-show-raw-insn "$second/$host/build/$object" | tail -n +3) | wc -l) || true
        [ "$lines" = 0 ] || echo "code differs ($lines diff lines): $object"
      done | head -40
    fi
    [ "$count" -gt 0 ] || { echo "no cross-linked programs in $artifacts" >&2; exit 1; }
    if [ "$failures" -gt 0 ]; then
      echo "$failures of $count cross-linked programs failed on $host" >&2
      exit 1
    fi
    echo "$count cross-linked programs ran on $host and printed what the native build printed"
    ;;
  *)
    echo "usage: ci-cross-link.sh build <compiler> <output-dir> | run <artifacts-dir>" >&2
    exit 1
    ;;
esac
