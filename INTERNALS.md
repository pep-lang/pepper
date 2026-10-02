# Pepper compiler internals

A map of the compiler for people and agents about to change it: where each
stage lives, how a program travels from source text to an executable, and the
patterns the code follows. It complements two other files:

- [README.md](README.md): setting up LLVM, building, running the CLI. Not
  repeated here.
- [AGENTS.md](AGENTS.md): the rules (workflow, CLI string handling, CI
  hygiene, the reference-counting model, the diagnostic standard, the
  library documentation standard). This file links to them and does not
  restate them.

The language itself is described in the book under [`docs/src/`](docs/src/introduction.md)
(tutorials, language guide, and the generated standard library reference).

A note on history: the Rust compiler is a port of an earlier C++
implementation, since deleted (#48). Many module doc comments still say
"port of `source/Sema/...cpp`". Those paths no longer exist, but the pass
names and the pass order come from that implementation.

---

## 1. Repository layout

| Path | Role |
| --- | --- |
| `src/main.rs` | The compiler binary, `pep-build` (run as `pepper build`): parses `Options`, calls `pepper_driver::run`, prints errors (colored on a TTY unless `NO_COLOR`). |
| `crates/pepper-parser` | winnow grammar → AST (`ast.rs`, `parser.rs`, `parser/parsers.rs`), clang-style diagnostics (`diagnostic.rs`), doc-comment parsing and the documentation check (`doc.rs`). No LLVM. |
| `crates/pepper-files` | Filesystem helpers shared by the driver and the LSP: import resolution (`imports.rs`) and runtime discovery (`runtime.rs`). No LLVM. |
| `crates/pepper-sema` | Program loading and module linking (`program.rs`, `modules.rs`, `visibility.rs`, `deprecation.rs`, and the scope walk they share, `scope_walk.rs`), AST → model builder (`builder.rs`), the sema model (`model.rs`), struct synthesis (`struct_body.rs`), and the transform passes (`passes/`). No LLVM. |
| `crates/pepper-codegen` | Sema model → LLVM IR through `inkwell` (`lib.rs`, plus `types.rs`, `address.rs`, `ops.rs`, `checks.rs` (runtime checks, see 4), `target.rs`, `facts.rs` (the IR facts, see 4.1), `jit_memory.rs`, `intrinsics.rs` (externs bound to LLVM intrinsics, see 4), and `context.rs`, the naked-assembly context-switch intrinsics). Also hosts the MCJIT entry points the tests use. |
| `crates/pepper-driver` | Glues the stages together (`compiler.rs`), CLI options (`options.rs`), object emission and linking (`lib.rs`, `linker.rs`). Holds nearly all integration tests (`tests/*.rs`). |
| `xtask/` | `cargo setup` (`cargo run -p xtask -- setup`): picks and runs `scripts/setup-llvm.{sh,ps1}` and writes `.cargo/config.toml`. Has no dependencies, so it builds before LLVM exists. |
| `tools/lsp` | `pep-lsp`, a tower-lsp language server. Parser and sema only, so it never links LLVM. |
| `tools/vscode-pepper` | VS Code extension: TextMate grammar, language configuration, and a client that launches `pep-lsp`. |
| `tools/docgen` | `pep-doc`: generates `docs/src/reference/` from runtime doc comments and builds the mdBook site. |
| `tools/syntax` | A Pepper library (written in Pepper): lexer and lossless syntax tree for Pepper source, for tools. See [section 8](#8-language-server-and-vs-code-extension). |
| `tools/pep-fmt` | `pep-fmt`, the code formatter, written in Pepper on `tools/syntax`. |
| `tools/pepper` | `pepper`, the entry point written in Pepper: `pepper <command>` runs `pep-<command>` found next to it or on the `PATH` (`pepper build` runs the compiler). Tested by `pepper_entry_tests.rs`. |
| `runtime/` | The standard library, written in Pepper. Top-level `*.pep` files form the prelude; each folder (`runtime/io/`, `runtime/process/`, ...) is an importable module. |
| `tests/` | `.pep` corpus: `hello.pep` (the README's example) plus one `tests/<Feature.Case>/test.pep` per folder, which `corpus_tests.rs` compiles and runs. |
| `docs/` | The user-facing book: mdBook sources (`src/`), tested examples (`examples/`), generated library reference (`src/reference/`). |
| `benchmarks/` | Benchmarks to compare a change against: `compress/` (`bench.py` times the compress module against `gzip`, `check.py` cross-checks it with Python's zlib, both driving `tool.pep`). |
| `scripts/` | LLVM provisioning and packaging (`setup-llvm.*`, `ci-provision-llvm.sh`, `package-llvm.*`, `probe-llvm-packages.sh`), and `install-vscode-extension.ps1`. |
| `.github/workflows/` | `ci.yml`, `platform-test.yml`, `vsix.yml`, `docs.yml`, `llvm-package.yml` (see [section 11](#11-ci)). |
| `.agents/skills/` | Agent workflows: `build`, `test`, `platform-test`, `finish-pr`. Read `build` and `test` before diagnosing a failure; they record failures this project has already hit. |

Dependency direction: `parser ← files ← sema ← codegen ← driver ← pep-build`.
`lsp` and `docgen` depend on the parser (and the LSP also on sema and files)
and nothing that links LLVM.

---

## 2. The pipeline end to end

```text
pep-build main.pep [-I dir] [--import name] [-l lib] [-o out] [--build dir]   (pepper build ...)
  │  src/main.rs: Options::parse → pepper_driver::run            (driver/src/lib.rs)
  │
  ├─ --emit-ast ─→ run_emit_ast: parse_source(entry) → print AST   (entry file only)
  ▼
compiler::compile → compile_sources                               (driver/src/compiler.rs)
  program::load_program                                           (sema/src/program.rs)
    runtime::discover()           PEPPER_RUNTIME, else runtime/ near cwd or exe
    imports::search_paths         -I dirs, then runtime dirs
    resolve_forced                --import NAME → prelude, ahead of the runtime
    program::load                 parse_source every reachable file; resolve imports
    modules::link                 bind imports/exports; rewrite m.x, aliases; mangle
                                  private names (helper@io/file) → FileScope
  compiler::merge
    Program::check                linking errors, then visibility::check_visibility
    Program::warnings             parser warnings + deprecation::check_uses → module.warnings
    builder::build_file(i)        AST → sema model, locations carry FileId(i)
    Module::merge                 all files into ONE sema Module (names already unique)
  compiler::run_passes (then print module.warnings, sorted, even on error)
    apply_platform_filters        drop [Target(...)] that is false on the host
    struct_body::apply            resolve_type_aliases; __refcount, ctor, dtor,
                                  __acquire/__release bodies
    passes::transform_pass        ~30 ordered steps (section 3)
  ▼
  ├─ --emit-llvm ─→ CodeGenerator::generate (whole program) → <build>/<name>.ll
  ▼
driver::objects: Program::units, cache::unit_key, then per unit, on parallel threads (driver/src/lib.rs)
  cache::Cache::object            source key hit → reuse the object, no codegen (locked)
  otherwise:
  CodeGenerator::generate with a UnitFilter                     (codegen/src/lib.rs)
    instantiate structs → sizes → methods → ctors → externs → functions
    emit_globals → codegen_unit (own bodies, then called instantiations)
  partition::finish               linkage, globaldce, symbol_name spelling
  cache::Cache::object            same bitcode → reuse the object, else emit + store
  → <build>/<name>.units/<unit>.o, plus the program module → <build>/<name>.o
link_libraries (from [Link]) + -l + runtime/*.a
linker::link → clang -o <out> <objs> -L… -l… (+ kernel32 user32 shell32 on Windows, m on Linux)
```

The CLI produces an executable and never runs it. Tests usually stop after
`generate` and JIT the module instead (see [section 9](#9-tests)).

**A checked runtime** (`sema/src/checked.rs`, design in
`design-notes/sema/canonical-specialization.md`). The test harnesses
(`compiler::compile_with_runtime`) and the language server (`sema_model_of`)
check many programs against one runtime, so they check the runtime alone
once per process and reuse it, and the CLI keeps it in the build cache
(§4.3) for the next process: `checked_runtime` builds the runtime files
(`runtime_files`: the prelude, forced imports, files under a runtime
folder), runs the passes, and marks every declaration checked
(`Module::checked`); `on_checked_runtime` clones that, swaps in the
program's sources, namespaces and extension scopes, adds the other files,
and the passes then check only those: they read the checked declarations
and leave them alone (`checked::stash_bodies` keeps their bodies out of
the passes that walk bodies, and `enums::resolve_enum_cases` skips their
parameter and field defaults, whose cases it resolved already), specializations the runtime already made are
reused, and `check_confinement` starts from the runtime's recorded link
summaries. A checked runtime keeps the link summaries of all its
functions that reach no trait call, by summary key (`Checked::summaries`),
and `check_confinement` neither summarizes nor checks those functions
again. What the passes derive from the checked declarations (the
`StructTable` and named-argument `Callees` of the checked structs and
functions, and the trait types they use) is built once per module, on
first use, as `checked::CheckedFacts` (`Module::checked_facts`; computed
with the runtime, so the in-process copies share it): a pass's table over
the program holds only what the program adds and reads the rest from the
facts, and `CheckedFacts::covers_struct` leaves out a checked struct a
program's extension adds members to. Passes that walk bodies skip
declarations with none, so the stashed runtime costs them nothing. The process-wide cache (`CHECKED_RUNTIMES`, a few entries) is
keyed by the target platform and each runtime file's place, name,
namespace (its mangled names carry it) and text. With a store (the CLI),
the store is the cache and memory is skipped. A program that overrides a runtime generic (`hash<int>`) changes
the runtime's own instances, so it is checked whole (`compiler::merge`).

### 2.1 CLI options (`crates/pepper-driver/src/options.rs`)

`Options` is a clap derive struct. Only these options take effect:
`source_files` (only the first is compiled; the rest are ignored), `-I`,
`--import`, `-l`, `-L`, `-o`, `--build`, `-O<n>` (`effective_opt_level`, see
[4.1](#41-object-emission-linking-running-driversrclibrs-linkerrs)),
`--emit-llvm`, `--emit-ast`, and
`--no-runtime`, `--no-runtime-checks=<list>` (`effective_runtime_checks`:
a `checks::RuntimeChecks`, every check on at `-O0` with a warning,
`runtime_checks_warning`; part of `cache::Build` and so of the cache key),
`--no-cache`, `--cache <dir>`, `--verify-cache`, `--no-verify-cache` (see [section 4.3](#43-build-cache-driversrccachers-codegensrcpartitionrs)), `-T time` (or `--Tall`), which prints each stage's
time on stderr (`StageTimer` in `driver/src/lib.rs`: load and parse, check
and build, sema passes, codegen and emission, link), `-T passes`, which
prints each sema pass's time summed over its runs (`sema/src/pass_timer.rs`,
fed by `transform_pass`'s `step!`), and `-T cache`, which
prints how the cache supplied each unit's object (`hit`, `hit (same code)`
or `miss`). `-g` emits debug info (see
[4.4](#44-debug-info-codegensrcdebugrs-debug_typesrs)). `-v` and the
other `-T` channels are parsed and ignored.
`--MSVC` returns an error. `output_path()` defaults to `<cwd>/<entry stem>`
with no extension, and `module_name()` is the output's stem.

### 2.2 Program loading (`crates/pepper-sema/src/program.rs`, `crates/pepper-files`)

- **Runtime discovery** (`pepper_files::runtime::discover`). When the
  `PEPPER_RUNTIME` environment variable is set and non-empty, it names the
  runtime directory and nothing else is searched. Otherwise the candidates
  are `<cwd>/runtime`, `<cwd>/.pep/runtime`, and `../runtime` up to five
  levels above the current directory, then `runtime` beside the running
  executable and up to five levels above it (so `target/debug/pep-build` finds
  the checkout's `runtime/` from anywhere). The **first** directory
  containing `.pep` files wins. Only that directory's top-level `.pep` files
  join the prelude (`runtime/io/` does not). Any `.a` files there are
  linked. Every directory scanned before the winner is also returned, and
  those become import search paths. `discover_from(cwd, exe_dir)` is the
  testable core. In `Mode::Strict`, `load_program` fails with `cannot find
  the Pepper runtime` when no runtime is found (unless `--no-runtime`);
  `Mode::Lenient` carries on without a prelude.
  Tests still `set_current_dir` to the repository root so the cwd candidate
  wins.
- **`load_program(root, &Setup)`** is the single loader. The CLI, test
  harnesses, and the LSP all call it. `Setup` holds `import_dirs` (`-I`),
  `forced_imports` (`--import`), `runtime`, and `mode`. `Mode::Strict`
  (compiler) fails on an unreadable or unparseable import. `Mode::Lenient`
  (LSP) skips it and records why.
- **`load`** walks a stack: the root is `files[0]`, then the files its
  imports reach, then the prelude. Each file goes through
  `parse_source`. For each import, `passes::platform::keep` evaluates its
  `[Target]` attributes first; an import that is dropped is never resolved.
  - `import "x"` (`imp.is_local`) goes through `imports::resolve_local`,
    which tries `x.pep` beside the file and then `x/module.pep`. A file
    target must be in the same module (`ModuleRoots::placement`); otherwise
    the import is reported as belonging to another module, or as outside
    this module or folder.
  - `import m` goes through `imports::resolve_module`, which returns the
    first `<search path>/m/module.pep`.
  - Files reached from prelude files through local imports are marked
    `prelude_part`, which exempts their functions from duplicate-export
    checks (types and variables never are: two prelude files exporting one
    is a `redefinition`).
- **`modules::link`** binds every file's imports and `export x as y`
  re-exports, then **rewrites each imported spelling in the AST**
  (`m.sqrt`, an alias `power`, a qualified type `m.Point`) to the name of the
  declaration it denotes. The type arguments of a generic method call
  (`b.run<S>(...)`), which the parser keeps in the member name, are
  rewritten the same way (`member_type`). It also gives each file's
  **private** top-level declarations, and every reference to them, a
  mangled name
  (`pepper_parser::namespace::mangle`: `helper@io/file`), keyed on the
  file's `ProgramFile::namespace`, which `load` computes with
  `ModuleRoots::namespace_of` (module name plus path inside the module;
  outside any module, the path from the project directory, the one the
  compiler runs in, such as `tests/util`; the file stem only for a file
  outside both, made unique with `#2`, `#3` in load order). A namespace
  depends only on the file's path, so a file's symbols are the same in
  every program that loads it, which the build cache relies on. Exports are
  mangled the same way (#244), so two modules may export one name, except
  those of the root file and the prelude (`prelude` or `prelude_part`;
  `exports_keep_names`), which every file reaches by their bare names. A
  reference to another file's mangled export that no import binds stays
  unrenamed, and the visibility check reports it as not imported. Externs
  and concrete overrides keep their names; so do
  the root file's private names, unless another file keeps the same name
  (so `main` and a JIT test's `test` stay findable). `own_names` decides
  this. Which generic functions are concrete overrides (`hash<int>`, and
  `hash<Point>` of a visible `hash<T>`) is decided by `modules::Overrides`,
  the same rule sema's `gather_generics::concrete_overrides` applies: every
  type parameter names a primitive, `String`, or a struct, and either all
  are primitives or `String`, or a generic of that name and arity exists.
  A constrained parameter (`describe<Point: Shape>`) is always a parameter,
  so a function with one is never an override, and counts as a base.
  "A type" and "a base" mean ones the declaring file can name: its own,
  the exports of the files it imports (a module's are its `module.pep`'s,
  re-exports included), the prelude's, under import-list aliases too
  (`visible_names`, iterated until re-exports settle). Linking marks an
  override's parameters (`GenericParam::is_argument`) and resolves them
  like type references to the structs they denote, mangled or imported,
  binding no names (`visit_function_generics`); a type alias there is an
  error. Sema (`concrete_overrides`) and the visibility check follow the
  mark; sema's own program-wide rule applies only to an unlinked module
  (`Module::linked`). A file's own function of a name hides the imported
  generics of that name. Several functions of one name in one file are an
  overload set, which sema resolves (`passes::overloads`); linking reports
  only a generic beside another function of its name with the same
  parameters (`parameter_shape`), or a generic whose type parameters all
  name structs the file sees (an override of a generic the file's own
  functions hide). The
  visibility check applies the same override rule (`Decl::is_override`).
  A file's overloads of a name take one name whatever their visibility, so
  an import binds the whole set. Where an import or re-export would bind
  one name to functions of two files of one module, it binds a union
  instead (`Unions::merge`, a name like `f@geo/a#set1`); `link` returns
  them (`Linked::overload_unions`, carried to `Module::overload_unions`),
  and `name_overloads` records each as a set of every member; sema hides a mixed set's private members
  (`Module::private_functions`) from calls in other files
  (`Overloads::set`, by the call's location).
  Codegen gives every mangled declaration internal linkage
  (`set_private_linkage`): no other object can name it, and ELF linkers
  read the `@` of a global symbol as a version. After this step every reference is spelled the way the merged
  model resolves it, with no two files' private names alike. Runtime
  functions the compiler calls by name (`_pep_malloc`, `_pep_format*`) must
  therefore be exported. For each file it records a
  `FileScope`: `imported` (span start → declaration, used by visibility),
  `named` (used by the LSP), and `extensions` (`visible_extensions`: the
  prelude and forced-module files, the files it imports, and every file of
  a module it imports, whose exported extensions it may use; `load` records
  each file's `module_root` for this). Errors are `ModuleError { file, span, message,
  unresolved }`.
- **`scope_walk.rs`** is the traversal linking, visibility, and the
  deprecation check share: it
  tracks the names bound at each point (parameters, locals, generic
  parameters, the members of the struct being defined or extended), which
  hide top-level names. The `scope_walker!` macro writes it once as two
  traits, `ScopeWalkMut` (linking's `Rewriter`, which rewrites the AST) and
  `ScopeWalk` (visibility's `Checker`, which only reads it); each pass
  implements the hooks for references, member names, type names, visible
  members, and `extend` parameters. `enter_declaration`/`exit_declaration`
  bracket every declaration (and field, and function body) with its
  attributes. In `extend Box<T>`, a name equal to `Box`'s own parameter at
  that position is always the parameter, even when the program also declares
  a struct `T` (a runtime `extend ArrayIterator<T>` must not see a user's
  `struct T`).
- **`Program::check`** reports link errors first and then
  `visibility::check_visibility`. That check covers private symbols (a
  reference linking left unrenamed is matched against other files' mangled
  names by its demangled spelling), symbols that were not imported,
  extension methods of a private extension or of an exported one in a file
  the referencing file does not import (`FileScope::extensions`), a bare
  call in a method, or in a trait's default method, that such an invisible
  extension would capture (sema binds it to any extension's method;
  `visit_callee`). A member access is accepted when a trait the file
  can see declares the method (`Members::in_traits`: a call may go through
  a trait value), or when its receiver's type is unknown here (`this` in a
  trait default, or a chain starting from a parameter, local, or closure
  parameter whose type is a generic parameter in scope, or that is
  initialized from such a value: `visit_binding` marks the binding in
  `Scopes`, and `Scopes::is_marked_value` finds the innermost binding),
  and when the trait is declared by a file the checking file's imports
  bind, spelled or not (`FileScope::bound`),
  duplicate
  exports, concrete overrides declared in several files, and a type or
  variable declared twice in one file or exported by two prelude files.
  Extern redeclarations are exempt.

### 2.3 Parsing (`crates/pepper-parser`)

- **Entry points** (`parser.rs`): `parse_source(name, text) ->
  Result<ast::Module, String>` returns a rendered error.
  `parse_source_diag(text) -> Result<_, Diagnostic>` returns a structured
  one; the LSP uses it. `parse_file` reads from disk. After a successful
  parse, two checks run on the finished AST: `check_pointer_syntax`
  (`T*` is legal only in `extern` declarations; elsewhere the message
  suggests `__ptr<T>`) and `check_import_order` (imports come before every
  declaration). The grammar itself rejects a second destructor in one
  struct (`redefinition of the destructor of 'S'`); several constructors
  are an overload set (see `overloads`).
- **Grammar** (`parser/parsers.rs`): hand-written winnow combinators over
  `&mut &str`. The precedence ladder is documented at the top of the file
  (`assignment → ternary → … → postfix → atom`, with `cast` for `as`).
  `parse_module` is the top-level loop: imports (with `export * from` and
  `export [...] from`, which `reexport` recognizes and parses as imports),
  `export` re-exports, then `declaration`. Rules return `ErrMode::Backtrack` (via `bt`) to let an
  alternative try, or `ErrMode::Cut` (via `cut`/`cut_expecting`) to commit.
- **Nesting limit.** Every stage recurses over the tree, so the parser
  bounds its depth: past `MAX_NESTING` (256) levels it fails with `code is
  nested too deeply` at the token that crosses, as clang's
  `-fbracket-depth` does. `nested` counts a rule that recurses into a child
  (`expression`, `block`, `type_name`, `else if`, unary and
  right-associative operators); a loop that wraps the tree so far
  (`binary_left`, `postfix`, interpolated strings) adds one level per turn
  above the taller of its operands, which `measured` reports. The driver's
  and the LSP's `STACK_SIZE` (8 MB) is sized to fit the deepest tree; the
  CLI compiles on a thread of that size, since Windows' main thread has 1 MB.
- **Semicolons.** Simple statements and non-block declarations end with
  `;` (`docs/src/language/statements.md`); line breaks are whitespace
  everywhere (`ws`), so an expression runs on across lines for as long as a
  token extends it. `semicolon` takes the `;`, or `missing_semicolon` fails
  the parse with `expected ';'` at the end of the statement's span, with a
  fix inserting it (the language server's quick fix). So that the error
  lands after the statement rather than after trailing whitespace, rules
  that look ahead for a continuing token (postfix, binary, ternary, cast,
  type suffixes) do so on a copy of the input and restore the position when
  nothing continues. The one place a line break matters is
  `missing_decl_semicolon`: a C-style declaration (`Box b = f()`) that
  `decl_boundary` rejects is still reported as a declaration missing its
  `;` when a line break follows it, rather than reparsed as an expression.
- **Generic method calls.** In postfix position, `.name<types>(` is a call
  with type arguments only when `<` follows the name and `(` follows `>`
  with no whitespace; the method name becomes the string `"map<long>"`.
  Otherwise `a.b < c, d > (e)` stays two comparisons. Struct and trait
  methods accept their own type parameters (`map<U>(…)`) through a probe.
- **Comments.** The only comment form is `#` to end of line (`ws`). A doc
  comment is a run of consecutive `##` lines directly above a declaration.
  Attributes and `export`/`static` may sit between the comment and the
  declaration; a blank line may not. `doc.rs` parses these comments
  (`doc_comment_before`, `doc_comment_of`, `file_doc`) into `DocComment {
  description, tags }`, with the tags `@param`, `@typeParam`, `@returns`,
  `@panics`, `@example`, `@see`, and `@note`. `check_documented` enforces
  the runtime documentation standard.
- **Interpolated strings.** `interpolated_string` parses `$"a{x}b"` and
  lowers it on the spot to `"a" + _pep_interpolate(x) + "b"`
  (`INTERPOLATE_FUNCTION`; the call is located at the braces, the expression
  at itself), so linking, visibility, the LSP and sema see ordinary references
  and calls. `{{`/`}}` are literal braces. Where the expression in braces
  ends is decided first by `interpolation_end`, a byte scan that nests
  brackets and skips string, character and nested interpolated literals
  whole, and stops at a line break or `#` (so a hole is one line with no
  comment); `tools/syntax/lexer.pep` mirrors it to find the end of the
  string token. The hole is then parsed with `expression` and must end
  exactly at that `}`; `find_mutation` rejects an assignment, compound
  assignment, `++` or `--` anywhere in it but inside a closure's body, at
  the operator. A lone `}`, an empty
  hole, a `#`, or a missing `}` (with a note at the `{`) is an `error_at`,
  except after a line break inside the literal, where it reports
  `missing terminating '"' character` at the opening quote.
  The runtime's `_pep_interpolate<T>` resolves `to_string(value)` in
  `string.pep`, so neither a struct's own `to_string()` method (which
  `convert_member_refs` would bind a bare call to) nor a file's own
  `to_string` functions (which hide the runtime's set) capture it.
  A `:` after the hole's expression starts a format specification
  (`format_spec` → `FormatSpec`, `[[fill]align][+][0][width][.precision][type]`);
  `interpolation_call` lowers the value to `_pep_format(value, fill, align,
  width)` (`FORMAT_FUNCTION`, at the braces) when it only pads, to
  `_pep_format_float(value, precision, plus, fill, align, width, zero)`
  (`FORMAT_FLOAT_FUNCTION`, at the `.`) when it has a precision, or to
  `_pep_format_integer(value, base, upper, plus, fill, align, width, zero)`
  (`FORMAT_INTEGER_FUNCTION`, located at the specification's character that
  needs an integer) otherwise. `check_interpolations` reports a value with
  no text conversion at the braces, a non-integer given to
  `_pep_format_integer`, and a value other than a `float` or `double`
  given to `_pep_format_float`, at that character. The shortest text of a
  `float` or `double` (`_float_text`, in `runtime/float_text.pep`) comes
  from a Pepper port of the Ryu algorithm; text with a precision
  (`_pep_format_float`) comes from C's `snprintf` with `%.1075f`; on Windows
  the UCRT defines `snprintf` inline, so `_print_double` calls
  `__stdio_common_vsprintf` with a hand-built `va_list`. The text scanning (`{{`, `}}`,
  a lone `}`, the closing quote) is `interpolation_parts`, shared with
  `String.format`.
- **`String.format`** is an intrinsic: `primary_expression` tries
  `string_format` on `String . format (`. Its first argument must be a
  string literal, whose braces hold an argument index and an optional
  specification. An index out of range and an argument no brace names are
  `error_at`s. When the braces name every argument once, in order, the
  arguments replace the placeholders and it lowers like an interpolated
  string; otherwise it lowers to a `match` over a tuple of the arguments
  whose one arm binds `_pep_format_0`, `_pep_format_1`, ... (a lone
  argument is paired with `false`), so each is evaluated once, left to
  right. `print_format` gives `print` the same body (`format_arguments`)
  when a string literal and a `,` follow `print (`, lowering
  `print("{0}", x)` to `print(String.format("{0}", x))`; `print` itself is
  the runtime's `print(text: String)`; `print<T>(value)` prints
  `to_string(value)`, and `check_interpolations` reports a value with no
  text at the argument, as it does for an interpolated one.
- **Thread-local parser state** lives in `parsers.rs`: `SRC_LEN`, `MAX_POS`
  (the furthest offset any rule reached), `EXPECTATION` (what was expected
  at that furthest failure), `QUALIFIERS` (import qualifiers bound so far,
  so `q.Box<int>()` counts as a generic construction only when `q` is an
  import), `EXPRESSION_PROBE`, `WARNINGS` (deprecations), `ERROR` (a
  hard error that is not an unmet expectation).
  `track_source(len)` returns a `SourceGuard` that resets all of it for one
  parse. **Any code that calls a grammar rule directly (the unit tests do)
  must hold that guard.** Parsing is not reentrant on one thread.
- **Spans and errors.** `pos(input)` converts the remaining slice into a
  byte offset in the source. A rule that gives up calls `expected(input,
  "')'")` or `cut_expecting`, or `expected_with_note` to add a note such as
  "to match this '{'". A failure that is not an unmet expectation (an
  out-of-range integer literal) calls `error_at(span, message)`, which
  records it in `ERROR` and cuts. `parse_error` reports that error first if
  there is one, otherwise the expectation recorded at the furthest offset
  (`expected ')'`), or `unexpected 'x'` when none was recorded. `token_at`
  sizes the caret.
- **AST** (`ast.rs`): `Module { imports, exports, declarations }`. An
  `export * from source` or `export [...] from source` is an `Import` with
  `reexport` set (`symbols` is `None` for `*`): the loader resolves it like
  an import, but linking binds no name from it; `resolve_reexports` adds the
  source's exports (all of them, or the listed ones) to the file's, and
  reports a name published twice for different declarations at the
  `export ... from` that adds the second, with a note at the first.
  `Declaration` is `Variable | Function | Struct | Trait | Extend |
  TypeAlias`. The file also defines `Statement`, `Expression`, `TypeName {
  name, generic_types, span }`, `Attribute { body: Expression, span }`,
  `Import`, and `ExportAlias`. Every node carries a byte `Span`; named nodes
  also carry `name_span`. Externs are `FunctionDecl { external: true, … }`.
  Every node implements `Display`; `--emit-ast` prints through it.
  A `GenericParam` carries its `bounds` (`T: Shape & Named`, parsed by
  `constraints`) before its default. An `extend` target may restate its
  struct's constraints (`extend Box<T: Shape>`): `extend_target` tries a
  plain type first and keeps the restated ones in
  `ExtendDecl::target_bounds`, per argument. An extension with a `with`
  clause may end in `;` instead of a body (`extend X with Trait;`); it
  parses to an `ExtendDecl` with no methods, as `{}` does.
  `tools/syntax/parser.pep` mirrors it, and `pep-fmt` writes an empty
  body after a `with` clause as `;`.
  Function types `(P…) => R` are parsed directly into
  `__function<R, P…>`, and thread-safe ones `shared (P…) => R` into
  `__shared_function<R, P…>` (`shared_function_type_name`; `shared` is a
  contextual keyword, not in `RESERVED`). C function pointer types
  `extern (P…) => R` become `__extern_function<R, P…>`
  (`extern_function_type_name`), whose parameter and return types parse
  like an extern's (`void*`). `starts_extern_function_type` keeps
  `extern (` at the start of a declaration or struct member a variable or
  field rather than an extern function.
  A `?` suffix wraps the type as `Optional<T>` (after any `[]`). While an
  expression is probed for a type (`EXPRESSION_PROBE`), `?` counts only where
  `optional_suffix_in_probe` rules out a ternary: before `>`/`,`, or before a
  name that ends a declaration. `tools/syntax/parser.pep` mirrors the rule.

### 2.4 Building the sema model (`crates/pepper-sema/src/builder.rs`, `model.rs`)

- `build_file(&ast::Module, FileId)` sets the thread-local `FILE`, so
  `loc(span)` stamps every `Loc` with the file being built. `build` uses
  `FileId(0)`; unit tests call it.
- **Type uses.** `type_name_from` records every generic type written with
  arguments (`Gallery<Circle>`, the callee of `total<Circle>(...)`) in
  `Module::type_uses` (`TypeUse`: the type and each argument's `Loc`), so
  `passes::constraints` can report an unmet constraint at the argument.
  Each use points into `Module::use_contexts` (`UseContext`: the generic
  parameters in scope, the extended type inside `extend`, and the
  attributes of the enclosing declarations and blocks), which the uses of
  one declaration share; `Module::merge` offsets the indices. The builder
  keeps the current context in `CONTEXT` (`in_generic_scope` adds a
  declaration's parameters, `with_attributes` its attributes) and records
  it once per change. `check_constraints` skips a use whose context a
  `[Target(...)]` removes on this platform (`platform::keep`), as the
  platform filters remove its code. A concrete override records its own
  arguments as a use of the generic it overrides.
- **Literal arguments.** A model literal (`IntLiteral`, ...) carries no
  `Loc`, so the builder records where each literal argument of a call is
  written in `Module::literal_args` (call location, position, literal
  location), and `Module::argument_loc` gives an error about an argument
  its own location or that one (constraint errors at an inferred call,
  `check_bounds`). Each generic parameter keeps the `Loc`
  of its name, of each constraint (`Bound`), and of its default.
- `type_name_from` lowers `T[]` to `Array<T>`.
- `variable_def` gives a variable or field of type `Optional<T>` with no
  initializer the default `Optional<T>()`, so it starts as Empty, not null.
- Lowering highlights:
  - A `for (var x in e)` loop becomes a block holding a hidden
    `__for_iterator_N` local (initialized with `Expression::ForIterator(e)`)
    and a `while (it.next()) { var x = it.current(); { body } }`. The model
    has no `for` statement.
  - A `with (var x = scope) { body } else { other }` block becomes a block
    holding a hidden `__with_scope_N` local (the scope), `var x =
    __with_scope_N.enter()` (`__with_value_N` when unnamed), and `if
    (Expression::WithEntered(x)) { body } else { other }`. The model has no
    `with` statement; `lower_with_blocks` resolves the condition.
  - A tuple literal `(a, b)` becomes `FunctionCall { function: "__tuple" }`;
    `resolve_implicit_types` renames it to its type (`__tuple<int, String>`)
    once its arguments are typed. The tuple type `(A, B)` is
    `TypeName { name: "__tuple", sub_types }` (`type_name::TUPLE`,
    `is_tuple`), displayed as `(A, B)`; `t.0` is a `MemberRef` named `"0"`.
    `Tuple<A, B>` builds the same type. Labels (`(line: int, column: int)`)
    ride on `TypeName::labels`, which equality, hashing and `Display` ignore
    (`display()` shows them); `check_labels` rejects a partly labeled or
    duplicate set, and `lower_destructures` renames `p.line` to `p.0`
    (`tuple_index`). A labeled literal `(line: 3, column: 7)` is built as
    a call to `__tuple(line,column)` (`tuples::constructor_name`), so
    `type_of_expr` gives an inferred `var` the labeled type
    (`labeled_literal_type`) before the rename drops the labels; the builder's
    `check_literal_labels` rejects labels that differ from a declared type's.
  - An array literal `[a, b, c]` becomes the chain
    `_array_literal(a)._literal_append(b)._literal_append(c)`, and a map
    literal `[k: v, k2: v2]` becomes `_map_literal(k, v)._literal_insert(k2,
    v2)` (`array_literal`, `map_literal`; the helpers are in
    `runtime/array.pep` and `runtime/hash.pep`). With no other type, the
    generic start function infers the element types from the first entry.
    Every pass and codegen recurse down a chain, so a literal of more than
    `literals::CHUNK` (16) steps is a balanced tree of short chains over
    one collection instead: a `WithSubject` whose subject is the start
    call and whose body joins chains on the `Subject` with
    `_literal_then` (`crates/pepper-sema/src/literals.rs`), keeping the
    depth logarithmic whatever the length.
    A variable declared as `Array<T>`, `HashSet<T>` or `HashMap<K, V>`
    types its literal in the builder (`typed_expression`), which also lets
    `[]` and `[:]` build an empty collection. Any other typed slot
    (argument, return, assignment) is handled by
    `convert_to_traits::convert_array_literal` / `convert_map_literal`,
    which rebuild the literal from `Array<T>()` / `HashMap<K, V>()` and
    convert each element to the slot's element type. A `HashSet` slot takes
    an array through its `[Implicit]` constructor.
  - A range `a..b` or `a..>b` (parsed by `range`, between the shift and
    `is` levels, as a `Binary` with op `..` / `..>`) becomes
    `_range(a, b, inclusive)` (`runtime/range.pep`), which returns a
    `[Value]` `Range<T>`, so a `for` loop over it drives a value in place
    and allocates nothing. `ranges::check_ranges` reports non-integer
    bounds (section 3).
  - `var (a, b: T, _) = e;` becomes a hidden `__tuple_N` local initialized
    with `Expression::Destructure { value: e, count }` followed by
    `var a = __tuple_N.0; var b: T = __tuple_N.1;` in the enclosing block
    (`destructure`). `(a, p.x) = e;` becomes a block holding the hidden
    local and one assignment per place (`destructuring_assignment`), so the
    right side is evaluated first. `tuples::lower_destructures` checks the
    count and removes the `Destructure` node. A nested pattern
    (`DestructureBinding::nested`) gets its own hidden local bound from the
    outer one's element (`bind_elements`, `assign_elements`), and
    `for (var (k, v) in e)` (`For::pattern`) binds the loop's element to a
    hidden variable and destructures it at the top of the body.
  - An `enum` is an `ast::StructDecl` whose `enumeration` is set, so
    linking, visibility, exports and name mangling treat it as a struct.
    When no case carries values, `enum_def` builds an `EnumDef` in
    `module.enums` instead (cases with their values folded, checked for
    range and duplicates); such an enum is not a struct in the model. Each
    method becomes a free function named `E::m` (`enum_method`,
    `enums::method_name`); an instance method gets a first parameter
    `this: E`, passed by value like any integer. A property's getter
    becomes `E::__get_p` the same way (`PropertyOwner::Enum`), and
    `passes::properties` reads a bare `p` in those functions as `this.p`.
    Any enum's properties must be computed and have no `set`
    (`enum_property_error`).
    An operator or indexer method is the function `E::<` (with `<` and `>`
    spelled `{` and `}` in the name, as for value types), and
    `resolve_operators` and `unary_operators::dispatch` turn `a < b`, `-a`
    and `a[i]` on such an enum into calls of it
    (`enums::declares_operator`, `operator_call`).
  - An enum with a case that carries values (a reference enum) *is* a
    struct in the model (`reference_enum_def`): `StructDef::enum_cases`
    lists its cases (`EnumCaseDef::payload` names each case's values, and
    its `value` is the case's tag, its position). Its fields are `__tag`
    (`model::TAG_FIELD`) and every case's values as `const` fields named
    `Case.value` (`model::payload_field`; the dot keeps source code from
    naming them). One constructor takes every field (`this.field`
    parameters); each case is a static method named after it that calls it
    with the case's tag, its values, and `Default` for the other cases'
    fields, or, for a case that carries nothing, returns
    `Expression::StaticCase`, one immortal object per enum type and case.
    The built-in `name()` is a method that tests `__tag`. Declared methods
    stay ordinary methods, so generics, `[Shared]`, `extend` and trait
    conformance work as for any struct.
  - A `match (e) { arms }` becomes a block holding a hidden `__match_N`
    local (`e`) and an `if`/`else if` chain whose conditions are
    `Expression::MatchArm` (the subject, the arm's `CasePattern`s, and a
    `MatchSite` shared by the arms of one `match`); the `else` arm is the
    chain's last `else`. The model has no `match` statement;
    `enums::lower_matches` turns each test into `==` comparisons. Each name
    an arm's patterns bind (`match_bindings`) is a `const` local at the top
    of the arm whose value is `Expression::CaseValue` (the subject, and per
    pattern the case and the binding's position), which
    `resolve_implicit_types` types from the payload field and checks
    (`enums::case_value_type`), and `lower_matches` replaces with the field.
    A literal pattern (`1`, `"import"`) carries the test `subject ==
    literal` in `CasePattern::literal`, so the passes type and resolve it
    like any `==` (a `String`'s `==` included); its `case` is the literal as
    written, for duplicate checks.
  - A tuple pattern `(Circle, 0, r)` is a `CasePattern` with `elements`,
    each over its path from the subject (`__match_N.0`, built by
    `element_path`), so a literal element carries `__match_N.1 == 0`. A bare
    name in a tuple pattern (`r`) is kept as a case pattern with no
    bindings; only its element's type says whether it is a case or binds
    the element. `match_bindings` declares it as a local reading its path
    when every pattern of the arm has it once at the same element
    (`ElementName::declared`), and lists every bare name in
    `MatchArmTest::element_names`. A case's binding inside a tuple pattern
    is a `CaseValue` whose subject is the element's path.
  - A case's values are patterns too (`CasePattern::bindings`,
    `Value(Text(t))`): each is built over its value's path, a `CaseValue`
    with one choice (`case_path`), so a nested literal carries
    `CaseValue(...) == ""` and a nested case's bindings read `CaseValue`s
    of that path. A bare name there is a binding (`Leaf::Payload`) that is
    also listed in `element_names`, since the value's enum may have a case
    of that name (`Value(Empty)`); one repeated in a pattern must be a case.
  - `if (x is P(a))` and `while (x is P(a))` become the same `match`
    statement with one arm (`is_branch`, `is_loop`; the loop is `while
    (true)` whose `else` breaks), its `MatchSite` marked `partial` so it
    need not handle every case; `a` is a local of the block.
  - Every case pattern also carries its name read as a type
    (`ast::Pattern::ty`, `CasePattern::ty`, `CaseChoice::ty`: `Circle`,
    `shapes.Circle`, `Box<int>`, the parser taking type arguments right
    after the name), which module linking resolves like any type
    (`visit_case_type`; a qualifier that is not a module is an enum's).
    It is what the pattern tests for when the subject is a trait value
    (§4.2); an enum ignores it.
  - `x as? T` (`ast::Expression::Cast::optional`) becomes the `match`
    expression `match (x) { T(__cast_value) => Optional<T>.some(...), else
    => Optional<T>.none() }` (`builder::optional_cast`).
  - `e?` (`ast::Expression::Unary` with op `?`, postfix; the parser's
    `propagates` tells it from a ternary's `?` by the token after it, and
    probes for `expression :` when that token could start either) is
    lowered per statement by `builder/tries.rs` (`lift`, called from
    `block_in_context`): each `?` in the statement's head expression (an
    expression statement, a `var` initializer, a condition, a `return`
    value, a `for` iterable, a `with` scope, a `match` subject), in
    evaluation order, becomes a hidden `__try_N` local holding its operand
    and `if (__try_N._propagates()) { return
    R._from_residual(__try_N._residual()); }`, where `R` is the declared
    return type (`RETURN_TYPE`); the `?` reads `__try_N.value()`. The
    `_propagates`, `_residual` and `_from_residual` members of `Result`
    and `Optional` (runtime) make this work without types, and an error
    converts as `_from_residual`'s argument (`[Implicit]`). A non-
    declaration statement is wrapped in a block with its locals. `lift`
    reports a `?` after a call in the same statement (hoisting would run
    it first), one that might not run (right of `&&`/`||`, a `?:` branch,
    a `match` arm), and a function with no declared, non-`void` return
    type; a `while` whose condition uses `?` becomes `while (true) { if
    (c) { body } else { break; } }`. Any other `?` (a global, a default)
    is an error in `expression`. `passes::check_tries` checks the types.
  - A `match` expression becomes `Expression::WithSubject` (evaluate the
    subject once, then the body) around a `?:` chain of `MatchArm` tests
    over `Expression::Subject` (the value, by the site's id). A name an arm
    binds is replaced in the arm's value by its `CaseValue`
    (`bind_in_expression`; a closure there may not use one). Without an
    `else`, the chain ends in `Expression::NoMatch`. An `is` test anywhere
    else is a `WithSubject` around a single test, and may not bind.
  - A range pattern (`1..9`, `ast::Pattern::range`) carries the test
    `subject >= start && subject < end` (`<=` for `..>`) in
    `CasePattern::literal`, with `range` set. A bare pattern name that module
    linking resolved to a module-scope variable (`Rewriter::
    visit_pattern_name`, the scope walk's `visit_pattern_values` hook, sets
    `ast::Pattern::constant` to its linked name) carries `subject == NAME`.
    `CasePattern::values` holds the integers a literal or range covers when
    its bounds are literals; `lower_matches` collects them per `match`
    (`Coverage::intervals`, `covers`) to report a covered pattern and to
    accept an integer `match` whose patterns cover its type without `else`.
  - An arm's guard (`Circle(r) if r > 10`) makes its test
    `MatchArm(...) && guard` (`arm_test`), the `MatchArmTest` marked
    `guarded`; the guard reads the arm's names as `CaseValue`s, as a `match`
    expression's value does (`bind_in_expression`). `enums::arm_test` finds
    the test in either form, and `lower_matches` lowers the guard's
    `CaseValue`s and leaves a guarded arm's patterns out of the coverage.
  - A character literal (`ast::Literal::Char`) becomes
    `Cast { IntLiteral(byte), byte }` (`CastKind::Synthesized`), so it is
    typed `byte` where nothing else gives it a type and widens like any
    `byte` value.
  - `x as T` becomes `Cast` with `CastKind::Static`, located at the `as`
    keyword (`ast::Expression::Cast::keyword_span`), and the intrinsic
    `unsafe_cast<T>(x)` becomes `Cast` with `CastKind::Unsafe`, located at
    the name (`builder::unsafe_cast`, which reports a missing or extra type
    argument or value). Every cast sema inserts is `Synthesized`. What each
    kind may convert is `casts::check` (`casts.rs`): `as` is a
    `static_cast` (numbers, `bool`, enum to integer, pointer to and from
    `__ptr<void>`, struct to a trait it conforms to, identity), and
    `unsafe_cast` a `reinterpret_cast` (pointer to pointer or integer and
    back, a number to another of the same width), never of a refcounted
    value.
  - A closure literal becomes `Expression::ClosureLiteral` (parameters,
    return type and body, types `auto` where not written); an expression
    body is lowered to `{ return expr; }`. `lift_closures` removes it
    (§2.6).
  - `t.m(args)` becomes `MethodCall`, and a named callee becomes
    `FunctionCall { function }`. A type literal callee (`Box<int>(…)`)
    becomes a constructor call named `"Box<int>"`. Any other callee becomes
    `Invoke`.
  - `[Implicit]` is accepted only on a constructor callable with one
    argument whose parameter is neither the struct nor a bare type
    parameter (`check_implicit_constructor`); anywhere else,
    `reject_implicit` reports it at the attribute.
  - Member names that start with `__` are rejected, except `__acquire` and
    `__release`, which source code may call. Codegen makes either a no-op
    on plain data (`__is_pod`), and on a buffer slot (`_data[i].__release()`)
    steps the count of the reference the slot holds without writing the
    slot: Array's destructor releases its elements that way.
  - An operator the builder has no mapping for is reported (`unsupported
    binary operator '…'`), and a comparison overload (`==`, `<`, …) whose
    declared return type is not `bool` is rejected, as is a `!` or `!!`
    (the truth test) not returning `bool` and a `!`, `~` or `!!` with
    parameters.
  - Structs get `constructors` (at least one: an empty one when none is
    declared; several are named `Point$1`, `Point$2`, … and at most one may
    be `[Implicit]`), `destructor` (`__dtor`), and empty `acquire` and
    `release` shells. Top-level `var`s go to `module.globals`. Externs
    go to `module.externs`.
- **Model** (`model.rs`): `Module { structs, traits, extensions, functions,
  externs, globals, type_aliases, struct_specs, func_specs, trait_types,
  imports, sources: SourceMap }`. Nodes are owned enum trees with no `Rc`/`RefCell`;
  passes mutate `&mut Module` in place. The main node types are `StructDef`
  (a method with type parameters of its own, `map<U>`, sits in
  `generic_methods` rather than `method_members` until specialized),
  `FunctionDef` (methods have `parent: Some(struct)`), `ExternDef` (with
  `link()` and `link_name()`), `VariableDef { kind: Variable|Field|Param, loc, type_loc
  }`, `Expression` (includes intrinsic nodes: `SizeOf`, `Default`, `IsPod`,
  `RefCount`, `Address`, `Atomic*`, `FunctionRef`, `Invoke`,
  `ForIterator`, `WithEntered`, `Destructure`, `Move`, `ToTrait`, `ClosureLiteral`, `MakeClosure`,
  `NamedArgument`, `DefaultArgument`,
  `MethodAddress`, `CallPointer`), and `Statement`. Each node that names something has a
  `Loc`; `Expression::loc()` returns it (`Loc::NONE` for literals and
  synthesized nodes).
- **Types**: `type_name::TypeName { name, sub_types, flags }`, with
  constants `AUTO` (`__auto`), `VOID`, and `FUNCTION` (`__function`),
  primitive alias sets, `widest`, and `replace_map` (generic substitution).
  `symbols::SymbolTable` maps names to indices. When a name is declared
  twice, the later entry overwrites the earlier one. `static_type::of`
  gives a best-effort static type for operator resolution and print
  conversion.
- `Module::merge` concatenates vectors into one namespace. Modules exist
  only up to `modules::link`, which has already made every private name
  unique by mangling it. The driver's `compiler::merge`
  then orders `module.globals` by `Program::initialization_order`: the
  prelude first (in reverse load order, so the runtime precedes the forced
  imports built on it), then every file after the files it imports. Globals
  are initialized in that order, so an initializer may use an imported
  file's globals, and the runtime's (`_pep_live_allocs_slot`, which every
  allocation counts into) exist before any other initializer runs.

### 2.5 Platform filters (`passes/platform.rs`)

`apply_platform_filters` evaluates every `[Target(<bool expr>)]` against the
**target**: the host, or the platform `--target <triple>` names. The grammar is `OS(Windows|Mac|MacOS|Linux)`, `Arch(x64|aarch64)`,
`!`, `&&`/`and`, and `||`/`or`. The pass drops top-level declarations,
struct/trait/extension members, and attributed blocks whose predicate is
false. Every predicate is validated before anything is dropped, so a typo in
code that another platform would compile is still reported. Attributes other
than `Target` are ignored here. `keep(&attrs)` is the reusable evaluator;
the loader, linking, and visibility all call it.
The target is a `platform::Target` (`os`, `arch`, and the LLVM triple, or
`None` for the host's own): `Target::parse` reads a `--target` triple (the
supported ones are `SUPPORTED_TRIPLES`), and `with_target(target, f)` runs
`f` compiling for it (thread-local; `current_target`, `target_os` and
`target_arch` read it). The driver's `run` sets it from `--target`, and its
`parallel` passes it to each codegen thread. Codegen's `target::triple`
reads it, so the machine, data layout, struct sizes, debug-info format
(CodeView for Windows) and the context-switch assembly all follow the
target. `with_simulated_host(os, arch, f)` is `with_target` with the
host's triple kept, for tests that compile another platform's code (and
JIT-run its portable parts) on this machine.

### 2.6 Struct bodies (`struct_body.rs`)

`struct_body::apply` first runs `equatable::derive`, which gives each
`[Equatable]` struct (or reference enum) a synthesized `==(other: T): bool`
comparing the tuples of its fields (`(this.a, this.b) == (other.a,
other.b)`, a lone field paired with `true`) and `__hash(): u64` returning
`hash` of the same tuple, leaving out a field marked `[Equatable(exclude =
true)]` or `[Equatable(include = false)]` (`equatable::included`); codegen's
`__address<T>` and `tuple_hash` call `T.__hash` for a non-null `T`, and
`tuple_hash` leaves out an object element whose `==` is declared but whose
hash would be its address (an `Array`), since equal elements would hash
apart (codegen's `hash_overrides` tells a program's `hash<T>` override from
the generic's specialization). It reports `[Equatable]` on a value type or
a payload-free enum, an `[Equatable]` struct's own `==`, arguments on the
struct's `[Equatable]`, a field's `[Equatable]` outside an `[Equatable]`
struct, and a contradicting `include`/`exclude`.
Then it runs `passes::closures::lift_closures`, which
turns every closure literal into a synthesized struct
`__closure_N@<namespace>`, numbered within its file (see §4.3) and generic
over the enclosing code's type parameters, and a `MakeClosure` creation
expression, so the new structs get their bodies below like any other.
A closure in a trait's default method is generic over the trait's
parameters and `closures::TRAIT_SELF` (`__This`), the type of its `__this`;
`apply_extensions` (and `value_types` for numbers and enums) maps
`__This` to the conforming type along with `this` when it copies the
method, so each conformer specializes its own closure.
Closures that passes make later (`function_references`, `shared_functions`'
adapters) are named after the declaration whose code makes them instead
(`closures::owned_closure_name`: `__closure_<escaped owner>_<k>@<namespace>`,
the owner's name escaped so no two owners share a name), so a
specialization makes the same closures whenever it is created.
`passes::strip_bodies` runs next, dropping the bodies of units the build
cache reuses (§4.3). The
struct's fields are `__invoke` and `__destroy` (defaults `MethodAddress`
of `__call` and `__dtor`), so its head matches the function type struct,
then one field per captured local, then `__this` when the body uses `this`
or a bare member of the enclosing struct (rewritten to `__this.member`; a
bare method name, a value, to `__this.m`, or `S.m` when static). The
body becomes the `__call` method; bare captured names become fields through
`convert_member_refs`. Each capture field is located at the closure's first
use of the value, with the captured local's declaration as its `type_loc`
(`shared_functions` reports a capture that is not thread-safe there). The
lift reports an assignment to a captured local
anywhere in the enclosing function, and a method storing a closure that
captures `this` in a field of `this`. Types the literal left out are filled
by `closures::sync_closures`, which `resolve_implicit_types` runs in its
fixpoint loop: parameter and return types from the function type of the slot
the closure flows into, capture field types from the constructor arguments,
and each `MakeClosure`'s type from its `__call`. `closures::check_closures`
reports what is still `auto` before `check_function_types`. Methods, constructors and
generic function specializations used as values become closure structs too,
late, in `function_references` (see the pass table).

Then `struct_body::apply` runs `resolve_type_aliases`, so no alias
survives into later stages. Then, for each struct:

- `apply_synthesized` inserts the two head fields: `u32 __refcount`
  (default 0) and `u32 __weakcount` (default 1: weak references plus one
  held by all strong references together, as in a C++ control block). It
  fills the `__acquire` body (null check, `++__refcount`, `trace_*` calls)
  and the `__release` body (null check, `--`, and at 0 a call to `__dtor`,
  then `--__weakcount` and `_pep_free(this)` if that reached 0). Each step
  is an `Expression::CountStep` node, which evaluates to the new count and
  is atomic when `StructDef::atomic_counts()` holds: the struct is
  `[Shared]` or a `shared` function type. Everything else, plain function
  types included, uses a plain load/add/store.
- `finish` builds each constructor. A hidden `size` local is patched with the
  real ABI size in codegen by `patched_ctors`. The constructor calls `this =
  _pep_malloc(size)`, initializes each field (explicit default or zero),
  assigns `this.field` constructor parameters (renamed `__init_<field>`),
  runs the user body, and ends with `return this`. The destructor does not
  free the object; `__release` does. The pass appends `__release`, `__acquire`, and `__dtor`
  to `method_members`.

---

### 2.7 Properties (`builder.rs` `property_members`, `passes/properties.rs`)

A property (`var name: T { get; set; } = init;`, `ast::PropertyDecl`) is
lowered to ordinary members; nothing after sema knows about it.

- **Parser.** `member_property` (traits, extensions) and
  `property_declaration` (a struct field followed by `{`) build the
  `PropertyDecl`. Each `ast::Accessor` carries the method it compiles to as
  a `FunctionDecl` (`__get_P(): T`, `__set_P(value: T)`; `body` is `None`
  for `get;` / `set;`), so tools that walk methods, such as the language
  server, see accessor bodies (`PropertyDecl::accessors`).
- **Builder.** `property_members` turns each property into the getter
  method `__get_P`, the setter `__set_P` when there is a `set`, and, when
  the storage is implied (a default accessor, or `field` in a body), the
  storage field: named `P` when `get` is default, else `__field_P`. `field`
  in a body becomes `this.<storage>` (`replace_field`); default bodies read
  and write the storage. A trait property becomes trait methods; an
  extension property must be computed. Each property is recorded in
  `Module::properties` (`PropertyDef`: owner, accessor kinds, storage,
  `[Shared]`), which the rest of sema reads. `scope_walk::walk_property`
  binds `field` and `value` for the visibility checks.
- **Reads and writes** are rewritten by `properties::lower`, which
  `resolve_implicit_types` calls first on every expression it walks
  (pre-order), once the receiver's type is known: `x.P` becomes
  `x.__get_P()`, `x.P = v` becomes `x.__set_P(v)`, and `x.P op= v` / `x.P++`
  become a read-modify-write whose receiver, when it is not a plain name,
  is evaluated once through a `WithSubject` (its id comes from the access's
  `Loc`, so builds are deterministic). A default accessor becomes direct
  storage access; inside its own accessors `this.P` is the storage
  (`Site::is_own_storage`). Assigning a get-only property is allowed only in
  the owning struct's constructors and methods (not its extensions:
  `Properties::extension_methods`), and assigning a `[Shared]` struct's
  property only in its constructors. `P()` on a property that is not a
  function type is an error. Assignments sema synthesizes (`Loc::NONE`:
  field initializers, `__copy`) are left alone, except a constructor's
  `this.P` parameter.
- **Typing.** `type_of_expr` gives `x.P` (and a bare `P` in a method) the
  getter's return type; `convert_member_refs` treats a property without a
  same-named field as a member, so a bare name becomes `this.P`.
- **Traits.** `apply_extensions` meets a trait property with the struct's
  property, or with a plain field through a synthesized accessor
  (`field_accessor`), and reports `'S' does not implement property 'P'`.

### 2.8 Static blocks and reflection (`builder/static_items.rs`, `passes/static_blocks.rs`)

`static (captures) { ... }` (`ast::StaticBlock`, parsed by `static_block`)
is compile-time work; docs/src/language/reflection.md describes the
language side.

- **Parser.** Inside a static block, each `for` loop's variable is added to
  `QUALIFIERS` until the block ends, so `field.Type` and
  `parse<field.Type>(s)` parse as types the way `module.Type` does
  (`STATIC_DEPTH`). The scope walk binds `reflect` like a local
  (`Scope::Static`), and linking leaves a type qualified by a value in
  scope alone (`Scopes::in_static_block`).
- **Builder.** `static_items::static_block` sorts the statements by name:
  one that uses a capture or a runtime local of the block (or calls `get`,
  `set` or `call`) is emitted, the rest is compile-time. The result is a
  `model::StaticBlock` of `StaticItem`s: `For`, `While`, `If`, `Var` and `Evaluate`
  keep their compile-time expressions as the AST; `Emit` holds a model
  statement, built normally except that a sub-expression of only
  compile-time names becomes `Expression::StaticValue` and `x.get(v)` /
  `x.set(v, y)` / `x.call(...)` become `Expression::StaticMember`
  (`placeholder`, through the `COMPILE_TIME` thread-local that
  `expression` checks first); `EmitIf` is a runtime `if` whose branches
  hold items. `break`/`continue` in a compile-time loop is a `Jump`; one
  under a runtime `if`, or outside any compile-time loop, is an error
  (`Names::loops`, `Names::in_runtime_if`).
- **Module scope.** A module-scope `static { ... }` is
  `ast::Declaration::Static`. The parser also declares each `const` at the
  top of the block as a module-scope variable (`static_constants`, with
  the block's attributes and `export`) whose initializer is its own name,
  so linking, visibility and mangling see an ordinary constant.
  `static_items::module_static_block` builds the block with
  `Names::module_scope` (nothing may be emitted; `case.get()` is
  evaluated) into `Module::static_blocks`, and
  `static_blocks::expand_module_blocks`, first in `transform_pass` after
  `check_attributes`, runs each and gives each constant the value it
  computed, matched by the location of its name.
- **Generic code.** The walks in `passes/mod.rs` reach the emitted
  statements, so the early passes lower them with the rest of a generic
  base; passes with their own statement walks skip `Statement::Static`.
  Specialization records its type arguments in the block
  (`StaticBlock::substitute`, from `replace_stmt_types` and
  `substitute_statement`) and substitutes them in the emitted statements.
- **Expansion.** `static_blocks::expand` replaces each block in concrete
  code (non-generic functions, methods of structs that are not generic
  bases) with a block of what it emits: it evaluates the compile-time items
  (`Expander::evaluate`, a small interpreter over `Value`s: numbers, `bool`,
  strings, enum cases, members, functions, lists and attribute values),
  unrolls each `For` into one block per element and each `While` into one
  per iteration (at most `MAX_ITERATIONS`; a `Jump` sets
  `Expander::jump`, which skips the rest of the pass), and fills in the emitted
  statements: `x.Type` types first (`replace_body_types`), then each
  placeholder (`fill`). `transform_pass` calls it at the start (concrete
  code, `lowered = false`), after the first specialization, inside the
  specialization loop after `specialize_functions` and after
  `specialize_methods` (an expansion forces `resolve_implicit_types` and
  another round, since emitted calls ask for new specializations), and
  after the loop's `apply_extensions`. `remove_from_generic_code` then
  empties the blocks left in generic bases. Errors carry a note per `for`
  pass, one naming the specialization, and one per `Module::spec_requests`
  entry back to the non-generic code that asked for it
  (`Expander::with_requests`), so an error inside `json`'s converters ends
  at the user's `json.encode(job)`.
- **Cases.** A case of a reference or `[Value]` enum lists its `values` as
  members whose `field` is the payload field (`Circle.radius`), so `get`
  reads it; `case.matches(v)` emits a `__tag` comparison (a comparison with
  the value for an integer enum), and `case.get(args)` the case's static
  method `Shape.Circle(args)`. A compile-time `var` in a static block is a
  parser qualifier like a `for` variable, so `first.Type` parses, and
  `gather_generics::contains_param` leaves any `x.Type` to the
  specialization that expands the block.
- **Reflection.** `reflect.properties<T>()` lists the public fields and the
  properties of a struct, in source order; `fields<T>()` every field but
  synthesized ones, only in `T`'s file. A member's attributes are its
  field's, or its getter's for a property.
- **Attributes.** A struct marked `[Attribute]` is an attribute.
  `check_attributes` (first in `transform_pass`) reports an attribute that
  is neither one of `BUILT_IN_ATTRIBUTES` nor an `[Attribute]` struct
  (`unknown attribute 'X'`, at the name), an argument that is not a
  constant of its field's type, and an attribute field of another type.
  `attribute_value` binds the arguments to the struct's `slots`: the
  constructor's parameters (`this.f`, or assigned to a field in its body)
  or, without one, the fields in order. The built-in attributes are also
  declared as `[Attribute]` structs in `runtime/attributes.pep`
  (`is_built_in`: a struct named like one); `check_attributes` leaves their
  arguments to the compiler's own checks, and `built_in_value` reads a
  value through the same binding, except `Target`, which holds its
  condition as written.

## 3. Sema transform passes (`crates/pepper-sema/src/passes/`)

`transform_pass(&mut Module) -> Result<(), Diagnostic>` runs the steps below
in order (`passes/mod.rs`). Each call is wrapped in `step!`, which stops at the first pass
that reported an error. The order came from the C++ implementation, and
several passes run more than once on purpose.

| # | Step | What it does |
| --- | --- | --- |
| 0′ | `static_blocks::check_attributes`, `static_blocks::expand_module_blocks`, `static_blocks::expand` (`static_blocks.rs`) | Reports unknown attributes and bad attribute arguments, runs the module-scope `static` blocks to set their constants, then expands the `static` blocks of concrete code (§2.8). |
| 0 | `enums::resolve_enum_cases` (`enums.rs`) | First, `value_types::lower_extensions` (`value_types.rs`) turns each extension of a value type (a number type, `char`, `bool`, or an enum whose cases carry no values; `value_types::key` files them under the enum's name or the number's canonical spelling, `i32` for `int`) into free functions `X::m` like an enum's own methods, copies the trait defaults its conformances need, reports a missing member, an enum extension without a trait, and an operator in a number extension that does not take exactly one non-number operand (`number_operator_error`), and leaves the extension in `module.extensions` with no methods (and `resolved` set) as the declaration of its conformances, which `Conformance` reads for `T: Tr`; `value_types::resolve_static_calls` turns `int.zero()` into `i32::zero()`, and `rewrite_static_calls` does the same for `T.zero()` in a specialization. `convert_to_traits` reports a value type flowing into a trait slot (`'int' cannot be converted to trait 'Tr'`). Installs the reference enums (structs with `enum_cases`) in their own registry (`enums::reference_cases`), rewrites `Doc.Line` to the call `Doc.Line()`, and reports a case that carries values used without them (`case 'Text' of 'Doc' takes 1 value`) and a direct `Doc(...)`. Installs `module.enums` in the thread-local enum registry (`enums::install`; `struct_body::apply` and codegen install it too), which `TypeName::is_integral`, `arithmetic` and codegen's `scalar_type` consult (`enums::stored_as`), so an enum type keeps its name through sema but is stored as its representation. Rewrites `Enum.Case` to `Cast { IntLiteral(value), Enum }`, reports `no case named 'X' in 'E'` and a user-written `n as Enum`, and gives enum locals and globals without an initializer the default case (value 0, else the first). Adds each enum's built-in `E::name` and `static E::from_value` (after platform selection, so they see only the surviving cases), records every `E::m` in the method registry (`enums::method_is_static`, installed by codegen too), rewrites `this` and bare sibling calls inside enum methods, turns a static call `E.m(...)` into `E::m(...)`, and reports `extend E`. A call on an enum value, `c.m(...)`, needs `c`'s type, so `resolve_implicit_types` rewrites it to `E::m(c, ...)` (`enums::call_on_value`), and a binary operator with a number on the left and a struct (or other non-number) on the right whose extension declares it, `2.0 * v`, to `f64::*(2.0, v)` (`number_operator`, which `type_of_expr` also uses to type it); `check_deprecated_members` finds deprecated enum methods by the function name, and codegen's argument-count errors leave out the `this` argument. |
| 0a | `entry_point::lower_main_arguments` (`entry_point.rs`) | The C `main` the compiler emits takes no `argc`/`argv`, so a root file's `main(args: String[])` is renamed `main@#args` (`MAIN_WITH_ARGUMENTS`; `#` cannot start a namespace, and messages demangle it to `main`) and a `main()` is synthesized at its location that returns `main@#args(_pep_arguments())` (a `void` one is called, then 0 returned). `_pep_arguments` is `arguments()` under a name a program's own `arguments` cannot shadow. Reports any other parameter list on `main` and `main` declared twice. `is_entry_point` gives both forms the inferred `int` return. |
| 1 | `check_bindings` | Reports a local declared twice in one scope (`redefinition of 'x'`, with a note at the previous one) and an assignment, compound assignment, or `++`/`--` to a `const` local, global, or (outside the constructor) field (`cannot assign to const variable 'x'`). |
| 1a | `named_arguments::check_attributes`, `check_link_attributes`, `named_arguments::bind_calls` (`named_arguments.rs`) | Reports a wrong `[Alias]`, `[Rename]`, or `[Link(...)]` (including the removed `[LinkName]`). Then binds named arguments: the builder keeps each `name = value` argument as an `Expression::NamedArgument` after the positional ones (reporting a positional one after a named one), and binding rewrites a call's arguments into parameter order, a skipped parameter becoming `Expression::DefaultArgument` (codegen passes the parameter's default there, as `missing_args` does for trailing ones; overload ranking treats it as `ArgKind::Default`). This step binds the calls a name decides (free functions, constructors, an own method called bare); `resolve_implicit_types` binds `value.method(...)` once the receiver is typed (`bind_method_call`, enum methods included), and reports a call through a function value; `check_unbound` (after the last `resolve_implicit_types`) reports what is left. An overloaded callee binds when every member the names fit binds the same positions. When binding reorders the named arguments, a receiver that is a call and each argument that is not a literal or a closure is evaluated first into a `WithSubject` around the call, in the order written. Former names (`[Rename]`) warn with a fix. |
| 2 | `synthesize_function_types` (`function_types.rs`) | Each tuple type `__tuple<A, B>` becomes a synthesized struct (`tuples::tuple_struct`) with const fields `"0"`, `"1"`, … and a constructor taking the elements, so every pass that types fields, constructor arguments and member reads handles tuples unchanged; codegen emits no object for it (§4.3). Each distinct `__function<R, P…>` and `__shared_function<R, P…>` becomes a synthesized refcounted struct (`__refcount`, `__weakcount`, `__invoke`, `__destroy`; its destructor calls `__destroy` through `CallPointer` when set, which releases a closure's captures), and each `__weak<T>` with a concrete struct `T` a weak view struct (`weak_types.rs`). A `shared` one counts atomically; a plain one counts plainly and leaves a count at or above `STATIC_REFCOUNT` alone, so the static object of a named function, which several threads may hold as plain values, is only ever read. |
| 3 | `resolve_literals` | Folds unary minus into numeric literals. |
| 4 | `overloads::name_overloads` | Renames concrete overrides of generic functions to their spelled type (`hash<int>`) (`gather_generics::concrete_overrides`). Then groups each file's free functions by name: a name with several is an overload set, whose members become `name$1`, `name$2`, ... (after any namespace: `f@ns$1`; `namespace::demangle` strips both), recorded in `module.overload_sets`. First, where prelude files (a forced import, then the runtime) export the same name, a later file's member with an earlier member's parameters is dropped and the rest form one set (`replace_prelude_members`), so a forced import replaces exactly the overloads it declares. Reports a redefinition, a difference only in return type, and an overloaded `extern`, and attaches an override of an overloaded generic to the member with its arity (`f$2<Point>`). Each struct's same-name methods (operators included) are renamed the same way (`add$1`, `+$2`), recorded in `module.method_overload_sets`; specializations copy the renamed members, and a static and an instance method may not share a name. A trait's same-name methods are renamed the same way, each its own vtable slot (`overloads::group_methods` serves structs, traits, and `apply_extensions`). `StructTable` and `convert_member_refs` also answer to a member's set name, so `a + b` and a bare `add(x)` in a method still find the set. Constructors arrive named by the builder (`Point$1`, `Point$2`; a specialization keeps the ordinal, `Box<int>$2`); this pass reports two with the same parameters (`constructor of 'P' cannot be redeclared`), and `Overloads::build` makes each concrete struct's constructors the set named by its type (`Point`, `Box<int>`), so `Point(args)` resolves like a function call. `Module::constructor_of` maps a call's name to its struct and constructor. |
| 5 | `convert_string_literals` | `"abc"` → `String(raw, size, length)` constructor call, in every body: functions, globals, struct and extension methods, and trait default bodies (copied into structs later, by `apply_extensions`). The raw literal stays a `char*` global. |
| 6 | `gather_generics` | Records generic uses as `struct_specs` and `func_specs`. |
| 7 | `resolve_implicit_types` | Infers `auto` locals and symbol types by scoped lookup (`p[i]` through a `__ptr<T>` or `T*` is a `T`; a `void` pointer is left to codegen), and a function's return type from its `return` statements when it declares none (`void` when it returns no value, `int` for `main`). Runs `closures::sync_closures` in the same fixpoint loop (§2.6). A call to a generic function or method without type arguments (`larger(3, 9)`, `b.map(f)`) gets them from its arguments' types through `type_arguments::GenericSignature` (bind each parameter type against an argument type, `unify`; a trait parameter `Iterator<U>` binds through the trait the argument's struct declares, from the `record_conformances` table each inferring pass sets; a bound naming another parameter, `I: Iterator<T>`, binds `T` from `I`'s binding the same way, `bind_through_bounds`), and is renamed to the specialization (`larger<int>`, `map<long>`); a call writing only the leading type arguments (`count_all<int>(it)`) gets the rest the same way (`GenericSignature::complete`), and `specialize_functions` / `specialize_methods` skip such a name until it is complete; a closure argument receives the partly bound parameter type as its expected type, so inference runs across fixpoint rounds. A call naming an overload set is resolved first, once its arguments' types are known (`overloads::Overloads::select`): each viable member ranks each argument (exact, promotion, conversion, `[Implicit]` constructor), the best member must be better in one argument and worse in none than every other (a non-generic wins a tie with a generic; a generic member whose inferred or written type arguments do not meet its constraints is not viable: `candidate function not viable: 'Circle' does not conform to 'Shape'`), and the call is renamed to it (a specialization for a generic member); a call whose argument types mention a type parameter waits for the specialization. A method call (`m.add(x)`, `Money.of(x)`) on a struct with a method set of that name resolves the same way against `Overloads::select_method`, by the receiver's type; `resolve_operators` resolves the method calls it creates for operators with `overloads::resolve_method_call`, typed by `static_type`. Each resolution goes to `module.call_targets` for the LSP (a method as `Struct.member`). The same loop runs `overloads::bind_function_values`, which rewrites a set (or an overloaded method, `p.add`) used as a value to the member whose function type matches its slot (closures' `for_each_site`), and `type_arguments::bind_generic_function_values`, which rewrites a generic function named as a value without type arguments (`larger` in an `(int, int) => int` slot) to a `FunctionRef` of the specialization the slot's type binds (`GenericSignature::infer_from_function_type`: parameters against the slot's parameters, the return type against its return type); `gather_generics` requests a `FunctionRef`'s specialization like a call's. Generic code is left to its specializations. |
| 7a | `check_tries::check_tries` (`check_tries.rs`) | For each `?` the builder lowered (its hidden `__try_N` local, now typed): reports an operand that is neither a `Result` nor an `Optional` (`'?' requires a Result or an Optional, not 'int'`), a function that does not return the same kind (`'?' requires the enclosing function to return a Result`, with a note at the function), and a `Result` error type that does not convert (`cannot convert error type 'X' to 'Y'`: neither the same type nor an `[Implicit]` constructor of struct `Y` from `X`), before the lowered calls fail with errors that name them. Concrete code only; it runs again after the specialization loop for generic code. |
| 8 | `resolve_resolvables(false)` | Resolves struct, function, and method references against the symbol table. |
| 9 | `apply_extensions(false)` | Clones `extend` methods onto their target and records traits. For `extend S with T`, checks that `S` has every method `T` declares and copies in `T`'s default methods (those with a body) that `S` lacks, reporting `'S' does not implement 'm', required by trait 'T'` otherwise (`'m(int)'` for an overloaded member). A trait member is implemented by the method of its set name with its parameter types, and a copied default takes the set name. Each implementation must have the declared signature, except that a struct result may stand for a declared trait result. Then `overloads::group_methods` regroups the struct's methods, so extension methods and defaults join its overload sets: named members keep their names, new ones take the next ordinal, and a repeated parameter list is `redefinition of 'm'`. Then `check_parameter_names` warns where an implementing method names a parameter differently from its trait (a fix renames it and its uses in the body), since a named argument through the trait uses the trait's names. |
| 9b | `interpolation::check_interpolations` (`interpolation.rs`) | Checks each interpolated value (a call `_pep_interpolate<X>`, see §2.3) converts: `X` is an integer type or `bool` (the runtime's `to_string` overloads), a struct or trait with a `to_string()` method, an enum declaring one (`E::to_string`), or has a concrete override `to_string<X>` (one not at the generic's location). Otherwise reports `cannot interpolate a value of type 'X'` at the `{name}`, with a note at a struct, before the runtime's `to_string<T>` body would fail on it. Runs again after the specialization loop for the calls in specializations of generic code. |
| 9c | `constraints::check_constraints` (`constraints.rs`) | Generic constraints (`T: Shape`), before anything is specialized. Reports a constraint that names no trait (`'Point' is not a trait; a constraint must name a trait`, with a note at the struct, or `unknown type name`), a constraint written on something other than an extension's own parameter (`only the parameters of 'Box' can restate its constraints`), a default that does not meet its parameter's constraints, and each `TypeUse` (and concrete override) whose argument does not conform: `'Circle' does not conform to trait 'Shape', required by 'T' in 'Gallery'` at the argument, a note at the constraint, and either `declare it with 'extend Circle with Shape'` at the struct (with a `Fix` inserting it after the struct, `copies::struct_end`) or, for a type parameter in scope, `add a constraint to 'T'` (with a `Fix` inserting `: Shape`). Conformance (`Conformance`, owned so `Overloads` can keep it) is nominal and computed from `module.extensions`: `extend Box<T> with Tr` (the struct's own parameters) covers every `Box<X>`, with `T` substituted into `Tr`; `extend Box<int>` only itself; a trait type conforms to itself when every member is dispatchable; a type parameter in scope (the enclosing declarations', and inside `extend Box<T>` those of `Box`) by its own constraints; nothing else conforms. Then runs `check_specializations`. |
| 9c′ | constrained extensions | `extend Box<T: Named>` restates or adds constraints (`ExtensionDef::restated`); `constraints::added_constraints` gives those the struct lacks. They are conditions: `Conformance` counts an extension's `with` traits only where its arguments meet them (`declaring`, and `condition_note` for the note naming the unmet one, used by this pass and `convert_to_traits`), `specialize_structs` calls `constraints::withhold` to drop the extension's methods, the trait defaults its conformances copied in (`FunctionDef::owner`), and its traits from a specialization whose arguments miss one (recorded in `Module::withheld`), `check_bounds` gives the extension's methods the combined constraints, and the builder puts them in the type-use scope. After the specialization loop, `constraints::check_withheld` reports a call of a withheld member (`no member named 'label' in 'Box<Circle>'`, with notes naming the condition and the constraint) before codegen would report it without them. |
| 9c″ | built-in `Shared` constraint | `T: Shared` (`constraints::SHARED`, `is_shared_bound`) is not a trait: `Conformance::unshared_part` decides it by `check_shared_types`' rule (numbers, `void`, enums, `[Shared]` structs and generic bases, `shared` and C function types, pointers, weak references and tuples of such types, a parameter constrained `Shared`), and the error says `does not conform to 'Shared'` with `check_shared_types::not_shared_note`. `scope_walk` does not link a `Shared` constraint, and a trait named `Shared` is an error, so the name is never a program's own declaration. It gives no members (`check_bounds`). The runtime's `Atomic`, `spawn`, `run_blocking`, `Lazy` and `_TaskResult` declare it; `check_shared_structs`' per-specialization error remains for `[Shared]` generics without it (a program's own). |
| 9d | `check_bounds::check_bounds` (`check_bounds.rs`) | Definition checking of constrained generic code: walks every generic base (free functions, struct methods and constructors, generic methods, trait default methods, lifted closures) that has a constrained parameter in scope, typing expressions with its own scopes of parameters and locals, the enclosing struct's fields, bare sibling calls, and `static_type`. A value of a constrained parameter's type may call instance methods and operators its constraints' traits declare (their signatures with the trait's parameters and `this` substituted), static members through the parameter (`T.unit()`), flow into a slot of a constraint's trait type, and be compared with `==`, `!=`, `===`, `!==`; anything else is reported: `no member named 'm' in 'T'` with a note at the constraint (`'T' is constrained by 'Shape', which has no member 'm'`), a field, `T()`, `'m' is declared by both 'A' and 'B'`, argument counts and clearly wrong argument types, `invalid operands to binary expression`, and a conversion to another type (`'T' converts only to its constraint 'Shape'`). An unconstrained parameter is left to the specializations. Produces no code. |
| 10–11 | `specialize_structs`, `specialize_functions` | Clones generic bases into `Name<args>` instances with substituted types. They clone `Module::templates`, the bases frozen once the constraints are checked (`Templates::freeze`), never a base later passes have changed, so an instance is the same whichever round of the fixpoint loop creates it (see `design-notes/sema/canonical-specialization.md`); it gets the passes the bases got after that point from the passes that run after the loop. `gather_generics` records who first asked for each specialization and where (`Module::spec_requests`), and both passes refuse to make one whose chain of requests is longer than `MAX_SPECIALIZATION_DEPTH` (64), reporting it at the request with the chain's places as notes (`specialization_too_deep`), so a generic that asks for a larger instance of itself is an error rather than a loop that stops after so many rounds. `apply_extensions` applies each extension once per struct (not once overall), so `extend Box<int>` reaches a `Box<int>` the loop creates, and runs again after the loop; `convert_intrinsics` converts the type of the node a call such as `__default<__ptr<void>>()` lowers to. A `void` argument erases what it types (`erase_void`): fields and parameters of that type, stores of them, a `return` of one, and an argument that is one (a removed field of `this` included), and a call stored into a removed field stays as a statement (`this._value = body()` becomes `body();` in `Task<void>`); for an enum, a case's `void` value goes with its field: the case, the patterns and bindings of it in the enum's own methods, and `enums::reference_cases` (which erases the same values for any `Result<void>`) no longer count it, so `Result<void>.Ok` carries nothing and `ok()` takes no argument. A generic struct's `generic_methods` are cloned with the struct's parameters substituted and keep their own. A static call through a type parameter (`T.unit()`, a `MethodCall` on `SymbolRef T`) is rewritten to the type argument (`Square.unit()`, or a type literal for `Box<int>`), and so is a constructor call `T(...)` (a `FunctionCall` named `T`), which `resolve_resolvables` lets stand in the generic base. |
| 11a | `ranges::check_ranges` (`ranges.rs`) | The builder lowers `a..b` / `a..>b` to `_range(a, b, inclusive)` (runtime/range.pep), its `T` inferred from the bounds. Once calls are specialized (`_range<String>`), reports a non-integer `T` at the range operator (`range bounds must be integers, not 'String'`), before the runtime's `Range<T>` body fails inside. Runs again in the specialization loop. |
| 11b | `specialize_methods` (`generic_methods.rs`) | For each method call named `m<args>` on a struct with a generic method `m` (or the method as a value, a `MemberRef` `b.map<long>`: the parser keeps `<args>` in the member name when `(` or the end of the expression follows the `>`; `bind_generic_method_values`, in `resolve_implicit_types`' loop, names one written without them from its slot's function type), first checks `m`'s constraints (`Conformance::check_call`, at the argument that fixed the type), then clones `m` into `method_members` as `m<args>` with its own parameters substituted. `apply_extensions` routes generic extension methods and generic trait default methods (`Iterator<T>.map<U>`) to `generic_methods`; `traits::is_dispatchable` excludes them, since a vtable has one slot per method. |
| 12 | `synthesize_function_types` | For function types that specialization exposed. |
| 13 | `convert_intrinsics` | Rewrites `__ptr<T>` to `T*`, including the `T` of intrinsic nodes that specialization substituted. Turns `__is_pod`, `__default`, `__refcount`, `__address`, `__atomic_load/store/cmpxchg/fetch_*` calls into intrinsic nodes, and `__function_pointer(f)` into `Expression::FunctionPointer` (a free function, or a static method of the enclosing struct, whose owner type specialization substitutes). |
| 14–15 | `resolve_resolvables`, `apply_extensions(true)` | Resolves what remains and applies specialized extensions. |
| 16 | `convert_member_refs` | In methods, a bare field becomes `this.field`, a bare call becomes a method call (unless no method of that name takes its argument count and a free function of that name exists, as `resolve_implicit_types::Scopes::calls_method` decides too: a `copy()` method's `copy(x)` is the free function), and a bare method name becomes `this.m` (`S.m` for a static method), which `reference_functions` makes a function value (parameters and locals are exempt). In a trait's default method copied into a struct (`FunctionDef::trait_default`, set by `apply_extensions`), only the trait's methods count and no fields. |
| 17–18 | `resolve_implicit_types`, `resolve_operators` | `x[i]` → `__index_get`/`__index_set` or POD `ArrayIndex`. A struct receiver typed only later (in the specialization loop) leaves `x[i]` an index until the final `resolve_operators`; `resolve_implicit_types` types it meanwhile as the `x.__index_get(i)` call it becomes, so an overloaded indexer picks its member. An overloaded binary operator becomes a method call. Without its own `!=`, `a != b` on a type with `==` becomes `!(a == b)`. `===` and `!==` are never overloaded; codegen compares their raw values (`BinaryOp::identity_as_equality`), addresses for references. `unary_operators::dispatch` turns `-x`, `~x` and `!x` on a struct declaring the operator into a zero-argument method call named after it, and a struct value in a boolean context (`if`/`while` condition, ternary condition, operand of `&&`/`\|\|` that the struct does not overload, operand of `!`) into `x.!!()`; `!x` without its own `!` is `!(x.!!())`, and `!!x` is `x.!!()`. `StructInfo::unary_operators` records which of `-`, `~`, `!`, `!!` a struct or trait declares as parameterless instance methods. |
| loop ≤16× | `gather_generics`, `constraints::check_specializations`, `specialize_structs`, `specialize_functions`, `check_ranges`, `static_blocks::expand`, `specialize_methods`, `static_blocks::expand`, `copies::synthesize_copies` | `check_specializations` checks the gathered `struct_specs` and `func_specs` of constrained generics before they are cloned; one that fails came from an inferred call (a written use was checked at 9c) and is reported at the call argument whose parameter type mentions the failing type parameter (`spec_site`). Repeats until the counts of structs, functions and methods stop growing and no copy was synthesized (specializing exposes new uses). When the module has generic methods or overload sets, each round first runs `resolve_implicit_types` so calls on newly specialized structs get their type arguments. Bounded because a self-nesting generic never converges. `synthesize_copies` (`copies.rs`) serves `copy(value)`: it checks every copy the program asks for (a `copy<T>` call outside a `Copyable` method) through everything it reaches and reports `cannot copy 'X' because it contains 'Y', ...` at the request (a `Channel<T>` is found through `check_shared_types::use_site`), with a note per field hop and, for a struct with a destructor or a raw pointer field, a `Copyable<T>` skeleton note and `Fix` that inserts it after the struct. It then lowers each concrete `__copy<T>(value, copies)` (the body of `_Copies.copy<T>`) to `value` for a thread-safe `T`, to `copies._copy_object<T>(value)` for a struct, whose `__copy_object<T>(value)` it lowers to the struct's synthesized `value.__copy()` (a `__` method source cannot call), or to a panicking `_pep_copy_failed<T>` for a type nothing asks to copy. A trait type `T` lowers to `copies._copy_trait<T>(value)`, which calls `value._pep_copy_trait(copies)` through the vtable: each round, `add_trait_copies` gives every trait that member (`_pep_copy_trait(copies: _Copies): Tr<T>`) and every concrete struct that declares a trait the method `return copies.copy<S>(this);`, or a `_pep_copy_failed<S>` panic naming the blocker when `S` cannot be copied (or is `[Isolated]`). Every trait gets the slot whether or not the program copies it, so a vtable depends only on declarations and a cached unit's vtable stays valid when another unit starts copying (`a_cached_vtable_serves_a_new_copy_of_its_trait`). It gives each such struct `__copy()`: `this.copy()` when the struct implements `Copyable<T>` (declares it and has `copy()`), `this.copy(_pep_copies())` for the deprecated `copy(copies: Copies)`, else a field-by-field copy that reads the running copy's context once (`var copies = _pep_copies();`, a thread-local read), allocates with `Expression::Allocate` (no constructor), registers the copy before copying fields (cycles), copies thread-safe fields as they are and others with `copies.copy<F>`, and defers weak fields to a `_pep_fix_weak` method run by `_Copies._finish`. The context is implicit (#463): the outermost `copy<T>` on a thread installs its `_Copies` behind a thread-local key and a nested `copy(x)` in a `Copyable` method continues it; the runtime's own `copy<T>` body is not a request (its caller's call is). `apply_extensions::conform` accepts the deprecated `copy(Copies)` as `Copyable<T>`'s `copy()`; the warning comes from the `[Deprecated]` alias `Copies`. `[NotCopyable("why")]` on a struct forbids copying it; its reason is read like `reflect.attribute<NotCopyable>()` (`static_blocks::attribute_string`). Reflection cannot replace this synthesis (no access to another file's private fields, no constructor-free allocation, no run-time types for trait values): see `design-notes/sema/copy-and-reflection.md`. |
| then | `static_blocks::remove_from_generic_code`, `check_interpolations`, `convert_intrinsics`, `resolve_resolvables`, `apply_extensions(true)`, `static_blocks::expand`, `convert_member_refs`, `synthesize_function_types` | Covers what the loop created. |
| final | `reference_functions` (`function_references.rs`) | A method, constructor or generic function specialization used as a value (`p.norm`, `Point.norm`, `Point`, `Box<int>`, `identity<int>`) becomes a `MakeClosure` of a new complete closure struct whose `__call` forwards to it; a bound method's receiver is its one capture (`__receiver`). Needs final types to tell a method from a field, so it runs here, before `release_field_refs` releases the receiver. A local inferred from the expression (`var f = Point;`) is retyped to the function type. Reports storing `this.m` in a field of `this`. |
| final | `release_field_refs` | Inserts `__release` calls for struct-typed fields, in reverse declaration order, at the end of the destructor. The object itself is freed by `__release` once `__weakcount` reaches 0, not by the destructor. |
| final | `resolve_implicit_types`, `resolve_operators`, `unary_operators::check_conditions`, `resolve_resolvables(true)`, `synthesize_function_types` | `check_conditions` reports a struct or trait value still in a boolean context, one whose type declares no `!!` (`'S' cannot be used as a condition: declare '!!(): bool' on it, or compare with '__null'`, with a note at the declaration): a struct is never null-tested implicitly. Pointers, numbers, `bool` and function values (synthesized `__…` structs) keep codegen's `as_bool`. `resolve_resolvables(true)` is the step that reports `use of undeclared identifier`, `call to undeclared function`, and similar. |
| final | `check_type_arguments` (`type_arguments.rs`) | Reports a generic call (a function, or a struct's generic method by the receiver's `static_type`) whose type arguments the arguments did not determine (`cannot infer the type arguments of 'make' from its arguments; write them: make<T>(...)`, with a note at the declaration), or whose written type arguments stop short of one with no default (`cannot infer the type argument 'U' of 'make' ...`), a generic function named as a value that no function type specialized (`cannot infer the type arguments of 'larger' used as a value; ...`), and likewise a generic method (`cannot infer the type arguments of method 'map' of 'Box<int>' used as a value; ...`). |
| final | `overloads::check_overloads` | Reports an overload call no member fits (`no matching function for call to 'f'`, a note per candidate saying why; for constructors `no matching constructor for initialization of 'P'`), one two members fit equally well (`call to 'f' is ambiguous`, `call to constructor of 'P' is ambiguous`), one whose argument type stayed unknown, and a set used as a value where no expected type picks a member (`cannot infer the type of 'g' from overloaded function 'f'`, `address of overloaded function 'f' does not match required type`). Method calls and method values (`overloaded method 'S.get'`) are checked the same way, by the receiver's `static_type` (a trait type's sets are its members). A method set's candidates at a call are the body methods plus the methods of extensions visible in the call's file (`Module::extension_scopes`, from each file's `FileScope::extensions`). Skips extensions' own copies of their methods (only the struct's copies are resolved) and generic bases, whose calls resolve in their specializations. |
| final | `check_closures` | Reports a closure parameter, return or capture type that nothing inferred (`cannot infer the type of parameter 'x'`). |
| final | `shared_functions`, `synthesize_function_types` | Reports a C function pointer type (`__extern_function<R, P…>`, `TypeName::is_extern_function_type`; not a refcounted type, it lowers to `ptr`) declared with a type C cannot pass (a struct). Where a value flows into a C function pointer slot, replaces a `FunctionRef`, or a `MakeClosure` whose closure captures nothing (its `__call` copied into a free function `<closure>_c_function`), with `Cast(FunctionPointer, slot type)`; reports a closure or bound method that captures (`sync_closures` inferred its parameter types from the slot's plain signature, `extern_as_function`). Where a function value flows into a `shared` function-typed slot, retypes a `FunctionRef` or `MakeClosure` to the `shared` type, reporting a capture that `check_shared_types::unsafe_part_in` finds not thread-safe (at its first use in the closure, with a note at the captured local). Where a `shared` value flows into a plain slot of the same signature, wraps it in a new plain adapter closure (`__inner`, `__call` forwarding to it; its destructor releases `__inner`), so plain counts never touch a shared object. Any other plain value in a `shared` slot is left for `check_function_types`. |
| final | `value_structs::check` (`value_structs.rs`) | Installs the program's `[Value]` structs (`value_structs::install`, which `struct_body::apply` and codegen also call; `is_value` answers by base name) and reports what a value cannot do: `===`/`!==` and `__null` on one, `__weak<V>`, `__refcount`, a value struct in an `extern` signature, and one that contains itself (`check_recursion`, an explicit-stack walk over value-typed fields, a note per step). Infers each value struct's mutating methods (`mutating_methods`, a fixpoint: a method that assigns a field of `this`, or of a value field of it, or calls a mutating method on either) and, walking each body with its scopes (`Uses`, an explicit statement stack), reports a change that would land in a copy or a `const`: a field of a call's result assigned or a mutating method called on one (`Root::Temporary`, with a note at the call that made the copy), the same on a `const` variable, and a change to a closure's `__this`. `__address` stays allowed: on a value it hashes the fields (§4.5). The builder rejects `destruct` and `[Shared]` on a value struct (`check_value_attributes`). A `for` over a `const` value iterator (no `iterate()`) is reported as a mutating `next` call. |
| final | `convert_to_traits` | Implicit constructor conversions and trait conversions, at every place a value flows into a typed slot (initializer, assignment, argument, return). A value flowing into a struct whose constructor is `[Implicit]` (`StructDef::implicit_from`) becomes a `FunctionCall` of that constructor when its type matches the parameter exactly or by promotion (integer widening, a fitting integer literal, `f32` → `f64`, struct → declared trait); the call's own argument never converts through another constructor. A string literal (the `String(raw, size, length)` call `convert_string_literals` made, matched by the literal's loc) flowing into a `char`, `u8`, or `void` pointer slot is unwrapped back to its raw literal, in each arm of a ternary too. It wraps every struct value that flows into a trait-typed slot in `ToTrait`, checking that the struct declares the trait; rejects calls through a trait value to members it cannot dispatch, and struct results of trait methods that do not conform to the declared trait type. Records the trait types in use in `module.trait_types`. See §4.2. |
| final | `check_function_types` | Rejects a value whose type does not match the typed slot it flows into (variable initializer, assignment, argument, return): a function value of a different signature, a plain function value where a `shared` one is expected (`cannot initialize variable 'f' of type 'shared () => void' with a value of type '() => void'`), a number or a raw pointer where a struct is expected or the reverse (a struct may pass as `void*`, but `void*` is never a struct; a string literal in a pointer slot is its `char*` global), or a different struct (`cannot initialize variable 'x' of type 'int' with a value of type 'String'`). A C function pointer slot takes only the same C function pointer type (`extern_flows_into`, with a hint saying what converts), and a C function pointer converts only to `void*`. An extern call's arguments are checked here only for its function-typed parameters; codegen checks the rest. It also rejects a call returning `void` used as a value (stored, passed, returned, an operand, or a condition). Errors are located `Diagnostic`s. |
| final | `check_casts` (`check_casts.rs`) | Reports each `as` or `unsafe_cast` whose conversion `casts::check` rejects, at the `as` or the `unsafe_cast` name (`cannot cast '__ptr<int>' to 'ulong' with 'as'; use 'unsafe_cast<ulong>(...)' to reinterpret`). Runs after `convert_to_traits`, which turns an `s as Trait` into the `ToTrait` a trait-typed slot gets. A cast whose operand `static_type::of` cannot type, or whose type still names a parameter of the generic base (`check_function_types::base_params`), is left to codegen: `codegen_cast` asks `casts::check` again with the operand's exact type, and lowers an `unsafe_cast` between a float and an integer as a `bitcast` and an integer to a pointer as `inttoptr`. |
| final | `check_shared_types` | Checks every `[Shared]` struct: each field must be `const` (on the declaration) and of a thread-safe type (on each concrete struct, so `Atomic<String>` is reported at the code that names it). A `shared` function type is thread-safe; a plain one is not. Then checks every module-scope variable, exported or not, by the same two rules, as if it were a field of a `[Shared]` struct (any function can hand a global to any thread). |
| final | `tuples::lower_destructures` | Checks each destructuring's element count against its value's tuple type (`cannot destructure '(int, int)' into 3 values: it has 2 elements`, `cannot destructure 'String': it is not a tuple`) and replaces the `Destructure` node with its value. Reports an element that does not exist (`no member named '2' in '(int, int)'`) and an assignment to an element (`tuple elements are immutable`). |
| final | `check_confinement` | The confinement rule for `with` blocks over `[Isolated]` guards (`MutexGuard`, `ThreadLocalGuard`), recognized by the builder's lowering (a hidden `__with_scope_N` local of an `[Isolated]` type). A flow-insensitive union-find over **regions** (`Fresh`, `Outer`: parameters, `this` and locals declared before the block, `Locked(n)`: the binding) links a call's operands as its callee's **link summary** says and an assignment's target with its value; linking `Outer` with `Locked`, or two locks, is an error at the value that would cross ("'line' cannot move into the value locked by 'names'", "'list[0]' is part of the value locked by 'names' and cannot outlive the lock"), as are returning a locked value from the block and a closure capturing one. Link summaries (for each function: which operand slots, `this` first, its body links together and into its result, and whether the result is tainted) come from the same walk over the callee, as a least fixed point over a worklist seeded with the functions that have `with` blocks or `[Move]` calls (callees start at the bottom, callers re-run when one changes). A result is **fresh** when no operand is in its class and it is not tainted (`returns_fresh`, shown by the LSP's hover). A tuple result has one result slot per element, and a tuple value one region per element (a literal keeps its elements apart, `t.0` reads one, a destructuring's hidden local takes the value's shape), so each element of `var (a, b) = f()` gets its own bit; passing a whole tuple as an operand links all its elements. `copy(x)` is fresh; an `extern` call links nothing and marks a returned pointer untracked, as is a pointer read from a thread-safe object's field (raw memory a `[Shared]` struct holds), so a reference read through either is tainted; `move(x)` (the runtime's `move<T>`, whose `[MoveSource]` argument `lower_moved_arguments` wraps in `Expression::Move`) out of raw memory, `move(p[i])`, is fresh (runtime files only, checked against the discovered runtime directory); a moved local is fresh when it is the only holder (`Region::holders`) of an unshared, untainted region, and a `[Move]` parameter starts in a fresh region of its own; a call through a function value, and a closure capture, taint; a trait call joins every implementation's summary; unknown callees link everything. Raw pointers carry the region they were read from (`this._data` is `this`'s), and raw reads are typed by their pointee. Also checks: an `[Isolated]` value anywhere but a `with` header (or inside the guard's own struct and functions returning one) or in a field; `[Move]` arguments must be disconnected (thread-safe, or a call whose result class holds only disconnected operands and is not tainted), with a note at the `return` that keeps a callee from being fresh; `ThreadLocal<T>.get()` for a non-thread-safe `T`; `Mutex` of a number; an argument to a `[Locked]` parameter must be a closure literal, whose lifted `__call` is walked with its parameters as a `Locked` region of their own (`check_locked_closure`; such closures are summary roots, so their callees are summarized); `move` of anything but a sole-holder local or a runtime raw slot, and use after move (`Moves`, a flow-sensitive dataflow over each function that moves: a loop reruns its body unless every path leaves it). A syntactic prefilter skips functions that mention no trigger name. For the build cache (`Module::record_summaries`), it summarizes every function and hands out, by location, the summaries that reach no trait call (`summaries_to_record`); a build that skips a cached unit's bodies seeds those (`recorded_summaries`, §4.3). |
| final | `lower_with_blocks` | Picks each `with` condition by `enter()`'s final type: a null test for a struct or pointer, no branch otherwise (a `void` result becomes an expression statement). Reports the `with` errors (no `enter()`, binding a `void` result, `else` on a non-nullable result, assigning to the binding). |
| final | `enums::lower_matches` | Turns each `MatchArm` test into `__match_N == Case || ...` (for a reference enum, `__match_N.__tag == tag || ...`, after a `_pep_assert` that the subject is not null; a literal pattern's own `==`) and each binding's `CaseValue` into its payload field (several patterns binding one name: an `if` chain on the tag that assigns it, or a `?:` on the tag inside a `match` expression). It checks each `match` (`MatchSite`): the subject must be an enum, an integer, `char`, `bool` or `String` (literal patterns), a pattern's qualifier must name it, each case or literal is handled once, and every case must be handled unless there is an `else` (a guarded arm's patterns handle nothing, but one after an unguarded arm for its case is still handled twice) (`match on 'E' does not handle ...`, at the keyword, with a note per missing case); a literal `match` needs an `else` unless it is a `bool` handling both values; an `is` test (`partial`) is not checked. An `else` after every case is a warning in `module.warnings`. For a `match` expression it sets the `WithSubject`'s null-check message, drops the chain's `NoMatch` (the last arm's value stands alone), and reports arms whose values do not mix (`check_arm_types`). `check_function_types` keeps enums apart from integers and from each other (`Kind::Enum`). Over a trait value (`trait_arm`, §4.2) each pattern's `ty` must name a struct that declares the trait or another trait (`trait_target`), each type is handled once, a binding becomes `FromTrait`, and a `match` expression needs an `else`. A case pattern's values (`enum_test`) are tested on their payload fields after the tag (`element_test` over `case_field`, typed by `case_payload_types`), and the `CaseValue`s the builder left in nested tests are lowered to fields (`lower_case_values`, `typed_path`). A pattern nested in a case's values handles part of the case: it is a row of the match's `spaces`, and `check_exhaustive` counts a case no pattern handles whole as handled when those rows cover it, else names the value they miss. A `match` over a tuple (`lower_tuple_arm`) tests each element on its path (`element_test`, `&&` over the elements), resolves each bare element name to a case or a binding and drops the local of one that is a case (reporting one that binds where it may not), and checks coverage with the usefulness algorithm (`useful` over `Space`s, a case with the spaces of its values, with each enum's and `bool`'s cases and their value types as `Domains`): a pattern the earlier ones cover is an error, a value no arm covers is reported with an example (`does not handle '(Line, _)'`), and an `else` after full coverage is a warning. |
| final | `check_deprecated_members` | Warnings only: each use of a field or method marked `[Deprecated]` (through `x.m`, `S.m()`, or a bare member in a method), found by the receiver's `static_type::of`, goes to `module.warnings`. Skips uses inside deprecated functions, methods, and structs (a closure lifted out of one inherits its `[Deprecated]`, see `closures::inherit_deprecation`), uses whose source text is not the member's name (calls sema synthesized), and repeated locations (specializations). |
| final | `check_hash_keys` | Errors: for each key type of a `_HashTable<K, V>` specialization (every `HashMap` and `HashSet` key), a struct that declares `==(other: K)` but no `hash<K>` override (a function of that name with no type parameters; the generic's own specialization keeps them), and a reference struct with the override but no `==`. Each is reported (`errors::report`) at the declaration to complete. Structs declared in the runtime (`passes::RuntimeDirectory`, shared with `check_confinement`) are skipped, and so are `[Equatable]` structs, whose hash is derived; overriding `hash<T>` for one is an error at the override. |
| last | `static_strings` | String literals as shared immortal objects (#410), after `checked::restore_bodies`, over every body. An operand slot of type `String` (a parameter, or `this` of a `String` method) is **free** when the body only reads its fields that hold no reference, passes it to free parameters of resolved calls (not an `extern`, a function value or a trait method; not `[Move]`), calls methods on it whose `this` is free, or compares it with null: the greatest fixed point over the call graph. Constructors, `__` methods, functions used as values (`FunctionRef`, `FunctionPointer`) and methods that implement a trait's are never free, since only a direct call can make the caller's copy (below). A literal (`String(raw, size, length)` matched by its loc) that is an argument to a free parameter, or the receiver of a method whose `this` is free, becomes `Expression::StaticString`, one immortal object that codegen's `static_string` emits; every other literal (a variable's, field's or element's value, a result, a capture) is still a new `String`, so `var s = "a"; s.append("b");` behaves as before. Free parameters are listed in `Module::caller_copies`, by codegen name: their caller makes the copy (§5). A caller depends on its callees' bodies here, so each recorded link summary carries its function's facts after `|s=` (`f` free, `k` kept, `-` not a `String`, per slot): they reach the file's interface hash (`summary_without_position` keeps them), and a body the cache skipped reads them back (a slot with none is kept). |

Shared helpers in `passes/mod.rs` are `walk_block`, `walk_statement`,
`walk_expression`, `walk_function`, `walk_global`, and
`replace_expression`; `visit_block`, `visit_statement`, `visit_expression`
and `visit_function` are the same walks for a pass that only reads (never
clone a body or an expression to walk it with `walk_*`); `children` and
`children_mut` iterate a node's direct sub-expressions without allocating,
for a walk that decides per node whether to descend. **When you add a model
`Expression` variant, add it to `walk_expression`, `visit_expression`,
`children` and `children_mut`.**

`resolve_implicit_types` runs eight times and loops inside each run, so its
helpers skip work that cannot change anything: `sync_closures` learns
nothing once no closure struct has an `auto` capture, `__call` parameter or
return type, and otherwise walks only the functions that create such a
closure (a creation's expected type comes from its own function); its table
holds generic bases' fields too, so a closure created in a generic closure's
method can type what it captures from `this`, and learning stops once it
has; `bind_function_values` types expressions only when some name could
still bind to an overload, and `bind_generic_function_values` only when an
untyped name of a generic function appears; `infer_type_arguments` and
`resolve_method_overload` check that a name is a generic function, a generic
method or a method overload set before typing the receiver or the
arguments, and `overload_call` checks that a call names a set
(`Overloads::call_set_name`) before parsing its type arguments; and
`traits::used_trait_types` prints and parses only types that spell a
trait's name as a whole word (`ArrayIterator` does not mention
`Iterator`). `specialize_methods` builds its `StructTable` only once a call
names a generic method. Compare a type to a spelling with
`TypeName::is_spelled`, not `to_string() ==`, in a loop.

`resolve_type_aliases` also expands aliases in constraints, in the arguments
of each `TypeUse` (not its head, whose own constraints are checked), and in
restated extension constraints, and keeps the aliases that constrain a
parameter in `Module::constrained_aliases` so their uses can be checked.

`struct_body::apply`'s `resolve_type_aliases` reports a recursive alias
at the alias's name (`type alias 'A' refers to itself`, with a note at each
alias the cycle passes through). Because `check_function_types` is a
transform step, the driver and the LSP both run it.

Error reporting inside passes goes through `crate::errors::report(diag)`, a
thread-local that keeps only the **first** diagnostic of a run. Other
per-run state is thread-local too: `apply_extensions::reset_applied` runs at
the start of each `transform_pass`, and `platform::SIMULATED_HOST` is set
only inside `with_simulated_host`. The counters that number synthesized
names (the builder's `FOR_LOOPS`, `WITH_BLOCKS`, `TUPLES` and `MATCHES`,
closure structs' `CLOSURES`) restart at the start of every `load_program`
(`pepper_sema::reset_program_counters`). This lets tests compile
concurrently on separate threads. `resolve_operators` numbers its
`_idx_tmp_N` temporaries within each function, after any that function
already declares, so they do not depend on the order functions are
resolved in. The builder's counters also restart for
each file (`build_file`), so the hidden locals of one file, and the bitcode
of its build cache unit, do not depend on which files the program built
before it.

**Output is deterministic**: the same program compiles to the same IR and
object bytes on any thread, after any other programs, in any process. So
never let a `HashMap`/`HashSet` iteration order decide what is emitted or in
what order (`gather_generics` collects specializations in `BTreeSet`s),
and never number synthesized names with a process-wide or never-reset
counter. `determinism_tests.rs` compiles every docs example twice, in
opposite orders across threads, and compares the IR. The planned build
cache, which reuses per-file objects, depends on this.

`resolve_implicit_types` builds its program-wide lookup tables (`Tables`:
struct fields and methods, function return types, function values,
generic signatures, globals) once per call, as hash maps, and every
function's `Scopes` borrows them; the struct being resolved overrides its
own entries through `Scopes::own`. Before this it cloned and linearly
scanned vectors of every table per function, which was most of sema's
time. `TypeName::is_auto` tests for `auto` without building a string.

---

## 4. Codegen (`crates/pepper-codegen`)

`CodeGenerator::new(&Context, name)` sets the host data layout.
`generate(&mut Module) -> Result<(), Diagnostic>` runs `generate_module`.

1. **Instantiation.** Every concrete struct is registered as an opaque type
   first (a field may name a struct declared later). Then:
   `instantiate_struct` (LLVM struct body, in which a struct-typed field is
   a `ptr` slot, so a struct may hold its own type) → ABI sizes via
   `TargetData::get_abi_size` → `instantiate_methods` → `instantiate_ctor`
   → `instantiate_extern` → `instantiate_function`. Generic bases (`st.name
   == st.ty.name` with generic `ty`, or `is_generic_func`) are skipped;
   sema has already cloned the concrete specializations.
2. **`emit_globals`.** Module-scope variables become LLVM globals. A
   constant initializer is set directly. Other initializers go into
   `__pep_global_init`, registered in `llvm.global_ctors`, in the order of
   `module.globals` (see `Program::initialization_order`).
3. **Codegen.** `codegen_struct` (patched ctor plus methods, mangled as
   `Struct.method` with an implicit `this` parameter 0; static methods have
   no `this`) and `codegen_function`. Then `module.verify()`. IR it
   rejects is a type check sema missed; `verification_error` locates the
   error at the first function the verifier rejects, and names it.

How the language lowers:

- **Structs are references.** A struct-typed local, field, parameter, or
  return value is an LLVM pointer to a heap object allocated with
  `_pep_malloc` (zeroed). `sizeof(StructType)` is
  pointer-sized, because a struct occupies a pointer-sized slot. The
  object's ABI size is used only inside the constructor and by
  `Expression::Allocate` (the synthesized copies' allocation: zeroed, both
  head counts 1, an owned rvalue like a constructor result).
- **Stores are type-checked** (`address.rs`). LLVM accepts a store of any
  type through an opaque pointer, so a value wider than its slot silently
  overwrites the next field or the next heap object. `Address::store`, and
  the raw `build_store`s into a local, the return slot, or an array element,
  first call `check_store_type`. It fails with `internal error: storing a
  value of LLVM type 'X' into 'name' ('T', LLVM type 'Y')`, located at the
  node being generated, whenever the two LLVM types differ, except into a
  slot still typed `__auto` (a `var` sema never inferred, an `i32` slot):
  that is `cannot infer the type of 'name'; write its type in place of
  'var'`, the user's workaround for an inference gap. A field's
  `Address` takes its LLVM type from the object's layout
  (`get_field_type_at_index`), so a struct-typed field is a `ptr` slot
  there, not the struct body. A new store into a typed slot goes through
  the same check.
- **Types** (`types.rs`): `Types::get(name)` maps primitive aliases (`int`
  and `i32`, `ulong` and `u64`, `char` and `i8`, …) to LLVM types. Any
  `T*` maps to an opaque pointer. Registered structs map to their struct
  type. A specialization name falls back to its base struct when it is not
  registered itself.
- **Generics**: none reach codegen. Sema monomorphizes them, and codegen
  looks up `Array<int>` by its full name.
- **Externs**: declared with the C prototype. Variadic externs use C default
  promotions. Narrow integer arguments get `signext`/`zeroext`.
  `[Link(name = "sym")]` changes the symbol (`ExternDef::link_name`). A string
  literal passed to an extern is passed as its raw NUL-terminated global.
  A call to an extern whose C symbol is `memcpy`, `memmove` or `memset`
  lowers to the LLVM intrinsic (`build_memory_intrinsic`), since a `void`
  extern is declared returning `i32` and LLVM would not recognize the
  builtin; so a constant-size copy optimizes to loads and stores.
  An extern whose symbol starts with `llvm.` (`[Link(name = "llvm.ctpop")]`)
  is an LLVM intrinsic (`intrinsics.rs`, #344): `instantiate_extern` declares
  it with the prototype as its signature (a `void` return is `void`), picking
  an overloaded intrinsic's mangled name from the prototype (return type,
  first parameter, or both) and checking each candidate by calling it in a
  scratch module and running the verifier, so a mismatch is an error at the
  extern. `codegen_call` checks each argument the intrinsic marks `immarg`
  is a constant (`check_intrinsic_argument`), located at the argument.
  `partition::finish` leaves `llvm.*` symbols alone. The runtime's integer
  bit methods, float functions (`runtime/number.pep`) and the `hint` module
  are written with these.
- **Branch hints**: `[Likely]` or `[Unlikely]` above an `if` or a `match`
  arm is parsed into that block's attributes (`marked_branch`, and the arm
  loop of `match_statement`); the builder checks them
  (`check_branch_hints`), and a `match` lowers to branches whose blocks
  are the arms' blocks, so they arrive on `Branch::if_block` or
  `else_block`. `weigh_branch` turns them into `!prof` branch weights
  (`ast::branch_hint`).
- **Builtins resolved by name in `codegen_call`**: `release<T>(v)`,
  `__is_pod`, and `__default<T>`. `__caller_location()` is handled in
  `codegen_expr` (#354): a constant C string `file:line:col`
  (`location_text`, null when unknown) for its own `Loc`, or, while a call's
  default arguments are generated (`codegen_default` sets
  `in_default_argument`), for the call's (`call_loc`, which `codegen_expr`
  sets for each `FunctionCall` and `MethodCall`). So `assert`, `panic`,
  `_pep_assert`, `_pep_check_bounds` and the runtime's checking methods take
  `location: __ptr<char> = __caller_location()` and report their caller;
  the null checks codegen emits pass their own location
  (`located_assert`). Without the `bounds` or `null` runtime
  check, a call to `_pep_check_bounds` (the runtime's index check) or
  `_pep_assert` (the null checks) is dropped, arguments and all.
- **Runtime checks** (`checks.rs`, #265): `codegen_binary` and
  `codegen_unary` send integer `+ - * / % ** << >>`, unary `-`, `++` and
  `--` through `checked_int_binary` / `checked_arithmetic`, which use
  `llvm.{s,u}{add,sub,mul}.with.overflow` and `panic_if`: a branch to a
  `check.fail` block calling `_pep_panic("integer overflow in 'int'
  addition", "file:line:col")` (`llvm.trap` without the runtime). Two constant operands
  are checked at compile time instead, an error at the operator.
  `CodeGenerator::runtime_checks` turns kinds off: overflow then wraps, a
  shift count is masked, a division is plain `sdiv`/`udiv`. Narrow types
  compute at `int` (C promotion), so only `int` and wider overflow.
  The arithmetic intrinsics `__wrapping_add/sub/mul(a, b)` and
  `__add/sub/mul_overflows(a, b)` are `BinaryOp` variants that the builder
  makes from those calls (`BinaryOp::intrinsic`); the overflow tests work at
  the lhs's own width and give `bool`. The integer types' `wrapping_`,
  `checked_`, `saturating_` and `overflowing_` methods (`runtime/number.pep`)
  are written with them. `call_function` declares unknown
  runtime helpers such as `_pep_malloc` on demand.
- **Intrinsic nodes** in `codegen_expr_unlocated`: `SizeOf`, `Default` (zero
  or null), `IsPod` (true unless the type is a reference or a tuple holding
  one, `is_pod_name`), `RefCount` (an atomic load), `CountStep` (an
  `atomicrmw` on the head count at byte offset 0 or 4, monotonic up and
  acq_rel down, or a plain load/add/store), `FunctionPointer` (the LLVM
  function's address; a static method is `Owner.name`), `Address` (FNV-folds POD values),
  `AtomicLoad` (acquire), `AtomicStore` (release, via `xchg`),
  `AtomicCmpXchg` (acq_rel/monotonic; floats are bitcast), `AtomicFetch`
  (`atomicrmw` acq_rel), and `ConstructAt` (`__construct_at(p[i], v)`, an
  element store into a slot the runtime knows is empty:
  `codegen_assignment` with `construct`, which acquires through
  `construct_refcount_ops` and never loads or releases the old occupant).
- **`match` expressions and `is` tests**: `WithSubject` (`with_subject`)
  evaluates the subject once, panics on a null reference enum, keeps the
  value in `subjects` by id for `Subject` to read, then evaluates the body
  (a `?:` chain). An owned subject is a deferred temporary, released at the
  end of the full expression, so an arm may yield one of its fields. A `?:`
  with one owned arm is owned: `codegen_ternary` acquires the other arm's
  read (`copy_arm`), as C++ yields a prvalue copy there. Numeric arms of
  different types convert, each in its own block before the branch, to
  `arithmetic::conditional_result` of the two (`convert_arm`), the type
  sema's `static_type::of` and codegen's `value_sema_type` report for the
  `?:`, so a `return`, initializer, argument or assignment converts from it.
- **Enum cases that carry nothing**: `StaticCase` (`static_case`) is the
  global `<Enum>.case<tag>`, the enum's struct with its counts at
  `STATIC_REFCOUNT` and 1, its `__tag` set and every other field zero. It
  is emitted with external linkage, like a function, and
  `partition::finish` makes it `linkonce_odr` (in a comdat), so the units
  that use it share one object and `===` holds across files (a bare
  `linkonce_odr` global crashes the JIT on Windows). A reference enum with such a case
  gets the same guard as a plain function type (`skip_static_objects`,
  added by `struct_body::apply_synthesized`): its `__acquire` and
  `__release` leave a count at or above `STATIC_REFCOUNT` alone, so the
  object any thread may reach is only ever read.
- **Shared string literals**: `StaticString` (`static_string`) is one
  private constant global per literal and unit, `{ String, [n x i8] }`:
  the `String` object, its counts at `STATIC_REFCOUNT` and 1, `_size` and
  `_length` set and `_data` pointing at the NUL-terminated bytes that
  follow it. Named `str.object` so `partition::finish` orders it with the
  other string constants. It is only ever an argument to a parameter whose
  copy the caller makes (`copy_argument` makes none for it) or a receiver,
  so no count step reaches it, and it can be constant.
- **Function values**: `FunctionRef` produces a static function object
  (`__function_object.<name>`, or `__function_object.shared.<name>` for a
  `shared` function type) whose `__invoke` points at a thunk
  (`__function_thunk.<name>`, one per function; for an `extern` function,
  which `function_types::referenceable_functions` lists unless it is
  variadic, the thunk calls the C function). Its strong count starts at
  `STATIC_REFCOUNT`, so it is never freed. `codegen_invoke` loads `__invoke` and calls
  it with the signature of the static type. A callee of C function pointer
  type goes to `codegen_call_c_function` instead: an indirect call to the
  address itself with the C signature, after a null check. `MakeClosure` is its closure
  struct's constructor call, used as the function value: the constructor
  stores `MethodAddress("__call")` (the method itself, whose `this` is the
  object) in `__invoke` and `MethodAddress("__dtor")` in `__destroy`.
- **Default arguments**: `param_defaults` stores each callable's default
  expressions. `missing_args` pads trailing arguments at the call site and
  reports `too many/too few arguments to 'f'`.
- **Control flow**: nested blocks, branches, and loops get their own basic
  blocks. `frame.exited` suppresses dead code after
  `return`/`break`/`continue`. Every unterminated block is patched to branch
  to the function's return block. Return values go through a `retval`
  alloca in the entry block. Locals get their slots there too
  (`entry_alloca`), so a `var` inside a loop does not grow the stack.
- **Errors**: codegen functions return `Result<_, String>`. A node that can
  fail and has a `Loc` gets the wrapper pattern:

  ```rust
  fn codegen_var_def(&mut self, var: &VariableDef) -> Result<(), String> {
      let result = self.codegen_var_def_unlocated(var);
      self.locate(&result, var.loc);   // innermost located node wins
      result
  }
  ```

  `generate` turns the string into a `Diagnostic` at `error_loc`.
- **JIT** (tests only): `jit_engine`, `jit_engine_mapped` (maps declared but
  undefined symbols to host addresses), `jit_call_i32`, and `jit_execute`.
  MCJIT does not run `llvm.global_ctors` by itself, so the engine calls
  `run_static_constructors`. A declared function that neither the mapping
  nor the process resolves (ws2_32 on a Windows test host) is mapped to a
  stub that aborts if called, because MCJIT crashes finalizing a module
  with an unresolved symbol even when nothing calls it.
  On Windows the engine allocates through `jit_memory::JitMemory`: one
  reserved region with the code first, then read-only data, then
  read-write data. MCJIT resolves `.pdata`'s `IMAGE_REL_AMD64_ADDR32NB`
  relocations as 32-bit offsets from the lowest section, and aborts the
  process ("requires an ordered section layout") when LLVM's default
  manager scatters the sections more than 4 GB apart, as it did under
  parallel test load.
- **Target** (`target.rs`): `initialize_targets` registers the x86 and
  AArch64 backends (inkwell's `target-x86` and `target-aarch64`, on every
  host, so `--target` can name either), and `target_machine` makes the
  machine for the target's triple (`triple`: `--target`'s, else LLVM's
  default). Every call site shares these. Read that file's header before
  touching backend registration.

### 4.2 Traits used as types (`sema/src/traits.rs`, `passes/convert_to_traits.rs`)

A trait name is a type (`Shape s`, `Array<Shape>`, `Iterator<int>`). The
value is a struct reference with its concrete type erased, like a
`shared_ptr` to an abstract base with a virtual destructor.

- **Sema.** `traits::instance` specializes a trait at its type arguments and
  keeps its *dispatchable* methods (instance methods whose signature does not
  name `this` as a type) in declaration order: that order is the vtable's.
  `static_type` knows trait types, so method calls on them type-check and
  infer like struct calls. `convert_to_traits` inserts `ToTrait { value,
  from, to }` at conversion sites; conformance is nominal (`extend S with
  Tr`). Specialization substitutes a struct's declared traits
  (`Box<int>` gets `Getter<int>`).
- **Representation.** `Types::register_trait` maps a trait type to
  `[2 x ptr]`: the object and the vtable. An array rather than a struct
  type keeps trait values out of every "struct type means pointer" path;
  they load, store, pass and return by value. `reference_value_type` gives
  the slot type of any reference, `object_pointer` its object.
- **Vtables** (`vtable`, emitted on first `ToTrait` for a pair):
  `__vtable.<Struct>.<Trait>` = `[S.__release, S.__acquire, S.m1, …]`,
  ending with `S._pep_copy_trait`, the member `copies` adds to every trait
  (see `synthesize_copies` in the pass table). A
  slot of an overloaded name holds the struct's member of that set with the
  slot's parameter types (`StructDesc::method_params`). A
  trait method the struct implements with a struct result where the trait
  returns a trait type goes through `covariant_adapter`, which converts
  the result.
- **Thunks** (`instantiate_trait`): `Trait.__acquire`, `Trait.__release`
  and `Trait.method` are ordinary functions taking the trait value as
  `this`. They null-check (refcount thunks) or assert (method thunks) and
  call through the vtable. Because they are named like struct members,
  every refcount path in §5 (`T.__acquire`/`T.__release` by type name) and
  every method call works on trait values without special cases. The
  release thunk runs the concrete `__release`, so the last release runs the
  concrete destructor.
- **Converting back** (`enums::lower_matches`, codegen
  `codegen_from_trait`). Every vtable ends with its struct's type id
  (`type_id`, a hash of the struct's name: a vtable is private to its
  unit, so its address is no identity). A type pattern over a trait value
  (`is Circle`, `Circle(c) =>`, and `as?`, which the builder lowers to a
  `match`) becomes `Expression::FromTrait`: with `test`, whether the id is
  one of `candidates` (the struct named, or each struct that declares both
  traits; false for a null value); without, the binding's value: the
  object, a value struct copied out of its box, or for another trait the
  object paired with the vtable `select`ed by id. The binding reads the
  `match`'s hidden subject, so it is an lvalue read like any other.
- **Weak trait values.** `__weak<Shape>` (inside `Weak<Shape>`) is the
  object's weak reference plus its vtable. Sema synthesizes its weak
  struct as for a struct target (atomic counts, since the object may be
  `[Shared]`), and `convert_to_traits` turns a `__null` flowing into one
  into `Default`. Codegen keeps the struct out (`weak_traits`) and gives
  the type a trait value's `[2 x ptr]` layout with its own
  `__acquire`/`__release` (`emit_weak_trait_thunk`: an atomic step of the
  head's weak count, freeing at 0); `codegen_weak` takes the object out of
  the pair and upgrades to the same pair, or a null one. A value struct's
  box (`box_member`) gives up the strong references' weak reference at
  its last release, as `struct_body` does, so a weak reference keeps the
  box's memory.
- **Identity.** `==`/`!=` on trait values compare objects, and
  `store_refcount_ops` treats the same object as self-assignment.
  `__address`/`__refcount` read the object. Array slots of a trait type are
  16 bytes, which Array's shifts and swaps move whole as bytes.

### 4.3 Tuples (`passes/tuples.rs`, codegen `register_tuple`)

A tuple is a value, like a `std::tuple` of `shared_ptr`s: no allocation, one
reference held per reference element.

- **Representation.** `register_tuple` maps `__tuple<A, B>` to a literal
  (unnamed) LLVM struct of its elements' slot types (a struct element is its
  pointer, a trait element its `[2 x ptr]`). Named LLVM structs are objects
  used through pointers; `types::is_object` tells the two apart, so
  parameters, returns, slots and array strides keep a tuple by value. The
  sema tuple struct gets no object layout, constructor or methods.
- **Refcounts.** `is_reference_name` includes tuples, and
  `emit_tuple_refcount_thunk` emits `Tuple.__acquire`/`Tuple.__release`,
  which step each reference element. So every §5 path (copies, scope exits,
  stores, temporaries, fields, the destructor's field releases) works on
  tuples by type name. `store_refcount_ops` skips the identity test for a
  tuple: acquiring the new elements before releasing the old ones makes
  self-assignment safe.
- **Literals.** `codegen_tuple` builds the aggregate with `insertvalue`: an
  lvalue-read element is acquired, an owned rvalue moves in, and numbers
  convert to the element type.
- **Element reads.** `t.0` is an `extractvalue`; an owned-rvalue tuple
  (`f().0`) goes on `deferred_temps`.
- **Destructuring** moves: `var a = __tuple_N.k` (`destructured_element`)
  takes element `k` without acquiring and clears it in the hidden tuple, so
  the binding holds the only reference, as a C++ structured binding would;
  `_` elements stay in the hidden tuple until its scope exits.
- **Comparing and hashing.** `codegen_binary` sends a tuple `==`/`!=`
  to `tuple_equal`, which compares element by element (`value_equal`: an
  element's own `==` when its type has one, else by value or identity).
  `Expression::Address` on a tuple (what `hash<T>` uses) is `tuple_hash`,
  which folds each element's `hash<E>` (or its bytes) with FNV-1a, so a tuple
  is a `HashMap` key. Its text comes from the runtime's `to_string<A, B, ...>`
  overloads (runtime/string.pep), which overload resolution prefers to the
  generic `to_string<T>` as more specialized.
- **Generic bases.** A tuple naming a generic parameter (`(K, V)` inside
  `HashMap`) is skipped by `register_tuple`; only its specializations get a
  layout.

### 4.1 Object emission, linking, running (`driver/src/lib.rs`, `linker.rs`)

`run` emits one object per compilation unit through `objects` (see
[4.3](#43-build-cache-driversrccachers-codegensrcpartitionrs)), plus the
program object `<build>/<module>.o`, with the target's `TargetMachine`
(the host's, or `--target`'s; see 2.5). Objects are written by
`target::write_object`, which for an ELF target first moves
`llvm.global_ctors` into an `.init_array` section (`use_init_array`): a
machine made through the C API emits `.ctors`, which GNU ld folds into
`.init_array` but lld, which cross-linking uses, ignores.

**Linking** (`linker.rs`). `link` runs clang as the link driver. For
another platform it adds `--target=<triple>`, LLVM's linker
(`--ld-path=` when `find_lld` finds `ld.lld`/`ld64.lld`, plain or as
`ld.lld-<major>`, beside clang, in the LLVM prefix or on the PATH; else
`-fuse-ld=lld`), and the
target's system root (`--sysroot`, else `PEPPER_SYSROOT_<TRIPLE>`; passed as
`--sysroot` for ELF and Mach-O, and as lld-link's `/winsysroot` for
Windows), and a failed link ends with a note naming what is missing
(`cross_link_note`). The default system libraries and the debug options
follow the target's OS. The JIT stays host-only.

**Optimization** (`codegen/src/target.rs`). `OptLevel` is `-O0` through
`-O3`: `-O<n>`, else `PEPPER_OPT_LEVEL`, else `-O0` (`main.rs` spells a bare
`-O` as `-O2` before clap sees it, so `-O main.pep` does not read the file
as a level). `cache::emit` runs `target::optimize` (LLVM's `default<On>`
pipeline, nothing at `-O0`) on each unit's module after `partition::finish`
and after the cache hashed its bitcode, then writes the object with
`target::machine(level, &cpu)`, whose codegen level matches. So the cache's code
hash is of the unoptimized module and a "same code" unit skips the
pipeline too; the level is in `Cache::compiler` and so in every key and
code hash. `--emit-llvm` optimizes the whole-program module the same way,
and the JIT (`create_jit_engine`) optimizes at `CodeGenerator::opt_level`,
which starts at `PEPPER_OPT_LEVEL`.

**Link-time optimization** (`driver/src/lto.rs`). Units optimized alone
cannot inline a call into another unit (user code into the runtime's
`_pep_malloc` or `String.__acquire`). `Options::effective_build` turns LTO
on at `-O2` and `-O3` unless `--lto=off` (`--lto=full` turns it on at
`-O1`; at `-O0` it is an error), as `cache::Build { opt_level, lto }`. With
it, `cache::emit` runs `Pipeline::PreLink` (`lto-pre-link<On>`) and writes
the unit's bitcode (`<unit>.bc`) where the object would go, cached like
one; then `run` hands every unit's bitcode to `lto::optimize`, which links
them into one module (`link_in_module`), makes every definition but
`main` internal and drops its comdat (`internalize`: nothing outside the
program calls Pepper code by name), runs `Pipeline::Link`
(`lto<On>`) over the whole program, and writes `<build>/<module>.lto.o`,
the only object the system linker sees. No linker plugin or `lld` is
involved, so it works wherever the compiler does. The LTO mode is part of
the cache's directory name and compiler identity (`O2-lto`, or `O2-lto-g` with `-g`). The JIT does
not use LTO: it compiles the whole program as one module already.

**Target CPU** (`codegen/src/target.rs`). `Cpu` is the CPU, the features
added to or removed from it, and the CPU to tune for. `Cpu::default` is
clang's default for the host triple (`default_for`: `x86-64` tuned for
`generic`, `penryn` on Intel macOS, `apple-m1` on Apple arm64, `generic`
on other AArch64), never the build machine's CPU. `Cpu::from_options` reads
`-m` options as clang does: on x86 `-march` names the CPU (`native` asks
LLVM for the host's CPU and features) and `-mcpu` is an error; on AArch64
`-mcpu` names the CPU and `-march=armv8.x-a+ext` the architecture
(`+v8.xa`, `+ext`, `-ext` for `+noext`); `-mtune` sets `tune-cpu`; and
`-m<feature>`/`-mno-<feature>` add `+feature`/`-feature` last. `Build`
carries it: `cache::emit` calls `Cpu::stamp`, which puts `target-cpu`,
`target-features` and `tune-cpu` on every defined function as clang does,
so LTO keeps each function's CPU, and every pass and object uses
`target::machine(level, &cpu)`. The CPU is part of the cache's directory
name and compiler identity (`O2-lto-x86-64@generic`; hashed when it is not
a plain file name, as `-march=native`'s feature list is not).

**IR facts** (`codegen/src/facts.rs`). `CodeGenerator::generate` ends with
`facts::annotate`, which states what the language guarantees: `nounwind`
on every function and `uwtable` on every definition; `noreturn` and `cold`
on `NO_RETURN` (`_pep_panic`, `_pep_exit`, `abort`, `_Exit`); `noalias` on
the result of `ALLOCATORS` (`_pep_malloc`, `_pep_realloc`); and `!tbaa` on
object memory. The TBAA tree has two types under one root, `reference
counts` and `fields`: a load or store whose address is a field address of
a struct object (`getelementptr %S, ptr, 0, <i>`: `i < 2` is the head) or
a head count address (`head_count_ptr`, found by its name `HEAD_COUNT_NAME`)
gets one; everything else stays untagged and may alias anything. The
module comment says which facts are left out and why.

It collects
libraries in this order: `-l` flags, then `runtime/*.a` (as
`-L<dir> -l<name>`, after the `-L` directories), then `link_libraries(&module)`, which gathers the
`[Link("name")]` attributes of externs that survived platform filtering,
deduplicated. `linker::link` invokes **clang as the link driver**,
preferring `$LLVM_SYS_<NN>1_PREFIX/bin/clang` so the linker matches the
LLVM the compiler was built against, and falling back to `clang` on PATH.
`default_system_libraries` adds `kernel32 user32 shell32` on Windows and `m` on Linux (float `**` calls `pow`). Link
warnings are forwarded. Failures include both stdout and stderr, because
MSVC's link.exe writes unresolved symbols to stdout.

### 4.3 Build cache (`driver/src/cache.rs`, `codegen/src/partition.rs`)

Phases 1, 2a, 2b and 2c of `design-notes/build-cache/build-cache-proposal.md`:
sema still runs over the whole program, but codegen and object emission run
per **compilation unit**, and a unit whose sources and inputs' interfaces are
unchanged takes its object from `.pep/cache` without generating any code,
and sema skips its non-generic bodies; a file whose text is unchanged is not
parsed.

- **Units** (`Program::units`, `sema/src/program.rs`): the runtime's
  top-level files (prelude files outside any module) are the unit
  `prelude`; every other file is in the unit of its import cycle (a
  strongly connected component of the import graph), named after its first
  file's namespace (`io/file`, `docs/examples/hello`). Names depend only on
  paths.
- **Owners.** While instantiating, `CodeGenerator::own` records the file of
  every symbol a declaration defines (`owners`): methods, constructors,
  functions, globals, and each file's global initializer
  `__pep_init@<namespace>`. A method belongs to `FunctionDef::owner` when
  set, else its own location's file, else its struct's: a trait's default
  method copied into a struct (`apply_extensions`) is owned by the file
  that declares the conformance, not the trait's file. Instantiations (a
  name with `<`), the `__copy`/`_pep_fix_weak`/`_pep_copy_trait` methods `copy`
  synthesizes on demand (`copies::is_synthesized_method`: a program has
  them only for the types it copies, so owning them would make a unit's
  object depend on the program), and code with no location have no owner.
- **Per-unit codegen.** With `CodeGenerator::unit` set (`UnitFilter`),
  `generate` declares everything in name order (so a unit's module does not
  depend on load order), declares only the externs its input files declare
  (externs are first-wins by C name, so another file's declaration must not
  change the unit's calls), defines only globals and initializers of the
  unit's files (listing globals by file namespace, not initialization
  order, since a unit of several files in an import cycle, such as io and
  async, is loaded in whatever order the program imports them), and `codegen_unit` emits, in name order, the unit's owned
  bodies, then every unowned body something already emitted calls, until
  nothing new is called. The program module (`unit: None`) defines only
  `__pep_global_init` and `llvm.global_ctors`, which call each file's
  initializer in initialization order. Each unit gets its own LLVM
  `Context` (struct type names are per context), so `objects` compiles
  units on one thread per CPU.
- **`partition::finish`**: owned symbols become external (hidden, except
  `main`); unowned definitions become `linkonce_odr` in a comdat (no comdat
  on Mach-O), except private helpers other than function objects and
  thunks; `globaldce` drops unused ones; private string constants are
  put in the order of their first use and numbered in it (code is
  generated in an order that depends on the rest of the program, so their
  creation order would make a unit's bitcode depend on it too); and `symbol_name` respells every Pepper symbol except `main`
  and plain member names (`Point.length`): `Array<int>.count` →
  `_PArray_3cint_3e.count`, `helper@io/file` → `_Phelper_40io_2ffile`, and
  a free function or global even when plain (`exit` → `_Pexit`), so no
  Pepper name collides with the C library's (Windows links its C runtime
  statically). Externs keep their C names. The whole-program
  path (JIT tests, `--emit-llvm`) is unchanged: it keeps readable names and
  gives private names internal linkage.
- **Unit inputs** (`Program::unit_inputs`): the files a unit's code can
  depend on: its own files, every prelude file, the files these import or
  take extensions from (transitively), and every file that declares a
  concrete override (`hash<Point>`), since sema honours an override
  wherever its generic is instantiated, imported or not.
- **Keys** (`driver/src/keys.rs`). `Keys::key` hashes (BLAKE3) the
  compiler's identity (crate version, LLVM version, and the running
  executable's path, size and modification time), the unit's name and
  files, and each input file's name, namespace and prelude flags, with its
  **interface hash** when the file belongs to another unit (early cutoff,
  phase 2c) and its text otherwise. An input whose unit reaches this unit
  back through inputs (a strongly connected component of units reading each
  other's files: an override file the prelude instantiates, a forced
  import) is hashed by text, since its interface can depend on this unit. A
  record also holds the hash of the bitcode its object was emitted from, and
  its files' interface hashes.
- **Interfaces** (`sema/src/interface.rs`, `interface_hash`): what code in
  other units can depend on. The file's declarations as `build_file` makes
  them, printed with `{:?}` inside `ast::without_positions` (spans and
  locations print as `_`: no unit's code depends on another's positions),
  with each body `strip_bodies` could skip (non-generic, explicit return
  type, not a copied trait default) replaced by its recorded link summary
  without the blame's position (`summary_without_position`), or kept when no
  summary was recorded, plus how many closures it creates (a file's closure
  structs are numbered in order). So a body edit, a comment or a moved
  declaration leaves the interface alone; a signature, a field, a generic
  body or an inferred return type changes it. That other units' code does
  not depend on the skipped bodies is what verifying's trial checks, and a
  verifying hit also requires its recorded interface hashes to match.
- **Resolving keys.** Before sema (`compiler::reused`), units resolve bottom
  up: a unit's key is known once every unit it reads through interfaces is a
  hit, whose record gives their hashes (`Cache::interfaces`, read without the
  lock: interfaces follow from the key). A unit whose dependency missed waits
  for sema, which checks its bodies. After sema (`objects`) every interface
  is known: recorded for the units whose bodies sema skipped
  (`ForObjects::interfaces`), else hashed from the program's syntax trees
  and `Module::summaries_to_record` (`file_interfaces`), so every unit is
  keyed, and a unit whose dependency changed only a body is still a hit.
- **Cache** (`cache::Cache`): `<cache>/v1/<target triple>/<unit>.o`,
  `<unit>.json` (`{"key": …, "bitcode": …, "warnings": "no", "interfaces":
  "<namespace>=<hash>;…"}`),
  `<unit>.summaries` (see below) and `<unit>.lock`. `object`
  takes an exclusive OS lock (`File::lock`) on the unit. When the record's
  key matches and the object exists, it is a **hit**: no code is generated.
  Otherwise it generates the unit; when the bitcode hash matches the
  record's (an edit that changed no code, such as a comment, or a body in a
  file the unit imports), the object is reused (**same code**); else the
  object and then the record are written through temporary files and
  renames (**miss**). Either way the object is hard-linked (or copied) into
  `<build>/<module>.units/` before unlocking, so a later writer cannot
  change what is linked. The OS releases the lock on exit or crash. The
  cache directory is `--cache`, else `$PEPPER_CACHE_DIR`, else
  `<cwd>/.pep/cache`; `--no-cache` skips it.
- **Skipping bodies** (phase 2b; `compiler::compile_for_objects`): before
  sema, `Cache::reuse` checks each unit's record and, for a hit that
  compiled without warnings, hard-links its object into the build
  directory under the unit's lock, so another program replacing it later
  (a program with other overrides gives a unit another key) cannot matter.
  `Module::cached_files` marks those units' files, and
  `passes::strip_bodies`, right after `lift_closures` in
  `struct_body::apply`, drops their non-generic functions' and methods'
  bodies with explicit return types, and the closure structs lifted out of
  them. It drops only a body whose link summary the cache recorded
  (`<unit>.summaries`: `check_confinement` reads callees' bodies to decide
  whether a result is fresh, so it uses the recorded summary instead; a
  summary that reaches a trait call depends on the program and is never
  recorded, so its body stays). Generic code, trait defaults, constructors
  and destructors stay whole. `Module::stripped` lists the functions it
  stripped: `Module::is_defined` counts them as defined, so they still
  resolve as function values. `objects` generates nothing for those units. A unit that warned is
  checked again, so its warnings print on every build. `--emit-llvm` and
  the JIT compile whole programs, never stripped.
- **Verifying** (`--verify-cache`, which `build_cache_tests.rs` passes, or
  `PEPPER_CACHE_VERIFY=1`, which the `llvm-versions` workflow sets;
  `test-linux` records each failure in the run's summary): a hit generates the unit anyway and fails if its bitcode differs
  from the record's, naming the unit; it keeps `<unit>.ll` beside each
  object it stores and writes `<unit>.verify.ll` on a mismatch, to diff.
  A mismatch means a unit's code depends on something its key leaves out:
  add it to `unit_inputs`, or make codegen stop depending on it. So names
  sema synthesizes are numbered per file, never per program: hidden locals
  restart in each `build_file`, and closure structs are
  `__closure_N@<namespace>` (`Module::namespaces`). Verifying also runs sema
  a second time with the hit units' bodies skipped (the "trial") and
  requires every other unit's code from it to match
  (`Cache::check_code`, `<unit>.trial.ll` on a mismatch).
  `--no-verify-cache` overrides the variable.
- **Unchanged programs** (`programs/<root namespace>.json` and `.o`): when
  `compiler::reused` finds every unit reused, it computes the program's key
  (`Keys::program_key`: every unit's key and the initialization order) and,
  when the program's record matches, puts its program object in place
  (`Cache::program`): `compile_for_objects` returns without running sema
  (`ForObjects::cached`), and `run` links the reused objects with the
  recorded `[Link]` libraries. The record also holds the last link's inputs
  (`link_key`: objects by content, libraries, output path) and the output's
  hash (`Cache::record_link`); when both still match, the link is skipped
  too. `run` stores the record after every build with a cache.
- **Syntax trees** (`.pepi`, phase 2c): `program::load_with` takes a
  `ParseCache` (`Setup::parsed`), which the driver backs with the cache
  (`impl ParseCache for Cache`): `parsed/<hash of the path>.pepi` holds a
  file's syntax tree, `postcard`-encoded (serde derives on the AST) after a
  stamp hashing the compiler and the file's text. A file whose stamp matches
  is loaded without parsing, whatever its unit; any other is parsed and its
  tree written, unless the parser warned (warnings are not serialized). A
  damaged or stale file is simply parsed again. As built, a `.pepi` holds
  the whole tree per file, not per unit with its declarations only as the
  proposal sketched: bodies are skipped later, in sema (phase 2b), where
  their link summaries are known, and a per-file tree also spares parsing
  the unchanged files of a unit that misses.
- **Checked runtime** (`.checked`, canonical specialization phase 4):
  `checked::checked_runtime` takes a `RuntimeStore`, which the driver backs
  with the cache (`impl RuntimeStore for Cache`): `runtime/<key>.checked`
  holds the runtime checked alone (§2), `postcard`-encoded after a stamp
  hashing the compiler and the key (the target and the runtime files' names,
  namespaces and texts, not their places in the program). Its locations number the
  runtime files in order; `with_file_map` maps them to and from the
  program's `FileId`s. A missing, stale or damaged file is checked again
  and rewritten.
- **Not yet**: compiling units on separate threads through sema.

---

### 4.4 Debug info (`codegen/src/debug.rs`, `debug_types.rs`)

`-g` sets `CodeGenerator::debug_info`; `generate_module` then creates a
`debug::DebugInfo`, one compile unit per LLVM module (a unit's first file,
else the module's name), with the module flags `Debug Info Version` and
`Dwarf Version` 4 (`CodeView` on Windows; DWARF 5's per-object
`.debug_names`, which the C API cannot turn off, is concatenated by GNU ld
into one gdb rejects). Modules carry the host triple, which CodeView needs.

- **Subprograms.** `codegen_function` calls `begin_function`, which gives
  the function a `DISubprogram` named as written (`demangle_name`), with
  no linkage name (a debugger would show the linker spelling,
  `partition::symbol_name`, instead). A method with no location (the
  synthesized `__acquire`, a constructor) is artificial and placed at its
  struct (`debug_struct_loc`).
- **Locations.** `enter_location`/`leave_location` stamp what
  `codegen_statement`, `codegen_var_def` and `codegen_expr` emit with
  their node's `Loc` and restore the outer one afterwards, so
  compiler-inserted code (acquires, the releases after a statement) is
  attributed to the statement that caused it. `statement_loc` gives a
  statement's location.
- **Scopes and variables.** `codegen_scoped_block` (a nested block, an
  `if` or `else` arm, a loop body) pushes a `DILexicalBlock` at its first
  statement. `debug_declare` declares each parameter (numbered from 1,
  `this` artificial) and each local that is not hidden or `__`-named, with
  a debug record (`LLVMDIBuilderInsertDeclareRecordAtEnd`; inkwell's
  wrapper expects an instruction) on LLVM 19 and later. Module-scope
  variables get a `DIGlobalVariableExpression` (`declare_global`).
- **Types** (`debug_types.rs`, `CodeGenerator::debug_type`): numbers under
  their written names (`written`), raw pointers, a plain enum as an
  enumeration, a tuple as a structure of `0`, `1`, ..., a trait value as
  `object` and `vtable`, a struct reference as a pointer to a
  structure with every field, the count head included, and a value struct
  (`CodeGenerator::values`, such as `Optional<T>`) as the structure itself.
  An enum's payload field `Case.value` is the member `Case__value`, which
  debugger expressions and natvis can name. Struct types are
  built from a work stack after the structs their fields name; a reference
  back to a struct or tuple still being built (`DebugInfo::building`) is a
  forward declaration (behind a pointer, except for a value, whose
  declaration carries its size), which debuggers resolve by name.
- **`DebugInfo::finish`**, before the module is verified, gives every other
  defined function (thunks, initializers) an artificial subprogram, moves
  to line 0 every instruction without a location in its own function's
  scope (codegen emits a thunk in the middle of a caller, and LLVM requires
  a location on every call in a function with a subprogram), adds
  `uwtable` to every definition so debuggers can unwind through it, and
  finalizes the builder.
- **Optimization** keeps all of it: LLVM's inliner writes the inlined-at
  chains itself, and `docs_examples_tests` builds every example at
  `-O2 -g`, so the verifier checks them.
- **Cache.** `-g` is part of `Cache::compiler` and the cache directory
  (`O<n>-g`). It also sets `Keys::exact_positions`, which hashes every
  input by its text: a unit's code holds the line numbers of the generics
  it instantiates from other files, which interface hashes leave out.
- **Linking.** `linker::link` passes `-g` to clang, which on Windows asks
  link.exe for a `.pdb` (with `/INCREMENTAL:NO`, so nothing else appears
  beside the output).

- **Formatters** for `String`, `Array` and `Optional` live in
  `runtime/debuggers/`. `DebugInfo::embed_gdb_printers` puts
  `gdb_printers.py` (`include_str!`) in the program module's
  `.debug_gdb_scripts` section on Linux, as an inline script (kind 4),
  kept by `llvm.used`; `run` links `pepper.natvis` into the `.pdb` with
  `/NATVIS` on Windows; `lldb_formatters.py` is imported by hand. Each
  matches the struct and a reference to it, by name, and shows the head
  counts first as `[ref count]` and `[weak count]`; `Optional`, a value
  enum, has no head and shows its case from `__tag` and its value from
  `Value__value`.

- **JIT.** A `CodeGenerator` with `debug_info` set JITs a module with
  debug info; MCJIT hands every object it loads to LLVM's GDB JIT
  interface (`__jit_debug_descriptor`), which gdb and lldb read
  (`jit_code_with_debug_info_runs_and_is_registered`).

Not done yet (issue #218): enums with payloads as variant parts, which the
LLVM C API cannot create.

### 4.5 Value structs (`sema/src/value_structs.rs`, codegen `values`)

A `[Value]` struct is a tuple with names and methods: no allocation, no
counts of its own, one reference held per reference field. Design:
[design-notes/sema/value-structs.md](design-notes/sema/value-structs.md).

- **Sema.** `struct_body` gives it no count fields and no `__acquire`,
  `__release` or destructor bodies, and its constructor starts with
  `var this: V = Default(V)` instead of allocating; `zero_for` is
  `Default(V)`. `copies` gives it `_pep_copy_value` (`var __made = this;`
  then each counted field copied), and `check_shared_types` treats it as
  thread-safe when every field is (a fixpoint over value fields).
- **Representation.** Codegen names its LLVM struct `value.<Name>`
  (`types::VALUE_PREFIX`), which `types::is_object` excludes, so slots,
  parameters, returns and array strides keep it by value, as for a tuple.
  `instantiate_struct` records its field types in `values`, and
  `aggregate_elements` answers for tuples and values alike, so equality,
  hashing (`Address`), stores, moves and the field refcount paths share the
  tuple code. `__acquire`/`__release` are `emit_tuple_refcount_thunk`
  thunks over the fields, declared before any tuple thunk is emitted, since
  a tuple or another value can hold a value (`(int, Optional<Box>)`). A
  unit declares them all but defines only the
  ones its code calls (`pending_value_thunks`, in `codegen_unit`'s loop):
  the runtime's iterators are values, and a thunk for every instantiation
  in the program would make a unit's code depend on the rest of it.
- **`this`.** A method's `this` parameter is a pointer to the receiver's
  storage (`value_this`), so a change through it lands in the caller's
  value; a `MethodCall` passes the receiver's address (`value_address`), and
  an rvalue receiver is spilled to a slot and released after the call. In a
  constructor `this` is an ordinary tracked local: `return this` copies it
  and the scope releases it.
- **Fields.** A field of a place is a GEP into it; a field of an rvalue
  (`make().end`) is an `extractvalue`, with the rvalue on `deferred_temps`.
- **Boxing.** `ToTrait` from a value struct copies it into a box,
  `{u32 strong, u32 weak, V}` (`box_type`, `box_value`), acquiring a read
  and moving an owned rvalue; the result is a new object (`is_owned_rvalue`
  true, `is_lvalue_read` false). The vtable's entries are `box_member`
  thunks: `__acquire`/`__release` count the box (the last release calls
  `V.__release` on the value and frees the box), and each method calls
  `V`'s with `this` at the value inside the box. `covariant_adapter` boxes a
  value struct result the same way (`iterate()` returning `ArrayIterator`
  for `Iterator<T>`).
- **`for` in place.** A `for` whose source is a value iterator stored in a
  place (no `iterate()`) binds the hidden iterator to that place's address
  instead of a copy (`codegen_var_def_unlocated`), so `break` and a second
  loop resume it.
- **One layout per type.** `value_structs::canonical` spells a value
  struct's name with omitted type arguments filled from their defaults and
  `__ptr<T>` as `T*`; `Types::ensure_value_opaque` keys the LLVM struct by
  it, so `Result<int>` and `Result<int, Error>` (separate specializations)
  store into each other.
- **Value enums.** `builder::reference_enum_def` keeps `[Value]` on the
  lowered struct, so a payload enum becomes a value struct: every case is a
  constructor call (no shared `StaticCase` object), the zero value is the
  first case, and `enums` emits no null assert for its `match` (neither in
  `lower_declaration` nor as a `WithSubject.null_message`). Equality and
  hashing guard each reference field (`unless_null`), since unused case
  fields are null. `Optional` and `Result` are value enums.

## 5. Reference counting: where the shared_ptr model is implemented

The model is defined in AGENTS.md ("Reference counting is
std::shared_ptr<T> passed by value"). This section maps each rule to the
code that implements it. Every rule is emitted in
`crates/pepper-codegen/src/lib.rs` through `acquire_ref` and `release_ref`,
which stand for `T.__acquire` and `T.__release`. Both are synthesized by
`struct_body::apply_synthesized` and are null-safe.

For a struct with the standard counts (`StructDesc::inline_counts`, set by
`standard_counts`: not a weak view, a function type's object, or a
reference enum with immortal cases, whose bodies differ), codegen inlines
the step instead of calling (`inline_count_step`): a null check and the
increment or decrement, atomic for a `[Shared]` struct (`count_step`, which
`CountStep` also uses). Only a release that reaches 0 makes a call, to
`T.__last_release`, a `cold`, `noinline` function that `last_release`
emits in each unit that needs it (no owner, so `linkonce_odr`): it calls
`__dtor`, drops the strong references' weak reference, and frees the object
when that reached 0, exactly as the zero branch of `__release`. So taking
or dropping a reference costs no call even across units and at `-O0`, and
the cache keys need nothing new: the step depends only on the head layout
and `[Shared]`, which are part of the struct's interface. Tuples and trait
values still call their thunks, which step their elements or object the
same way.

**Folding pairs** (#263). LLVM's own passes remove an acquire and a
release of the same object once both are inlined into one function and
nothing between them can read or change the count, but only if they can
tell the release does not reach 0. Codegen tells them: a copy from a slot
that owns a reference (`acquire_copy`, when `reads_owning_slot`: a local,
parameter, global, field or pointer element, never `this`) loads the count
with `!range [1, 2^31)`, since the slot's own reference keeps it at 1 or
more. GVN and InstCombine then fold the copy's step and its release's test
for 0, and dead-store elimination drops the count stores. Nothing changes
at `-O0`, observable counts stay exact wherever the program reads them
(a `__refcount` read is a load of the count, so the steps around it
stay), and atomic counts are never folded, so no fence is lost. Copies the
model cannot prove live (a constructor's result, `this`, a parameter at
entry, whose caller may pass its only reference) keep both steps.

| shared_ptr construct | Where |
| --- | --- |
| `make_shared` | The constructor's `return this` is an lvalue read of `this`, so the return site acquires (`Statement::Return` → `is_lvalue_read` → `acquire_ref`). A constructor result therefore arrives with one reference. This is net-identical to AGENTS.md's "construction leaves 0; the first owner acquires": the constructor's `this` local is never tracked, so nothing releases that reference. |
| `var x = expr` | `codegen_var_def_unlocated`: acquire when `expr` is an lvalue read. An owned rvalue (a call result, see `is_owned_rvalue`) moves in. The slot is registered with `track_scope_local`. |
| `x = y`, field and element stores | `store_refcount_ops`: if the new pointer equals the old one (self-assignment), do nothing; otherwise acquire the new value, store it, then release the old, so a destructor the release runs that reads the slot finds the new value (as `shared_ptr::operator=`). Fields use `field_refcount_ops` and indexed slots use `index_refcount_ops`. |
| By-value parameter | `codegen_function_unlocated`: acquire each struct parameter on entry (`this` excepted) and track it in the function scope. A `[Move]` parameter is not acquired: the caller hands its reference over (`pass_argument`: an owned temporary is not released after the call, an lvalue is acquired for it). |
| `std::construct_at` | `__construct_at(p[i], v)` (`Expression::ConstructAt`): acquire `v` and store it into a raw buffer element that holds no reference, with no load, compare or release of the old occupant (`construct_refcount_ops`). The runtime uses it where a slot is known empty: `Array.append` and `insert`, and `HashMap`'s insert and rehash. A non-empty slot leaks its occupant. |
| `move(x)` | `codegen_move`: load the reference from the place and store null there, with no count step; the result is an owned rvalue (`is_owned_rvalue`). |
| Scope exit | `scopes: Vec<Vec<(name, type, slot)>>`. `release_scope` runs at block fall-through, `release_all_scopes` at `return`, and `codegen_loop_break` releases the scopes a `break` or `continue` leaves. |
| `return` | An lvalue read is acquired before `release_all_scopes`. A call result moves. |
| Discarded temporary | `Statement::Expression` releases `owned_temp_type(expr)`. Arguments that are owned rvalues are released after the call (`owned_arg_temps` in `codegen_call`). The receiver of `f().x` or `f()[i]` goes on `deferred_temps` and is released at the end of the full expression by `flush_deferred_temps`. Ternary arms use `codegen_expr_in_arm`. |
| Tuples | Same rules, same call sites: `Tuple.__acquire`/`Tuple.__release` step each reference element (§4.3). A destructuring binding moves its element out of the hidden tuple. |
| Value structs | Same rules, same call sites, as for tuples: `V.__acquire`/`V.__release` step each reference field (§4.5). A method's `this` is the receiver's address, so it does no count work; a constructor's `this` is a local released at scope exit. |
| Trait values | Same rules, same call sites: `Trait.__acquire`/`Trait.__release` are thunks into the vtable (§4.2), so the concrete type's `__release`, and at zero its `__dtor`, run. `ToTrait` does no refcount work of its own: converting an lvalue read acquires as the read would, and an owned rvalue moves. |
| Destruction | At zero, `__release` calls `__dtor`, which runs the user's `destruct` body, then the field releases added by `release_field_refs`. `__release` then drops the strong references' weak reference and frees the object if `__weakcount` reached 0. |
| Closures | `MakeClosure` is an owned rvalue like the constructor call it wraps (`make_shared`): each captured value is a constructor argument, acquired into its field. The value's type is the function type, so every other row applies through `__function<…>.__acquire`/`__release`. At zero, the function type's `__dtor` calls `__destroy`, the closure's `__dtor`, whose `release_field_refs` releases the captures. |
| `std::weak_ptr<T>` | `__weak<T>` (`passes/weak_types.rs`): a synthesized struct that is a view of `T`'s two head fields, so the rows above apply to weak slots through its `__acquire` (`++__weakcount`) and `__release` (`--__weakcount`, free at 0), atomic when `T` is `[Shared]`. `__weak_from<T>`, `__weak_upgrade<T>` and `__weak_expired<T>` are `Expression::Weak` nodes (`codegen_weak`); the first two are owned rvalues. `__weak_upgrade` is a compare-and-swap loop that increments the strong count only while it is non-zero (`weak_ptr::lock`). `check_function_types` rejects implicit `T` ↔ `__weak<T>` conversions. |
| Threads | Counts are plain by default. A `[Shared]` struct (`StructDef::is_shared`) and every `shared` function type (`shared (T) => R`) step them atomically (`CountStep`), like `std::shared_ptr`'s control block; plain function types count plainly. `passes/check_shared_types.rs` keeps non-thread-safe values (plain function values included) out of shared structs and globals, and `passes/shared_functions.rs` lets a closure become `shared` only when its captures are thread-safe, and wraps a `shared` value used as a plain one in a plain adapter that holds it (a struct holding a `shared_ptr` field). |
| By-value parameter the caller copies | For a parameter listed in `Module::caller_copies` (a `String` parameter the function neither keeps nor changes, `passes::static_strings`), the caller constructs and destroys the copy around the call, as the Itanium C++ ABI does: `copy_argument` (from `pass_argument` and `default_temp`) acquires an lvalue argument before the call and puts it on `owned_arg_temps`, released after; an owned temporary is the copy; a shared string literal (`StaticString`) needs none. The callee neither acquires nor tracks the parameter (`codegen_function_unlocated`, `copied_params`). Passing such a parameter on to another one copies it with `guarded_step`, which leaves a count at or above `STATIC_REFCOUNT` alone, since it may be a shared literal (`guarded_temps` releases it the same way). |

Debugging aids: set `PEP_CHECK_SYNC` to make every `MutexGuard.exit`
check, before it unlocks, that nothing outside the locked value refers into
it. `exit` calls the `__census<T>(slot, waiting)` intrinsic, which
`copies::synthesize_copies` lowers to `_pep_check_sync<T>` (`copy.pep`) for
a `T` that is not thread-safe and can be copied, and to nothing otherwise.
`_pep_check_sync` copies the value through its own `_Copies` context (installed
like an outermost `copy`'s, and the previous one restored after) whose `_edges`
counts, per original object, the references `_copy_object` passes through
(the slot's included), then compares each object's strong count with its
tally and panics on a difference. Each holder asleep in `Condition.wait`
keeps its `with` binding, one more reference to the root: the Mutex counts
them (`_waiting`, which `wait` and `wait_for` step around the sleep) and the
census adds them to the root's tally. The flag `_PEP_CHECK_SYNC_ON` is read
once, in `internals.pep` (module constants initialize file by file, and
that file's allocation counter must exist before any `String` is built).

`_pep_live_allocs()` counts live
allocations: the sum of 61 atomic counters on separate cache lines, one
picked per thread by its id, so threads allocating concurrently do not
contend for one cache line;
leak-census tests (`crates/pepper-driver/tests/integration/shared_ptr_semantics_tests.rs`)
read it through the JIT. The counter lives in a runtime global, and every
JIT engine has its own copy of the runtime, so each test counts only its own
program's allocations and census tests run in parallel with no lock.

---

## 6. Diagnostics (`crates/pepper-parser/src/diagnostic.rs`)

The standard is in AGENTS.md ("Compiler errors are clang-style
diagnostics"). The mechanics:

- `FileId(u32)` indexes a `SourceMap`. `Loc { file, span }` has a
  `Loc::NONE` value for nodes the compiler synthesized.
- `Diagnostic { severity, message, loc, notes }` has the builders
  `Diagnostic::error(msg).at(loc).with_note(msg, Some(loc))` and `or_at`.
- Rendering spells mangled private names as written
  (`pepper_parser::namespace::demangle`), so messages may name model
  types and functions directly, **in single quotes**: only quoted names
  are demangled, so a path or string holding an `@` is left alone.
- Rendering goes through the `Sources` trait, which is implemented by
  `SourceMap` (`module.sources`, filled by `compiler::merge` in load order,
  so `FileId(i)` is `program.files[i]`) and by `Program`. `render_in(name,
  text)` handles a single file. `colorize` and `is_rendered` are used by
  `src/main.rs`.
- Each layer reports errors its own way: the parser through
  `expected`/`cut_expecting`, the builder by returning `Diagnostic` with
  `.at(loc(span))`, passes through `errors::report`, codegen through
  `Err(String)` plus `locate`, and linking through `ModuleError` and
  `VisibilityError`, each with a `to_diagnostic` method.
- Warnings exist only as deprecations, and never stop a compile. Every
  one has the code `deprecated`, and may carry a `Fix` whose `Edit`s replace
  source spans; the renderer prints the fix under the caret, and the
  language server offers it as a quick fix. There are two kinds:
  - Deprecated syntax: the parser's `deprecated_syntax` builds
    `Diagnostic::deprecated(what, instead, loc, fix)` (always with a fix)
    into `ast::Module::warnings`. The book lists these in
    `docs/src/language/compiler-errors.md`.
  - Uses of a declaration marked `[Deprecated("message", "replacement")]`
    (`crates/pepper-sema/src/deprecation.rs`):
    `Diagnostic::deprecated_declaration(name, message, loc)` plus a note at
    the declaration and, with a replacement, a fix renaming the use. The
    builder validates the attribute (`deprecation_of`; errors at the
    attribute or argument). `deprecation::check_uses` walks the linked ASTs
    (a `ScopeWalk`) for top-level names, as values and types and in import
    lists; `passes::check_deprecated_members` finds member uses on the
    model, which knows receiver types.
- How warnings flow: `Program::warnings()` is the parser's warnings plus
  `check_uses`; `compiler::merge` seeds `module.warnings` with them, the
  passes append the member warnings, and `compiler::compile` prints
  `module.render_warnings()` (sorted by location) after the passes, whether
  or not they failed. The LSP publishes the ones located in the open
  document (`deprecation_warnings` in `tools/lsp/src/main.rs`).

---

## 7. Runtime (`runtime/`)

| File | Contents |
| --- | --- |
| `internals.pep` | C externs (`malloc`, `memcpy`, `puts`, …; none exported, so a runtime file that needs one declares it itself), `assert`/`panic` (each overloaded on a `String` or `__ptr<char>` message; a string literal picks the pointer one) and the internal `char*` forms `_pep_assert`/`_pep_panic` that compiler-generated checks call (`_pep_panic(message, location)` flushes stdout and writes `location: panic: message` to stderr with `write`/`_write`, then aborts), `_pep_malloc`/`_pep_free`/`_pep_realloc`/`_pep_live_allocs`, `_pep_hash_bytes` (FNV-1a), and UTF-8 helpers. `print(text: String)` and `print<T>(value)` are ordinary functions in `string.pep`. |
| `string.pep` | `String` (fields `_data`, `_length`, `_size`, `_version`), `StringIterator`, `StringBuilder`, the `to_string` overloads (integers, `bool`, and the generic `to_string<T>` calling `value.to_string()`), the `ToString` trait, and `_pep_interpolate<T>`, which interpolated strings call. |
| `float_parse.pep` | `_float_correct`, which `double.parse` runs on Windows only (`_number_strtod` in `number.pep`): the C runtime's `strtod` there is sometimes one unit in the last place off, so it compares the exact decimal with the midpoints around the result in 32-bit-limb big integers and steps to the nearest double, ties to even. Up to 15 digits with a power of 10 up to 22 take Clinger's fast path, computed in Pepper because the C runtime misses some of those too. |
| `float_text.pep` | `_float_text`, the shortest text that reads back as a `float` or `double`, which `to_string` and interpolation call: a port of Ryu's `d2s.c` with its small tables (`_float_tables`, 125 words stored one by one at start-up, since module constants initialize before the allocation counter), run with a float's mantissa width and bias for a `float`, then laid out as Swift prints a number. |
| `attributes.pep` | The built-in attributes (`Deprecated`, `Target`, `Link`, `Shared`, ...) as `[Attribute]` structs, so `static` blocks read their values (§2.8); the compiler acts on them by name. |
| `array.pep`, `hash.pep` | `Array<T>` (also written `T[]`), `HashMap`, `HashSet`, and their iterators. Both hash containers hold one `[Value] _HashTable<K, V>` inline; a `HashSet`'s values are the empty `_NoValue`, whose stores `sizeof<V>()` guards drop. |
| `map.pep`, `ordered_map.pep` | `compare<T>` (the generic asks `<`; `compare<String>` overrides it) and the sorted `Map`/`Set` over one `[Value] _RedBlackTree<K, V>`: a CLRS red-black tree whose nodes live in parallel arrays addressed by index (0 is the black sentinel), so links are plain integers with no reference cycles, and removed nodes go on a free list. `OrderedMap` keeps entries in insertion-order arrays with a `_HashTable<K, ulong>` from key to position; removal leaves a hole that iteration skips, compacted once holes outnumber entries. |
| `iterator.pep` | `Iterator<T>` and `Iterable<T>` traits, the `for` protocol (`next()`/`current()`, `iterate()`). |
| `scoped.pep` | `Scoped<T>`, the `with` protocol (`enter()`, and `exit()` called from the destructor). |
| `weak.pep` | `Weak<T>` over `__weak<T>`; implements `Scoped<T>` (`enter()` upgrades). |
| `handle.pep` | `Handle<T>`, a raw resource (a C library's object) with a release closure that runs once, from the destructor or `release()`; `detach()` keeps it from running. |
| `result.pep` | `Error`, `None`, `Result<TValue, TError=Error>`. |
| `uri.pep` | `Uri`: RFC 3986 URI references (any scheme, or none) split into their components, `Uri.decode` for percent-escapes. `http` parses URLs and request targets with it. |
| `copy.pep` | `copy<T>`, `register_copy<T>`, the `Copyable<T>` trait (`copy(): T`), the internal `_Copies` context (original-to-copy addresses, deferred weak fixes) with the thread-local key that points at the running copy's (`_pep_copies()`, `_copy_enter`/`_copy_leave`; the key is made on first use, since every program loads the file), the deprecated alias `Copies`, and `_pep_check_sync<T>`, the `PEP_CHECK_SYNC` census. `_Copies.copy<T>` is the `__copy<T>` intrinsic that `passes/copies.rs` lowers. `String`, `Array`, `HashMap`, `HashSet`, `Map`, `Set` and `OrderedMap` implement `Copyable` with `copy()`; `io.File` is `[NotCopyable]`. |
| `process.pep` | `arguments()` and `exit(code)`, and `_pep_arguments()`, which a `main(args: String[])` receives through `entry_point` (§ pass 0a). The C `main` the compiler emits takes no `argc`/`argv`, so `arguments()` asks the platform: `/proc/self/cmdline` on Linux, `_NSGetArgc`/`_NSGetArgv` on macOS, `__p___argc`/`__p___argv` on Windows. `exit` flushes the C streams and calls `_Exit`, since the exported name takes C `exit`'s. |
| `number.pep` | A static `parse(text)` on every number type, in `extend int { ... }` extensions (lowered by `value_types::lower_extensions`, pass 0): the integer types take a base from 2 to 36 and share `_parse_signed`/`_parse_unsigned`; `float` and `double` check the decimal syntax themselves (`_is_decimal`) and then call C's `strtof`/`strtod` for correct rounding (on Windows `double` corrects `strtod`'s result with `_float_correct`), rejecting an overflow to infinity. |
| `io/` | The `io` module (`import io`): `module.pep` re-exports the public API. `types.pep`, `path.pep`, `file.pep`, `directory.pep`, `address.pep` (`IpAddress`, `SocketAddress`, `resolve`; parsing and formatting in pure Pepper) and `socket.pep` (`TcpListener`, `SharedTcpListener`, `TcpStream`, `SocketTransfer`, `UdpSocket`, the shared sockaddr encoding, `_SockAddr`, a sockaddr with its length that frees its buffer with the value, and the `_io_stream_*`/`_io_socket_*`/`_io_listener_accept` helpers that take a socket handle and do each method's work, closed-socket check included, so every stream and listener method in both files is a one-line delegation on its `_handle`), `stream.pep` (the `Reader` trait, whose `lines()`/`chunks()` defaults return the `Lines`/`Chunks` iterators over a `Reader` value, and the `Writer` trait, whose `print`/`print_line` defaults call `write_all(u8[])`; both declared on `File`, `TcpStream` and `UnixStream` there and on `TlsStream` in `tls/stream.pep`, and the http connection reads and writes through them), `memory.pep` (`ByteReader` and `ByteWriter`, a `Reader` over an array and a `Writer` into one), `print.pep` (the deprecated `Print` trait) and `unix.pep` (`UnixListener`, `SharedUnixListener`, `UnixStream`: the same `_io_sys_socket_*` calls on an `AF_UNIX` socket from `_io_sys_socket_open_unix`, with a sockaddr_un `_SockAddr` passed to `_io_sys_socket_bind_raw`/`_connect_raw`) implement it. Scratch memory a system call wrapper hands to C (stat buffers, poll descriptors, path buffers) is an `_IoBuffer` local (`types.pep`) whose destructor frees it, so no early return frees by hand. `sys_posix.pep`/`sys_windows.pep` hold the file-system platform layer and `socket_posix.pep`/`socket_windows.pep` the socket layer (BSD sockets and `getaddrinfo`; Winsock through `ws2_32`, started once with `WSAStartup`, sockets created overlapped for the planned IOCP driver). Sockets are non-blocking on every OS: a call that would block waits in `wait.pep`'s `_io_socket_wait` and retries. `wait.pep` is the seam to the task runtime (`async` imports `io`, so `io` cannot import `async`): `async.run` registers its worker as the thread's `_IoWaiter` (a trait `io/module.pep` exports under `_` names for `async` only), which parks the task; with none, or outside a task, the wait is `poll()`/`WSAPoll()`. The waiter also hears when a socket closes (`_forget`), moves to another thread (`_release`, from `into_transfer`), or is done with for now (`_release_idle`, after each `SharedTcpListener.accept`, so that a worker watches a listener other threads may close only while it waits on it). |
| `async/` | The `async` module (`import async`): `atomic.pep` (`Atomic<T>` over the `__atomic_*` intrinsics; `[Shared]`, so its `T` must be thread-safe. `io` uses it too, so `io` and `async` import each other: module imports may form a cycle), `thread.pep` (`Thread`, `ThreadId`, `ThreadBody`, the `_async_thread_main` entry point passed to the OS with `__function_pointer`), `thread_local.pep` (`ThreadLocal<T>` over OS thread-local keys whose destructor is its static `_release_slot`, and the `[Isolated]` `ThreadLocalGuard<T>` that `enter()` returns for `with` access), `cpus.pep` (`logical_cpus`, `physical_cpus`), the synchronization types in `mutex.pep` (`Mutex<T>`, `MutexGuard<T>`, `Condition<T>`), `once.pep` (`Once`, `Lazy<T>`) and `channel.pep` (`Channel<T>`, `ChannelIterator<T>`), `select.pep` (`Select<E>`), `sync_wait.pep` (how tasks wait on them), `task.pep` (tasks: `run`, `Task<T>`, `spawn`, `spawn_on_each_worker`, `run_blocking`, `sleep`, `yield_now`; see below), and the platform layer in `sys_posix.pep` (pthreads and pthread mutexes and condition variables, `clock_gettime`, `sysconf`, sysfs topology through `io`, `sysctlbyname`) and `sys_windows.pep` (`CreateThread`, `FlsAlloc`, `SRWLOCK` and `CONDITION_VARIABLE`, `GetTickCount64`, `GetLogicalProcessorInformationEx`). The synchronization types are `[Shared]`: platform locks live in fixed heap blocks (`const __ptr<void>`), and state that changes lives in raw heap slots read and written only under the lock. `Lazy` stores its value behind a `const __ptr<T>` field, so `check_shared_types` accepts only a thread-safe `T`. `Mutex` accepts any struct `T` (its slot is a `__ptr<void>`): its `MutexGuard<T>` is `[Isolated]`, so `check_confinement` keeps the locked value apart from the rest of the program, and its constructor and `replace` take `[Move]` values and `move` them into the slot under the lock, with no copy. `Channel` accepts any `T`: its buffer is a `__ptr<__ptr<void>>`; `send` and `try_send` take `[Move]` values and move them into the buffer under the lock, and `_pop` moves them out. A Mutex records its holder's id (`_async_holder_id`: the OS thread id, or in a task a per-task token above 2^62) to panic on a re-lock and to check `Condition.wait`'s caller. In a task, a wait on a `Mutex`, `Condition` or `Channel` parks the task instead of the thread (`sync_wait.pep`): the task adds a one-shot `[Shared]` `_SyncWaiter` (its worker's inbox and task id) to the object's `_SyncQueue` and parks in `_async_sync_park`, registered in the worker's `_sync_waits`; whoever unlocks, notifies, sends or receives also calls the queue's `_wake_one`/`_wake_all`, which CAS the waiter from waiting to woken and wake the task directly on its own worker or with a `_Message.Wake` to its inbox. A waiter that gives up (cancel, timeout) CASes to abandoned and leaves the queue, so no wake is spent on it. A `Select<E>` (`select.pep`) waits on several channels with one waiter: it looks at each case in turn from `_next` (`_SelectCase<E>`, a private trait implemented by `_ReceiveCase<T, E>`, the channel plus its `wrap`; `Channel._select_take` takes a value under the channel's lock), then joins every open channel's `_receivers` queue with one waiter (`Channel._select_join`, which declines when a value is already there and skips a closed channel, so it never sleeps on nothing and never spins), sleeps, leaves every queue and looks again. A plain thread's waiter carries a `_ThreadWake` (a platform lock and condition): `_async_sync_wake` signals it, and the thread sleeps in `_async_thread_park`. `Condition.wait_while` asks its `[Locked]` predicate with the locked value and calls `wait` while it returns true. `Mutex` in a task only ever `try_lock`s the platform lock (push a waiter, try again, park), so the lock and unlock stay on the task's one thread. `Thread.sleep` in a task calls `_async_task_sleep`. `task_local.pep`'s `TaskLocal<T>` keeps each task's value in a malloc'd slot listed in `_TaskCore._locals` (found by the variable's id, released by a closure when the body returns) and, outside a task, in a `ThreadLocal<T>`; `check_confinement` treats its `get` like `ThreadLocal.get`. Tasks (`task.pep`): `run` makes a `_Worker` (ready queue, timer min-heap, idle fibers) and publishes it through a raw thread-local key (`_async_worker_key`). Every fiber runs `_async_fiber_main`, a loop that runs the task the worker assigned it and switches back to the scheduler, so fibers are reused and no fiber entry returns; the loop calls a function that returns, so a finished task's frame holds no references. A waiting task is `_parked`; waking re-queues it once, and a timer carries its sleep's sequence number so a stale one wakes nothing. Fibers are `fiber_posix.pep` (mmap stack with a guard page, and the `__switch_context` / `__prepare_context` intrinsics that `pepper-codegen/src/context.rs` defines as naked assembly for x86-64 System V and AArch64) and `fiber_windows.pep` (the Fibers API). The worker is also the thread's `io._IoWaiter`: a socket that would block is watched by the worker's `_Driver` (`driver.pep`: a trait chosen at run time from the `Backend` enum, `RuntimeOptions.backend` or `PEPPER_IO_BACKEND`; every driver type exists on every OS, with `[Target]`ed system calls and failing stubs elsewhere). `driver_epoll.pep` and `driver_kqueue.pep` register each socket once, edge-triggered; `driver_io_uring.pep` arms one multishot `IORING_OP_POLL_ADD` per socket in `_want`, for the directions tasks wait on (widened when a task waits the other way, re-armed for still-parked directions when the kernel ends it), on a ring made with `IORING_SETUP_DEFER_TASKRUN` (else `COOP_TASKRUN`) so wakeups from other CPUs do not interrupt the worker (user data is a per-driver request number, so completions for a closed, reused descriptor are dropped; `_forget` submits `IORING_OP_POLL_REMOVE` at once because a pending poll holds the file open), over raw `io_uring_setup`/`io_uring_enter` syscalls, one mmap for both rings, `__atomic_load`/`__atomic_store` on the ring indices, and `IORING_ENTER_EXT_ARG` for timed waits; `driver_iocp.pep` sends a one-shot AFD poll request (IOCTL_AFD_POLL through a `\Device\Afd` handle, as mio and libuv do) per socket and direction when a task starts waiting (`_want`), whose completion arrives on an I/O completion port; `driver_poll.pep` hands `poll()`/`WSAPoll` every waiting socket on each wait. A driver's `_poll` appends each ready socket to the worker's `_ready_sockets`, an `Array<(handle: ulong, interest: int)>`, and `_finished_files` appends `(task, result)` tuples, both read with index loops (a `for` would allocate an iterator on this path). The task parks in `_waits` until an event wakes it; the loop blocks in the driver when no task is ready and polls it every `_POLL_INTERVAL` tasks otherwise. `timeout` returns a `Deadline` (a `Scoped`) that sets the task's `_deadline`, and every wait arms a timer for it. Several workers (`workers.pep`): `run_with` makes a `[Shared]` `_Runtime` and one `_Worker` per `RuntimeOptions.workers` (the calling thread plus `Thread`s); each worker stores an `_Inbox` (a `Channel<ulong>` of `id * 4 + kind` messages, kind a `_Message` and its driver's `_Doorbell`: eventfd (epoll, io_uring), `EVFILT_USER`, `PostQueuedCompletionStatus`, or a self-pipe / loopback UDP socket rung from a second socket for poll) in the runtime, plus a `_pinned` queue for `spawn_on_each_worker`'s tasks, which a worker takes before the shared queue (and hands to the shared queue if one arrives after it stopped). `spawn<T>` is a free function so that only its callers instantiate `_TaskResult<T>`, whose `__ptr<T>` field makes `check_shared_types` require a thread-safe `T` (the error follows the specialization out to the user's call, `user_use_site`); it queues a `_SharedTask` on the runtime's shared queue and gives the caller a stand-in `_TaskCore` (`_proxy`) that finishes when the running worker sends `_Message.Complete`. Idle workers take unstarted tasks from the queue; started tasks never move. Cancelling a spawned task sets its atomic flag and sends `_Message.Cancel` to the worker running it. A worker about to block sets `_sleeping`, clears `_notified` and re-checks its inbox and the queue; senders ring the doorbell unless `_notified` is set. When the first task returns the runtime stops: every worker cancels its tasks, runs until none are left, and waits for the others (`_leave`) before closing its driver, so no doorbell rings a closed handle. File reads and writes in a task go through `io._io_file_transfer` (io/wait.pep): the worker's `_file_transfer` hands a `[Shared]` `io._FileTransfer` to the driver's `_start_file` (io_uring: `IORING_OP_READ`/`WRITE` at offset -1, the file's position, results back through `_finished_files`) or, when the driver declines (every other backend), to `run_blocking`; the task parks, uninterruptible, and the file methods pin their array (`Array._pins`, checked in `reserve`) for the duration. `run_blocking` queues its body on the runtime's `_blocking` channel and parks on a stand-in; `_Runtime._block` claims an idle pool thread or tells the worker to start one (up to `RuntimeOptions.blocking_threads`, joined by that worker when the runtime ends), and the pool thread (`_async_blocking_main`) reports `_Message.Complete` like a worker. |
| `math/` | The `math` module (`import math`): `parse.pep` (`parse_int`, deprecated: a wrapper over `long.parse`). The home for numeric functions beyond the operators. |
| `regex/` | The `regex` module (`import regex`): `regex.pep` (`Regex`, `Match`, `Matches`), over `syntax.pep` (a recursive-descent parser of RE2 syntax into `_RegexNode` trees, groups nested at most 250 deep; character classes are sorted, merged code point ranges packed as `lo << 32 \| hi`, with case folding and negation applied at parse time), `compile.pep` (Thompson construction, through a growable `_RegexBuilder`, into a `[Shared]` `_RegexProgram` (its arrays frozen into heap blocks behind `const __ptr` fields, so `Regex` is `[Shared]` too) of `SPLIT`/`JUMP`/`SAVE`/`ASSERT`/`CHAR`/`CLASS` instructions, at most 100,000) and `vm.pep` (`_RegexMatcher`, a Pike VM: sparse-set thread lists with per-thread capture slots, leftmost-first priority order, and an explicit stack for following epsilon edges, so no search recurses or backtracks). Positions are byte offsets; text is decoded one code point at a time. |
| `json/` | The `json` module (`import json`): `value.pep` (`JsonValue`, a reference enum with indexers that give `Null` on a miss; `_JsonWriter` writes compact or indented text from an explicit stack of `[Value] _JsonStep`s, keeping its punctuation in fields because a string literal allocates each time it runs) and `parse.pep` (`parse`, `JsonError`; `_JsonParser` is a loop over an explicit stack of open containers and pending keys, bounded by `max_depth`, that checks UTF-8 up front with `text.Utf8.find_invalid` and copies strings without escapes whole; with `_notes` it tracks each value's path and files the comments it skips in a `_JsonComments`, by path, before, after or at the end of a value) and `document.pep` (`JsonDocument`, a root plus its `_JsonComments`, written back by `_json_write_commented`, whose steps carry the paths). |
| `compress/` | The `compress` module (`import compress`): `format.pep` (`Format`; `Deflate`, `Zlib`, `Gzip`, whose static `compress`/`decompress` run a whole array through one `_Deflater`/`_Inflater`; `DecompressReader`, `CompressWriter`), `inflate.pep` (`_Inflater`: pulls input from an `io.Reader` 64 KiB at a time into a bit buffer, reads the zlib or gzip header and trailer, several gzip members included, and decodes DEFLATE blocks into one `output` array, a state machine at block and symbol granularity so `fill(want)` stops as soon as enough output is ready; `_codes_fast` is the hot loop, like zlib's `inflate_fast`: while 8 input bytes are left it refills the bit buffer 8 bytes at a time, writes through raw pointers into reserved room and copies matches 8 bytes at a time; `_HuffmanDecoder` decodes codes of up to 10 bits with one table lookup and longer ones bit by bit over the canonical counts; the streaming reader `compact`s `output` to its last 32 KiB once 96 KiB were handed out), `deflate.pep` (`_Deflater`: LZ77 over a buffer addressed by absolute stream position, hash chains of three-byte hashes over a 32 KiB window holding 32-bit positions, and zlib's per-level table of chain length, good, lazy and nice lengths: levels 1-3 take the first match and leave long matches' positions out of the chains (`deflate_fast`), levels 4-9 match lazily (`deflate_slow`); `_find` compares candidates 8 bytes at a time with `trailing_zeros`; each block of up to 16384 tokens is written stored, with the fixed codes or with dynamic codes, whichever is smallest, through a 64-bit bit buffer stored 8 bytes at a time; `_compress_code_lengths` builds Huffman code lengths with the two-queue method and limits them to 15 or 7 bits) and `checksum.pep` (`Crc32`, slicing-by-8, and `Adler32`; `_compress_load_64`/`_compress_store_64`, little-endian 8-byte loads and stores that LLVM turns into single unaligned ones). `benchmarks/compress/` holds `bench.py` (speed and size against the `gzip` command) and `check.py` (round trips against Python's zlib, corrupt input). Corrupt input is an `io.IoError` with `io._io_sys_code_invalid_input()`. |
| `archive/` | The `archive` module (`import archive`): `tar.pep` (`TarEntry`, `EntryKind`; `TarReader`, an `io.Reader` of the current entry's contents that reads ustar headers, GNU `L`/`K` long names and pax `x` records, skips pax `g` headers, and `extract`s with `_tar_safe_components` refusing absolute paths and `..`, `\` and `:`; `TarWriter`, which splits a long path into the ustar prefix or writes a pax header first). It reads and writes through `io.Reader`/`io.Writer`, so `.tar.gz` is a `compress` stream around it. |
| `text/` | The `text` module (`import text`): `Utf8`, `Utf16` and `Ascii` (`utf8.pep`, `utf16.pep`, `ascii.pep`), each with `encode`, a strict `decode` (none on invalid input) and `decode_lossy` (U+FFFD). Built on `String._utf8_sequence` and the prelude's `String._from_bytes`, which prelude files such as `uri.pep` call directly since the prelude does not import modules. `io.File.read_string` and http decode through it. |
| `tls/` | The `tls` module (`import tls`): `stream.pep` (`TlsConnector`, `TlsAcceptor`, `TlsStream`) over a `_tls_sys_*` layer in `openssl.pep` (Linux, macOS) and `schannel.pep` (Windows: SSPI over buffers, checking the server's certificate itself with `CertVerifyCertificateChainPolicy`, and importing a server's PKCS #8 key into the user's key storage provider under a per-process name that freeing the context deletes). `openssl.pep` loads libssl with `dlopen` on first use (`_OpenSsl`, a `[Shared]` table of C function pointers behind a `Lazy`), so programs link nothing extra and Homebrew's OpenSSL needs no search path. Each connection's bytes go through a custom BIO whose callbacks call `io._io_sys_socket_receive`/`_send`: those wait (parking a task) when the socket would block, so OpenSSL never sees `SSL_ERROR_WANT_*`, and an io error a callback meets is kept in the session block and returned instead of OpenSSL's report. |
| `http/` | The `http` module (`import http`): `message.pep` (`Headers`, `Request`, `Response`), `client.pep` (`Client`: parses the URL with `Uri`, opens a `TcpStream` and, for `https://`, a `TlsStream`, sends one request with `Connection: close` and reads the response), `server.pep` (`Server.serve`: `spawn_on_each_worker` accept loops on a `SharedTcpListener`, one `spawn_local` task per connection, keep-alive, `100-continue`, 400/413/431 refusals) and `wire.pep` (`_HttpConnection`, plain or TLS; `_HttpReader`, a buffered reader of lines and byte runs; header, Content-Length, chunked and read-to-close body parsing; a field line that is not UTF-8, such as Latin-1 obs-text, is read with U+FFFD in place of those bytes). |
| `process/` | The `process` module (`import process`): `command.pep` (`Command`, `Stream`, `Output`; `run()` reads standard output in the calling task and standard error on its own thread), `child.pep` (`Child`, `ExitStatus`; `wait()` runs the blocking wait through `run_blocking`, encoding the status in one `long`), `current.pep` (`arguments`, `exit`, `id`, `executable_path`, working directory), over a `_process_sys_*` layer in `sys_posix.pep` (`posix_spawnp` with file actions; close-on-exec pipes; macOS adds `POSIX_SPAWN_CLOEXEC_DEFAULT`; the inherited `environ` comes from the `os` module) and `sys_windows.pep` (`CreateProcessW` with the C runtime's argument quoting and a UTF-16 environment block; the child's inheritable handles exist only under `_process_spawn_lock`). `arguments` and `exit` are declared as `_process_arguments`/`_process_exit` and re-exported under their names, because the deprecated prelude functions in `runtime/process.pep` still hold those names until per-module export namespaces (#244). |
| `os/` | The `os` module (`import os`): `environment.pep` (`environment`, `environment_variables`; read-only, since `setenv` races with `getenv` on POSIX), `time.pep` (`Duration`, `Instant`, `SystemTime`: value structs counting nanoseconds), `machine.pep` (system name and version, architecture, host name, processor counts forwarded to `async`, memory, page size) and `user.pep` (user name, home and temporary directories), over a `_os_sys_*` layer in `sys_posix.pep` (`getenv`; `environ` through `dlsym` on Linux and `_NSGetEnviron` on macOS; `clock_gettime`; `uname`/`sysctlbyname`; `getpwuid_r`, reading `pw_name` and `pw_dir` at their per-OS offsets) and `sys_windows.pep` (`GetEnvironmentVariableW`, `QueryPerformanceCounter`, `GetSystemTimePreciseAsFileTime`, `RtlGetVersion` from ntdll, `GetUserNameW` from advapi32). The `process` module takes the inherited environment from `_os_environment_entries` and, on POSIX, `_os_environ`. |
| `cli/` | The `cli` module (`import cli`): `parser.pep` (`Parser`, and the handles `Flag`, `Argument`, `ArgumentList`). Each declaration is a private `_CliArgument` record (names, help, kind: flag, single or list, required, default, and the values and count a parse fills in) that the parser lists and its handle shares, so parsing writes what the handle reads. `_parse` walks the arguments once, left to right, and hands the rest to a subcommand's own `Parser` when it meets the command's name (recursion one level per declared command, never per input). Errors are `Result` errors; the parser that failed records its usage on the top-level parser for `parse` to print. Suggestions for misspelled options and commands use a byte edit distance (`_cli_edit_distance`, at most 2). |
| `digest/` | The `digest` module (`import digest`): `sha256.pep` (`Sha256`), `sha1.pep` (`Sha1`), `blake3.pep` (`Blake3`) and `hex.pep` (`to_hex`), each with its one-shot function, in portable Pepper with no link dependency. `words.pep` holds the shared helpers: word loads and stores, rotations, and `_DigestBuffer`, the 64-byte block buffering and Merkle-Damgård padding SHA-1 and SHA-256 share, generic over the `_DigestCompressor` trait so each hasher's `_compress` is called directly. `Blake3` is the reference implementation's algorithm one block at a time (no SIMD): the chunk state, a stack of subtree chaining values merged by the trailing zero bits of the chunk count, and a precomputed message schedule in place of permuting the words each round. |

- **Loading.** Every top-level `runtime/*.pep` is a prelude file. Its
  `export`s are visible in every program without an import. `runtime/io` is
  found as a module because the runtime directory is on the search path.
- **Naming convention for internals.** Names prefixed `_pep_` (core),
  `_io_` (io module), `_async_` (async module), `_process_` (process module), `_regex_` (regex module), `_os_` (os module), `_cli_` (cli module), `_compress_` (compress module), `_tar_` (archive module) and `_digest_` (digest module) are internals. They are `export`ed so other runtime
  files can use them. They are exempt from the documentation standard, and
  a module does not re-export them (`io/module.pep` re-exports only the
  public types).
- **Lowered by name.** Interpolated strings and `String.format` call
  `_pep_interpolate` and `_pep_format*`. A name the compiler synthesizes must be exported:
  linking mangles private names per file. Every constructor calls `_pep_malloc`, and `__release`
  calls `_pep_free` once the weak count reaches 0. Compiler-generated checks (null function and trait
  values) call `_pep_assert`, which takes a raw `char*` message and location.
  Codegen calls these by name after visibility has run, so they
  need not be exported.
- **Intrinsics available to runtime code**: `__ptr<T>` (a raw pointer, the
  only pointer spelling allowed outside `extern`), `__null`, `sizeof(T)`,
  `__default<T>()`, `__is_pod<T>()`, `__refcount<T>(x)`, `__address<T>(x)`,
  `__atomic_load/store/cmpxchg/fetch_{add,sub,and,or,xor}<T>(…)`,
  `__weak<T>` with `__weak_from/upgrade/expired<T>(…)`, and
  `__function_pointer(f)` (a C-callable `__ptr<void>` to a free function or
  a static method of the enclosing struct; also documented for users in the
  book's C chapter).
- **Documentation.** The standard is in AGENTS.md (the library documentation
  section): `##` doc comments with the tags listed above.
  `crates/pepper-driver/tests/integration/runtime_docs_tests.rs` enforces it. The
  reference pages in `docs/src/reference/` and the reference part of
  `docs/src/SUMMARY.md` are **generated** by
  `cargo run -p pepper-docgen -- reference`. CI fails if they are stale
  (`cargo run -p pepper-docgen -- check`). See `docs/src/contributing/docs.md` for the
  book.

---

## 8. Language server and VS Code extension

**`tools/lsp/src/main.rs`** (`pep-lsp`, stdio, tower-lsp):

- **Properties.** Hover and definition find a property by name
  (`infer::Kind::Property`); its accessor bodies are walked as methods
  through `PropertyDecl::accessors` (`function_at`, `infer::each`).

- **Crash safety.** `main` serves from a thread with the compiler's 8 MB
  stack (`STACK_SIZE`, also the async runtime's worker stack), which fits
  every pass on the deepest tree the parser accepts (`MAX_NESTING`, §2);
  Windows' 1 MB main thread did not. Every request (`PepperLsp::answer`)
  and background analysis computes under `guarded` (`catch_unwind`), so a
  panic answers that request with nothing instead of ending the server.
- **Requests never wait for sema** (`tools/lsp/src/analysis.rs`). Sema
  takes seconds on a program that pulls in much of the runtime, and the
  editor sends code actions on every cursor move and hovers on every mouse
  move; running it per request once queued a go-to-definition behind
  minutes of stale work.
  - `Documents` holds each open document: an `Analysis` of its current
    text (`latest`) and the newest one whose sema passed (`ready`). An
    `Analysis` loads its program and runs sema each at most once
    (`OnceLock`), so every reader of one text shares them.
  - An analysis records every file its program read, or found and failed
    to load (`Program::failed`), with its modification time.
    `PepperLsp::view` checks them before each request
    (`Documents::refresh`, about a millisecond) and schedules a fresh
    analysis of the same text when one changed; until it passes, requests
    answer from the current text without sema, since the old analysis
    would place the changed files' names as they were. The server also asks the client to watch
    `**/*.pep` (`initialized`), and `did_change_watched_files` reschedules
    the documents a change affects (`Documents::forget`; all of them when
    a file is created or deleted, since that can change what an import
    resolves to). A renewed document has no passed analysis until the
    fresh one passes.
  - `did_open`/`did_change` record the text and `schedule_analysis`: after
    the text has stayed unchanged for `SETTLE` (250 ms), one background
    analysis at a time (`Documents::running`) runs sema on the blocking
    pool, becomes `ready` if it passed (`Documents::finished`), publishes
    its diagnostics if its text is still current, and logs how long it
    took, then asks the editor to fetch inlay hints again
    (`inlay_hint_refresh`). An analysis whose text was edited before its
    turn is skipped.
  - Requests read a `View`. When `ready` is of an older text, an `EditMap`
    (the common prefix, in whole lines, and suffix of the two texts) carries
    the cursor to the old text (`to_old`, only when its line is outside the
    edit, since a name's meaning depends on its expression) and the answer's ranges in the document back
    (`range_to_new`). A name inside the edit, or with no passed analysis
    yet, is answered from the current text's parse and linked program
    (`Analysis::program`, milliseconds) with no sema model.
    `Analysis::program` loads through `PARSED`, a process-wide in-memory
    `ParseCache` (by path and text), so only files that changed are parsed
    again; the runtime's never are. Code actions
    use the current text's sema only once it has run. A hover from an
    analysis older than the current text ends with a note saying so
    (a declaration edited since may read differently), and says when the
    latest edit does not check.
  - A request slower than `SLOW_REQUEST` (200 ms) is logged to the
    editor's output (`window/logMessage`), as is the server's start.
- Each background analysis runs these checks (`PepperLsp::diagnostics`):
  1. `parse_source_diag` on the buffer (precise parse errors).
  2. Otherwise, `Analysis::program` → `load_program(Root { unsaved text },
     Setup { mode: Lenient, parsed: PARSED })`, then `sema_model_of` (build
     every file on the checked runtime (`checked::on_checked_runtime` with
     `Build::Document`; the whole program when the document is a runtime
     file), run the platform filters, `struct_body::apply`, and
     `transform_pass`
     **under `catch_unwind`**), then `visibility_diagnostics`.
     Unresolved-module imports are downgraded to warnings because the
     editor does not know the compile's `-I` directories.
  3. Warnings: the parser's, then `deprecation_warnings` (the program's
     `deprecation_warnings()` and the sema model's `warnings`, in the
     document only). `code_action` collects them again from the
     analysis (`document_warnings`) and `quick_fixes` turns each fix into
     a code action.
- **Code for other platforms** (`platforms.rs`): `inactive_regions` walks
  imports, re-exports, declarations, methods, enum cases and attributed
  blocks, and returns the outermost spans `passes::platform` drops on this
  host, mirroring it (constructors, destructors and fields are never
  dropped);
  `diagnostics` publishes each as a hint with the `Unnecessary` tag
  (`inactive_hints`), which the editor dims. An `Analysis` loads and
  checks its program for the build target's OS, unless that build leaves
  out most of the document and keeps none of another OS's code; then for
  the OS that leaves out the least of it (`Analysis::os`, `target_os`), under
  `platform::with_simulated_host`, so a Linux-only file opened on Windows
  resolves; the dimming still follows the build target, and the background
  log names the OS when it differs.
- `lsp_diagnostic` maps a `Diagnostic` to the document. A location in
  another file appears at the top of the document, prefixed with that
  file's name. Notes become `relatedInformation`.
- **Hover** (`hover_at`) and **definition** (`definition_at`) re-parse the
  buffer and find the expression or type under the cursor (`find_expr`,
  `expr_at`, `locals_at`, `body_at`). They use the sema model for member
  types and follow imports through `imports.rs` (`in_imports`,
  `in_expression`, `in_type`), which reads the `FileScope.named` and
  `imported` maps that linking recorded. Hover text includes the
  declaration's doc comment (`declaration_doc`, `member_doc` →
  `DocComment::to_markdown`). Definition of a member of any expression
  (`x.y.z`, `f().m()`) asks the sema model:
  `pepper_sema::member_lookup::member_declaration` finds the innermost
  `MemberRef` or `MethodCall` whose name covers the offset, types its owner
  with `static_type::of`, and returns the field's or method's location.
  `expr_at` starts a binary expression at its left operand (`expr_start`),
  since the parser's span for it starts at the operator.
  Hover types a local whose type is inferred (`var w = f()`) from the sema
  model (`member_lookup::local_type`, by its name's location; also on the
  name where it is declared), and a field reached through any owner by
  `member_lookup::field_type`. The locals in scope (`scope_locals`) are the
  enclosing function's parameters (`function_at`: functions, methods,
  constructors, extension methods) and what its body declares before the
  cursor. An expression statement starts at its expression's start
  (`expr_start`), since an assignment's span starts at its `=`.
- **Code sema leaves untyped** (`tools/lsp/src/infer.rs`, `Typer`). Sema
  checks only the specializations of generic code, so the body of a generic
  nothing instantiates has no types in the model (`runtime/copy.pep`,
  `async/mutex.pep` opened on their own), and patterns have no node of
  their own. Where the model has no answer, hover and definition type the
  syntax: a name from its declaration, else sema's inferred type
  (`member_lookup::local_type`, closure parameters included), else its
  initializer (constructor and call results, fields, ternaries, elements of
  an array or of what `iterate()` yields, destructuring, a closure
  parameter's place in the function type its callee or variable gives it),
  and a member from the declarations of every program file (`member`: the
  struct or enum, its extensions, the traits those add, a type parameter's
  bounds, a tuple's labels) with the owner's type arguments bound to the
  declaration's parameters. `pattern_at` answers a pattern's case (`Circle`
  of `Circle(r) =>`, from the matched value's type, else the one enum with
  that case) and the names it binds, typed by the case's values; the arms
  of `match` expressions bind their names in `scope_locals`
  (`push_match_bindings`). Its walk over a module (`each`) keeps an explicit
  stack, and typing gives up past `MAX_DEPTH` steps. Also answered from the
  syntax: a type argument written in a call (`copy<T>(x)`, which the parser
  keeps in the member's name, `type_argument_at`), a tuple's labels
  (`label_at`, `label_declared`), enum built-ins (`name`, `from_value`, at
  the enum's name), `String.format` (lowered by the parser,
  `string_format_at`), `print`, and names the parser's sugar places outside
  their parents' spans (`find_expr` falls back to the name itself).
- **Implicit conversions.** `convert_to_traits` records each conversion it
  inserts whose value has a location in `Module::conversions` (string
  literals carry their `Loc` for this, and the `String` constructor call
  they become keeps it). `hover_at` reads the sema model and appends a note when
  the offset is inside a converted value (`conversion_at`); `inlay_hint`
  returns `To(` / `)` around each one in the document (`conversion_hints`),
  unless the client's `inlayHints.implicitConversions` initialization option
  is `false`. It also returns `name:` before each literal argument passed by
  position (`parameter_hints`, from `Module::argument_names`, which
  `named_arguments::record_argument_names` fills after `check_unbound` for
  callees of two or more parameters), unless `inlayHints.parameterNames` is
  `false`.
- Completion lists keywords, globals, locals, and struct members; after
  `Enum.` it lists that enum's cases alone (`enum_cases_before`, on a parse
  with a placeholder after the dot, `parse_after_dot`, since `Color.` alone
  does not parse). Where an argument starts (after a call's `(` or a `,`),
  it also offers the callee's parameter names and `[Alias]` names not yet
  named (`argument_names`; the callee comes from the AST through
  `Typer::callees_named` or `Typer::member_access`, on a parse with a
  placeholder argument when the text does not parse). Document symbols come
  from the AST.
- Enums: hover on `Enum.Case` shows its value from the sema model
  (`enum_case_of`), or the values a case carries (`Doc.Text(text:
  String)`), or the bare case while the program does not build
  (`enum_case_in`). A `match on 'E' does not handle ...` error offers a
  quick fix that adds an empty arm per missing case before the `match`'s
  closing brace (`missing_arms_fix`, `find_match`), binding a case's values
  by their declared names.
- Runtime discovery is the same as the compiler's (section 2.2): from the
  directory the server was started in, then from the `pep-lsp`
  executable's directory, unless `PEPPER_RUNTIME` is set. In `Lenient`
  mode a missing runtime is not an error.
- Tests: `tools/lsp/src/tests.rs` builds a module tree in a temp directory
  and asserts hover and definition results. `tools/lsp/src/sweep.rs` is the
  resolution sweep: it opens real files as the editor would and asks for
  the hover and definition of every name. `clean_files_resolve` holds a list
  of files where all of them resolve; the ignored `resolution_sweep` covers
  the runtime, `docs/examples` and `tests` and writes
  `target/resolution-sweep.txt`, one line per name that does not resolve.
  A file whose every name resolves belongs in the clean list.
- Declarations answer too: hovering or going to the definition of a name
  where it is declared (`declared_at`: top-level declarations, members,
  enum cases and the values they carry, locals, parameters of any
  signature, generic parameters, any variable such as a closure's parameter
  in a default value)
  shows or goes to itself; a type name anywhere goes to its declaration in
  any file (`imports::named_type`); a call of a function another file
  declares goes there (`imports::in_expression`); locals inside closures
  include the closures' parameters (`closure_in_block`). `tools/lsp/smoke-test.mjs`
  exercises raw JSON-RPC.

**`tools/vscode-pepper`**: `src/extension.js` launches the server. It runs
a *shadow copy* of the binary because Windows locks a running exe (copied
under a temporary name, then renamed), polls the binary and restarts on
change, and registers `pepper.restartServer`. Restarts are serialized,
retry a failed start, and reuse one output channel.
The server comes from `pepper.lspPath` or from the bundled
`server/<platform-arch>/` (`serverPath.js`). Syntax highlighting is
`syntaxes/pepper.tmLanguage.json`. `vsix.yml` builds the VSIX for four
targets (x64 Windows and Linux, x64 and arm64 macOS) and publishes it as
a `vsix-v*` release; it runs only for a `vX.Y.Z` tag or a manual dispatch.
`scripts/install-vscode-extension.ps1 [-Watch]` builds `pep-lsp` in
release mode, packages the VSIX with `npx @vscode/vsce`, and runs
`code --install-extension` from the current branch.

**`tools/syntax` and `tools/pep-fmt`** are Pepper programs, built with
`pepper build -I tools tools/pep-fmt/main.pep`. They are the project's largest
dogfooding of the language.

- `tools/syntax` (a module: `module.pep` is four `export * from` lines) is a lexer
  (`lexer.pep`, `token.pep`; an interpolated string `$"..."` is one
  `TOKEN_STRING`) and a recursive-descent parser (`parser.pep`)
  that builds a *lossless* tree (`tree.pep`): every token is a leaf, in
  source order, and each comment hangs off the token next to it (a comment
  on the same line after a token is its `trailing_comment`, any other is an
  entry in `leading_comments` of the next token). Nodes are uniform (`kind`, `leaf`,
  `children`): `kind` is a `NodeKind` (a token's is a `TokenKind`), and
  the formatter dispatches on it with `match` (`_node`, then `_expression`,
  whose `else` prints any other node's parts in order).
- The parser mirrors `parsers.rs` decision for decision; like it, it
  treats line breaks as whitespace except at a declaration missing its `;`
  (`_declaration_boundary`, using the next token's `newlines_before`), and
  `_finish_statement` reports a missing `;` right after the statement, over
  any error found further on, as `missing_semicolon` does.
  `>` is always its own token; the parser
  joins adjacent ones into `>>`, `>=` and `>>=` where the compiler's
  grammar would read those operators.
- `tools/pep-fmt` turns the tree into a Wadler-style layout document
  (`doc.pep`: text, soft and hard lines, indentation, groups, and a
    `DocKind.Choice` of layouts tried in order) and renders it at 120 columns;
    `format.pep` holds the style; a long binary
  expression breaks before each operator, and `_member_chain` breaks a chain
  of three or more calls before each `.`. Trailing comments are emitted as line
  suffixes marked with byte 0x01, which `align_trailing_comments` aligns and
  removes. `_format_off` copies a `# format: off` region from the source by
  the comments' offsets, at the top level and in `_braced` item lists.
- `pep_fmt_tests.rs` compiles pep-fmt and runs it on every `.pep` file in
  the repository: each must format, be idempotent, and give the same AST
  (the compiler's `Display` of `Module`, imports sorted) before and after.
  So a grammar change to `parsers.rs` that `tools/syntax` does not mirror
  fails there. The tool's own sources and `runtime/` must be pep-fmt formatted.

---

## 9. Tests

`cargo test --workspace` runs everything. Without `--workspace`, only the
root package's test runs. The suite has roughly 810 `#[test]` functions.

| Kind | Where | Notes |
| --- | --- | --- |
| Parser unit | `crates/pepper-parser/src/parser/parsers.rs` (`mod tests`), `parser.rs`, `diagnostic.rs`, `doc.rs` | Helpers `parse`, `parse_expr`, and `parse_type` take the `track_source` guard. `parser.rs` tests pin exact rendered parse errors. |
| Sema model | `crates/pepper-sema/src/model_tests.rs`, `visibility.rs` tests | `compile()` = parse → `build` → filters → `struct_body::apply` → `transform_pass`, then assertions on the model. |
| Codegen JIT | `crates/pepper-codegen/tests/codegen_tests.rs`; `target.rs` unit test | JIT `test()`, check the returned `i32`. |
| Driver integration | `crates/pepper-driver/tests/integration/*_tests.rs` (arrays, strings, hashes, io, modules, visibility, platform, atomics, function values, iterators, `with` blocks, shared_ptr semantics, C arithmetic semantics, store types (`store_type_tests.rs`), edge cases, docs-audit regressions in `audit_fixes_tests.rs`, …) | Usual shape: `compiler::compile_with_runtime("test.pep", src)` → `CodeGenerator::jit_execute(&mut m, "test")`, asserting 0 (each check returns a distinct negative code). `compile_with_runtime` checks the program against the checked runtime (§2), as the CLI does. Multi-file tests (`module_tests.rs`, `diagnostic_tests.rs`) write a tree to `temp_dir()` and compile through `Options::parse_from` + `compiler::compile`. `platform_tests.rs` uses `with_simulated_host`. `corpus_tests.rs` and `link_tests.rs` link real executables. |
| Diagnostics | `crates/pepper-driver/tests/integration/diagnostic_tests.rs` | `error_of(name, src)` returns the full rendered error (header, source line, caret). Add one for every new error. |
| Corpus | `tests/*/test.pep` | `corpus_tests.rs::corpus_files_compile_and_run` checks (visibility included), compiles, links, and runs each fixture with `-I tests`. `pep_fmt_tests.rs` parses and formats every file under `tests/`. |
| Runtime discovery | `crates/pepper-files/src/runtime.rs` (`mod tests`) | Calls `discover_from` with a cwd outside the checkout and an executable directory inside it. |
| Runtime docs | `crates/pepper-driver/tests/integration/runtime_docs_tests.rs` | `check_documented` over every `runtime/**/*.pep`. |
| Docs examples | `crates/pepper-driver/tests/integration/docs_examples_tests.rs` | Compiles and runs every `docs/examples/*.pep` (or `name/main.pep`) through `pepper_driver::run`. Filter with `PEPPER_DOCS_EXAMPLE=prefix`. |
| Determinism | `crates/pepper-driver/tests/integration/determinism_tests.rs` | Compiles every docs example twice (the second round in reverse order, across threads) and requires identical IR. |
| Build cache | `crates/pepper-driver/tests/integration/build_cache_tests.rs` | Emits programs as unit objects through a scratch cache, verifying every hit: unchanged units hit and are byte-identical, the runtime unit is shared between programs, a mismatched record misses, an edit rebuilds only its unit (importers reuse their objects when their code is the same), a comment edit reuses the object, an override in a file a unit never imports is in its key, and concurrent builds share one cache. Without verifying, sema skips hit units' bodies (not one whose return type is inferred), a unit that warned keeps its bodies and warns again, skipping the runtime's bodies changes no other unit's code, and a skipped body's recorded link summary stands in for it. |
| LSP | `tools/lsp/src/tests.rs` | See section 8. |
| xtask, docgen | `xtask/src/main.rs`, `tools/docgen/src/site.rs` | Unit tests. |

To run a subset:

```bash
cargo test --workspace --test integration module_tests::  # one driver module
cargo test --workspace utf8                           # name substring
cargo test -p pepper-parser                           # one crate
cargo test --workspace --no-default-features --features llvm19-1
```

Harness gotchas: runtime discovery and several harnesses `chdir` to the
repository root (a process-wide change; every test sets the same
directory). Temp directories are named after the module and test, so give new tests
unique names.

The driver's integration tests are modules of one test binary
(`tests/integration/main.rs`): add a new file there as a module, not as a
new `tests/*.rs` binary. Each binary statically links LLVM, so every extra
one costs a link, and on macOS Gatekeeper scans each freshly linked
executable on its first run (about 2s apiece on the CI runner, where it was
most of the `test-macos` job).

Keep the suite parallel. Cargo runs test binaries one after another, so a
test that loops over many programs (every example, fixture, or simulated
host) is wall-clock time for the whole suite: spread the loop with
`support::parallel_map` (`crates/pepper-driver/tests/integration/support/mod.rs`,
`use crate::support;` in the test module), giving each item its own temp directory.
The compiler keeps its state in thread-locals (the simulated host included),
so programs compile independently on separate threads; do not add a global
lock. `RUST_TEST_THREADS=1` makes both the harness and `parallel_map`
serial. The front end (parsing the whole runtime for every program) is most
of each test's cost, which is why `pepper-parser`, `pepper-sema` and
`pepper-files` build at `opt-level = 1` in the dev profile.

---

## 10. Recipes

### Add a syntax form

1. Add the AST node in `crates/pepper-parser/src/ast.rs`, with a `Span`
   and a `name_span` if it names something, and implement `Display`.
2. Add the grammar rule in `parser/parsers.rs`. Call `pos()` for spans,
   `expected(input, "…")` where it can fail, `cut_expecting` once the form
   is committed, and `keyword()` for keywords. Update `RESERVED` or
   `OPERATORS` if needed.
3. Extend the AST walkers that must see the new node:
   `check_pointer_syntax` (`ptr_check_*`), `scope_walk.rs` (the one walk
   module linking and the visibility check share, so imported names inside
   it are rewritten and checked, and names it binds shadow imports), and the LSP's
   `expr_at`, `find_expr_in_block`, `collect_locals_upto`, and
   `imports.rs::in_statement`.
4. Lower it in `crates/pepper-sema/src/builder.rs`. Prefer desugaring into
   existing model nodes, as `for_loop` does. If you do add a model node, add
   it in `model.rs`, `passes/mod.rs` (`walk_expression`, `visit_expression`,
   `children`, `children_mut`), the passes that must
   understand it, and `codegen_expr_unlocated` / `value_sema_type` in
   codegen.
5. Add tests: parser unit tests (including the error message), a driver
   test, and a `tests/<Feature.Case>/test.pep` fixture if useful. Update
   the language guide chapter in `docs/src/language/` (with a tested
   example in `docs/examples/`) and the TextMate grammar in
   `tools/vscode-pepper`.
6. Mirror the rule in `tools/syntax/parser.pep` (and its `NodeKind` case in
   `tree.pep`), and print the node in `tools/pep-fmt/format.pep`.
   `pep_fmt_tests.rs` fails until the formatter keeps a file that uses the
   form unchanged in meaning.

### Add a sema pass

1. Create `passes/<name>.rs` with `pub fn <name>(module: &mut Module)`.
   Start it with a `//!` header that says what it rewrites.
2. Register `pub mod` in `passes/mod.rs` and add `step!(<name>(module))` at
   the right point in `transform_pass`. Consider whether it must run again
   after the specialization loop.
3. Report errors with `crate::errors::report(Diagnostic::error(…).at(loc))`
   and keep going. Keep per-run state thread-local and reset it at the start
   of the run.
4. Test in `model_tests.rs` (model shape) and with a driver JIT test
   (behavior).

### Add a compiler error

Follow AGENTS.md ("Compiler errors are clang-style diagnostics"): report at
the exact token and use clang wording. Use the mechanism of the layer the
error belongs to (section 6). If the node has no `Loc`, add one. Add a
rendered-output test in `crates/pepper-driver/tests/integration/diagnostic_tests.rs`.

### Add a runtime API

1. Write it in Pepper in the right `runtime/*.pep` file (or a new top-level
   file, which joins the prelude automatically). Mark it `export`. Put
   internals under `_pep_`/`_io_`.
2. Document it with `##` doc comments per AGENTS.md. Run
   `cargo test --workspace --test integration runtime_docs_tests::`.
3. For the `io` module, add it to the implementing file and re-export it
   from `runtime/io/module.pep`.
4. Regenerate the reference: `cargo run -p pepper-docgen -- reference`.
   Commit the changed `docs/src/reference/*.md` and `docs/src/SUMMARY.md`.
5. Test it with `compile_with_runtime` + JIT in the matching
   `crates/pepper-driver/tests/integration/*_tests.rs`. For behavior the docs show, add a
   `docs/examples/` program.

### Add an attribute

The parser accepts any `[Name]` or `[Name(args)]` on functions, externs,
structs, members, traits, extensions, aliases, globals, imports,
re-exports, and blocks, and sema carries it on `attributes`. An attribute
must be one of `static_blocks::BUILT_IN_ATTRIBUTES` or a struct marked
`[Attribute]` (`check_attributes` reports any other), so a new built-in
attribute goes in that list, and gets a documented `[Attribute]` struct in
`runtime/attributes.pep` describing its value (regenerate the reference).
To give one meaning, read it where it applies:

- `[Link("lib")]`, `[Link(lib = "lib", name = "sym")]` → `ExternDef::link`
  (validated by `passes::check_link_attributes`), read by
  `pepper_driver::link_libraries` and, through `ExternDef::link_name`, by
  `instantiate_extern`
- `[Alias("alias", "parameter")]`, `[Rename("old", "new")]` (functions) →
  `passes/named_arguments.rs`
- `[Target(...)]` → `passes/platform.rs`
- `[Deprecated("message", "replacement")]` → `deprecation.rs` (checked by
  the builder, read by `check_uses` and `check_deprecated_members`)
- `[Shared]` → `StructDef::is_shared`
- `[Isolated]` (structs), `[Move]` (parameters; the parser accepts
  attributes before any parameter), `[MoveSource]` (the parameter of the
  runtime's `move<T>`; runtime free functions only) and `[Locked]` (a
  function-value parameter called with a locked value, such as
  `Condition.wait_while`'s predicate; runtime only) →
  `passes/check_confinement.rs`, which reports any other parameter
  attribute (`check_parameter_attributes`) and wraps each `[MoveSource]`
  argument in `Expression::Move` (`lower_moved_arguments`); codegen reads
  `[Move]` and `[MoveSource]` (`check_confinement::takes_over`,
  `sending_params`)
- `[NotCopyable("why")]` → `passes/copies.rs`
- `[Implicit]` → `StructDef::implicit_from`, checked in `builder.rs` and
  applied by `convert_to_traits`
- `[Equatable]` (structs and reference enums; with `include`/`exclude`,
  their fields) → `equatable.rs` (§2.6), checked again by `check_hash_keys`

An attribute's arguments may be named, as in a call (`[Link(name =
"sym")]`): `ast::Attribute::name()` and `arguments()` read them. Validate the
arguments and report a located error. Add driver tests (see
`link_tests.rs`, `platform_tests.rs`).

### Add a platform-specific runtime function

Write twin declarations with the same name and signature, guarded
`[Target(OS(Windows))]` and `[Target(!OS(Windows))]` (see
`runtime/io/path.pep`, `sys_posix.pep`, and `sys_windows.pep`). Dropped
twins are never compiled together. Use `[Link(name = "sym")]` when the
C symbol differs by platform, and `[Link]` for extra libraries. Cover the
other platforms in `platform_tests.rs` with `with_simulated_host`, which
compiles the code but cannot run it. Run it for real with the
`platform-test` workflow (`.agents/skills/platform-test`).

---

## 11. CI

Every job in every workflow runs on a self-hosted runner, never a
GitHub-hosted one: **`pepper-windows`** and **`pepper-linux`** (x64), and
**`pepper-macos`** (arm64). A new job picks one of those labels. `ci.yml` jobs build into a
target dir beside the checkout that persists across runs of every PR, with
`CARGO_INCREMENTAL=0`: rustc's incremental cache mixed objects across branches
there. `RUST_TEST_THREADS=16` caps each suite's test threads (and
`support::parallel_map`'s), since several runners share one host.

- **`ci.yml`** (push to `main`, PRs):
  - `test` is the required check: a gate job that always runs (`if:
    always()`, so never skipped, since a skipped job counts as passing) and
    passes only when `test-windows` and `test-linux` succeeded,
    the PR is prose only, or the PR is still a draft (asked again of the API
    at gate time). It fails on a cancelled run, and when a job it needs was
    cancelled it runs on `ubuntu-latest` rather than queueing behind the
    self-hosted test jobs. On a ready PR, `changes`
    first posts an in-progress `test` check run that `test` completes with
    its verdict, so a pass left by a draft run cannot let the PR merge while
    the ready run is still testing it.
  - `test-windows` runs on the self-hosted **`pepper-windows`** runner:
    provision LLVM (`ci-provision-llvm.sh`, cached), `cargo build
    --workspace --locked`, `cargo test --workspace --locked`, and
    `cargo run -p pepper-docgen -- check`.
  - `test-macos` (**`pepper-macos`**) and `test-linux` (**`pepper-linux`**)
    run the suite against the default LLVM. `test-linux` is required,
    through `test`; `test-macos` is not for now (it takes about twice as
    long and held up the merge queue), so `test` does not wait for it.
  - `changes` runs first. It asks the API whether the PR is a draft now (the
    event payload can be stale when a push races "ready for review"), and
    diffs the PR against its base. A draft, or a PR that changed only prose
    (`*.md` other than `docs/src/SUMMARY.md` and `docs/src/reference/`, or
    `.agents/`/`.claude/`), skips the three test jobs.
- **`llvm-versions.yml`**: runs as the first stage of `vsix.yml` and
  `docs.yml` on a release tag, which package and publish nothing unless it
  passes, or by dispatch (`gh
  workflow run llvm-versions.yml --ref main`). `llvm-matrix` discovers every
  supported LLVM major apt offers and `llvm-versions` runs the suite against
  each on **`pepper-linux`**.
- **`platform-test.yml`**: runs on dispatch only, for any script on
  Linux/macOS/Windows (`gh workflow run platform-test.yml -f platforms=…
  -f script=…`). It has a failure/cancel diagnostics step. Read AGENTS.md's
  CI section before writing a script for it.
- **`vsix.yml`**: builds the extension and server for win32-x64,
  linux-x64, darwin-x64 and darwin-arm64. It runs only on a `vX.Y.Z` tag
  push or a manual dispatch, and publishes the release from a tag or from
  `main`. There is no arm64 Windows or Linux runner, so those platforms get
  no bundled server.
- **`docs.yml`**: builds the mdBook site to `gh-pages` (`dev/` on `main`,
  `X.Y.Z/` on tags).
- **`llvm-package.yml`**: runs on dispatch and publishes the stripped
  Windows LLVM package that CI installs.

---

## 12. Conventions and patterns

- **Loc on every naming node.** Synthesized nodes copy the source `Loc`
  they stand for (the `for` iterator uses the iterable's). Use `Loc::NONE`
  only when there is no source. Codegen's `*_unlocated` wrappers exist to
  attach these locations.
- **Errors never panic on user input.** Panics that remain are internal
  invariants, such as the `expect` in `lower_with_blocks` that relies on
  the builder giving each hidden `with` value its `enter()` call. The
  LSP wraps sema and visibility in `catch_unwind` as a backstop, not as a
  license to panic.
- **Thread-local state, not globals.** This covers the parser's position
  and expectation tracking, the builder's `FILE`, sema errors, the
  extension set, and the simulated host. Tests compile in parallel threads.
- **One loader.** The CLI, tests, and LSP all load programs through
  `program::load_program`. Tests use `compiler::compile_with_runtime`
  instead of hand-merging the runtime (#71).
- **Pointers.** Outside `extern` declarations, write `__ptr<T>`
  (`check_pointer_syntax` rejects `T*` there). Internally,
  `convert_intrinsics` rewrites `__ptr<T>` to `T*`, and codegen treats any
  `*`-suffixed name as a pointer. Extern prototypes mirror C and keep
  `char*`.
- **Naming.** Language and runtime types are PascalCase (`String`, `Array`,
  `HashMap`, renamed in #50). Methods and functions are snake_case, with
  whole words preferred (`remove_at`, `read_to_string`, `is_permission_denied`,
  `capacity`). Compiler-synthesized names start with `__` (`__refcount`,
  `__dtor`, `__index_get`, `__for_iterator_N`, `__function`) and cannot be
  reached from source. Methods are mangled as `Struct.method`, and
  specializations as `Name<args>`.
- **Comments explain why.** Module headers (`//!`) state what a file does
  and what invariant it keeps, and they often cite the bug that motivated a
  choice (see `target.rs`, `linker.rs`). Keep that style.
- **Commits and PRs.** Branch first. Titles are imperative, sentence case,
  with the PR number appended on merge (`Add for loops and the iterator
  protocol (#66)`). Bodies explain the why in prose. Write messages to a
  file (`git commit -F`, `gh pr create --body-file`; see AGENTS.md). The
  `finish-pr` skill covers push → PR → review → merge; it never resolves
  review findings on its own.

---

## 13. Known limitations and sharp edges

- **Mangled private names.** Every file merges into one `Module`; private
  names are kept apart only by mangling (`helper@io/file`). Anything that
  shows a model name to the user must go through `pepper_parser::namespace`:
  `demangle` (single-quoted names in messages; `Diagnostic::render` and the
  LSP's diagnostics), `demangle_known` (only the program's own namespaces;
  the LSP's hover signatures, never doc comments), or `demangle_name` (one
  bare name). The LSP matches the document's own declarations by their
  demangled names before other files' (`find_sema_struct`,
  `declaration_doc`, `member_doc`). Code that synthesizes a reference by name
  (`_pep_interpolate`) can reach only a declaration that keeps its name, so
  it must be exported by the runtime or the root file, whose exports keep
  their names. `SymbolTable` lets a later declaration overwrite an earlier one.
- **Trait values are one level deep.** There are no supertraits, so one
  trait type converts to another only through `as?` or a type pattern,
  which test the struct behind it at run time. `Atomic<T>` of a trait type is rejected (a trait type is not `Shared`): two
  pointers do not swap atomically, and the struct behind it may not be
  thread-safe; the book points to `Mutex<Shape>`. `for` and `with` still choose their
  protocol by the methods a type has (`ForIterator`), statically for a
  struct and through the vtable for a trait value.
- **Constrained bodies are checked, not compiled, against their
  constraints.** `check_bounds` types a generic base's expressions itself
  (best effort: its own scopes, `static_type`, the struct table with each
  generic struct's parameters substituted) and reports only what it can
  type; an expression it cannot type is left to the specializations, which
  still compile each body for its type argument and dispatch statically.
- **Runtime discovery is by location.** The runtime must sit within five
  levels above the current directory or the executable, or be named by
  `PEPPER_RUNTIME`. The compiler reports an error when none is found; the
  LSP silently runs without a prelude.
- **Host-only targets.** `[Target]` evaluates against the host, and the
  triple is always the host's. 32-bit x86 is unreachable by construction
  (see `crates/pepper-codegen/Cargo.toml`).
- Some passes leave unresolved nodes for codegen to report as
  `unknown …`.
- **Sync types.** `Lazy<T>` relies on `check_shared_types` to reject a
  non-thread-safe `T`. `Mutex<T>` holds any struct, confined by
  `check_confinement`; its constructor and `replace` take their `[Move]`
  value without a copy (the caller hands its reference over) and `move` it
  into the slot under the lock. `Channel<T>` takes any `T`: its buffer
  field is `__ptr<__ptr<void>>`, `send` and `try_send` take a `[Move]`
  value and `_push` moves it into its slot under the lock, and `_pop` moves
  it out.
- **Confinement and raw memory.** Raw pointers, `extern` code and
  Array's raw slot moves are the code's own promise. A reference read through a
  pointer the walk cannot follow to its owner (one an `extern` returned,
  such as a thread-local slot, or one a `[Shared]` struct's field holds,
  such as a `Channel`'s buffer) is tainted, never fresh. The runtime's
  `move(p[i])` (`Channel._pop`, `Mutex.replace`) promises instead that the
  slot held the only reference; the promise is unchecked, so only runtime
  files may make it.
- **Confinement is flow-insensitive** within a function, and a variable
  declared outside a `with` block is an outside value whatever it holds, so
  a value received into a variable needs `copy` (or `move`, when the
  variable is its only holder) to move into a locked value.
- **`copy` of a trait value** cannot be checked at compile time: one that
  holds a struct that cannot be copied panics at run time.
- **Only the first sema error is reported** per compile
  (`errors::report`).
- **Unused CLI flags**: `-v`, and `-T` channels other than `time`; `--MSVC` returns an
  error. Only the first source file is compiled.
