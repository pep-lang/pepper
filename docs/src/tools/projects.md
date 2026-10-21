# Projects: pep.toml

A `pep.toml` file marks the root of a project. It names the project, says
how `pepper build` builds it, and lists the packages it depends on, so a
project builds with `pepper build` and nothing else:

```bash
cd my_app
pepper build          # builds the program pep.toml describes
./my_app
```

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
`--offline` builds with only what `.pep/deps` holds (`--frozen` is both;
`PEPPER_LOCKED=1` and `PEPPER_OFFLINE=1` do the same). See
[Reproducible builds](pep-package.md#reproducible-builds).

## `[fetch]`

```toml
[fetch]
hosts = ["codeberg", "github"]
```

| Key | What it is | Default |
| --- | --- | --- |
| `hosts` | The hosts `pepper package add owner/name` looks a repository up on, in order, when the argument names none; it adds the first that has it | `["github", "gitlab", "codeberg"]` |

## Errors

A problem in `pep.toml` is an error located at the key or value to change:

```text
pep.toml:9:1: error: dependency 'io' has the name of the runtime module 'io'; give it another name, which source code then imports
    9 | io = { github = "someone/io" }
      | ^~
```

- Two dependencies with the same name, or a dependency named like a runtime
  module (`io`, `async`), which it would otherwise hide.
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
