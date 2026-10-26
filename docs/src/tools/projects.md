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

[build-dependencies]
codegen   = { github = "someone/codegen", version = "1" }    # only the build script imports it

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
| `script` | The package's [build script](#build-scripts), which builds its C code, or generates Pepper code, before its Pepper code is built | `build.pep`, when there is one |

Options on the command line still apply: `pepper build -O` builds the
project optimized, and `-o` names another output. A file argument builds that
file instead (`pepper build tools/gen.pep`); the project's dependencies,
`include` folders and `link` libraries still apply to it, since it is in the
project.

## Build scripts

A package that binds a C library can carry the library's C source and build
it itself, so its users install nothing. Its build script, a Pepper program
in `build.pep` at the package's root (or the file `[build]`'s `script`
names), compiles the C code, and prints what the build must link. It can
also write Pepper modules the package imports ([Generated
modules](#generated-modules)) and define build options its code reads.
Every build of a program that uses the package (a dependency, or the
project itself) compiles the script for the machine it runs on and runs it
before it loads the program, even when it builds for another platform with
`--target`. The script imports the runtime and its package's
[`[build-dependencies]`](#build-dependencies), and stands apart from the
code it builds: building it does not load its package's root module,
which may import what the script generates, though it may import a file
beside it. Cargo users know it as `build.rs`.

```text
native/
├── pep.toml
├── module.pep        # extern int native_add(int a, int b); and the API around it
├── build.pep
└── c/add.c
```

```pepper
# build.pep: compiles c/add.c for the build's target and links it.
import [Path] from io;
import os;
import process;

main(): int {
    var object = Path(os.environment("PEP_OUT_DIR").value()).join(Path("add.o"));
    var compiled = process
        .Command(os.environment("PEP_CLANG").value())
        .arguments(["--target=" + os.environment("PEP_TARGET").value(), "-c", "c/add.c", "-o", object.to_string()])
        .run();
    if (compiled.is_err() or !compiled.value().status.success()) {
        return 1;
    }
    print($"pep:object={object}");
    print("pep:rerun-if-changed=c");
    return 0;
}
```

The script runs in the package's folder, with these environment variables:

| Variable | What it holds |
| --- | --- |
| `PEP_TARGET` | The triple the program is built for (`x86_64-pc-windows-msvc`), as `--target` names it |
| `PEP_TARGET_OS`, `PEP_TARGET_ARCH` | Its OS (`linux`, `macos`, `windows`, `wasi`, `ios`, `android`) and architecture (`x86_64`, `aarch64`) |
| `PEP_HOST` | The triple of the machine the build runs on |
| `PEP_OPT_LEVEL` | The optimization level, `0` to `3` |
| `PEP_FEATURES` | The package's [features](#features) the build turns on, separated by commas |
| `PEP_PACKAGE_NAME`, `PEP_PACKAGE_DIR` | The package's name and folder |
| `PEP_OUT_DIR` | A folder of the package's own for what the script makes, and the package's [generated modules](#generated-modules): `.pep/build/<package>-<hash>/out`, `<hash>` naming where the package is (below `--build`'s folder when given) |
| `PEP_CLANG` | The clang the build links with (see [What the compiler links](../language/linking.md#what-the-compiler-links)), empty when there is none; it compiles C for any target LLVM supports |
| `PEP_SYSROOT` | The target's system root (`--sysroot`), empty when there is none |

What the script prints on standard output, a line each, tells the build
what to do; other lines are its own and ignored:

| Line | What it does |
| --- | --- |
| `pep:object=<file>` | Links an object file or a static library (`.a`, `.lib`) |
| `pep:link=<name>` | Links a library by name, as `-l` does |
| `pep:link-path=<dir>` | Adds a folder the linker searches, as `-L` does |
| `pep:build-option=<NAME>[=<value>]` | Defines the [build option](../language/build-options.md) `<package>_<NAME>`, as `-D` does (a bare `NAME` is `NAME=1`); the package's code reads it as a feature's |
| `pep:warning=<text>` | Shows `warning: <package>: <text>` |
| `pep:rerun-if-changed=<path>` | Runs the script again when the file, or any file in the folder, changes |
| `pep:rerun-if-env-changed=<name>` | Runs the script again when the environment variable changes |

A relative path is relative to the package's folder. A line starting `pep:`
that is none of these is an error, as is a script that exits with a status
other than 0, which shows what it printed. What the script printed on
standard error is passed on.

**When it runs again.** The build keeps the script's output in
`.pep/build/<package>-<hash>/stamp`, and uses it again until something the script
depends on changes: its own file, every Pepper file it imports (files of
its own beside it, and its build-dependencies' sources; not the runtime),
its package's `pep.toml`, the project's `pep.lock` (which holds its
build-dependencies' revisions), the variables above, and what its
`rerun-if-changed` and `rerun-if-env-changed` lines name; or until its
`PEP_OUT_DIR`, or an object it named, is gone. The files it imports are the
ones the [build cache](pep-build.md#the-build-cache) recorded its last
build used, so after the cache is emptied the script runs again. A script that
reads other files at run time, such as its C sources, names them with
`rerun-if-changed`; a change to a file it neither imports nor names leaves
its last output in use. Builds that run side by side
(`pepper test`) run one package's script one at a time.

### Generated modules

A script can write Pepper code, such as bindings made from a C header or
tables computed at build time, into `PEP_OUT_DIR`: its `module.pep` there is
the module the package's code imports as `generated`, and a folder there
holding a `module.pep` is `generated.<folder>`. Only the package's own
files see it, and its imports resolve against the package's dependencies.

```pepper
# build.pep: generates the module that names what it was built for.
import [File, Path] from io;
import os;

main(): int {
    var out = Path(os.environment("PEP_OUT_DIR").value());
    var target = os.environment("PEP_TARGET").value();
    File.write_text(out.join(Path("module.pep")), "export built_for(): String {\n    return \"" + target + "\";\n}\n");
    print("pep:build-option=FAST=1");
    return 0;
}
```

```pepper
# module.pep of the package `native`
import generated;

export describe(): String {
    return "native for " + generated.built_for();
}

[BuildOption("native_FAST")]
export fast(): bool {
    return true;
}
```

A generated module is part of the program like any file: its build cache
key covers its text, so a script that writes something new rebuilds what
imports it. A package with no build script has no `generated` module, and a
dependency the package names `generated` is imported in its place. An
import of a module the script did not write is an error at the import:

```text
module.pep:1:8: error: the build script of 'native', native/build.pep, wrote no module 'generated': no native/.pep/build/native-1a2b3c4d/out/module.pep
```

The language server finds a package's generated modules after a build has
made them in the project's `.pep/build`, and does not see the build options
a script defines.

**What a build script can do.** A build script is a program like any
other: it runs with your permissions, can read and write any file you
can, start programs and use the network. Building a project that depends
on a package with a build script runs that package's code on your machine,
before any of its code is in a program you chose to run. So:

- `pepper package add`, `update` and `fetch` name each package that
  arrives (new, or at another commit) with a build script, and the file to
  read: `note: native 1.0.0 (github:someone/native) has a build script,
  which every build of the project compiles and runs on this machine: read
  ...`.
- `pepper build --no-build-scripts` (or `PEPPER_NO_BUILD_SCRIPTS=1`, which
  `pepper test` and `pepper run` builds see too) fails instead of running a
  dependency's script, naming it. The project's own script still runs: it
  is your code.

What is not supported yet: a helper package for finding a library with
`pkg-config` and compiling C with the target's flags, and a `[native]`
table that compiles C sources without a script.

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
| `package` | With a repository: the member of the repository's [workspace](#workspaces-workspace) it is, by its `[package]` `name` (see [A member as a Git dependency](#a-member-as-a-git-dependency)) |
| `version` | A semver range of the repository's version tags: `1.2`, `0.4.x`, `>=1.0, <2` |
| `branch` | A branch |
| `tag` | A tag |
| `commit` | A commit |
| `optional` | `true`: a build uses it only when a [feature](#features) turns it on |
| `features` | An array of the dependency's features to turn on |
| `default-features` | `false` leaves the dependency's `default` feature off |
| `workspace` | `true`: its source and revision are its [workspace's](#workspaces-workspace) |

A dependency has exactly one source, and at most one of `version`, `branch`,
`tag` and `commit`; with none, it follows the repository's default branch.
A `path` dependency takes only a `version`, which a build ignores and
[`publish`](pep-package.md#publish) asks for.

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
same copies. When packages need different majors of one package, each
major is a copy of its own, `<name>@v<major>`, and an import resolves to
the copy of the major its key's range asks for (see
[Two majors of one package](pep-package.md#two-majors-of-one-package)).

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

## `[build-dependencies]`

A package the [build script](#build-scripts) imports, such as a code
generator or a helper for compiling C, goes in `[build-dependencies]`,
written as in `[dependencies]`:

```toml
[build-dependencies]
codegen = { github = "someone/codegen", version = "1" }
```

- **Who sees them:** only the package's build script, which is built for
  the machine the build runs on, so they are too; they are never linked
  into the program. The script sees no other dependency of its package
  (an import of one says to add it here), and the package's code does not
  see its build-dependencies. A name may be in `[dependencies]` too, for
  both to import.
- **Part of the package:** unlike dev-dependencies, every package's
  build-dependencies are resolved, a dependency's included, since its
  script runs in your build. One the package's other packages need too is
  one copy, at one version, as for any dependency.
- **Locked and vendored with the rest:** `pep.lock` records them beside the
  other packages, each that only build-dependencies lead to marked
  `build = true` (and `pepper package tree` marks it `[build]`), `pepper
  build` fetches them, `pepper package vendor` copies them, `audit` checks
  them, and `[overrides]` and [two majors](pep-package.md#two-majors-of-one-package)
  apply to them as to the rest. A build-dependency's own build script runs
  in the build of the script that imports it.
- **Not optional:** `optional = true` there is an error; a script reads its
  package's features from `PEP_FEATURES`.
- **Only on some hosts:** `[target.'<condition>'.build-dependencies]`
  holds those a script needs only on some machines; see
  [below](#targetconditionbuild-dependencies).
- **Added with** `pepper package add --build` (see
  [pep-package](pep-package.md#add-ownernamerange)).
- **Needs toolchain 0.11.0**, as `[dev-dependencies]` does.

```text
main.pep:1:8: error: 'codegen' is a build-dependency, which only the package's build script imports; add it to '[dependencies]' to import it here
    1 | import codegen;
      |        ^~~~~~~
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
holds only `dependencies` and
[`build-dependencies`](#targetconditionbuild-dependencies).

## `[target.'<condition>'.build-dependencies]`

A package the [build script](#build-scripts) needs only on some machines
goes in a `[target]` table's `build-dependencies`, written as in
[`[build-dependencies]`](#build-dependencies):

```toml
[target.'OS(Windows)'.build-dependencies]
vswhere = { github = "someone/vswhere", version = "1" }
```

- **The condition holds for the host**, the machine building, not the
  target: the script is built for and runs on the host. A cross build
  for Linux on Windows gives its script the `OS(Windows)` ones, and none
  of the `OS(Linux)` ones. Guard the script's import the same way:

  ```pepper
  [Target(OS(Windows))]
  import vswhere;
  ```

  An import a script reaches on another host is an error:

  ```text
  build.pep:1:8: error: 'vswhere' is a build-dependency only for hosts where 'OS(Windows)' holds, which this one does not; put '[Target(OS(Windows))]' on the import
  ```

- **Locked and fetched on every host:** `pep.lock` is shared by every
  machine, so it records no condition for them, and a build fetches them
  whatever it builds for.
- **The rest is as for `[build-dependencies]`:** never optional, a name
  only once among them, added with `pepper package add --build --target
  '<condition>'`.

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

## Workspaces: `[workspace]`

A repository holding several related packages, such as a library with its
examples or a client and a server, makes them one workspace: a `pep.toml`
at the root lists them, and they share one `pep.lock` and one
`.pep/deps`, so every member builds with the same revision of each
dependency.

```text
shapes/
  pep.toml            [workspace]
  pep.lock            one lock for every member
  app/pep.toml        [package] name = "app"
  libs/geo/pep.toml   [package] name = "geo"
  libs/draw/pep.toml  [package] name = "draw"
```

```toml
# shapes/pep.toml
[workspace]
members = ["app", "libs/*"]

[workspace.dependencies]
numbers = { github = "someone/numbers", version = "1.2" }
geo     = { path = "libs/geo", version = "0.3" }
```

```toml
# shapes/app/pep.toml
[package]
name = "app"

[dependencies]
numbers = { workspace = true }                   # someone/numbers 1.2
geo     = { workspace = true, features = ["3d"] }
draw    = { path = "../libs/draw", version = "0.1" }
```

- **`members`** lists the member folders, relative to the root: a folder
  (`app`), or a glob of folders (`libs/*`, see
  [`io.glob`](../reference/io-glob.md)). Each holds a package's `pep.toml`.
  The root may be a package too, with a `[package]` of its own: it is
  then a member without being listed. A root without one only holds the
  workspace.
- **One lock:** `pepper package` and `pepper build`, run in the root or
  any member, resolve every member's dependencies together into the
  root's `pep.lock`, and fetch into the root's `.pep/deps`. The members'
  own dependencies count as the project's, so when two ask for one
  package, both ranges must hold (see
  [Resolving versions](pep-package.md#resolving-versions)).
- **`[workspace.dependencies]`** gives a source and revision once, for
  each member to inherit with `workspace = true`. A member's entry adds
  `optional`, `features` and `default-features`, and nothing else; a
  `path` there is relative to the root.
- **Members depend on each other** with `path`. A `version` beside the
  `path` is for [`publish`](pep-package.md#publish), which refuses a
  `path` without one, and checks the sibling is published at a version
  it accepts; a build in the workspace uses the folder. A project outside
  the workspace that fetches the member reads it as the sibling of the
  same repository at that version (see below).
- **Building:** `pepper build` in a member builds that member; in a root
  with no `[package]`, every member. `--all` builds every member, and
  `-p <name>` (repeated for more) the members by package name, from the
  root or any member, each into its own output; a member with no entry
  file, a library, is skipped. `pepper test --all` and `pepper test -p
  <name>` test them the same way (see [pep-build](pep-build.md) and
  [pep-test](pep-test.md)).
- **Features are unified** across the members a build selects, as in
  Cargo: each member's `default` and its dependencies' features are on
  in every one of them, and `--features` turns a feature on in each
  member that has it.
- **[`[overrides]`](#overrides)** belong in the root, and apply to every
  member; a member's own are ignored.
- **One level:** a member cannot be a workspace itself, and a package is
  in the workspace of the nearest `pep.toml` above it with
  `[workspace]`, when that lists it. A package in `.pep/deps` is in none
  of the project's.
- **Needs toolchain 0.11.0,** as for
  [`[dev-dependencies]`](#dev-dependencies): `[workspace]` and a
  dependency's `workspace` and `package` are unknown to older toolchains.

### A member as a Git dependency

A project outside the workspace depends on one of its members by the
repository and `package`, the member's `[package]` `name`, as Cargo does
with a package inside a Git repository's workspace:

```toml
[dependencies]
geo = { github = "someone/shapes", package = "geo", version = "0.3" }
```

`pepper package add someone/shapes --package geo` writes that entry (see
[pep-package](pep-package.md#add-ownernamerange)).

- **Found through the root's `members`:** the member is the package of
  that name among the folders the root's `[workspace]` `members` lists, so
  it may move between folders without its dependents changing. Without
  `package`, a dependency is the repository's root package.
- **Tagged on its own:** [`publish`](pep-package.md#publish) in a member
  tags `<name>-v<version>` (`geo-v0.3.1`), and a member's `version` range
  reads only its own tags, so each member is released at its own pace. The
  root package keeps `v<version>`, as a single-package repository does.
  A package name is an identifier, with no `-`, so the tags cannot clash.
- **Its own checkout and lock entry:** it is locked as
  `github:someone/shapes#geo` (see [pep.lock](pep-package.md#peplock)),
  and checked out at its own commit in
  `.pep/deps/github.com/someone/shapes#geo`, from the same repository in
  the [download cache](pep-package.md#the-download-cache) as every other
  member. [`[overrides]`](#overrides) name it by that source too.
- **Its siblings:** a `path` with a `version` in the member's `pep.toml`
  names another package of its workspace, so the project depends on that
  member (or the root) of the same repository, at the newest of its own
  tags the version accepts, not at the commit the member was fetched at.

A `package` with a `path`, which names a member's folder itself, or one
that is not an identifier, is an error at the key. A `package` the
workspace lacks is an error at its value when `pepper package` fetches it:

```text
pep.toml:5:43: error: someone/shapes has no workspace member 'gem'; its members are 'geo', 'draw'
    5 | geo = { github = "someone/shapes", package = "gem" }
      |                                              ^~~~~
```

### Workspace errors

The problems of a workspace are errors at the member in the root's
`members`, or at the dependency that inherits:

```text
pep.toml:2:19: error: workspace member 'app' is listed twice
    2 | members = ["app", "app"]
      |                   ^~~~~
```

- a member that is not a package (no `pep.toml`), one listed twice, or
  one that is a workspace itself;
- `workspace = true` with a source or revision of its own, in a package
  no workspace lists, or naming what `[workspace.dependencies]` lacks;
- `optional`, `features`, `default-features` or `workspace` in
  `[workspace.dependencies]`.

## `[overrides]`

To try a fix in a package deep in the graph, or to use a fork until the
fix is released, the project replaces the package wherever the graph
reaches it, without editing the `pep.toml` of each package on the way:

```toml
[overrides]
"github:other/numbers" = { github = "me/numbers", branch = "fix-overflow" }
"github:someone/geometry" = { path = "../geometry" }
```

- **The key** is the source of the package it replaces, as
  [`pep.lock`](pep-package.md#peplock) writes it: the host's key, `:`,
  and the repository (`github:owner/name`, and `#` and the member for a
  [workspace member](#a-member-as-a-git-dependency)). One table keyed by the source
  is enough, since a source is what makes two dependencies the same
  package in the graph; the name each dependent imports it by does not.
- **The value** is the package that replaces it, written as a dependency
  is: a repository (`github`, `gitlab`, `codeberg`) with at most one of
  `version`, `branch`, `tag` and `commit`, or a `path`, relative to this
  `pep.toml`. It takes no `optional`, `features` or `default-features`;
  those stay on each dependency.
- **Everywhere, whatever is asked:** every package that depends on the
  source gets the replacement, the project included, whatever version
  range or branch each asks for, in whatever major, so an override also
  makes a graph that holds [two majors](pep-package.md#two-majors-of-one-package)
  of the package hold one. A fork is checked out in the original's
  folder, `.pep/deps/<host>/<owner>/<name>`, and a `path` override's
  folder is read in its place, its own dependencies included. Imports do
  not change.
- **Locked:** `pep.lock` records the replacement in the package's
  `override`, with the fork's commit (see
  [pep.lock](pep-package.md#peplock)), so `--locked` and `--offline`
  builds stay reproducible, and adding, changing or removing an override
  changes the lock.
- **Only the project's own:** a dependency's `[overrides]` do not apply
  to the projects that use it, and `pepper package publish` refuses a
  package with any (see [publish](pep-package.md#publish)). In a
  [workspace](#workspaces-workspace), only the root's apply, to every
  member; a member's are ignored, which `pepper package` warns about.
- **Checked by `pepper package`:** an override that matches no package in
  the graph is a warning at its key, and a replacement whose `[package]`
  `name` differs from the name `pep.lock` records for the package it
  replaces is an error there:

  ```text
  pep.toml:9:1: error: 'github:someone/geometry' is the package 'geometry', not 'numbers', which it overrides; name a fork or copy of 'numbers'
      9 | "github:other/numbers" = { github = "someone/geometry", tag = "v1.0.0" }
        | ^~~~~~~~~~~~~~~~~~~~~~
  ```

- **Needs toolchain 0.11.0:** an older toolchain rejects a `pep.toml`
  with `[overrides]` as an unknown table.

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

## `[retract]`

A package withdraws its own broken releases, as Go's `retract` does: each
key is a version, or a range as dependencies write it, and its value says
why.

```toml
[retract]
"1.1.0" = "loses data on Windows"
">=1.2.0, <1.2.3" = "PEP-2026-0001"
```

A key that is a version names that version alone, not the `^` range a
dependency's `version = "1.1.0"` means; keys are quoted, as TOML reads
`1.1.0` unquoted as three nested keys. Release the table in a newer
version (a workspace member's newest release by its own tags, read from
the member's `pep.toml`): the `[retract]` of a package's newest release
speaks for every version, so a range no longer picks a retracted one, `pepper package
outdated` flags one `pep.lock` holds, and `update` moves off it (see
[Retracted versions](pep-package.md#retracted-versions)). A key that is
neither a version nor a range is an error at the key in the project's
own `pep.toml` (a dependency's retracts nothing, so its dependents still
resolve):

```text
pep.toml:8:1: error: '1.x.q' in '[retract]' is not a version or range: ...
```

- **Needs toolchain 0.11.0:** an older toolchain rejects a `pep.toml` with
  `[retract]` as an unknown table, so a package that has one sets
  `minimum_toolchain = "0.11.0"` (or later), which `pepper package
  publish` checks.

## `[audit]`

```toml
[audit]
ignore = ["PEP-2026-0001"]   # its code is never called here
```

| Key | What it is | Default |
| --- | --- | --- |
| `ignore` | The advisories, by id, that [`pepper package audit`](pep-package.md#audit) reports but does not fail on, with `--ignore` | `[]` |

Only the project's own (in a workspace, its root's) `[audit]` applies.
An older toolchain than 0.11.0 rejects the table.

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
  or more than one of `version`, `branch`, `tag` and `commit`; a `package`
  with a `path`, or one that is not an identifier.
- An `[overrides]` key that is not a source (`github:owner/name`), or an
  override with `optional`, `features` or `default-features`.
- A table or key `pep.toml` does not have, or a value of the wrong type.
- A `[build]` `script` that names a file that does not exist, which a
  build reports.

An import of a dependency that is not on disk says which folder is missing:

```text
main.pep:1:8: error: dependency 'geometry' is not fetched: no /home/you/my_app/.pep/deps/github.com/someone/geometry; run 'pepper package fetch'
    1 | import geometry;
      |        ^~~~~~~~
```

The language server reads `pep.toml` the same way, so imports of fetched
dependencies resolve in the editor with no `-I`.
