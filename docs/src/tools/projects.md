# Projects: pep.toml

A `pep.toml` file marks the root of a project. It names the project, says
how `pepper build` builds it, and lists the packages it depends on, so a
project builds with `pepper build` and nothing else:

```bash
cd my_app
pepper build          # builds the program pep.toml describes
./my_app
```

`pepper new my_app` starts a project with a `pep.toml`, a `main.pep` and a
test, and `pepper new my_lib --lib` a package (see
[Starting a project: pep-new and pep-init](pep-new.md)). A `pep.toml` can
say more:

```toml
[package]
name = "my_app"
version = "0.1.0"
description = "Draws shapes"
authors = ["Ada <ada@example.com>"]
license = "MIT"
repository = "https://github.com/me/my_app"

[build]
entry = "src/main.pep"

[dependencies]
geometry  = { github = "someone/geometry", version = "1.2" }
json      = { gitlab = "group/pepper-json", version = "0.4.x" }
fast_json = { github = "other/json", version = "2" }   # renamed: 'json' was taken
http      = { codeberg = "someone/http", branch = "main" }
shapes    = { path = "../shapes" }

[dev-dependencies]
fixtures  = { github = "someone/fixtures", version = "1" }   # only tests and examples import it

[target.'OS(Windows)'.dependencies]
winapi    = { github = "someone/winapi", version = "1" }     # only builds for Windows see it

[features]
default   = ["tls"]
tls       = ["dep:openssl"]          # a build with it defines 'my_app_tls' and uses openssl
```

A package is a project other projects depend on: a repository (or folder)
with a `pep.toml` at its root. Its root `module.pep` is the module its
dependency name imports, and any folder inside it holding a `module.pep` is a
module of the package too.

## `[package]`

| Key | What it is |
| --- | --- |
| `name` | The project's name: letters, digits and `_`, not starting with a digit. Required. `pepper build` names the executable after it. |
| `version` | Its version, `major.minor.patch` |
| `description` | One line saying what it is |
| `authors` | An array of names |
| `license` | Its license, such as `MIT` |
| `repository` | Where its source lives |
| `toolchain` | The toolchain it builds with: `0.3.0`, `0.3` for the newest installed 0.3.x, or `latest`. A `pepper` installed by [pep-install](pep-install.md) runs that toolchain's tools in the project (see [Toolchains](pepper.md#toolchains)); the compiler itself only checks that it is a version |
| `minimum_toolchain` | The oldest toolchain release that builds it: `0.11.0`, or a prerelease such as `0.11.0-dev`, which comes before `0.11.0`. Resolving versions, `pepper package` skips a version of a package whose `minimum_toolchain` is newer than its own toolchain (see [Resolving versions](pep-package.md#the-toolchain-a-package-needs)). Unlike `toolchain`, which picks the toolchain the project itself builds with, it says what the package's users need |

## `[build]`

`pepper build` with no file builds the project: it finds the nearest
`pep.toml` in the current folder or a folder above it, and builds the
`[build]` table's entry file into its output. Every path is relative to the
folder holding `pep.toml`, and the build's intermediate files and cache go in
that folder's `.pep`, wherever `pepper build` runs.

| Key | What it is | Default |
| --- | --- | --- |
| `entry` | The file that holds `main` | `main.pep` |
| `output` | The executable; building for Windows adds `.exe` to a name with no extension | the package's `name` |
| `include` | An array of extra folders to search for modules, as `-I` adds | none |
| `link` | An array of C libraries to link, as `-l` adds | none |

Options on the command line still apply: `pepper build -O` builds the
project optimized, and `-o` names another output. A file argument builds that
file instead (`pepper build tools/gen.pep`); the project's dependencies,
`include` folders and `link` libraries still apply to it, since it is in the
project.

## `[dependencies]`

Each key is the name source code imports, and its value says where the
package comes from and which revision to use:

```toml
[dependencies]
geometry = { github = "someone/geometry", version = "1.2" }
```

```pepper
import geometry;
import geometry.solids;     # the module in the package's solids/ folder

main(): int {
    print("{0} {1}", geometry.area(3, 4), solids.volume(2));
    return 0;
}
```

| Key | What it is |
| --- | --- |
| `github`, `gitlab`, `codeberg` | The repository, `owner/name` (on GitLab, `group/subgroup/name` too) |
| `path` | A folder on disk, relative to this `pep.toml`, instead of a repository |
| `version` | A semver range of the repository's version tags: `1.2`, `0.4.x`, `>=1.0, <2` |
| `branch` | A branch |
| `tag` | A tag |
| `commit` | A commit |
| `optional` | `true`: a build uses it only when a [feature](#features) turns it on |
| `features` | An array of the dependency's features to turn on |
| `default-features` | `false` leaves the dependency's `default` feature off |

A dependency has exactly one source, and at most one of `version`, `branch`,
`tag` and `commit`; with none, it follows the repository's default branch.
A `path` dependency takes none of them.

### Imports

`import geometry` imports the package's root module, its `module.pep`.
`import geometry.solids` imports the module in its `solids` folder, and binds
the last name, so its declarations are `solids.volume`; `as` names it
otherwise (`import geometry.solids as s`). A dotted import whose first name
is not a dependency looks for the nested folder on the search paths:
`import a.b` finds `a/b/module.pep`.

Because the name lives only in `pep.toml`, a package that moves to another
host or organization, or a switch to a fork, changes one line of `pep.toml`
and no source file. Two packages whose repositories share a name get
different keys:

```toml
json      = { gitlab = "group/pepper-json" }
fast_json = { github = "other/json" }
```

### Where dependencies live

A dependency from a Git host lives in the project's
`.pep/deps/<host>/<owner>/<name>`, such as
`.pep/deps/github.com/someone/geometry`. One copy serves the whole project:
each package's own `pep.toml` names the packages it needs under its own
keys, and an import in one of its files resolves against those keys, to the
same copies.

`pepper package` fetches them there and records the commit of each, the
dependencies' dependencies included, in `pep.lock` beside `pep.toml`; commit
`pep.lock` with `pep.toml`. `pepper build` fetches what `pep.lock` lists and
`.pep/deps` lacks or holds at another commit, so a fresh clone builds with
`pepper build` alone, with git or, where git is missing, by downloading each
locked commit's archive over HTTPS and checking it against the checksum
`pep.lock` records. See
[The package manager: pep-package](pep-package.md), which also says how
versions are chosen when several packages need one.

```bash
pepper package add someone/geometry       # adds it to pep.toml and fetches it
pepper build
```

In CI, `pepper build --locked` and `pepper test --locked` fail when
`pep.lock` is out of date with `pep.toml` instead of updating it, and
`--offline` builds with only what `.pep/deps` and the shared
[download cache](pep-package.md#the-download-cache) hold (`--frozen` is both;
`PEPPER_LOCKED=1` and `PEPPER_OFFLINE=1` do the same). See
[Reproducible builds](pep-package.md#reproducible-builds). They apply to
dev-dependencies as to the rest.

A project that sets `[fetch] vendor` (`pepper package vendor` does) keeps
its dependencies in that folder of the repository instead, and builds with
no network and no download cache; see [`[fetch]`](#fetch).

## `[dev-dependencies]`

A package the project's tests and examples use but its code does not, such
as a test helper, goes in `[dev-dependencies]`, written as in
`[dependencies]`:

```toml
[dev-dependencies]
fixtures = { github = "someone/fixtures", version = "1" }
```

- **Who sees them:** a test build (`pepper test`, which builds with
  `pep-build --test`) and a build of a file in the project's `examples`
  folder, or a folder below it. Any other build of the project, such as
  `pepper build`, does not: an import of one there is an error that says to
  move it to `[dependencies]`.
- **Not part of the package:** a project that depends on this package
  neither fetches nor resolves its dev-dependencies, so one that conflicts
  with the dependent's own dependencies does no harm.
- **Locked with the rest:** `pep.lock` records them beside the other
  packages, each that only dev-dependencies lead to marked `dev = true`,
  and `pepper build` fetches them with the rest.
- **Needs toolchain 0.11.0:** an older toolchain rejects a `pep.toml` with
  `[dev-dependencies]` as an unknown table, a dependency's included. So a
  package that has one sets `minimum_toolchain = "0.11.0"` (or later) in
  `[package]`, and `pepper package` on an older toolchain skips its
  versions instead of failing to build them. `pepper package publish`
  checks it (see [pep-package](pep-package.md#publish)).

`pepper package add --dev` adds one, and `pepper package remove` removes one
from either table (see [pep-package](pep-package.md#add-ownernamerange)). A
name may be in only one of the two tables.

```text
main.pep:1:8: error: 'fixtures' is a dev-dependency, which only tests and the files in examples/ import; move it to '[dependencies]' to import it here
    1 | import fixtures;
      |        ^~~~~~~~
```

## `[target.'<condition>'.dependencies]`

A package only some platforms need, such as a binding to a Windows API,
goes in a `[target]` table whose key is the condition, written as in
`[dependencies]`:

```toml
[target.'OS(Windows)'.dependencies]
winapi = { github = "someone/winapi", version = "1" }

[target.'OS(Linux) && Arch(x64)'.dependencies]
epoll = { github = "someone/epoll", version = "0.3" }
```

- **The condition** is what `[Target(...)]` takes, `OS(...)`, `Arch(...)`
  and `BuildOption(...)` with `&&`, `||` and `!` (see
  [Platform selection](../language/platform-selection.md)), and it is
  checked the same way: `OS(Darwin)` is an error at the key.
- **Who sees them:** a build whose target the condition selects: the
  machine building, or the platform `--target` names in a cross build.
  Guard the import the same way, so other targets skip it:

  ```pepper
  [Target(OS(Windows))]
  import winapi;
  ```

  An import a build for another target reaches is an error:

  ```text
  main.pep:1:8: error: 'winapi' is a dependency only for targets where 'OS(Windows)' holds, which this build's does not; put '[Target(OS(Windows))]' on the import
      1 | import winapi;
        |        ^~~~~~
  ```

- **Locked for every platform:** `pep.lock` lists every platform's
  packages, so it is the same on each, and marks those only some need
  with their `target` (see [pep.lock](pep-package.md#peplock)). A build
  fetches only what its target needs; resolving a change to `pep.toml`,
  or checking the lock with `--locked`, reads every package's `pep.toml`,
  so it fetches every platform's.
- **In a package:** a dependency's `[target]` tables apply to the
  projects that use it, for their build's target.
- **Needs toolchain 0.11.0:** an older toolchain rejects a `pep.toml` with
  a `[target]` table as an unknown table, so a package that has one sets
  `minimum_toolchain = "0.11.0"` (or later) in `[package]`, as for
  [`[dev-dependencies]`](#dev-dependencies); `pepper package publish`
  checks it.

`pepper package add --target 'OS(Windows)'` adds one, and `pepper package
remove` removes one (see [pep-package](pep-package.md#add-ownernamerange)).
A name may be in only one of the dependency tables, and a `[target]` table
holds only `dependencies`.

## `[features]`

A package with optional parts, such as TLS support in a client, names
them in `[features]`, so a project that does not want one neither builds
its code nor its dependencies. Each key is a feature, and its value lists
what turning it on turns on:

```toml
[package]
name = "http"

[dependencies]
openssl = { github = "someone/openssl", version = "3", optional = true }
zlib    = { github = "someone/zlib", version = "1", optional = true }

[features]
default = ["tls"]
tls     = ["dep:openssl"]                  # the optional dependency openssl
gzip    = ["dep:zlib", "zlib/simd"]        # zlib, and zlib's feature 'simd'
full    = ["tls", "gzip"]                  # other features of this package
```

- **Code reads a feature as a build option:** a feature that is on defines
  the build option `<package>_<feature>`, the package's `name` and the
  feature joined with `_` (`http_tls`), so `[Target(BuildOption(...))]`,
  `[BuildOption("...")]` and `reflect.build_option` select code by it, as
  for a `-D` option (see [Build options](../language/build-options.md)).
  A feature name is an identifier. The names join with a bare `_`, so two
  packages of one build should not share a `name`: their features would
  define the same options.
- **What a feature lists:** another feature of the package (`tls`); an
  optional dependency, `dep:<name>`; or a feature of a dependency,
  `<name>/<feature>`, which turns the dependency on too when it is
  optional. Each is checked against the package's own `pep.toml`.
- **`default`** is the feature a package has on unless it is asked not
  to: `--no-default-features` on `pepper build` and `pepper test` for the
  project's package, `default-features = false` in a dependency's entry
  for that dependency.
- **Turning features on:** `pepper build --features tls,gzip` (and
  `pepper test --features`) for the project's package; a dependency's
  entry, `features = ["gzip"]`, for that package. Features are additive
  and unified across the graph, as in Cargo: a package that two others
  depend on has every feature either turns on, and there is one copy of
  it in the build.
- **Optional dependencies** (`optional = true`) are seen only by a build
  with a feature that turns them on; guard the import with the feature's
  build option, so a build without it skips the import:

  ```pepper
  [Target(BuildOption(http_tls))]
  import openssl;
  ```

  An import of one that no feature this build turns on lists is an error:

  ```text
  module.pep:1:8: error: 'openssl' is an optional dependency, which no feature this build turns on lists; put the '[BuildOption(...)]' of a feature that lists 'dep:openssl' on the import
  ```

  A dev-dependency cannot be optional.
- **Locked whatever the features:** `pep.lock` records optional
  dependencies like the rest, and a build fetches them whether or not a
  feature turns them on, so the lock does not depend on which features a
  build picks, as it does not on the platform.
- **Needs toolchain 0.11.0:** an older toolchain rejects `[features]`, and
  a dependency's `optional`, `features` and `default-features`, so a
  package that uses them sets `minimum_toolchain = "0.11.0"` (or later),
  as for [`[dev-dependencies]`](#dev-dependencies); `pepper package
  publish` checks it.

`pepper package add --optional`, `--features` and `--no-default-features`
write a dependency's `optional`, `features` and `default-features` (see
[pep-package](pep-package.md#add-ownernamerange)).

## `[fetch]`

```toml
[fetch]
hosts = ["codeberg", "github"]
vendor = "vendor"
```

| Key | What it is | Default |
| --- | --- | --- |
| `hosts` | The hosts `pepper package add owner/name` looks a repository up on, in order, when the argument names none; it adds the first that has it | `["github", "gitlab", "codeberg"]` |
| `vendor` | The folder, relative to the project, that [`pepper package vendor`](pep-package.md#vendor-dir) copied every locked package into, which sets it. Builds then read each dependency from `<vendor>/<host>/<owner>/<name>` instead of `.pep/deps`, fetch nothing, and fail when a package is missing, at another commit than `pep.lock`'s, or edited. A package that sets it needs `minimum_toolchain = "0.11.0"` or later | none: dependencies are fetched into `.pep/deps` |

## Errors

A problem in `pep.toml` is an error located at the key or value to change:

```text
pep.toml:9:1: error: dependency 'io' has the name of the runtime module 'io'; give it another name, which source code then imports
    9 | io = { github = "someone/io" }
      | ^~
```

- Two dependencies with the same name (in one table, or in two of
  `[dependencies]`, `[dev-dependencies]` and the `[target]` tables), or a
  dependency named like a runtime module (`io`, `async`), which it would
  otherwise hide.
- A `[target]` condition `[Target(...)]` would reject.
- A feature that lists a feature the package lacks, a `dep:` that names
  no optional dependency, or a `<name>/<feature>` whose dependency does
  not exist; a dependency's `features` asking for one its package lacks
  (`package 'zlib' has no feature 'smid'`), which a build reports once
  the package is fetched.
- A dependency name that is not an identifier (`fast-json`): it is the name
  `import` uses.
- A dependency with no source or two, a repository not written `owner/name`,
  or more than one of `version`, `branch`, `tag` and `commit`.
- A table or key `pep.toml` does not have, or a value of the wrong type.

An import of a dependency that is not on disk says which folder is missing:

```text
main.pep:1:8: error: dependency 'geometry' is not fetched: no /home/you/my_app/.pep/deps/github.com/someone/geometry; run 'pepper package fetch'
    1 | import geometry;
      |        ^~~~~~~~
```

The language server reads `pep.toml` the same way, so imports of fetched
dependencies resolve in the editor with no `-I`.
