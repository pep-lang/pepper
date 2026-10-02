#!/usr/bin/env python3
"""Cross-checks the compress module against Python's zlib and gzip: every
format, level and mode on a small corpus must round-trip both ways, and
corrupted streams must fail cleanly (an error, never a crash).

    python3 benchmarks/compress/check.py [--tool PATH]

Prints the compressed sizes next to zlib's at level 6 and ends with
`failures 0` when everything passed (exit status 1 otherwise).
"""
import argparse, gzip, os, random, subprocess, tempfile, zlib

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))

parser = argparse.ArgumentParser()
parser.add_argument("--tool")
args = parser.parse_args()

work = tempfile.mkdtemp(prefix="compress-check-")
tool = args.tool
if tool is None:
    tool = os.path.join(work, "tool")
    subprocess.run([os.path.join(root, "target", "release", "pep-build"), os.path.join(here, "tool.pep"),
                    "-O", "-o", tool], check=True, cwd=root)
source = os.path.join(work, "in")
packed = os.path.join(work, "in2")
out = os.path.join(work, "out")

random.seed(1)
text = open(os.path.join(root, "INTERNALS.md"), "rb").read()
sources = b""
for directory, _, files in sorted(os.walk(os.path.join(root, "runtime"))):
    for name in sorted(files):
        sources += open(os.path.join(directory, name), "rb").read()
corpus = [
    ("empty", b""),
    ("one", b"a"),
    ("text", text),
    ("random", random.randbytes(200000)),
    ("zeros", b"\0" * 300000),
    ("mixed", b"".join(random.choice([b"abc", b"hello world ", random.randbytes(5), b"\n"]) for _ in range(100000))),
    ("runtime", sources),
]

def wrap(form, data, level):
    if form == "raw":
        compressor = zlib.compressobj(level, zlib.DEFLATED, -15)
        return compressor.compress(data) + compressor.flush()
    if form == "zlib":
        return zlib.compress(data, level)
    return gzip.compress(data, level)

def unwrap(form, data):
    if form == "raw":
        return zlib.decompress(data, -15)
    if form == "zlib":
        return zlib.decompress(data)
    return gzip.decompress(data)

def run(*command):
    return subprocess.run([tool, *command], capture_output=True)

failures = 0
for name, data in corpus:
    open(source, "wb").write(data)
    for form in ["raw", "zlib", "gzip"]:
        for level in [0, 1, 6, 9]:
            for mode in ["c", "sc"]:
                run(mode, form, str(level), source, out).check_returncode()
                result = open(out, "rb").read()
                try:
                    ok = unwrap(form, result) == data
                except Exception as error:
                    ok = False
                    print(error)
                if not ok:
                    failures += 1
                    print("FAIL compress", name, form, level, mode)
                if form == "gzip" and mode == "c" and level == 6:
                    print(f"{name:8} {len(data):9,} bytes: pepper {len(result):9,}, zlib {len(wrap(form, data, 6)):9,}")
            open(packed, "wb").write(wrap(form, data, level))
            for mode in ["d", "sd"]:
                if run(mode, form, "0", packed, out).returncode != 0 or open(out, "rb").read() != data:
                    failures += 1
                    print("FAIL decompress", name, form, level, mode)

# Several gzip members one after another.
open(packed, "wb").write(gzip.compress(b"first ") + gzip.compress(b"second"))
for mode in ["d", "sd"]:
    run(mode, "gzip", "0", packed, out).check_returncode()
    if open(out, "rb").read() != b"first second":
        failures += 1
        print("FAIL multi-member", mode)

# Corrupted and truncated streams: an error (exit status 2) or, by chance,
# some output, but never a crash.
random.seed(7)
for index in range(200):
    damaged = bytearray(wrap("raw", text[:60000], random.choice([1, 6, 9])))
    for _ in range(random.randint(1, 8)):
        damaged[random.randrange(len(damaged))] = random.randrange(256)
    if random.random() < 0.3:
        damaged = damaged[:random.randrange(len(damaged))]
    open(packed, "wb").write(damaged)
    for mode in ["d", "sd"]:
        status = run(mode, "raw", "0", packed, out).returncode
        if status not in (0, 2):
            failures += 1
            print("FAIL corrupt input", index, mode, "exit status", status)

print("failures", failures)
raise SystemExit(1 if failures else 0)
