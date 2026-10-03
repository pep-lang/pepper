# Profiling with pep-profile

`pep-profile` runs a program under a sampling profiler and writes a
[flame graph](https://www.brendangregg.com/flamegraphs.html) of where it
spends its time: an SVG that any browser opens, with one box per function,
as wide as the share of samples the function was on the stack for, above
the function that called it. Hover over a box to see its numbers; click it
to zoom in, and click "Reset zoom" to zoom back out.

```bash
pepper profile main.pep                     # build it, run it, write main.svg
pepper profile ./server -- --port 8080      # an executable, with its arguments
pepper profile --pid 4242 --duration 10     # a running process, for 10 seconds
pepper profile -i main.json -o main.svg     # draw a recording made earlier
```

`pep-profile` records with a profiler that is already installed rather than
sampling the program itself:

| Profiler | Platforms | Install |
| --- | --- | --- |
| [samply](https://github.com/mstange/samply) | Linux, macOS, Windows | `cargo install --locked samply` |
| perf | Linux | your distribution's `linux-tools` (or `perf`) package |
| `sample` | macOS | comes with macOS |

It uses samply when it is installed, and otherwise perf on Linux or
`sample` on macOS; on Windows, samply is the one supported. When none is
installed it says what to install. `--profiler` picks one.

On Windows, samply records the system's ETW events, which needs
administrator rights: run `pep-profile` from an Administrator terminal
("Run as administrator"). Without them it stops at once and says so, rather
than waiting on a UAC prompt. Drawing a recording with `--input` needs no
rights.

`pep-profile` is written in Pepper (`tools/pep-profile`). Build it with the
compiler, with `tools/` on the import path, and put it next to `pepper` so
that `pepper profile` finds it:

```bash
target/release/pep-build -I tools tools/pep-profile/main.pep -o target/release/pep-profile
```

## Usage and options

```text
pep-profile [options] <program.pep | executable> [-- arguments...]
pep-profile [options] --pid <PID>
pep-profile [options] --input <FILE>
```

| Option | What it does | Default |
| --- | --- | --- |
| `<program>` | The `.pep` file or executable to profile, then its arguments | |
| `-o <file>`, `--output <file>` | The flame graph to write | the program's name with `.svg` |
| `-F <hz>`, `--frequency <hz>` | Samples per second | 999 |
| `-d <seconds>`, `--duration <seconds>` | Stop recording after this long | when the program ends; 10 s with `--pid` |
| `-p <pid>`, `--pid <pid>` | Record a running process instead of starting one | |
| `-i <file>`, `--input <file>` | Draw a recording made earlier instead of recording | |
| `--profiler <name>` | Record with `samply`, `perf` or `sample`, or the profiler at a path | the first installed |
| `--symbolizer <path>` | The `llvm-symbolizer` that names frames, or `none` | found on the `PATH` |
| `-l`, `--lines` | End each frame's name with its file and line | off |
| `--idle` | Keep the samples of threads that were waiting, not running (samply) | off |
| `--title <text>` | The flame graph's title | `Flame graph: <name>` |
| `--renderer <name>` | What draws the flame graph: `builtin`, `inferno` or `flamegraph.pl` | `builtin` |
| `--folded <file>` | Also write the folded stacks | |
| `--raw <file>` | Also keep the profiler's own recording | |
| `-I <dir>`, `--import-path <dir>` | A folder `pep-build` searches for imports, when building a `.pep` file | |
| `--open` | Open the flame graph when it is written | off |
| `-h`, `--help` | Print the options | |
| `-V`, `--version` | Print the version | |

Give exactly one of a program, `--pid` and `--input`. The program's own
arguments go after it; put `--` before them when any starts with `-`, so
that `pep-profile` does not read them as its own options. `pep-profile`
exits with 0 once the flame graph is written, whatever the program's own
exit status, with 1 when it cannot record or draw one, and with 2 for a
usage error.

## Profiling a program

Given a `.pep` file, `pep-profile` first builds it with `pep-build`, found
next to `pep-profile` or on the `PATH`, as

```bash
pep-build main.pep -O -g --frame-pointers -o <scratch>/main
```

`-O` profiles the code that ships; `-g` gives the frames their names and
lines; and `--frame-pointers` keeps the frame pointer in every function, so
that the profiler walks each sampled stack quickly and completely (see
[pep-build](pep-build.md#--frame-pointers)). Pass `-I` for each folder the
program imports from. An executable is run as it is: build it with the
same options to get the same detail.

The program runs with the terminal's standard input and output. Recording
stops when it exits, or after `--duration` seconds. With perf, `--duration`
stops the program with `timeout`; with samply and `sample` the program
keeps running once recording stops, and `sample` then ends it.

`--pid` records a process that is already running, for `--duration`
seconds (10 by default). samply and perf need permission to do that: on
Linux, `kernel.perf_event_paranoid` must allow it (samply asks for 1 or
lower) or the profiler must run as root; on macOS, `sample` can attach to
your own processes.

samply also records each thread while it waits, as samples that used no
CPU. On Windows, a thread pool that Windows starts in every process sits
waiting the whole run, and alone would fill half the graph. So
`pep-profile` leaves out every sample of a samply recording in which its
thread used no CPU, and the graph shows where the program ran. `--idle`
keeps them, to see where threads block. It changes nothing with perf or
`sample`.

## Names in the flame graph

Every frame is named the way the source names it:

- A function or method by its name: `work`, `Point.length`,
  `Box<int>.get`. A generic specialization keeps its type arguments.
- A closure by where it is written: `closure at main.pep:14`.
- A function the optimizer inlined still has a frame of its own, inside the
  function it was inlined into.
- With `--lines`, a frame also gives the file and line it is at:
  `work (main.pep:17)`. A function then gets one frame per line that was
  running, which shows where in a long function the time goes.

These names come from the program's debug info, read by
[`llvm-symbolizer`](https://llvm.org/docs/CommandGuide/llvm-symbolizer.html),
which LLVM installs: `pep-profile` looks for `llvm-symbolizer` and its
versioned names (`llvm-symbolizer-20`) on the `PATH`, then in
`$LLVM_SYS_<major>1_PREFIX/bin` and the usual LLVM install folders.
`--symbolizer` names one, and `--symbolizer none` skips it. Without one,
frames take the profiler's symbol names, which `pep-profile` demangles:
Pepper's linker name `_PArray_3cint_3e.count` shows as `Array<int>.count`,
and a closure as `closure #0 in main`. Inlined functions then have no
frames of their own, and `--lines` adds nothing.

## Recordings

`--raw <file>` keeps the profiler's recording: samply's profile (with its
symbols beside it, in `<file>` with `.syms.json` in place of `.json`),
perf's `perf.data`, or `sample`'s report. A samply profile opens in the
[Firefox Profiler](https://profiler.firefox.com/) (`samply load <file>`),
which shows the samples over time; `perf.data` opens in `perf report`.

`--input <file>` draws a flame graph from such a recording instead of
making a new one, telling the format from what the file holds:

- a samply profile (JSON);
- a `perf.data` file (read with `perf script`), or the text
  `perf script -F ip,sym,symoff,dso` writes;
- the report `sample` writes;
- folded stacks, as `--folded` writes them.

Frames are named from the libraries the recording names, when they are
still on this machine.

`--folded <file>` writes the folded stacks the flame graph is drawn from,
in the "collapsed" format other flame graph tools read: one line per
distinct stack, its frames from the outermost in, joined by `;`, then a
space and its sample count.

```text
_start;__libc_start_main_impl;main;work;Box<int>.get 533
```

## Renderers

The flame graph is drawn by a renderer built into `pep-profile`, so it needs
nothing else installed. `--renderer inferno` draws it with
[inferno](https://github.com/jonhoo/inferno)'s `inferno-flamegraph`
(`cargo install inferno`), and `--renderer flamegraph.pl` with Brendan
Gregg's [`flamegraph.pl`](https://github.com/brendangregg/FlameGraph), each
found on the `PATH`, for their extra features such as search.
