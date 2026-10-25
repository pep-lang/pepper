# The package manager: pep-package

`pep-package` fetches a project's dependencies and keeps its `pep.toml` and
`pep.lock`. `pepper package` runs it with the same arguments:

```bash
pepper package add someone/geometry          # the newest version, imported as 'geometry'
pepper package add other/json@2.x --name fast_json
pepper package add semver                    # the package the index lists as 'semver'
pepper package search terminal               # the index's packages these words describe
pepper package info semver                   # its description, versions, toolchain and license
pepper package add --dev someone/fixtures    # only the project's tests and examples import it
pepper package add --target 'OS(Windows)' someone/winapi   # only builds for Windows use it
pepper package add --optional --features simd someone/zlib  # only a feature turns it on
pepper package remove geometry
pepper package update                        # every dependency, as far as the ranges allow
pepper package update --verify               # one at a time, keeping the updates that build
pepper package fetch                         # what pep.lock lists
pepper package publish --dry-run             # check and test the release pep.toml's version names
pepper package publish                       # ... then tag it v<version> (<member>-v<version>) and push the tag
pepper package tree                          # the dependency graph pep.lock records
pepper package tree --invert numbers         # what depends on numbers
pepper package why numbers                   # the paths from the project to numbers
pepper package outdated                      # packages behind their ranges or the newest version
pepper package install someone/tool          # builds its program into the Pepper home's bin
pepper package install --list                # what is installed there, and from where
pepper package uninstall tool
pepper package audit                         # locked packages a security advisory affects
pepper package vendor                        # every locked package into vendor/, for builds with no network
pepper package cache info                    # the download cache every project shares
pepper package cache clean
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

In a [workspace](projects.md#workspaces-workspace), `pep.lock` and
`.pep/deps` are the root's, resolved for every member at once, wherever
it runs; `add` and `remove` change the `pep.toml` of the member it runs
in, and `publish` publishes that member.

`pepper build` fetches on its own what `pep.lock` lists and `.pep/deps`
lacks, so a fresh clone of a project builds with `pepper build` alone.
Every package is downloaded once per machine, into a
[download cache](#the-download-cache) that all projects share.

## Options and commands

| Command or option | What it does |
| --- | --- |
| `-C <dir>`, `--directory <dir>` | Works on the project at or above `<dir>` instead of the current folder |
| `--locked` | Fails, leaving `pep.lock` as it is, when the command would change it (see [Reproducible builds](#reproducible-builds)) |
| `--offline` | Uses only what `.pep/deps` and the [download cache](#the-download-cache) hold, and fails on anything that needs the network |
| `--frozen` | Both `--locked` and `--offline` |
| `fetch` | Fetches what `pep.lock` lists, and resolves what `pep.toml` changed since `pep.lock` was written |
| `fetch <source>...` | Fetches only those locked packages (`github:owner/name`), at their locked commits, resolving nothing |
| `add <owner/name>[@<range>]` | Adds a dependency at its newest version, or at a range |
| `add <name>[@<range>]` | Adds the package the [package index](#the-package-index) lists as `<name>`, imported by that name |
| `add ... --name <name>`, `-n <name>` | The name source code imports it by |
| `add ... --package <name>` | Depends on the member `<name>` of the repository's workspace, at a version of its own `<name>-v<version>` tags (see [A member as a Git dependency](projects.md#a-member-as-a-git-dependency)) |
| `add ... --dev` | Adds it to `[dev-dependencies]`, which only the project's tests and examples import |
| `add ... --target <condition>`, `-t <condition>` | Adds it to `[target.'<condition>'.dependencies]`, which only builds for the targets the condition selects use |
| `add ... --optional` | Marks it `optional = true`: a build uses it only when a feature turns it on |
| `add ... --features <names>`, `-F <names>` | The dependency's features to turn on, written to its `features`: a comma-separated list, or repeat the option |
| `add ... --no-default-features` | Leaves the dependency's `default` feature off: `default-features = false` |
| `remove <name>` | Removes a dependency or dev-dependency, by its name or its `owner/name` |
| `update [<name>...]` | Moves dependencies to the newest versions their ranges allow; every one when none is named |
| `update --verify` | Updates one dependency at a time and builds after each, keeping only the updates that build |
| `publish` | Checks the package and runs its tests, then tags its version and pushes the tag (see [`publish`](#publish)) |
| `publish --dry-run` | Checks and tests, but neither tags nor pushes |
| `tree` | Prints the dependency graph `pep.lock` records (see [`tree`](#tree)) |
| `tree --depth <n>`, `-d <n>` | Prints only `<n>` levels of dependencies below the project |
| `tree --invert <name>`, `-i <name>` | Prints what depends on a package instead, down to the project (see [`tree --invert`](#tree---invert-name)) |
| `tree --json` | Prints the tree as JSON (see [JSON output](#json-output)) |
| `why <name>` | Prints the paths from the project to a package, the first 20 (see [`why`](#why-name)) |
| `why --all` | Prints every path |
| `why --json` | Prints the paths as JSON |
| `outdated` | Lists the packages behind the newest version their ranges allow, or the newest overall (see [`outdated`](#outdated)) |
| `outdated --exit-code` | Exits with status 1 when a package is outdated |
| `outdated --json` | Prints the outdated packages as JSON |
| `install <owner/name>[@<range>]` | Builds a package's program optimized and puts it in the Pepper home's `bin`; installing it again upgrades it (see [`install`](#install)) |
| `install ... --package <name>` | Installs the member `<name>` of the repository's (or `--path` folder's) workspace; from a repository, at a version of its own `<name>-v<version>` tags |
| `install --path <dir>` | Installs the package in `<dir>` instead |
| `install --list` | Lists the programs `install` put in `bin`, with their versions and sources |
| `install ... --force`, `-f` | Replaces a program in `bin` that was installed from another source, or not by `install` |
| `install ... --features <names>`, `-F <names>` | The package's features to turn on: a comma-separated list, or repeat the option |
| `install ... --no-default-features` | Leaves the package's `default` feature off |
| `uninstall <name>` | Removes a program `install` put in `bin` |
| `audit` | Checks every package `pep.lock` records against the security advisory database, and exits with status 1 when one is affected (see [`audit`](#audit)) |
| `audit --ignore <id>` | Reports that advisory but does not fail on it; repeat it for more |
| `audit --json` | Prints the affected packages as JSON |
| `vendor [<dir>]` | Copies every locked package into `<dir>` in the project (default: `pep.toml`'s `[fetch] vendor`, else `vendor`), and sets `[fetch] vendor` so builds read it (see [`vendor`](#vendor-dir)) |
| `search [<word>...]` | Lists the packages in the [package index](#the-package-index) whose name, description or keywords hold every word; every package when none is given (see [`search`](#search-word)) |
| `info <package>` | Prints a package's description, versions, minimum toolchain, license and repository; the package is the name the index lists it by, or `[host:]owner/name` (see [`info`](#info-package)) |
| `cache info` | Prints the [download cache](#the-download-cache)'s folder, then each package it holds |
| `cache clean` | Removes what the download cache holds, except a package a fetch is using; projects keep what their `.pep/deps` holds |
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
lock lists every dependency and holds packages for other platforms:
`pepper build` names the packages its target needs and `.pep/deps` lacks,
so a build fetches no other platform's.

### `add <owner/name>[@<range>]`, `add <name>[@<range>]`

Adds a dependency to `pep.toml`'s `[dependencies]` and fetches it, keeping
the file's comments and layout. An argument that starts with `github:`,
`gitlab:` or `codeberg:` (`gitlab:group/pepper-json`) names its host.
Without one, `add` looks the repository up on each host in the order
`pep.toml`'s `[fetch]` `hosts` lists (GitHub, GitLab, then Codeberg by
default; see [Projects: pep.toml](projects.md#fetch)) and uses the first
that has it. When more than one does, it says so:

```text
pep-package: other/numbers is on github and codeberg; using github:other/numbers (prefix it with 'codeberg:' for another)
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

A bare name, with no `/` (`semver`, `semver@1.x`), is the package the
[package index](#the-package-index) lists by that name: `add` adds its
source, and source code imports it by the index's name:

```bash
pepper package add semver   # semver = { github = "pep-lang/pepper-semver", version = "1.0.0" }
```

`--package <name>` adds a member of the repository's
[workspace](projects.md#a-member-as-a-git-dependency) instead of its root
package: the entry gets `package = "<name>"`, its version comes from the
member's own `<name>-v<version>` tags, and the name source code imports
defaults to the member's:

```bash
pepper package add someone/shapes --package geo   # geo = { github = "someone/shapes", package = "geo", version = "0.3.1" }
```

`--dev` adds it to `[dev-dependencies]` instead: only the project's tests
and examples import it, and projects that depend on this one ignore it
(see [Projects: pep.toml](projects.md#dev-dependencies)).

`--target <condition>` adds it to `[target.'<condition>'.dependencies]`:
only a build for a target the condition selects sees it. The condition is
what `[Target(...)]` takes (`OS(Windows)`, `OS(Linux) && Arch(x64)`; see
[Platform selection](../language/platform-selection.md)); quote it for the
shell. It cannot be given with `--dev`.

`--optional`, `--features <names>` and `--no-default-features` write the
entry's `optional = true`, `features = [...]` and `default-features =
false` (see [Features](projects.md#features)). A dev-dependency cannot be
optional. The package's features are not checked until a build turns
them on.

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
`pep-package`, else on the `PATH`) on the project after each, with
`--all` in a workspace. An update
that does not build is rolled back, and the command lists those it rolled
back.

### `publish`

Releases the package at the version `pep.toml`'s `[package]` `version`
names: other projects then depend on it by that version (see
[Resolving versions](#resolving-versions)). Raise `version`, commit,
merge it to the default branch, then run it from the package's clone:

```text
$ pepper package publish
pep-package: running 'pepper +0.11.0 test'
pep-package: running 'pepper +latest test'
pep-package: published shapes 1.2.0: tagged 3f9c2e01a7b4 v1.2.0 and pushed it to origin
```

First it checks, and lists every check that fails at once:

- the work tree has no changes `git status` shows, and `HEAD` is the tip
  of the default branch of `origin`, so the commit it tags is the one
  that branch holds;
- `version` is a version (`1.2.0`), newer than every version tag
  `origin` has;
- `[package]` has a `description`, `license` and `repository`;
- every dependency asks for a version range, not a branch, tag, commit
  or the default branch, so a project depending on this one can resolve
  it with its other packages; a `path` dependency, such as a workspace
  sibling, needs a `version` beside it, and one inherited with
  `workspace = true` is checked as the workspace gives it. A
  dev-dependency may be anything, since a dependent ignores it;
- every `path` dependency with a `version` is a package of this
  workspace, its root or a member, published at a version the range
  accepts: `origin` has its tag (`numbers-v1.2.0`, or `v1.2.0` for the
  root), which a project outside the workspace resolves it by (see
  [A member as a Git dependency](projects.md#a-member-as-a-git-dependency)).
  Each is an error at its `path`, printed before the list:

  ```text
  geo/pep.toml:9:20: error: 'numbers' is not published at a version '1' accepts: origin has no such tag numbers-v<version>, which a dependent resolves it by; publish numbers first
      9 | numbers = { path = "../numbers", version = "1" }
        |                    ^~~~~~~~~~~~
  ```

- `minimum_toolchain` is at least the release that reads each newer
  `pep.toml` feature the package uses: `[dev-dependencies]`, `[target]`,
  `[features]`, `[overrides]` and `[workspace]` tables, and a
  dependency's `optional`, `features`, `default-features`, `workspace`
  and `package`, need 0.11.0;
- `pep.toml` has no `[overrides]`: a dependent builds with the packages
  they replace, not the code the package was tested with, so a release
  waits until the fix it needs is released too.

```text
pep-package: error: cannot publish shapes 1.2.0:
  '[package]' has no 'license'
  dependency 'numbers' names branch main, not a version range, so a dependent cannot resolve it
  dependency 'draw' names path ../draw and no 'version', so a dependent cannot resolve it; give it the version of the package there
  'version' 1.2.0 is not newer than the newest tag, 1.2.0; raise it in pep.toml
```

Run from a workspace member, it checks and tests that member, in its
folder, and tags it `<name>-v<version>` (`geo-v0.3.1`): each member is
released on its own, and its `version` need only be newer than its own
tags. The workspace's root package, and a package that is no workspace's
member, are tagged `v<version>`.

Then it runs the package's tests with `pepper +<minimum_toolchain> test`
and `pepper +latest test` (only the second without a `minimum_toolchain`),
with the Pepper home's own `pepper` (in the home whose toolchain
`pep-package` is, else the one `PEPPER_HOME` names, else the default one; see [Toolchains: pep-install](pep-install.md)), so
both toolchains must be installed there; `latest` is the newest
installed release, not a prerelease. A failing run stops it and shows
what the tests printed. Last, it tags `HEAD` `v<version>` (a member's
tag) and pushes the
tag to `origin`; when the push fails, it deletes the tag again.

`--dry-run` checks and tests, then says what it would tag, without
tagging or pushing anything. `publish` neither creates a release page on
the host nor needs `pep.lock`, which a dependent does not read.

### `tree`

Prints the dependency graph `pep.lock` records, as the `pep.toml` of the
project and of each locked package declare it. Each line is the name the
dependent imports the package by, when that is not the package's own
(`win: winapi`), its locked version (or short commit) and source, and
marks:

- `[dev]`: only the project's dev-dependencies lead to it;
- `[target: <condition>]`: only builds for the targets the condition
  selects need it (see [`[target]` tables](projects.md#targetconditiondependencies));
- `[override: <source>]`: the project's [`[overrides]`](projects.md#overrides)
  replace it with a fork (`github:me/numbers`) or a folder (`path:../numbers`),
  in `tree` and `why` alike;
- `[optional]` and `[features: ...]`: the dependent's entry says
  `optional = true`, and the features its `features` turns on. A build
  turns on more: each package's `default` feature, and what the features
  it turns on list (see [Features](projects.md#features)).

A package whose dependencies were listed above ends in `(*)` instead of
listing them again:

```text
$ pepper package tree
app
|-- geometry 1.0.0 (github:someone/geometry)
|   `-- numbers 1.3.1 (github:other/numbers)
|-- win: winapi 1.0.0 (github:other/winapi) [target: OS(Windows)] [optional] [features: wide]
`-- fixtures 1.0.0 (github:other/fixtures) [dev]
    `-- geometry 1.0.0 (github:someone/geometry) (*)
```

`--depth <n>` stops `<n>` levels below the project (`--depth 1`: only its
own dependencies). `tree`, `why` and `outdated` read the graph from
`pep.lock`, checking each locked package out at its commit (with
`--offline`, only from what it holds), and never change `pep.lock`. When
`pep.toml` names a package `pep.lock` does not list, they fail and say to
run `fetch` first.

### `tree --invert <name>`

Prints the tree upside down: the package, then each package whose
`pep.toml` asks for it, and so on down to the project. The package is
named as for [`why`](#why-name). Each line has the same marks as in
`tree`, except that `[optional]` and `[features: ...]` describe the
dependent's entry for the package on the line above, and `(*)` ends a
package whose dependents were listed already. `--depth` counts levels
below the package:

```text
$ pepper package tree --invert geometry
geometry 1.0.0 (github:someone/geometry)
|-- app
`-- fixtures 1.0.0 (github:other/fixtures) [dev]
    `-- app
```

### `why <name>`

Prints the paths from the project to the package, one per line. The
package is named by its own name, its `owner/name` or source, or the name
a dependency imports it by:

```text
$ pepper package why numbers
app -> geometry 1.0.0 -> numbers 1.3.1
app -> fixtures 1.0.0 -> geometry 1.0.0 -> numbers 1.3.1
```

It prints the first 20, then a line saying how many more there are
(`and 7 more paths; --all prints every one`); `--all` prints every one.

### `outdated`

Lists each locked package that is behind, with its locked version, the
revision its requirements now choose (`wanted`: the newest version
every range on it in the locked graph allows and this toolchain builds,
or a branch's newest commit; updating a package that depends on it can
change those ranges), and the newest version it offers (`latest`, not a prerelease).
A package `[overrides]` replaces is left out, since its revision is the
override's:

```text
$ pepper package outdated
package   locked  wanted  latest  source
numbers   1.3.1   1.3.1   3.0.0   github:other/numbers
geometry  1.0.0   1.1.0   1.1.0   github:someone/geometry
```

Here `pepper package update` moves geometry to 1.1.0, and numbers stays
below 3.0.0 until geometry's range on it allows that. With none behind,
it prints `every package is at the newest version`. It reads what each
package offers over the network, so with `--offline` it fails, saying it
cannot check. The exit status is 0 whatever it finds, unless
`--exit-code` asks for 1 when a package is outdated, for CI.

A locked version its author [retracted](#retracted-versions) is outdated
too: its `locked` cell says `(retracted)`, and a line after the table says
why:

```text
$ pepper package outdated
package  locked             wanted  latest  source
shapes   1.1.0 (retracted)  1.2.0   1.2.0   github:other/shapes
shapes 1.1.0 is retracted: loses data
```

### `search [<word>...]`

Lists each package in the [package index](#the-package-index) whose name,
description or keywords hold every word given, ignoring case, one a line;
with no words, every package. A word matches part of a word
(`term` matches `terminal`). Finding nothing prints nothing, says so on
stderr, and exits with status 0.

```text
$ pepper package search terminal
term (github:pep-lang/pepper-term): Interactive terminals: raw mode, key and mouse input, ...
tui (github:pep-lang/pepper-tui): Full-screen terminal apps in the style of Ratatui: ...
```

### `info <package>`

Prints what is known of a package: the index's description and keywords,
its versions (its version tags, newest first, those its newest release
[retracts](#retracted-versions) marked), and the `minimum_toolchain`,
`license` and `repository` of its newest release's `pep.toml`, which is
read from the [download cache](#the-download-cache) (fetched into it
when missing). The package is the name the index lists it by, or a
repository as `add` takes one (`[host:]owner/name`), which need not be
in the index; then the description is its `pep.toml`'s. A line with
nothing to say is left out. It reads the versions from the host, so it
fails under `--offline`.

```text
$ pepper package info semver
semver: Semantic Versioning 2.0.0: parse, compare and order versions, and match them against ranges
source: github:pep-lang/pepper-semver
versions: 1.0.0
license: Apache-2.0
repository: https://github.com/pep-lang/pepper-semver
keywords: semver, version, range
```

### The package index

The index that `search`, `info` and `add <name>` read is a Git
repository with one TOML file per package in its `packages` folder:
`https://github.com/pep-lang/index.git`, or the repository
`PEPPER_PACKAGE_INDEX` names (a mirror, a private index, or a `file://`
folder). The file's name is the package's name, the one `add <name>`
takes and source code imports it by (`packages/semver.toml`):

```toml
source = "github:pep-lang/pepper-semver"   # required: host:owner/name
description = "Semantic Versioning 2.0.0: parse, compare and order versions, and match them against ranges"
keywords = ["semver", "version", "range"]
```

The index lists no versions: they are the source's version tags, which
`info` reads from the host, so a release needs no change to the index.
To list a package, open a pull request that adds its file; a maintainer
reviews it, and the first pull request for a name claims it. A malformed
file fails the command with an error at its key.

Like the [advisory database](#audit), the index is cloned into the
download cache's home, `cache/index`, and fetched again once the copy is
an hour old. A fetch that fails falls back to the cached copy with a
warning that gives its age, and fails only when there is no copy; with
`--offline`, `search` uses the copy as it is, and fails when there is
none. The packages are also listed on
<https://pepper-lang.dev/packages.html>.

### `audit`

Checks every package `pep.lock` records, for every platform and
dev-dependencies included, against a database of security advisories, as
`cargo audit` does with RustSec. For each advisory that affects a locked
version it prints the advisory, the package (marked `[dev]` or with its
`[target: ...]` as in [`tree`](#tree)), and the paths that lead to it, as
[`why`](#why-name) prints them:

```text
$ pepper package audit
PEP-2026-0001 (high): numbers 1.3.1 (github:other/numbers)
  numbers_version() lies
  patched: >=2.0.0
  https://example.com/PEP-2026-0001
  app -> geometry 1.1.0 -> numbers 1.3.1
1 advisory affects pep.lock
```

The exit status is 1 when an advisory affects a package, for CI, and 0
when none does (`no advisory affects pep.lock (12 in <database>)`).
`--ignore <id>`, or the project's [`[audit] ignore`](projects.md#audit)
list, names an advisory that does not fail it, such as one whose code the
project never calls; `audit` still says on stderr which package it
affects. Only packages locked at a version are checked: one at a branch or
commit names no version to match.

**The database** is a Git repository of TOML files, one advisory each,
anywhere in it: `https://github.com/pep-lang/advisories.git`, or the
repository `PEPPER_ADVISORY_DB` names (a mirror, a private database, or a
`file://` folder). `audit` clones it into the
[download cache](#the-download-cache)'s home, `cache/advisories`, and
fetches it again once the copy is an hour old. When that fetch fails (no
network, or the host erroring), `audit` checks against the cached copy
and warns on stderr, giving the copy's age:

```text
pep-package: warning: cannot fetch the advisory database https://github.com/pep-lang/advisories.git, so using the cached copy from 3 days ago: ...
```

With no cached copy, it fails. With `--offline` it uses the copy as it
is, and fails when there is none. An advisory:

```toml
id = "PEP-2026-0001"                      # required
package = "github:other/numbers"          # required: the source pep.lock records (a member's: github:owner/name#member)
title = "numbers_version() lies"
severity = "high"                          # as written: low, medium, high, critical
url = "https://example.com/PEP-2026-0001"
patched = [">=2.0.0"]                      # the versions that fix it
unaffected = ["<1.0.0"]                    # the versions it never affected
```

A version is affected unless a `patched` or `unaffected` entry holds it.
Each entry is a version, which names that version alone (`"1.2.3"`), or a
range as dependencies write it (`">=1.2.3, <2"`, `"^1.4"`). A malformed
advisory fails `audit` with an error at its key.

### `vendor [<dir>]`

Copies every package `pep.lock` lists into a folder of the project, so
the repository carries its dependencies and builds with no network and no
[download cache](#the-download-cache), as `cargo vendor` and
`go mod vendor` do: for an air-gapped build, or a release archive. It
first resolves and fetches as [`fetch`](#fetch) does, then writes each
package at its locked commit to `<dir>/<host>/<owner>/<name>`
(`vendor/github.com/someone/geometry`), its files as `git archive` gives
them, without `.git`, and sets `[fetch] vendor = "<dir>"` in `pep.toml`
(see [`[fetch]`](projects.md#fetch)):

```text
$ pepper package vendor
pep-package: vendored geometry 1.1.0 (github:someone/geometry)
pep-package: vendored numbers 1.3.1 (github:other/numbers)
pep-package: set '[fetch] vendor = "vendor"' in pep.toml: builds now read the packages from vendor
```

Commit the folder with `pep.toml` and `pep.lock`. It holds every package
in the lock: every platform's, and those only `[dev-dependencies]` lead
to, since `pepper test` and the examples build from it too (Cargo vendors
everything for the same reason). A fork an `[overrides]` entry names is vendored in
the original's place; a `path` override is not, its folder being the
project's already. `<dir>/.gitattributes` turns git's
line-ending conversion off there, so a checkout keeps the files byte for
byte.

Each package's folder also holds `.pep-commit`, its commit, and
`.pep-checksum`, the SHA-256 of its files' paths and contents. In a
vendored project, `pepper build` and `pepper test` fetch nothing: they read
the packages from the vendor folder and check that each one the build
needs is there at its locked commit and unedited, and fail otherwise, with
or without `--locked` and `--offline`:

```text
error: the files in vendor/github.com/someone/geometry were changed since they were vendored (sha256 1c0f..., recorded 7b3e...); run 'pepper package vendor' to restore them, or make the change in the package itself
```

`pepper package fetch` checks the same, and that `pep.lock` still matches
`pep.toml`, reading only the vendor folder; it changes neither. To change
a dependency, run `add`, `remove` or `update` (which fetch into `.pep/deps`
as usual), then `vendor` again: that rewrites the packages that changed,
restores edited ones, and removes those `pep.lock` no longer lists.
`.pep/deps` is unchanged in a project that is not vendored.

In a [workspace](projects.md#workspaces), run from the root or any member,
`vendor` writes one folder at the workspace's root, holding every
member's locked packages, and sets `[fetch] vendor` in the root's
`pep.toml`; every member's build reads it.

### `install`

Installs a command-line tool from a package, as `cargo install` and
`go install` do: it builds the package's program, the one `pepper build`
builds in its folder, with `-O`, and puts it in the Pepper home's `bin`,
which [`pep-install setup`](pep-install.md#setting-a-machine-up) puts on
the `PATH`. It needs no project.

```bash
pepper package install someone/tool          # the newest release
pepper package install github:someone/tool@1.2
pepper package install someone/tools --package fmt  # the workspace member fmt
pepper package install --path .              # the package in this folder
pepper package install --list
pepper package uninstall tool
```

- **Which version:** the newest release the range allows (any, without
  one) that this toolchain builds, as [`add`](#add-ownernamerange) picks
  it; a package with no version tags is installed from its default
  branch. Installing it again upgrades it, or moves it to another range.
  With `--package <name>`, it is the workspace member `<name>`, by its
  own `<name>-v<version>` tags, as `add --package` reads them; with
  `--path`, the member `<name>` of that folder's workspace.
- **Its dependencies** are those its own `pep.lock` records, when it has
  one, fetched through the [download cache](#the-download-cache);
  `--locked` fails rather than build with a `pep.lock` that is out of
  date, and `--offline` works only with `--path`, since choosing a version
  reads the network. `--features` and `--no-default-features` choose the
  package's features, as for `pepper build`.
- **The program's name** is its `[build]` table's `output`, else its
  package's `name` (with `.exe` on Windows).
- **What it installed** is recorded in `installed-tools.toml` in the home:
  each program's source, version, commit and the toolchain that built it,
  which `install --list` prints and `uninstall` reads.
- **Overwriting:** a program already in `bin` is replaced only when
  `install` put it there from the same source; one from another package,
  or one it did not install (`pepper` and `pep-install` are the home's
  own), needs `--force`.
- **Replacing a running program:** the new program is written beside the
  old one and renamed into place, the old one first moved aside to
  `<name>.old`. On Windows a running program cannot be removed, so its
  `.old` file stays until the next `install` or `uninstall` of that
  program removes it.

The home is the one whose toolchain `pep-package` is, else `PEPPER_HOME`,
else `%LOCALAPPDATA%\pepper` on Windows and `~/.pepper` elsewhere, as for
[`pep-install`](pep-install.md#where-toolchains-go).
`pepper install` is a different command: it installs toolchains.

### JSON output

`--json` makes `tree`, `why` and `outdated` print one JSON object instead,
for scripts. Its form is stable: a later release may add members, but
does not rename or remove one.

`tree --json` writes the project's name and its dependencies as nodes,
each with the nodes of its own dependencies:

```json
{
  "name": "app",
  "dependencies": [
    {
      "name": "win",
      "package": "winapi",
      "version": "1.0.0",
      "commit": "79c8011a9d932b141794ad50938f3cad7ac01efd",
      "source": "github:other/winapi",
      "dev": false,
      "target": "OS(Windows)",
      "override": null,
      "optional": true,
      "features": ["wide"],
      "repeated": false,
      "dependencies": []
    }
  ]
}
```

A node holds the package and the entry in its dependent's `pep.toml` that
asks for it:

| Member | What it holds |
| --- | --- |
| `name` | The name the dependent imports the package by |
| `package` | The package's own name (the project's, for the project) |
| `version` | Its locked version, or `null` when it is locked by commit |
| `commit` | Its locked commit, or `null` for the project and a folder |
| `source` | Its source (`github:other/winapi`); `""` for the project |
| `dev` | Whether only the project's dev-dependencies lead to it (`[dev]`) |
| `target` | The condition of the targets that need it (`[target: ...]`), or `null` for every target |
| `override` | What `[overrides]` replaces it with (`[override: ...]`), or `null` |
| `optional` | Whether the entry says `optional = true` (`[optional]`) |
| `features` | The features the entry turns on (`[features: ...]`) |
| `repeated` | Whether its dependencies were listed already (`(*)`), so its `dependencies` is empty |
| `dependencies` | The nodes of its dependencies, empty below `--depth` |

`tree --invert <name> --json` writes the project's name and `packages`:
a node for each package the name matches, whose `name`, `optional` and
`features` are its own name, `false` and `[]`, and which has no
`repeated`. In place of `dependencies`, each node has `dependents`: the
nodes of the packages that ask for it, the project among them as a
node whose `source` is `""`. In those, `name`, `optional` and `features`
describe the dependent's entry for the package above.

`why --json` writes `paths`, the paths it prints (every one with
`--all`), each an array of the nodes from the project's dependency to the
package, without `repeated` or `dependencies`, and `total`, the number of
paths there are:

```text
{
  "paths": [
    [
      { "name": "geometry", "package": "geometry", "version": "1.0.0", ... },
      { "name": "numbers", "package": "numbers", "version": "1.3.1", ... }
    ]
  ],
  "total": 1
}
```

`outdated --json` writes `packages`, an object for each row of the table,
with `--exit-code` as without `--json`:

| Member | What it holds |
| --- | --- |
| `package` | The package's name |
| `locked` | Its locked version, or short commit |
| `wanted` | The revision its requirements now choose |
| `latest` | The newest version it offers, or `null` when it has none |
| `source` | Its source |
| `dev` | Whether only the project's dev-dependencies lead to it |
| `target` | The condition of the targets that need it, or `null` |
| `retracted` | Why its author retracted the locked version, or `null` |

`audit --json` writes `advisories`, an object for each affected package,
with the exit status as without `--json`:

| Member | What it holds |
| --- | --- |
| `id`, `title`, `severity`, `url` | The advisory's, each `""` when it gives none |
| `patched` | Its `patched` versions, as written |
| `package`, `version`, `source` | The affected package, its locked version and its source |
| `dev` | Whether only the project's dev-dependencies lead to it |
| `target` | The condition of the targets that need it, or `null` |
| `paths`, `total` | The first 20 paths to it and how many there are, as `why --json` writes them |

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

A member of a repository's workspace (a dependency with
[`package`](projects.md#a-member-as-a-git-dependency)) has `#` and the
member after the repository in its `source`, and its own commit, the one
its own tag names, checked out in `.pep/deps/<host>/<owner>/<name>#<member>`
(or the vendor folder). Its siblings are entries of their own:

```toml
[[package]]
name = "geo"
source = "github:someone/shapes#geo"
version = "0.3.1"
commit = "..."
sha256 = "..."
```

Features do not change the lock: an optional dependency is resolved,
locked and fetched like any other, whether or not a build turns it on, so
`pep.lock` is the same whichever `--features` a build gives (see
[Features](projects.md#features)).

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

A package the project's [`[overrides]`](projects.md#overrides) replace
keeps its own `source` and has `override`, the replacement's source: a
fork, whose commit `commit` is and whose files `sha256` covers, or
`path:` and the folder as `pep.toml` writes it, with no commit, since a
folder has none to pin:

```toml
[[package]]
name = "numbers"
source = "github:other/numbers"
override = "github:me/numbers"
commit = "9d1e0c3b7a2f4e6d8c0b1a2f3e4d5c6b7a8f9e0d"
sha256 = "..."
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
  locked commit is used, or else one the
  [download cache](#the-download-cache) holds; one neither holds is an
  error, and so is anything that
  must read which versions a repository offers (`add`, `update`, or a
  `pep.toml` change `pep.lock` does not cover).
- **`--frozen`**: both.

A [vendored](#vendor-dir) project needs neither the network nor the
download cache, so `fetch --frozen` and `pepper build --frozen` pass with
only the repository.

```text
$ pepper package fetch --locked
pep-package: error: pep.lock would change, and --locked keeps it as it is:
  updated numbers: numbers 1.3.1 -> numbers 2.0.0
run the command without --locked (or PEPPER_LOCKED), then commit pep.lock

$ pepper package fetch --offline
pep-package: error: cannot fetch github:someone/geometry: --offline, and neither .pep/deps/github.com/someone/geometry nor the package cache holds the commit 0582024b9cd7; run 'pepper package fetch' without --offline (or PEPPER_OFFLINE) first
```

`pepper build` and `pepper test` take the same three options for the
fetch they do on their own (see [The compiler: pep-build](pep-build.md)).

## The download cache

Each package is downloaded once per machine, into a cache in the Pepper
home that every project shares, as Cargo's `~/.cargo/registry` and Go's
module cache are: `cache/packages` in the home whose toolchain
`pep-package` is, else the one `PEPPER_HOME` names, else
`%LOCALAPPDATA%\pepper` on Windows and `~/.pepper` elsewhere (see
[Toolchains: pep-install](pep-install.md)). It holds, for each package,

- `<host>/<owner>/<name>.git`: a bare git repository of every commit any
  project has fetched, fetched from the host only when it lacks the commit
  a project needs, one for the repository and all its workspace members;
- `<host>/<owner>/<name>/<commit>.tar.gz`: each archive fetched without
  git (see [Fetching without git](#fetching-without-git)).

A project's `.pep/deps/<host>/<owner>/<name>` is a clone of the cache's
repository (its `origin` is still the host's address). Git hard-links
the objects of a clone from a folder on the same drive, so it takes
little space, and copies them from another drive. A clone is complete on
its own, so deleting the cache never breaks a project: it builds from
what `.pep/deps` holds, and the next fetch that needs a commit the
project lacks downloads it into the cache again. Checking out a cached
package still checks its files against `pep.lock`'s `sha256`.

Processes take turns at a package: each holds a lock on
`<host>/<owner>/<name>.lock` while it fetches it, so projects fetching
the same package at once each wait for the other and fetch it once.
`cache clean` takes each package's lock before it removes the package,
and keeps one a fetch is using, saying so; the lock files themselves stay.

```text
$ pepper package cache info
/home/me/.pepper/cache/packages
github.com/other/numbers
github.com/someone/geometry
$ pepper package cache clean
pep-package: removed 2 packages from /home/me/.pepper/cache/packages
```

## Fetching without git

When git is not on the `PATH`, `pep-package` fetches each commit
`pep.lock` pins as the host's archive of it, over HTTPS, into the
[download cache](#the-download-cache) (once per machine), checks its files
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
  each package's requirement and the versions the repository offers. A
  workspace member's range reads only its own tags (`geo-v1.2.3`), and a
  repository's root package only the plain ones.
- A `path` with a `version` in a fetched package's `pep.toml` is the
  package of the same workspace it names, resolved by its own tags as a
  dependency on that member of the same repository (see
  [A member as a Git dependency](projects.md#a-member-as-a-git-dependency)).
- A branch, tag or commit must be the same in every package that names it.
- The project's own `pep.toml` overrides its dependencies: a package it
  names gets the revision it asks for, even outside the range a dependency
  declares, and `pep-package` says which requirement it overrode.
- A locked revision stays while it still satisfies every requirement;
  `update` is what moves it.
- The project's [`[overrides]`](projects.md#overrides) replace a package
  wherever the graph reaches it: the override's own revision is chosen,
  from the fork, whatever the dependents ask, and a `path` override's
  folder is read in its place. A locked revision of an override stays
  until the override changes or `update` names the package.
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
them out, each once per run. A workspace member's is the `pep.toml` of the
package with its name among the folders its root's `[workspace] members`
lists at that version's commit, so a member that moved between releases is
read where each release has it.

### Retracted versions

A package's author withdraws a broken release in the
[`[retract]`](projects.md#retract) table of a newer release's `pep.toml`,
as Go's `retract` does: the `[retract]` of a package's newest version
(not a prerelease) speaks for every version.

- A version range skips each retracted version, picking the newest one
  left, and says so:

  ```text
  pep-package: github:other/shapes skipped 1.1.0 (retracted: loses data)
  ```

  When every version the ranges accept is retracted, resolution fails and
  names each with its reason.
- A version `pep.lock` already holds stays, and builds: `fetch` reads no
  network for it. [`outdated`](#outdated) flags it, and `update` moves off
  it.

## Environment variables

| Variable | What it does |
| --- | --- |
| `PEPPER_PACKAGE_GITHUB_URL`, `PEPPER_PACKAGE_GITLAB_URL`, `PEPPER_PACKAGE_CODEBERG_URL` | Fetches that host's repositories from another address (a mirror, or a folder of repositories as a `file://` URL): `<address>/<owner>/<name>.git` |
| `PEPPER_PACKAGE_GITHUB_ARCHIVE_URL`, `PEPPER_PACKAGE_GITLAB_ARCHIVE_URL`, `PEPPER_PACKAGE_CODEBERG_ARCHIVE_URL` | Downloads that host's archives, when git is missing, from another `http://` or `https://` address (a mirror): `<address>/<owner>/<name>/<commit>.tar.gz` |
| `PEPPER_PACKAGE_INDEX` | The Git repository of the [package index](#the-package-index) `search`, `info` and `add <name>` read, instead of `https://github.com/pep-lang/index.git` |
| `PEPPER_ADVISORY_DB` | The Git repository of the advisory database [`audit`](#audit) reads, instead of `https://github.com/pep-lang/advisories.git` |
| `PEPPER_LOCKED` | Set to anything but empty or `0`, the same as `--locked` |
| `PEPPER_OFFLINE` | Set to anything but empty or `0`, the same as `--offline` |
| `PEPPER_HOME` | The Pepper home that holds the [download cache](#the-download-cache), whose `pepper` [`publish`](#publish) runs the tests with, and whose `bin` [`install`](#install) puts programs in, as for `pep-install` |
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
