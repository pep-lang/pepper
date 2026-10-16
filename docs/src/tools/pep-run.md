# Running a program: pep-run

`pep-run` builds a program and runs it straight away, the way
`python script.py` runs a script: there is no `-o` to choose and no
executable to clean up. `pepper run` runs it with the same arguments.

```bash
pepper run hello.pep               # build hello.pep, then run it
pepper run args.pep a b            # main sees a and b
pepper run -O2 -D FAST main.pep    # build options go before the file
pepper run -- --port 8080          # the project pep.toml describes
pepper run --entry bench tool.pep  # start in bench() instead of main()
```

```text
pep-run [BUILD OPTIONS] [<entry.pep>] [ARGUMENTS]...
pep-run [BUILD OPTIONS] -- [ARGUMENTS]...
```

## Arguments

- The arguments before the entry file are `pep-build`'s options (`-O2`,
  `-D NAME`, `-I DIR`, `-l LIB`, ...; see
  [The compiler: pep-build](pep-build.md)), and they apply as they do for
  `pepper build`, as do a project's `[build]` table and its `[Link]`
  libraries.
- The entry file is the first argument that ends in `.pep` and does not
  start with `-`. Everything after it goes to the program's `main`,
  options included: in `pepper run tool.pep --help`, `--help` is the
  program's.
- `--` ends the build options too. With no entry file, `pep-run` builds the
  project whose `pep.toml` is in the current folder or the nearest folder
  above it, as `pepper build` does, and the arguments after `--` go to it.
- The options that choose what `pep-build` writes are not taken: `-o`,
  `--lib`, `--test`, `--target` and the `--emit-...` options are an error
  that exits with status 2.

| Option | What it does |
| --- | --- |
| `--entry <name>` | Starts the program in the function `name` instead of `main`, as `pep-build --entry` does; it takes no parameters or one `String[]` (before the entry file only) |
| `-h`, `--help` | Prints the usage (before the entry file only) |
| `-V`, `--version` | Prints the version (before the entry file only) |

## How it runs

1. `pep-run` runs `pep-build` (beside `pep-run`, else on the `PATH`) to
   build the program into a folder of its own:
   `<Pepper home>/run/<key>/<entry stem>` (`main` for a project), where the
   key is a hash of the current folder, the build options and the entry
   file, and the Pepper home is `PEPPER_HOME`, else `~/.pepper`
   (`%LOCALAPPDATA%\pepper` on Windows; see
   [Toolchains: pep-install](pep-install.md)).
2. The build cache is `PEPPER_CACHE_DIR` when it is set, else
   `<Pepper home>/cache`, which every run shares, so the standard library is
   compiled once for all your scripts. When nothing changed, `pep-build`
   finds the program up to date and the run starts at once; when something
   did, only what changed is compiled again.
3. A compile error is reported exactly as `pepper build` reports it, nothing
   runs, and `pep-run` exits with `pep-build`'s status.
4. Otherwise the program runs in the folder `pep-run` was started in, so a
   relative path such as `data.txt` is found there, with `pep-run`'s
   standard input, output and error. On Linux and macOS it takes
   `pep-run`'s place, so signals such as Ctrl-C reach it directly; on
   Windows `pep-run` waits for it. Either way `pep-run` exits with the
   program's exit status.

Two runs of one program at the same time are safe: the linker writes the
executable to a temporary file and renames it into place, so neither ever
starts a half-written program.

The run folders are not removed on their own; delete `<Pepper home>/run`
to reclaim the space.
