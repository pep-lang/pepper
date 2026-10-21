# The package manager: pep-package

`pep-package` fetches a project's dependencies and keeps its `pep.toml` and
`pep.lock`. `pepper package` runs it with the same arguments:

```bash
pepper package add someone/geometry          # the newest version, imported as 'geometry'
pepper package add other/json@2.x --name fast_json
pepper package add --dev someone/fixtures    # only the project's tests and examples import it
pepper package add --target 'OS(Windows)' someone/winapi   # only builds for Windows use it
pepper package remove geometry
pepper package update                        # every dependency, as far as the ranges allow
pepper package update --verify               # one at a time, keeping the updates that build
pepper package fetch                         # what pep.lock lists
```

```text
pep-package [-C <dir>] [--locked] [--offline] [--frozen] <command> [arguments]
```

It works on the project whose `pep.toml` is in the current folder or the
nearest folder above it (see [Projects: pep.toml](projects.md)). Packages
are fetched with `git` when it is on the `PATH`; signing in to a private
repository is git's concern (its credential helpers and SSH keys), so
whatever lets `git clone` reach a repository lets `pep-package` fetch it.
Without git, `pep-package` downloads the host's archive of each commit
`pep.lock` pins over HTTPS instead (see [Fetching without git](#fetching-without-git)),
so a project with a `pep.lock` builds on a machine with no git.

`pepper build` fetches on its own what `pep.lock` lists and `.pep/deps`
lacks, so a fresh clone of a project builds with `pepper build` alone.

## Options and commands

| Command or option | What it does |
| --- | --- |
| `-C <dir>`, `--directory <dir>` | Works on the project at or above `<dir>` instead of the current folder |
| `--locked` | Fails, leaving `pep.lock` as it is, when the command would change it (see [Reproducible builds](#reproducible-builds)) |
| `--offline` | Uses only what `.pep/deps` holds, and fails on anything that needs the network |
| `--frozen` | Both `--locked` and `--offline` |
| `fetch` | Fetches what `pep.lock` lists, and resolves what `pep.toml` changed since `pep.lock` was written |
| `fetch <source>...` | Fetches only those locked packages (`github:owner/name`), at their locked commits, resolving nothing |
| `add <owner/name>[@<range>]` | Adds a dependency at its newest version, or at a range |
| `add ... --name <name>`, `-n <name>` | The name source code imports it by |
| `add ... --dev` | Adds it to `[dev-dependencies]`, which only the project's tests and examples import |
| `add ... --target <condition>`, `-t <condition>` | Adds it to `[target.'<condition>'.dependencies]`, which only builds for the targets the condition selects use |
| `remove <name>` | Removes a dependency or dev-dependency, by its name or its `owner/name` |
| `update [<name>...]` | Moves dependencies to the newest versions their ranges allow; every one when none is named |
| `update --verify` | Updates one dependency at a time and builds after each, keeping only the updates that build |
| `-h`, `--help` | Prints the options; after a command, that command's |
| `-V`, `--version` | Prints the version |

`--locked`, `--offline` and `--frozen` go before or after the command
(`pepper package fetch --locked`). The exit status is 0 on success, 1 when
a command fails, and 2 for a mistake on the command line.

### `fetch`

Fetches every package in `pep.lock` into the project's `.pep/deps` at its
locked commit. When `pep.toml` names a dependency `pep.lock` does not list,
or asks for a revision the locked one does not satisfy, `fetch` resolves it
and updates `pep.lock`; everything else keeps its locked revision.
Resolving reads the `pep.toml` of every package in the graph, so it
fetches every platform's packages, those of
[`[target]` tables](projects.md#targetconditiondependencies) included.

`fetch <source>...` fetches only the locked packages named, at the commits
`pep.lock` records, and resolves nothing. It is what a build runs when its
lock lists every dependency: `pepper build` names the packages its target
needs and `.pep/deps` lacks, so a build fetches no other platform's.

### `add <owner/name>[@<range>]`

Adds a dependency to `pep.toml`'s `[dependencies]` and fetches it, keeping
the file's comments and layout. An argument that starts with `github:`,
`gitlab:` or `codeberg:` (`gitlab:group/pepper-json`) names its host.
Without one, `add` looks the repository up on each host in the order
`pep.toml`'s `[fetch]` `hosts` lists (GitHub, GitLab, then Codeberg by
default; see [Projects: pep.toml](projects.md#fetch)) and uses the first
that has it. When more than one does, it says so:

```text
pep-package: other/numbers is on github and codeberg; adding github:other/numbers (prefix it with 'codeberg:' for another)
```

```bash
pepper package add someone/geometry        # geometry = { github = "someone/geometry", version = "1.4.2" }
pepper package add someone/geometry@1.2.x  # ... version = "1.2.x"
pepper package add codeberg:third/shapes   # only Codeberg, without looking elsewhere
```

Without a range, the dependency gets the newest version tag this toolchain
builds (see [Resolving versions](#resolving-versions); as a range
that accepts compatible later versions: `1.4.2` accepts 1.4.2 up to, not
including, 2.0.0); a repository with no version tags follows its default
branch. The name source code imports defaults to the repository's last part,
with `-` and `.` turned into `_` (`other/json` adds `json`); `--name` gives
another. A name already in `pep.toml`, or the name of a runtime module
(`io`, `async`), is an error that suggests `--name`.

`--dev` adds it to `[dev-dependencies]` instead: only the project's tests
and examples import it, and projects that depend on this one ignore it
(see [Projects: pep.toml](projects.md#dev-dependencies)).

`--target <condition>` adds it to `[target.'<condition>'.dependencies]`:
only a build for a target the condition selects sees it. The condition is
what `[Target(...)]` takes (`OS(Windows)`, `OS(Linux) && Arch(x64)`; see
[Platform selection](../language/platform-selection.md)); quote it for the
shell. It cannot be given with `--dev`.

### `remove <name>`

Removes the dependency with that name (or that `owner/name`) from
`pep.toml`, whichever table it is in, and drops from `pep.lock` every
package nothing needs any more.

### `update [<name>...]`

Moves the named dependencies (every one, when none is named) to the newest
version their ranges allow, and says which other package holds one back
when one does:

```text
pep-package: github:other/numbers stays at 1.3.1, not 2.0.0: geometry 1.1.0 wants 1
```

A dependency on a branch moves to the branch's newest commit.

### `update --verify`

Updates one dependency at a time and runs `pep-build` (beside
`pep-package`, else on the `PATH`) on the project after each. An update
that does not build is rolled back, and the command lists those it rolled
back.

## pep.lock

`pep.lock`, beside `pep.toml`, records the exact commit of every package in
the dependency graph, its dependencies' dependencies included, and the
`sha256` checksum of its files. Commit it with `pep.toml`: it is what makes
a fresh clone build the same code.

```toml
version = 1

[[package]]
name = "geometry"
source = "github:someone/geometry"
version = "1.1.0"
commit = "0582024b9cd7a71044ee1aaa7099286f59e2df46"
sha256 = "7546a83a7f23d13454fd8b8f94281b6fd35f8dce49e9db9729c81208d35dacc8"
```

A package that only the project's `[dev-dependencies]` lead to has
`dev = true`; one that a dependency leads to as well does not.

`pep.lock` lists every platform's packages, so it is the same whichever
system writes it, as `Cargo.lock` is: a project locked on Linux builds on
Windows with no change to the lock, and `--locked` passes on both. A
package that only `[target.'<condition>'.dependencies]` lead to has
`target`, the condition under which a build needs it; on the way to it,
conditions join with `&&` and other ways with `||`, so
`target = "(OS(Linux)) || (OS(Windows))"` is needed on either. A build
fetches a package only when its `target` holds for what it builds for,
the platform `--target` names in a cross build.

```toml
[[package]]
name = "winapi"
source = "github:someone/winapi"
version = "1.0.0"
commit = "4a1f0c7e9b2d3c5a6e8f0a1b2c3d4e5f60718293"
sha256 = "..."
target = "OS(Windows)"
```

The checksum covers the files of the commit as the host's archive of it
holds them, not the archive's bytes, which a host may compress
differently from one download to the next. It is the SHA-256 of every
file, symlink and hard link, in path order, each written as its kind
(`f`, `x` for a file anyone may run, `l`, `h`), its path, its length and
its contents. With git, `pep-package` computes it from `git archive` of
the checkout, which holds the same files, so a lock written with git
verifies a later fetch without it. A lock from before checksums were kept
gains them on the next fetch.

A package whose files do not match is an error that names it and both
checksums:

```text
pep-package: error: cannot fetch github:other/numbers: the files of github:other/numbers 2c7a9e01d4f3 do not match pep.lock: sha256 9f2c..., expected 41b0...
```

A command that leaves the graph as it was leaves `pep.lock` untouched, so
a checkout with Windows line endings stays as git wrote it.

## Reproducible builds

CI builds want to fail rather than quietly change what they build:

- **`--locked`** (or `PEPPER_LOCKED=1`): a command that would change
  `pep.lock` fails instead, says what would change, and leaves `pep.lock`
  as it was. `fetch --locked` passes only when `pep.lock` already matches
  `pep.toml`; it may still check packages out into `.pep/deps`.
- **`--offline`** (or `PEPPER_OFFLINE=1`): nothing is cloned, fetched,
  downloaded or looked up. A package `.pep/deps` already holds at its
  locked commit is used; one it lacks is an error, and so is anything that
  must read which versions a repository offers (`add`, `update`, or a
  `pep.toml` change `pep.lock` does not cover).
- **`--frozen`**: both.

```text
$ pepper package fetch --locked
pep-package: error: pep.lock would change, and --locked keeps it as it is:
  updated numbers: numbers 1.3.1 -> numbers 2.0.0
run the command without --locked (or PEPPER_LOCKED), then commit pep.lock

$ pepper package fetch --offline
pep-package: error: cannot fetch github:someone/geometry: --offline, and .pep/deps/github.com/someone/geometry does not hold the commit 0582024b9cd7; run 'pepper package fetch' without --offline (or PEPPER_OFFLINE) first
```

`pepper build` and `pepper test` take the same three options for the
fetch they do on their own (see [The compiler: pep-build](pep-build.md)).

## Fetching without git

When git is not on the `PATH`, `pep-package` fetches each commit
`pep.lock` pins as the host's archive of it, over HTTPS, checks its files
against the lock's `sha256` and unpacks it, without its top-level folder,
into `.pep/deps`:

| Host | Archive |
| --- | --- |
| GitHub | `https://codeload.github.com/<owner>/<name>/tar.gz/<commit>` |
| GitLab | `https://gitlab.com/<owner>/<name>/-/archive/<commit>/<name>-<commit>.tar.gz` |
| Codeberg | `https://codeberg.org/<owner>/<name>/archive/<commit>.tar.gz` |

An unpacked package has a `.pep-commit` file naming its commit in place of
`.git`. Choosing a revision still needs git, since it reads which tags
and branches a repository offers: `add`, `update`, and a `fetch` that must
resolve a dependency `pep.lock` does not pin (or a tag, which may have
moved) fail without it, saying so. Private repositories need git too, as
authentication is git's concern.

## Resolving versions

The whole project uses one version of each package: one checkout of
`github:other/numbers` serves every package that depends on it, whatever
name each imports it by.

- A version range picks the newest version tag (`v1.2.3` or `1.2.3`) that
  every package's range accepts. When none does, resolution fails and names
  each package's requirement and the versions the repository offers.
- A branch, tag or commit must be the same in every package that names it.
- The project's own `pep.toml` overrides its dependencies: a package it
  names gets the revision it asks for, even outside the range a dependency
  declares, and `pep-package` says which requirement it overrode.
- A locked revision stays while it still satisfies every requirement;
  `update` is what moves it.
- The project's own `[dev-dependencies]` are resolved with its
  dependencies, as requirements of the project; a dependency's
  `[dev-dependencies]` are not part of the graph at all.
- Every `[target.'<condition>'.dependencies]`, the project's and its
  dependencies', is resolved with the rest, whatever the platform
  resolving, so one version of a package serves every platform.

### The toolchain a package needs

A package states the oldest toolchain release that builds it with
`minimum_toolchain` in its `[package]` table (see
[Projects](projects.md#package)). `add`, `update` and `fetch` resolve for
the toolchain `pep-package` belongs to (the release `pep-package --version`
prints, which `pepper` picks with the rest of the toolchain):

- A version range skips every version whose `minimum_toolchain` is newer,
  picking the newest one left, and says which it skipped and why:

  ```text
  pep-package: github:other/websocket skipped 1.3.0 (needs toolchain 0.11.0); this is 0.10.1
  ```

  When every version the ranges accept needs a newer toolchain, resolution
  fails and names what each needs.
- A locked version that needs a newer toolchain is an error naming the
  package's version and both toolchains; `update` moves it to a version
  this toolchain builds. So is a branch, tag or commit that needs one.

Only the `pep.toml` of the version picked, and of the newer ones the ranges
accept, are read: from the package's clone in `.pep/deps`, without checking
them out, each once per run.

## Environment variables

| Variable | What it does |
| --- | --- |
| `PEPPER_PACKAGE_GITHUB_URL`, `PEPPER_PACKAGE_GITLAB_URL`, `PEPPER_PACKAGE_CODEBERG_URL` | Fetches that host's repositories from another address (a mirror, or a folder of repositories as a `file://` URL): `<address>/<owner>/<name>.git` |
| `PEPPER_PACKAGE_GITHUB_ARCHIVE_URL`, `PEPPER_PACKAGE_GITLAB_ARCHIVE_URL`, `PEPPER_PACKAGE_CODEBERG_ARCHIVE_URL` | Downloads that host's archives, when git is missing, from another `http://` or `https://` address (a mirror): `<address>/<owner>/<name>/<commit>.tar.gz` |
| `PEPPER_LOCKED` | Set to anything but empty or `0`, the same as `--locked` |
| `PEPPER_OFFLINE` | Set to anything but empty or `0`, the same as `--offline` |
| `PEPPER_RUNTIME` | The runtime folder whose modules a dependency may not be named like, as for the compiler |

## Building it

`pep-package` is written in Pepper (`tools/pep-package`) and reads and
edits `pep.toml` and `pep.lock` with the runtime's
[toml module](../reference/toml-module.md), and its versions and ranges
with the [`semver` package](https://github.com/pep-lang/pepper-semver),
which its first build fetches (with git when no `pep-package` is
installed):

```bash
pepper build tools/pep-package/main.pep -o pep-package
```
