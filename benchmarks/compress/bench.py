#!/usr/bin/env python3
"""Times the compress module against zlib (the gzip command) on the runtime
sources repeated 8 times (about 12 MB), and checks every result round-trips.

    python3 benchmarks/compress/bench.py [--runs N] [--tool PATH]

Builds `tool.pep` with `target/release/pep-build -O` unless --tool names a
binary already built (to compare two builds of the runtime). Prints the best
of N wall-clock runs of each operation; both sides pay for process start-up
and file I/O.
"""
import argparse, gzip, os, subprocess, sys, tempfile, time

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))

parser = argparse.ArgumentParser()
parser.add_argument("--runs", type=int, default=5)
parser.add_argument("--tool")
args = parser.parse_args()

work = tempfile.mkdtemp(prefix="compress-bench-")
tool = args.tool
if tool is None:
    tool = os.path.join(work, "tool")
    subprocess.run([os.path.join(root, "target", "release", "pep-build"), os.path.join(here, "tool.pep"),
                    "-O", "-o", tool], check=True, cwd=root)

sources = b""
for directory, _, files in sorted(os.walk(os.path.join(root, "runtime"))):
    for name in sorted(files):
        if name.endswith(".pep"):
            sources += open(os.path.join(directory, name), "rb").read()
data = sources * 8
plain = os.path.join(work, "input.txt")
open(plain, "wb").write(data)
packed = os.path.join(work, "input.gz")
open(packed, "wb").write(gzip.compress(data, 6))
out = os.path.join(work, "out")
reference = os.path.join(work, "reference")

def best(command):
    fastest = float("inf")
    for _ in range(args.runs):
        start = time.perf_counter()
        subprocess.run(command, check=True)
        fastest = min(fastest, time.perf_counter() - start)
    return fastest

print(f"input: {len(data):,} bytes, best of {args.runs}")
print(f"{'operation':24} {'pepper':>8} {'gzip':>8} {'ratio':>6}  {'pepper size':>12} {'gzip size':>12}")
for level in [1, 6, 9]:
    mine = best([tool, "c", "gzip", str(level), plain, out])
    size = os.path.getsize(out)
    if gzip.decompress(open(out, "rb").read()) != data:
        sys.exit(f"level {level}: the output does not decompress to the input")
    theirs = best(["sh", "-c", f"gzip -{level} -c '{plain}' > '{reference}'"])
    print(f"{'compress, level ' + str(level):24} {mine:8.3f} {theirs:8.3f} {mine / theirs:6.2f}  "
          f"{size:12,} {os.path.getsize(reference):12,}")
for mode, name in [("d", "decompress, one call"), ("sd", "decompress, streaming")]:
    mine = best([tool, mode, "gzip", "0", packed, out])
    if open(out, "rb").read() != data:
        sys.exit(f"{name}: wrong output")
    theirs = best(["sh", "-c", f"gzip -dc '{packed}' > '{reference}'"])
    print(f"{name:24} {mine:8.3f} {theirs:8.3f} {mine / theirs:6.2f}")
