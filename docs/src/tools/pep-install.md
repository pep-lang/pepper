# Toolchains: pep-install

`pep-install` installs Pepper toolchains side by side and picks the default
one, the way rustup and nvm do. `pepper install` runs it with the same
arguments:

```bash
pepper install list               # the installed toolchains, marking the default and the one in use here
pepper install list --available   # the releases with an archive for this machine
pepper install add 0.3            # installs the newest 0.3.x; the default stays as it is
pepper install use 0.3.0          # makes it the default
pepper install update             # installs the newest release and makes it the default
pepper install add --force 0.3.0  # installs 0.3.0 again, replacing it
pepper install remove 0.2.1
pepper install which              # the toolchain this folder uses, why, and its pep-build
```

```text
pep-install <command> [arguments]
```

A toolchain is one release of the compiler, its runtime and the tools
(`pep-build`, `pep-fmt`, `pep-test`, ...). The [`pepper` command](pepper.md)
that `pep-install` sits beside runs the tools of the toolchain a folder
uses: the one `pepper +<version>` names, else `PEPPER_TOOLCHAIN`'s, else the
one the project's `pep.toml` pins with `toolchain = "0.3"`, else the default
(see [Toolchains](pepper.md#toolchains)).

## Options and commands

| Command or option | What it does |
| --- | --- |
| `list` | Lists the installed toolchains, newest first, marking the default and the one the current folder uses, with why |
| `list --available`, `-a` | Lists the releases that have an archive for this machine instead, marking those installed |
| `add <version>` | Installs the newest release `<version>` names, unless it is installed; it becomes the default only when there was none |
| `add --force <version>`, `-f` | Installs it even when it is installed, replacing the home's copy |
| `use <version>` | Makes the newest installed toolchain `<version>` names the default |
| `update` | Installs the newest release, unless it is installed, and makes it the default; older toolchains stay installed. Then updates the home's `pepper` and `pep-install` from it |
| `update --force`, `-f` | Installs the newest release even when it is installed, replacing the home's copy |
| `remove <version>` | Removes the installed toolchain `<version>` names; it must name just one, and not the default |
| `which` | Prints the toolchain the current folder uses and why, then the path of its `pep-build`; fails when that toolchain is not installed |
| `--path <dir>` | Also finds toolchains in `<dir>`, before those `PEPPER_TOOLCHAIN_PATH` lists; repeatable, before or after the command (see [More toolchain folders](#more-toolchain-folders)) |
| `-h`, `--help` | Prints the commands; after a command, that command's options |
| `-V`, `--version` | Prints the version |

A `<version>` is exact (`0.3.0`), or a prefix (`0.3`, `0`) for the newest
release, or installed toolchain, that starts so, or `latest` for the newest.
A prerelease such as `0.4.0-dev`, the build of main that each merge
replaces, is picked only by naming it exactly; prefixes, `latest` and
`update` leave prereleases out.
Only releases are installed; there is no nightly channel.

The exit status is 0 on success, 1 when a command fails, and 2 for a
mistake on the command line.

## Where toolchains go

The Pepper home holds them:

```text
~/.pepper/bin/pepper                 the entry point
~/.pepper/bin/pep-install
~/.pepper/toolchains/0.3.0/bin/      a toolchain's pep-build, pep-fmt, ...
~/.pepper/toolchains/0.3.0/runtime/  and its runtime
~/.pepper/default-toolchain          the default toolchain's version
```

The [install scripts](install.md) set up the home: they install the newest
release this way, put its `pepper` and `pep-install` in `bin`, and move an
install from before toolchains into `toolchains/`.

`update` replaces the home's `pepper` and `pep-install` with the new
toolchain's when they differ. Each is written beside the old one and
renamed into place, the old one first moved aside to `<name>.old`; on
Windows, where a running program cannot be removed, that `.old` file is
removed by the next `update`.

`add --force` and `update --force` install a toolchain that is already
installed again, the way a fresh one is: downloaded, checked and unpacked
beside its folder. The old folder is then moved aside, the new one put in
its place and the old one removed, so no stale files remain, and a failed
download or unpack leaves the old toolchain as it was. On Windows a
toolchain one of whose programs is running (a `pep-lsp` the editor
started, say) cannot be moved, and the install fails, leaving it in place.

The home is the folder above the running `pep-install` when that is a home
(it has a `toolchains` folder), else `PEPPER_HOME`, else
`%LOCALAPPDATA%\pepper` on Windows and `~/.pepper` elsewhere.

## More toolchain folders

Toolchains are also found in the folders `PEPPER_TOOLCHAIN_PATH` lists,
separated as `PATH` separates them (`;` on Windows, `:` elsewhere), and for
`pep-install` in each `--path` folder, which come first. Each is laid out
as the home's `toolchains` folder is, a folder per toolchain named by its
version:

```text
/opt/pepper/0.3.0/bin/pep-build
/opt/pepper/0.3.0/runtime/
```

```bash
PEPPER_TOOLCHAIN_PATH=/opt/pepper pepper +0.3.0 build main.pep
pepper install --path /opt/pepper use 0.3.0
```

The home's own `toolchains` folder is searched first, so a toolchain there
wins over one of the same version elsewhere. `list` marks a toolchain found
elsewhere with its folder; `use`, `which` and `pepper +<version>` take it
as they take one in the home, and `add` and `update` count it as
installed (`--force` installs into the home all the same). `remove` removes
only toolchains in the home: a toolchain in another folder is left to
whoever put it there. A project's `pep.toml` cannot add folders, since
where toolchains are differs from one machine to the next.

## Editors

The VS Code extension runs the language server of the toolchain the
workspace uses, as `pepper install which` reports it; see
[pep-lsp](pep-lsp.md).

## Downloads

`add` and `update` find this machine's archive (`linux-x64`, `macos-arm64`,
`macos-x64` or `windows-x64`) among the GitHub releases, as the
[install scripts](install.md) do, download it and check it against its
`.sha256`. The archive is unpacked beside the toolchain's folder first, so
a download that fails or does not match its checksum leaves nothing behind.

| Variable | What it does |
| --- | --- |
| `PEPPER_HOME` | Where toolchains go, when `pep-install` does not run from a home |
| `PEPPER_TOOLCHAIN_PATH` | More folders to find toolchains in (see [More toolchain folders](#more-toolchain-folders)) |
| `PEPPER_INSTALL_RELEASES_URL` | Lists the releases from this URL instead of GitHub's API, for a mirror; it serves the same JSON |
| `GITHUB_TOKEN`, `GH_TOKEN` | A token sent to GitHub's API while the repository is private, and to nothing else |
