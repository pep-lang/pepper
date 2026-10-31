# Pepper

Pepper is a compiled, memory-safe programming language in the spirit of Rust
and Swift, built for clarity, simplicity and safe concurrency. Every struct
is reference counted, exactly like C++'s `std::shared_ptr`, so there is no
garbage collector and no ownership annotations to learn, and only
thread-safe values can be shared between threads. It compiles to native
code through LLVM, and it is written in Pepper.

```pepper
import async;

# [Shared] lets threads share a Point: the compiler checks every field is
# const and thread-safe.
[Shared]
struct Point {
    const x: int;
    const y: int;
    construct(this.x = 0, this.y = 0) {}
}

const total = async.Atomic<int>(0);

main(): int {
    var points = [Point(1, 2), Point(3, 4)];
    var threads = Array<async.Thread>();
    for (var p in points) {
        threads.append(async.Thread.spawn(() => { total.fetch_add(p.x * p.y); }));
    }
    for (var thread in threads) {
        thread.join();
    }
    print($"total: {total.load()}");
    return 0;
}
```

Take `[Shared]` away and the build fails: the closure captures a `Point`,
which is not thread-safe.

## Documentation

**The Pepper book: <https://docs.pepper-lang.dev/>** covers the
language, the tools and the standard library. It opens the newest release's
docs; [`/dev/`](https://docs.pepper-lang.dev/dev/) is main's, which
the links below open. Its source is [`docs/`](docs/src/SUMMARY.md).

## Install

Each release has the toolchain prebuilt for Linux (x64), macOS (arm64, x64)
and Windows (x64), and an install script that downloads it, puts `pepper`
on the `PATH` and offers to install what linking needs (clang, Xcode's
command line tools, or the Visual Studio Build Tools). While the repository
is private the script needs a GitHub token, which the
[GitHub CLI](https://cli.github.com) provides:

```sh
# Linux, macOS
gh api repos/pep-lang/pepper/contents/scripts/install.sh -H "Accept: application/vnd.github.raw" > install.sh
GITHUB_TOKEN=$(gh auth token) sh install.sh
```

```powershell
# Windows (PowerShell)
gh api repos/pep-lang/pepper/contents/scripts/install.ps1 -H "Accept: application/vnd.github.raw" > install.ps1
$env:GITHUB_TOKEN = gh auth token
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Then open a new terminal and check it with `pepper --version`. Toolchains
install side by side:

```sh
pepper install update             # the newest release, made the default
pepper install add 0.9.1          # another, kept beside it
pepper install list --available   # every release, and the x.y.z-dev build of main
pepper +0.9.1 build hello.pep     # one command with another toolchain
```

A project pins its toolchain with `toolchain = "0.9"` in its `pep.toml`.
See [Installing Pepper](https://docs.pepper-lang.dev/dev/tools/install.html)
and [Toolchains](https://docs.pepper-lang.dev/dev/tools/pep-install.html).

## Using it

`pepper` is the entry point to every tool:

| Command | What it does |
| --- | --- |
| [`pepper build`](https://docs.pepper-lang.dev/dev/tools/pep-build.html) | compiles a file, or the project a [`pep.toml`](https://docs.pepper-lang.dev/dev/tools/projects.html) describes |
| [`pepper new`](https://docs.pepper-lang.dev/dev/tools/pep-new.html) | starts a program or package (`pepper init` in the current folder) |
| [`pepper run`](https://docs.pepper-lang.dev/dev/tools/pep-run.html) | builds a program and runs it (0.9.3 and later) |
| [`pepper test`](https://docs.pepper-lang.dev/dev/tools/pep-test.html) | builds and runs the `[Test]` functions |
| [`pepper fmt`](https://docs.pepper-lang.dev/dev/tools/pep-fmt.html) | formats source in the one standard style |
| [`pepper doc`](https://docs.pepper-lang.dev/dev/tools/pep-doc.html) | generates the standard library reference and builds the book |
| [`pepper profile`](https://docs.pepper-lang.dev/dev/tools/pep-profile.html) | profiles a program and draws a flame graph |
| [`pepper package`](https://docs.pepper-lang.dev/dev/tools/pep-package.html) | adds and fetches a project's dependencies |

```sh
pepper run hello.pep              # build and run
pepper build -O hello.pep -o hello
pepper test src
pepper fmt -w src
pepper help                       # every command
```

The [VS Code extension](https://docs.pepper-lang.dev/dev/tutorial/getting-started.html#editor-support)
runs the language server, `pep-lsp`, for errors as you type, hover,
completion and go to definition.

## Contributing

The compiler (`tools/compiler`, also called pepc), the standard library
(`runtime/`) and every tool (`tools/`) are Pepper programs, built with the
`x.y.z-dev` build of main (CI and the release use stage 0, the build that
`.github/stage0` pins) and tested with `scripts/pepper-tests.sh`.
[Building Pepper from source](https://docs.pepper-lang.dev/dev/contributing/building.html)
([source](docs/src/contributing/building.md)) walks through the setup,
including LLVM 20, the build and the tests.

- [`AGENTS.md`](AGENTS.md): the rules every change follows, for people and
  agents alike.
- [`INTERNALS.md`](INTERNALS.md): the map of the compiler.
- [`.agents/skills/`](.agents/skills): step-by-step workflows, and the
  failure signatures of the build and the tests.

## License

Pepper is licensed under the [Apache License 2.0](LICENSE.md).
