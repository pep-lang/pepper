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
| `use <version>` | Makes the newest installed toolchain `<version>` names the default |
| `update` | Installs the newest release, unless it is installed, and makes it the default; older toolchains stay installed |
| `remove <version>` | Removes the installed toolchain `<version>` names; it must name just one, and not the default |
| `which` | Prints the toolchain the current folder uses and why, then the path of its `pep-build`; fails when that toolchain is not installed |
| `-h`, `--help` | Prints the commands; after a command, that command's options |
| `-V`, `--version` | Prints the version |

A `<version>` is exact (`0.3.0`), or a prefix (`0.3`, `0`) for the newest
release, or installed toolchain, that starts so, or `latest` for the newest.
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

The home is the folder above the running `pep-install` when that is a home
(it has a `toolchains` folder), else `PEPPER_HOME`, else
`%LOCALAPPDATA%\pepper` on Windows and `~/.pepper` elsewhere.

## Downloads

`add` and `update` find this machine's archive (`linux-x64`, `macos-arm64`,
`macos-x64` or `windows-x64`) among the GitHub releases, as the
[install scripts](install.md) do, download it and check it against its
`.sha256`. The archive is unpacked beside the toolchain's folder first, so
a download that fails or does not match its checksum leaves nothing behind.

| Variable | What it does |
| --- | --- |
| `PEPPER_HOME` | Where toolchains go, when `pep-install` does not run from a home |
| `PEPPER_INSTALL_RELEASES_URL` | Lists the releases from this URL instead of GitHub's API, for a mirror; it serves the same JSON |
| `GITHUB_TOKEN`, `GH_TOKEN` | A token sent to GitHub's API while the repository is private, and to nothing else |
