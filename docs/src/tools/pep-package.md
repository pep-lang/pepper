# The package manager: pep-package

`pep-package` fetches a project's dependencies and keeps its `pep.toml` and
`pep.lock`. `pepper package` runs it with the same arguments:

```bash
pepper package add someone/geometry          # the newest version, imported as 'geometry'
pepper package add other/json@2.x --name fast_json
pepper package remove geometry
pepper package update                        # every dependency, as far as the ranges allow
pepper package update --verify               # one at a time, keeping the updates that build
pepper package fetch                         # what pep.lock lists
```

```text
pep-package [-C <dir>] <command> [arguments]
```

It works on the project whose `pep.toml` is in the current folder or the
nearest folder above it (see [Projects: pep.toml](projects.md)). Packages
are fetched with `git`, which must be on the `PATH`; signing in to a private
repository is git's concern (its credential helpers and SSH keys), so
whatever lets `git clone` reach a repository lets `pep-package` fetch it.

`pepper build` fetches on its own what `pep.lock` lists and `.pep/deps`
lacks, so a fresh clone of a project builds with `pepper build` alone.

## Options and commands

| Command or option | What it does |
| --- | --- |
| `-C <dir>`, `--directory <dir>` | Works on the project at or above `<dir>` instead of the current folder |
| `fetch` | Fetches what `pep.lock` lists, and resolves what `pep.toml` changed since `pep.lock` was written |
| `add <owner/name>[@<range>]` | Adds a dependency at its newest version, or at a range |
| `add ... --name <name>`, `-n <name>` | The name source code imports it by |
| `remove <name>` | Removes a dependency, by its name or its `owner/name` |
| `update [<name>...]` | Moves dependencies to the newest versions their ranges allow; every one when none is named |
| `update --verify` | Updates one dependency at a time and builds after each, keeping only the updates that build |
| `-h`, `--help` | Prints the options; after a command, that command's |
| `-V`, `--version` | Prints the version |

The exit status is 0 on success, 1 when a command fails, and 2 for a
mistake on the command line.

### `fetch`

Fetches every package in `pep.lock` into the project's `.pep/deps` at its
locked commit. When `pep.toml` names a dependency `pep.lock` does not list,
or asks for a revision the locked one does not satisfy, `fetch` resolves it
and updates `pep.lock`; everything else keeps its locked revision.

### `add <owner/name>[@<range>]`

Adds a dependency to `pep.toml`'s `[dependencies]` and fetches it, keeping
the file's comments and layout. The repository is on GitHub unless the
argument starts with `gitlab:` or `codeberg:` (`gitlab:group/pepper-json`).

```bash
pepper package add someone/geometry        # geometry = { github = "someone/geometry", version = "1.4.2" }
pepper package add someone/geometry@1.2.x  # ... version = "1.2.x"
```

Without a range, the dependency gets the newest version tag (as a range
that accepts compatible later versions: `1.4.2` accepts 1.4.2 up to, not
including, 2.0.0); a repository with no version tags follows its default
branch. The name source code imports defaults to the repository's last part,
with `-` and `.` turned into `_` (`other/json` adds `json`); `--name` gives
another. A name already in `pep.toml`, or the name of a runtime module
(`io`, `async`), is an error that suggests `--name`.

### `remove <name>`

Removes the dependency with that name (or that `owner/name`) from
`pep.toml`, and drops from `pep.lock` every package nothing needs any more.

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
the dependency graph, its dependencies' dependencies included. Commit it
with `pep.toml`: it is what makes a fresh clone build the same code.

```toml
version = 1

[[package]]
name = "geometry"
source = "github:someone/geometry"
version = "1.1.0"
commit = "0582024b9cd7a71044ee1aaa7099286f59e2df46"
```

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

## Environment variables

| Variable | What it does |
| --- | --- |
| `PEPPER_PACKAGE_GITHUB_URL`, `PEPPER_PACKAGE_GITLAB_URL`, `PEPPER_PACKAGE_CODEBERG_URL` | Fetches that host's repositories from another address (a mirror, or a folder of repositories as a `file://` URL): `<address>/<owner>/<name>.git` |
| `PEPPER_RUNTIME` | The runtime folder whose modules a dependency may not be named like, as for the compiler |

## Building it

`pep-package` is written in Pepper (`tools/pep-package`) and depends on the
[toml package](https://github.com/justinboswell/pepper-toml) through a
`path` dependency on its copy in `tools/toml`, so building it needs no
network:

```bash
cargo build --release
target/release/pep-build tools/pep-package/main.pep -o target/release/pep-package
```

Not yet: fetching without git (downloading a host's archive over HTTPS),
and `add` looking a name up on several hosts.
