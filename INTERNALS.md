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
| `src/main.rs`, `src/lib.rs` | The `pepper` CLI binary: parses `Options`, calls `pepper_driver::run`, prints errors (colored on a TTY unless `NO_COLOR`). The lib only re-exports the parser for `tests/parser_corpus.rs`. |
| `crates/pepper-parser` | winnow grammar → AST (`ast.rs`, `parser.rs`, `parser/parsers.rs`), clang-style diagnostics (`diagnostic.rs`), doc-comment parsing and the documentation check (`doc.rs`). No LLVM. |
| `crates/pepper-files` | Filesystem helpers shared by the driver and the LSP: import resolution (`imports.rs`) and runtime discovery (`runtime.rs`). No LLVM. |
| `crates/pepper-sema` | Program loading and module linking (`program.rs`, `modules.rs`, `visibility.rs`, `deprecation.rs`, and the scope walk they share, `scope_walk.rs`), AST → model builder (`builder.rs`), the sema model (`model.rs`), struct synthesis (`struct_body.rs`), and the transform passes (`passes/`). No LLVM. |
| `crates/pepper-codegen` | Sema model → LLVM IR through `inkwell` (`lib.rs`, plus `types.rs`, `address.rs`, `ops.rs`, `target.rs`). Also hosts the MCJIT entry points the tests use. |
| `crates/pepper-driver` | Glues the stages together (`compiler.rs`), CLI options (`options.rs`), object emission and linking (`lib.rs`, `linker.rs`). Holds nearly all integration tests (`tests/*.rs`). |
| `xtask/` | `cargo setup` (`cargo run -p xtask -- setup`): picks and runs `scripts/setup-llvm.{sh,ps1}` and writes `.cargo/config.toml`. Has no dependencies, so it builds before LLVM exists. |
| `tools/lsp` | `pepper-lsp`, a tower-lsp language server. Parser and sema only, so it never links LLVM. |
| `tools/vscode-pepper` | VS Code extension: TextMate grammar, language configuration, and a client that launches `pepper-lsp`. |
| `tools/docgen` | `pepper-docgen`: generates `docs/src/reference/` from runtime doc comments and builds the mdBook site. |
| `tools/syntax` | A Pepper library (written in Pepper): lexer and lossless syntax tree for Pepper source, for tools. See [section 8](#8-language-server-and-vs-code-extension). |
| `tools/pep-fmt` | `pep-fmt`, the code formatter, written in Pepper on `tools/syntax`. |
| `runtime/` | The standard library, written in Pepper. Top-level `*.pep` files form the prelude; `runtime/io/` is an importable module. |
| `tests/` | `.pep` corpus: standalone files plus one `tests/<Feature.Case>/test.pep` per folder, and `tests/parser_corpus.rs` (the root package's only test). |
| `docs/` | The user-facing book: mdBook sources (`src/`), tested examples (`examples/`), generated library reference (`src/reference/`). |
| `scripts/` | LLVM provisioning and packaging (`setup-llvm.*`, `ci-provision-llvm.sh`, `package-llvm.*`, `probe-llvm-packages.sh`), and `install-vscode-extension.ps1`. |
| `.github/workflows/` | `ci.yml`, `platform-test.yml`, `vsix.yml`, `docs.yml`, `llvm-package.yml` (see [section 11](#11-ci)). |
| `.agents/skills/` | Agent workflows: `build`, `test`, `platform-test`, `finish-pr`. Read `build` and `test` before diagnosing a failure; they record failures this project has already hit. |

Dependency direction: `parser ← files ← sema ← codegen ← driver ← pepper`.
`lsp` and `docgen` depend on the parser (and the LSP also on sema and files)
and nothing that links LLVM.

---

## 2. The pipeline end to end

```text
pepper main.pep [-I dir] [--import name] [-l lib] [-o out] [--build dir]
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
linker::link → clang -o <out> <objs> -L… -l… (+ kernel32 user32 shell32 on Windows)
```

The CLI produces an executable and never runs it. Tests usually stop after
`generate` and JIT the module instead (see [section 9](#9-tests)).

### 2.1 CLI options (`crates/pepper-driver/src/options.rs`)

`Options` is a clap derive struct. Only these options take effect:
`source_files` (only the first is compiled; the rest are ignored), `-I`,
`--import`, `-l`, `-o`, `--build`, `--emit-llvm`, `--emit-ast`, and
`--no-runtime`, `--no-cache`, `--cache <dir>`, `--verify-cache`, `--no-verify-cache` (see [section 4.3](#43-build-cache-driversrccachers-codegensrcpartitionrs)), `-T time` (or `--Tall`), which prints each stage's
time on stderr (`StageTimer` in `driver/src/lib.rs`: load and parse, check
and build, sema passes, codegen and emission, link), and `-T cache`, which
prints how the cache supplied each unit's object (`hit`, `hit (same code)`
or `miss`). `-g`, `-v`, and the
other `-T` channels are parsed and ignored.
`--MSVC` returns an error. `output_path()` defaults to `<cwd>/<entry stem>`
with no extension, and `module_name()` is the output's stem.

### 2.2 Program loading (`crates/pepper-sema/src/program.rs`, `crates/pepper-files`)

- **Runtime discovery** (`pepper_files::runtime::discover`). When the
  `PEPPER_RUNTIME` environment variable is set and non-empty, it names the
  runtime directory and nothing else is searched. Otherwise the candidates
  are `<cwd>/runtime`, `<cwd>/.pep/runtime`, and `../runtime` up to five
  levels above the current directory, then `runtime` beside the running
  executable and up to five levels above it (so `target/debug/pepper` finds
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
    `prelude_part`, which exempts them from duplicate-export checks.
- **`modules::link`** binds every file's imports and `export x as y`
  re-exports, then **rewrites each imported spelling in the AST**
  (`m.sqrt`, an alias `power`, a qualified type `m.Point`) to the name of the
  declaration it denotes. It also gives each file's **private** top-level
  declarations, and every reference to them, a mangled name
  (`pepper_parser::namespace::mangle`: `helper@io/file`), keyed on the
  file's `ProgramFile::namespace`, which `load` computes with
  `ModuleRoots::namespace_of` (module name plus path inside the module;
  outside any module, the path from the project directory, the one the
  compiler runs in, such as `tests/util`; the file stem only for a file
  outside both, made unique with `#2`, `#3` in load order). A namespace
  depends only on the file's path, so a file's symbols are the same in
  every program that loads it, which the build cache relies on. Exports, externs, and concrete overrides keep their names; so do
  the root file's private names, unless another file keeps the same name
  (so `main` and a JIT test's `test` stay findable). `own_names` decides
  this. Which generic functions are concrete overrides (`hash<int>`, and
  `hash<Point>` of a visible `hash<T>`) is decided by `modules::Overrides`,
  the same rule sema's `gather_generics::concrete_overrides` applies: every
  type parameter names a primitive, `String`, or a struct, and either all
  are primitives or `String`, or a generic of that name and arity exists.
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
  visibility check applies the same override rule (`Decl::is_override`), and
  requires one file's overloads of a name to be all exported or all private
  (`MixedOverloads`), so an import binds the whole set.
  Codegen gives every mangled declaration internal linkage
  (`set_private_linkage`): no other object can name it, and ELF linkers
  read the `@` of a global symbol as a version. After this step every reference is spelled the way the merged
  model resolves it, with no two files' private names alike. Runtime
  functions the compiler calls by name (`_pep_malloc`, `_pep_print*`) must
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
  exports, and concrete overrides declared in several files. Extern
  redeclarations are exempt.

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
  (`INTERPOLATE_FUNCTION`; the call is located at the braces, the name at
  itself), so linking, visibility, the LSP and sema see ordinary references
  and calls. `{{`/`}}` are literal braces; between braces only an identifier
  is accepted. A lone `}`, a missing name, or a missing `}` (with a note at
  the `{`) is an `error_at`, except after a line break inside the literal,
  where it reports `missing terminating '"' character` at the opening quote.
  The runtime's `_pep_interpolate<T>` resolves `to_string(value)` in
  `string.pep`, so neither a struct's own `to_string()` method (which
  `convert_member_refs` would bind a bare call to) nor a file's own
  `to_string` functions (which hide the runtime's set) capture it.
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
- `type_name_from` lowers `T[]` to `Array<T>`.
- `variable_def` gives a variable or field of type `Optional<T>` with no
  initializer the default `Optional<T>()`, so it starts as None, not null.
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
    A variable declared as `Array<T>`, `HashSet<T>` or `HashMap<K, V>`
    types its literal in the builder (`typed_expression`), which also lets
    `[]` and `[:]` build an empty collection. Any other typed slot
    (argument, return, assignment) is handled by
    `convert_to_traits::convert_array_literal` / `convert_map_literal`,
    which rebuild the chain from `Array<T>()` / `HashMap<K, V>()` and
    convert each element to the slot's element type. A `HashSet` slot takes
    an array through its `[Implicit]` constructor.
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
    `this: E`, passed by value like any integer.
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
  - `if (x is P(a))` and `while (x is P(a))` become the same `match`
    statement with one arm (`is_branch`, `is_loop`; the loop is `while
    (true)` whose `else` breaks), its `MatchSite` marked `partial` so it
    need not handle every case; `a` is a local of the block.
  - A `match` expression becomes `Expression::WithSubject` (evaluate the
    subject once, then the body) around a `?:` chain of `MatchArm` tests
    over `Expression::Subject` (the value, by the site's id). A name an arm
    binds is replaced in the arm's value by its `CaseValue`
    (`bind_in_expression`; a closure there may not use one). Without an
    `else`, the chain ends in `Expression::NoMatch`. An `is` test anywhere
    else is a `WithSubject` around a single test, and may not bind.
  - A character literal (`ast::Literal::Char`) becomes
    `Cast { IntLiteral(byte), byte }`, so it is typed `byte` where nothing
    else gives it a type and widens like any `byte` value.
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
    `__release`, which source code may call.
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
  `link_name()`), `VariableDef { kind: Variable|Field|Param, loc, type_loc
  }`, `Expression` (includes intrinsic nodes: `SizeOf`, `Default`, `IsPod`,
  `RefCount`, `Address`, `Atomic*`, `FunctionRef`, `Invoke`,
  `ForIterator`, `WithEntered`, `Destructure`, `Move`, `ToTrait`, `ClosureLiteral`, `MakeClosure`,
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
**host**. The grammar is `OS(Windows|Mac|MacOS|Linux)`, `Arch(x64|aarch64)`,
`!`, `&&`/`and`, and `||`/`or`. The pass drops top-level declarations,
struct/trait/extension members, and attributed blocks whose predicate is
false. Every predicate is validated before anything is dropped, so a typo in
code that another platform would compile is still reported. Attributes other
than `Target` are ignored here. `keep(&attrs)` is the reusable evaluator;
the loader, linking, and visibility all call it.
`with_simulated_host(os, arch, f)` runs `f` with a different host
(thread-local) so tests can compile another platform's code. The emitted
target triple is always the host's (`target::host_machine`); there is no
cross-compilation.

### 2.6 Struct bodies (`struct_body.rs`)

`struct_body::apply` first runs `passes::closures::lift_closures`, which
turns every closure literal into a synthesized struct
`__closure_N@<namespace>`, numbered within its file (see §4.3) and generic
over the enclosing code's type parameters, and a `MakeClosure` creation
expression, so the new structs get their bodies below like any other.
`passes::strip_bodies` runs next, dropping the bodies of units the build
cache reuses (§4.3). The
struct's fields are `__invoke` and `__destroy` (defaults `MethodAddress`
of `__call` and `__dtor`), so its head matches the function type struct,
then one field per captured local, then `__this` when the body uses `this`
or a bare member of the enclosing struct (rewritten to `__this.member`). The
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

## 3. Sema transform passes (`crates/pepper-sema/src/passes/`)

`transform_pass(&mut Module) -> Result<(), Diagnostic>` runs the steps below
in order (`passes/mod.rs`). Each call is wrapped in `step!`, which stops at the first pass
that reported an error. The order came from the C++ implementation, and
several passes run more than once on purpose.

| # | Step | What it does |
| --- | --- | --- |
| 0 | `enums::resolve_enum_cases` (`enums.rs`) | Installs the reference enums (structs with `enum_cases`) in their own registry (`enums::reference_cases`), rewrites `Doc.Line` to the call `Doc.Line()`, and reports a case that carries values used without them (`case 'Text' of 'Doc' takes 1 value`) and a direct `Doc(...)`. Installs `module.enums` in the thread-local enum registry (`enums::install`; `struct_body::apply` and codegen install it too), which `TypeName::is_integral`, `arithmetic` and codegen's `scalar_type` consult (`enums::stored_as`), so an enum type keeps its name through sema but is stored as its representation. Rewrites `Enum.Case` to `Cast { IntLiteral(value), Enum }`, reports `no case named 'X' in 'E'` and a user-written `n as Enum`, and gives enum locals and globals without an initializer the default case (value 0, else the first). Adds each enum's built-in `E::name` and `static E::from_value` (after platform selection, so they see only the surviving cases), records every `E::m` in the method registry (`enums::method_is_static`, installed by codegen too), rewrites `this` and bare sibling calls inside enum methods, turns a static call `E.m(...)` into `E::m(...)`, and reports `extend E`. A call on an enum value, `c.m(...)`, needs `c`'s type, so `resolve_implicit_types` rewrites it to `E::m(c, ...)` (`enums::call_on_value`); `check_deprecated_members` finds deprecated enum methods by the function name, and codegen's argument-count errors leave out the `this` argument. |
| 0a | `entry_point::lower_main_arguments` (`entry_point.rs`) | The C `main` the compiler emits takes no `argc`/`argv`, so a root file's `main(args: String[])` is renamed `main@#args` (`MAIN_WITH_ARGUMENTS`; `#` cannot start a namespace, and messages demangle it to `main`) and a `main()` is synthesized at its location that returns `main@#args(_pep_arguments())` (a `void` one is called, then 0 returned). `_pep_arguments` is `arguments()` under a name a program's own `arguments` cannot shadow. Reports any other parameter list on `main` and `main` declared twice. `is_entry_point` gives both forms the inferred `int` return. |
| 1 | `check_bindings` | Reports a local declared twice in one scope (`redefinition of 'x'`, with a note at the previous one) and an assignment, compound assignment, or `++`/`--` to a `const` local, global, or (outside the constructor) field (`cannot assign to const variable 'x'`). |
| 2 | `synthesize_function_types` (`function_types.rs`) | Each tuple type `__tuple<A, B>` becomes a synthesized struct (`tuples::tuple_struct`) with const fields `"0"`, `"1"`, … and a constructor taking the elements, so every pass that types fields, constructor arguments and member reads handles tuples unchanged; codegen emits no object for it (§4.3). Each distinct `__function<R, P…>` and `__shared_function<R, P…>` becomes a synthesized refcounted struct (`__refcount`, `__weakcount`, `__invoke`, `__destroy`; its destructor calls `__destroy` through `CallPointer` when set, which releases a closure's captures), and each `__weak<T>` with a concrete struct `T` a weak view struct (`weak_types.rs`). A `shared` one counts atomically; a plain one counts plainly and leaves a count at or above `STATIC_REFCOUNT` alone, so the static object of a named function, which several threads may hold as plain values, is only ever read. |
| 3 | `resolve_literals` | Folds unary minus into numeric literals. |
| 4 | `overloads::name_overloads` | Renames concrete overrides of generic functions to their spelled type (`hash<int>`) (`gather_generics::concrete_overrides`). Then groups each file's free functions by name: a name with several is an overload set, whose members become `name$1`, `name$2`, ... (after any namespace: `f@ns$1`; `namespace::demangle` strips both), recorded in `module.overload_sets`. First, where prelude files (a forced import, then the runtime) export the same name, a later file's member with an earlier member's parameters is dropped and the rest form one set (`replace_prelude_members`), so a forced import replaces exactly the overloads it declares. Reports a redefinition, a difference only in return type, and an overloaded `extern`, and attaches an override of an overloaded generic to the member with its arity (`f$2<Point>`). Each struct's same-name methods (operators included) are renamed the same way (`add$1`, `+$2`), recorded in `module.method_overload_sets`; specializations copy the renamed members, and a static and an instance method may not share a name. A trait's same-name methods are renamed the same way, each its own vtable slot (`overloads::group_methods` serves structs, traits, and `apply_extensions`). `StructTable` and `convert_member_refs` also answer to a member's set name, so `a + b` and a bare `add(x)` in a method still find the set. Constructors arrive named by the builder (`Point$1`, `Point$2`; a specialization keeps the ordinal, `Box<int>$2`); this pass reports two with the same parameters (`constructor of 'P' cannot be redeclared`), and `Overloads::build` makes each concrete struct's constructors the set named by its type (`Point`, `Box<int>`), so `Point(args)` resolves like a function call. `Module::constructor_of` maps a call's name to its struct and constructor. |
| 5 | `convert_string_literals` | `"abc"` → `String(raw, size, length)` constructor call. The raw literal stays a `char*` global. |
| 6 | `gather_generics` | Records generic uses as `struct_specs` and `func_specs`. |
| 7 | `resolve_implicit_types` | Infers `auto` locals and symbol types by scoped lookup (`p[i]` through a `__ptr<T>` or `T*` is a `T`; a `void` pointer is left to codegen), and a function's return type from its `return` statements when it declares none (`void` when it returns no value, `int` for `main`). Runs `closures::sync_closures` in the same fixpoint loop (§2.6). A call to a generic function or method without type arguments (`larger(3, 9)`, `b.map(f)`) gets them from its arguments' types through `type_arguments::GenericSignature` (bind each parameter type against an argument type, `unify`), and is renamed to the specialization (`larger<int>`, `map<long>`); a closure argument receives the partly bound parameter type as its expected type, so inference runs across fixpoint rounds. A call naming an overload set is resolved first, once its arguments' types are known (`overloads::Overloads::select`): each viable member ranks each argument (exact, promotion, conversion, `[Implicit]` constructor), the best member must be better in one argument and worse in none than every other (a non-generic wins a tie with a generic), and the call is renamed to it (a specialization for a generic member); a call whose argument types mention a type parameter waits for the specialization. A method call (`m.add(x)`, `Money.of(x)`) on a struct with a method set of that name resolves the same way against `Overloads::select_method`, by the receiver's type; `resolve_operators` resolves the method calls it creates for operators with `overloads::resolve_method_call`, typed by `static_type`. Each resolution goes to `module.call_targets` for the LSP (a method as `Struct.member`). The same loop runs `overloads::bind_function_values`, which rewrites a set (or an overloaded method, `p.add`) used as a value to the member whose function type matches its slot (closures' `for_each_site`). |
| 8 | `resolve_resolvables(false)` | Resolves struct, function, and method references against the symbol table. |
| 9 | `apply_extensions(false)` | Clones `extend` methods onto their target and records traits. For `extend S with T`, checks that `S` has every method `T` declares and copies in `T`'s default methods (those with a body) that `S` lacks, reporting `'S' does not implement 'm', required by trait 'T'` otherwise (`'m(int)'` for an overloaded member). A trait member is implemented by the method of its set name with its parameter types, and a copied default takes the set name. Each implementation must have the declared signature, except that a struct result may stand for a declared trait result. Then `overloads::group_methods` regroups the struct's methods, so extension methods and defaults join its overload sets: named members keep their names, new ones take the next ordinal, and a repeated parameter list is `redefinition of 'm'`. |
| 9b | `interpolation::check_interpolations` (`interpolation.rs`) | Checks each interpolated value (a call `_pep_interpolate<X>`, see §2.3) converts: `X` is an integer type or `bool` (the runtime's `to_string` overloads), a struct or trait with a `to_string()` method, an enum declaring one (`E::to_string`), or has a concrete override `to_string<X>` (one not at the generic's location). Otherwise reports `cannot interpolate a value of type 'X'` at the `{name}`, with a note at a struct, before the runtime's `to_string<T>` body would fail on it. Runs again after the specialization loop for the calls in specializations of generic code. |
| 10–11 | `specialize_structs`, `specialize_functions` | Clones generic bases into `Name<args>` instances with substituted types. A `void` argument erases what it types (`erase_void`): fields and parameters of that type, stores of them, and a `return` of one, so `Result<void>` has no `Value` and `ok()` takes no argument. A generic struct's `generic_methods` are cloned with the struct's parameters substituted and keep their own. |
| 11b | `specialize_methods` (`generic_methods.rs`) | For each method call named `m<args>` on a struct with a generic method `m`, clones `m` into `method_members` as `m<args>` with its own parameters substituted. `apply_extensions` routes generic extension methods and generic trait default methods (`Iterator<T>.map<U>`) to `generic_methods`; `traits::is_dispatchable` excludes them, since a vtable has one slot per method. |
| 12 | `synthesize_function_types` | For function types that specialization exposed. |
| 13 | `convert_intrinsics` | Rewrites `__ptr<T>` to `T*`, including the `T` of intrinsic nodes that specialization substituted. Turns `__is_pod`, `__default`, `__refcount`, `__address`, `__atomic_load/store/cmpxchg/fetch_*` calls into intrinsic nodes, and `__function_pointer(f)` into `Expression::FunctionPointer` (a free function, or a static method of the enclosing struct, whose owner type specialization substitutes). |
| 14–15 | `resolve_resolvables`, `apply_extensions(true)` | Resolves what remains and applies specialized extensions. |
| 16 | `convert_member_refs` | In methods, a bare field becomes `this.field` and a bare call becomes a method call (parameters are exempt). In a trait's default method copied into a struct (`FunctionDef::trait_default`, set by `apply_extensions`), only the trait's methods count and no fields. |
| 17–18 | `resolve_implicit_types`, `resolve_operators` | `x[i]` → `__index_get`/`__index_set` or POD `ArrayIndex`. An overloaded binary operator becomes a method call. Without its own `!=`, `a != b` on a type with `==` becomes `!(a == b)`. `===` and `!==` are never overloaded; codegen compares their raw values (`BinaryOp::identity_as_equality`), addresses for references. `unary_operators::dispatch` turns `-x`, `~x` and `!x` on a struct declaring the operator into a zero-argument method call named after it, and a struct value in a boolean context (`if`/`while` condition, ternary condition, operand of `&&`/`\|\|` that the struct does not overload, operand of `!`) into `x.!!()`; `!x` without its own `!` is `!(x.!!())`, and `!!x` is `x.!!()`. `StructInfo::unary_operators` records which of `-`, `~`, `!`, `!!` a struct or trait declares as parameterless instance methods. |
| loop ≤16× | `gather_generics`, `specialize_structs`, `specialize_functions`, `specialize_methods`, `copies::synthesize_copies` | Repeats until the counts of structs, functions and methods stop growing and no copy was synthesized (specializing exposes new uses). When the module has generic methods or overload sets, each round first runs `resolve_implicit_types` so calls on newly specialized structs get their type arguments. Bounded because a self-nesting generic never converges. `synthesize_copies` (`copies.rs`) serves `copy(value)`: it checks every copy the program asks for (a `copy<T>` call outside a `Copyable` method) through everything it reaches and reports `cannot copy 'X' because it contains 'Y', ...` at the request (a `Channel<T>` is found through `check_shared_types::use_site`), with a note per field hop and, for a struct with a destructor or a raw pointer field, a `Copyable<T>` skeleton note and `Fix` that inserts it after the struct. It then lowers each concrete `__copy<T>(value, copies)` (the body of `Copies.copy<T>`) to `value` for a thread-safe `T`, to `copies._copy_object<T>(value)` for a struct, which calls the struct's `_pep_copy` method, or to a panicking `_pep_copy_failed<T>` for a type nothing asks to copy. It gives each such struct `_pep_copy`: `this.copy(copies)` when the struct implements `Copyable<T>` (has `copy(Copies)`), else a field-by-field copy that allocates with `Expression::Allocate` (no constructor), registers the copy before copying fields (cycles), copies thread-safe fields as they are and others with `copies.copy<F>`, and defers weak fields to a `_pep_fix_weak` method run by `Copies._finish`. `[NotCopyable("why")]` on a struct forbids copying it. |
| then | `check_interpolations`, `convert_intrinsics`, `resolve_resolvables`, `convert_member_refs`, `synthesize_function_types` | Covers what the loop created. |
| final | `reference_functions` (`function_references.rs`) | A method, constructor or generic function specialization used as a value (`p.norm`, `Point.norm`, `Point`, `Box<int>`, `identity<int>`) becomes a `MakeClosure` of a new complete closure struct whose `__call` forwards to it; a bound method's receiver is its one capture (`__receiver`). Needs final types to tell a method from a field, so it runs here, before `release_field_refs` releases the receiver. A local inferred from the expression (`var f = Point;`) is retyped to the function type. Reports storing `this.m` in a field of `this`. |
| final | `release_field_refs` | Inserts `__release` calls for struct-typed fields, in reverse declaration order, at the end of the destructor. The object itself is freed by `__release` once `__weakcount` reaches 0, not by the destructor. |
| final | `resolve_implicit_types`, `resolve_operators`, `unary_operators::check_conditions`, `convert_print_calls`, `resolve_resolvables(true)`, `synthesize_function_types` | `check_conditions` reports a struct or trait value still in a boolean context, one whose type declares no `!!` (`'S' cannot be used as a condition: declare '!!(): bool' on it, or compare with '__null'`, with a note at the declaration): a struct is never null-tested implicitly. Pointers, numbers, `bool` and function values (synthesized `__…` structs) keep codegen's `as_bool`. `convert_print_calls` turns a `String` argument of `print` into `arg._data`. `resolve_resolvables(true)` is the step that reports `use of undeclared identifier`, `call to undeclared function`, and similar. |
| final | `check_type_arguments` (`type_arguments.rs`) | Reports a generic call whose type arguments the arguments did not determine (`cannot infer the type arguments of 'make' from its arguments; write them: make<T>(...)`, with a note at the declaration). |
| final | `overloads::check_overloads` | Reports an overload call no member fits (`no matching function for call to 'f'`, a note per candidate saying why; for constructors `no matching constructor for initialization of 'P'`), one two members fit equally well (`call to 'f' is ambiguous`, `call to constructor of 'P' is ambiguous`), one whose argument type stayed unknown, and a set used as a value where no expected type picks a member (`cannot infer the type of 'g' from overloaded function 'f'`, `address of overloaded function 'f' does not match required type`). Method calls and method values (`overloaded method 'S.get'`) are checked the same way, by the receiver's `static_type` (a trait type's sets are its members). A method set's candidates at a call are the body methods plus the methods of extensions visible in the call's file (`Module::extension_scopes`, from each file's `FileScope::extensions`). Skips extensions' own copies of their methods (only the struct's copies are resolved) and generic bases, whose calls resolve in their specializations. |
| final | `check_closures` | Reports a closure parameter, return or capture type that nothing inferred (`cannot infer the type of parameter 'x'`). |
| final | `shared_functions`, `synthesize_function_types` | Reports a C function pointer type (`__extern_function<R, P…>`, `TypeName::is_extern_function_type`; not a refcounted type, it lowers to `ptr`) declared with a type C cannot pass (a struct). Where a value flows into a C function pointer slot, replaces a `FunctionRef`, or a `MakeClosure` whose closure captures nothing (its `__call` copied into a free function `<closure>_c_function`), with `Cast(FunctionPointer, slot type)`; reports a closure or bound method that captures (`sync_closures` inferred its parameter types from the slot's plain signature, `extern_as_function`). Where a function value flows into a `shared` function-typed slot, retypes a `FunctionRef` or `MakeClosure` to the `shared` type, reporting a capture that `check_shared_types::unsafe_part_in` finds not thread-safe (at its first use in the closure, with a note at the captured local). Where a `shared` value flows into a plain slot of the same signature, wraps it in a new plain adapter closure (`__inner`, `__call` forwarding to it; its destructor releases `__inner`), so plain counts never touch a shared object. Any other plain value in a `shared` slot is left for `check_function_types`. |
| final | `convert_to_traits` | Implicit constructor conversions and trait conversions, at every place a value flows into a typed slot (initializer, assignment, argument, return). A value flowing into a struct whose constructor is `[Implicit]` (`StructDef::implicit_from`) becomes a `FunctionCall` of that constructor when its type matches the parameter exactly or by promotion (integer widening, a fitting integer literal, `f32` → `f64`, struct → declared trait); the call's own argument never converts through another constructor. A string literal (the `String(raw, size, length)` call `convert_string_literals` made, matched by the literal's loc) flowing into a `char`, `u8`, or `void` pointer slot is unwrapped back to its raw literal, in each arm of a ternary too. It wraps every struct value that flows into a trait-typed slot in `ToTrait`, checking that the struct declares the trait; rejects calls through a trait value to members it cannot dispatch, and struct results of trait methods that do not conform to the declared trait type. Records the trait types in use in `module.trait_types`. See §4.2. |
| final | `check_function_types` | Rejects a value whose type does not match the typed slot it flows into (variable initializer, assignment, argument, return): a function value of a different signature, a plain function value where a `shared` one is expected (`cannot initialize variable 'f' of type 'shared () => void' with a value of type '() => void'`), a number or a raw pointer where a struct is expected or the reverse (a struct may pass as `void*`, but `void*` is never a struct; a string literal in a pointer slot is its `char*` global), or a different struct (`cannot initialize variable 'x' of type 'int' with a value of type 'String'`). A C function pointer slot takes only the same C function pointer type (`extern_flows_into`, with a hint saying what converts), and a C function pointer converts only to `void*`. An extern call's arguments are checked here only for its function-typed parameters; codegen checks the rest. It also rejects a call returning `void` used as a value (stored, passed, returned, an operand, or a condition). Errors are located `Diagnostic`s. |
| final | `check_shared_types` | Checks every `[Shared]` struct: each field must be `const` (on the declaration) and of a thread-safe type (on each concrete struct, so `Atomic<String>` is reported at the code that names it). A `shared` function type is thread-safe; a plain one is not. Then checks every module-scope variable, exported or not, by the same two rules, as if it were a field of a `[Shared]` struct (any function can hand a global to any thread). |
| final | `tuples::lower_destructures` | Checks each destructuring's element count against its value's tuple type (`cannot destructure '(int, int)' into 3 values: it has 2 elements`, `cannot destructure 'String': it is not a tuple`) and replaces the `Destructure` node with its value. Reports an element that does not exist (`no member named '2' in '(int, int)'`) and an assignment to an element (`tuple elements are immutable`). |
| final | `check_confinement` | The confinement rule for `with` blocks over `[Isolated]` guards (`MutexGuard`, `ThreadLocalGuard`), recognized by the builder's lowering (a hidden `__with_scope_N` local of an `[Isolated]` type). A flow-insensitive union-find over **regions** (`Fresh`, `Outer`: parameters, `this` and locals declared before the block, `Locked(n)`: the binding) links a call's operands as its callee's **link summary** says and an assignment's target with its value; linking `Outer` with `Locked`, or two locks, is an error at the value that would cross ("'line' cannot move into the value locked by 'names'", "'list[0]' is part of the value locked by 'names' and cannot outlive the lock"), as are returning a locked value from the block and a closure capturing one. Link summaries (for each function: which operand slots, `this` first, its body links together and into its result, and whether the result is tainted) come from the same walk over the callee, as a least fixed point over a worklist seeded with the functions that have `with` blocks or `[Move]` calls (callees start at the bottom, callers re-run when one changes). A result is **fresh** when no operand is in its class and it is not tainted (`returns_fresh`, shown by the LSP's hover). A tuple result has one result slot per element, and a tuple value one region per element (a literal keeps its elements apart, `t.0` reads one, a destructuring's hidden local takes the value's shape), so each element of `var (a, b) = f()` gets its own bit; passing a whole tuple as an operand links all its elements. `copy(x)` is fresh; an `extern` call links nothing and marks a returned pointer untracked, as is a pointer read from a thread-safe object's field (raw memory a `[Shared]` struct holds), so a reference read through either is tainted; `move(x)` (the runtime's `move<T>`, whose `[MoveSource]` argument `lower_moved_arguments` wraps in `Expression::Move`) out of raw memory, `move(p[i])`, is fresh (runtime files only, checked against the discovered runtime directory); a moved local is fresh when it is the only holder (`Region::holders`) of an unshared, untainted region, and a `[Move]` parameter starts in a fresh region of its own; a call through a function value, and a closure capture, taint; a trait call joins every implementation's summary; unknown callees link everything. Raw pointers carry the region they were read from (`this._data` is `this`'s), and raw reads are typed by their pointee. Also checks: an `[Isolated]` value anywhere but a `with` header (or inside the guard's own struct and functions returning one) or in a field; `[Move]` arguments must be disconnected (thread-safe, or a call whose result class holds only disconnected operands and is not tainted), with a note at the `return` that keeps a callee from being fresh; `ThreadLocal<T>.get()` for a non-thread-safe `T`; `Mutex` of a number; `move` of anything but a sole-holder local or a runtime raw slot, and use after move (`Moves`, a flow-sensitive dataflow over each function that moves: a loop reruns its body unless every path leaves it). A syntactic prefilter skips functions that mention no trigger name. For the build cache (`Module::record_summaries`), it summarizes every function and hands out, by location, the summaries that reach no trait call (`summaries_to_record`); a build that skips a cached unit's bodies seeds those (`recorded_summaries`, §4.3). |
| final | `lower_with_blocks` | Picks each `with` condition by `enter()`'s final type: a null test for a struct or pointer, no branch otherwise (a `void` result becomes an expression statement). Reports the `with` errors (no `enter()`, binding a `void` result, `else` on a non-nullable result, assigning to the binding). |
| final | `enums::lower_matches` | Turns each `MatchArm` test into `__match_N == Case || ...` (for a reference enum, `__match_N.__tag == tag || ...`, after a `_pep_assert` that the subject is not null; a literal pattern's own `==`) and each binding's `CaseValue` into its payload field (several patterns binding one name: an `if` chain on the tag that assigns it, or a `?:` on the tag inside a `match` expression). It checks each `match` (`MatchSite`): the subject must be an enum, an integer, `char`, `bool` or `String` (literal patterns), a pattern's qualifier must name it, each case or literal is handled once, and every case must be handled unless there is an `else` (`match on 'E' does not handle ...`, at the keyword, with a note per missing case); a literal `match` needs an `else` unless it is a `bool` handling both values; an `is` test (`partial`) is not checked. An `else` after every case is a warning in `module.warnings`. For a `match` expression it sets the `WithSubject`'s null-check message, drops the chain's `NoMatch` (the last arm's value stands alone), and reports arms whose values do not mix (`check_arm_types`). `check_function_types` keeps enums apart from integers and from each other (`Kind::Enum`). |
| final | `check_deprecated_members` | Warnings only: each use of a field or method marked `[Deprecated]` (through `x.m`, `S.m()`, or a bare member in a method), found by the receiver's `static_type::of`, goes to `module.warnings`. Skips uses inside deprecated functions, methods, and structs (a closure lifted out of one inherits its `[Deprecated]`, see `closures::inherit_deprecation`), uses whose source text is not the member's name (calls sema synthesized), and repeated locations (specializations). |

Shared helpers in `passes/mod.rs` are `walk_block`, `walk_statement`,
`walk_expression`, `walk_function`, `walk_global`, and
`replace_expression`. **When you add a model `Expression` variant, add it to
`walk_expression`.**

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
closure structs' `CLOSURES`, `resolve_operators`' `INDEX_TEMPORARIES`)
restart at the start of every `load_program`
(`pepper_sema::reset_program_counters`). This lets tests compile
concurrently on separate threads. The builder's counters also restart for
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
   no `this`) and `codegen_function`. Then `module.verify()`.

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
  node being generated, whenever the two LLVM types differ. A field's
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
  `[LinkName("sym")]` changes the symbol (`ExternDef::link_name`). A string
  literal passed to an extern is passed as its raw NUL-terminated global.
- **Builtins resolved by name in `codegen_call`**: `print`
  (`codegen_print` → `_pep_print`, `_pep_print_int`, or `_pep_print_float`
  by argument type), `release<T>(v)`,
  `__is_pod`, and `__default<T>`. `call_function` declares unknown
  runtime helpers such as `_pep_malloc` on demand.
- **Intrinsic nodes** in `codegen_expr_unlocated`: `SizeOf`, `Default` (zero
  or null), `IsPod`, `RefCount` (an atomic load), `CountStep` (an
  `atomicrmw` on the head count at byte offset 0 or 4, monotonic up and
  acq_rel down, or a plain load/add/store), `FunctionPointer` (the LLVM
  function's address; a static method is `Owner.name`), `Address` (FNV-folds POD values),
  `AtomicLoad` (acquire), `AtomicStore` (release, via `xchg`),
  `AtomicCmpXchg` (acq_rel/monotonic; floats are bitcast), and `AtomicFetch`
  (`atomicrmw` acq_rel).
- **`match` expressions and `is` tests**: `WithSubject` (`with_subject`)
  evaluates the subject once, panics on a null reference enum, keeps the
  value in `subjects` by id for `Subject` to read, then evaluates the body
  (a `?:` chain). An owned subject is a deferred temporary, released at the
  end of the full expression, so an arm may yield one of its fields. A `?:`
  with one owned arm is owned: `codegen_ternary` acquires the other arm's
  read (`copy_arm`), as C++ yields a prvalue copy there.
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
- **Function values**: `FunctionRef` produces a static function object
  (`__function_object.<name>`, or `__function_object.shared.<name>` for a
  `shared` function type) whose `__invoke` points at a thunk
  (`__function_thunk.<name>`, one per function). Its strong count starts at
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
- **Target** (`target.rs`): `initialize_host` and `host_machine` register
  only the host's backend (x86 or aarch64, chosen by
  `cfg(target_arch)` in `Cargo.toml`). Four call sites share this one
  function. Read that file's header before touching backend registration.

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
  `__vtable.<Struct>.<Trait>` = `[S.__release, S.__acquire, S.m1, …]`. A
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
- **Identity.** `==`/`!=` on trait values compare objects, and
  `store_refcount_ops` treats the same object as self-assignment.
  `__address`/`__refcount` read the object. Array slots of a trait type are
  16 bytes, which `_pep_move_ref`/`_pep_swap_refs` move whole.

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
- **Comparing, hashing, printing.** `codegen_binary` sends a tuple `==`/`!=`
  to `tuple_equal`, which compares element by element (`value_equal`: an
  element's own `==` when its type has one, else by value or identity).
  `Expression::Address` on a tuple (what `hash<T>` uses) is `tuple_hash`,
  which folds each element's `hash<E>` (or its bytes) with FNV-1a, so a tuple
  is a `HashMap` key. `print` writes a tuple with `write_tuple` through the
  runtime's `_pep_write*` helpers.
- **Generic bases.** A tuple naming a generic parameter (`(K, V)` inside
  `HashMap`) is skipped by `register_tuple`; only its specializations get a
  layout.

### 4.1 Object emission, linking, running (`driver/src/lib.rs`, `linker.rs`)

`run` emits one object per compilation unit through `objects` (see
[4.3](#43-build-cache-driversrccachers-codegensrcpartitionrs)), plus the
program object `<build>/<module>.o`, with the host `TargetMachine`. It collects
libraries in this order: `-l` flags, then `runtime/*.a` (as
`-L<dir> -l<name>`), then `link_libraries(&module)`, which gathers the
`[Link("name")]` attributes of externs that survived platform filtering,
deduplicated. `linker::link` invokes **clang as the link driver**,
preferring `$LLVM_SYS_<NN>1_PREFIX/bin/clang` so the linker matches the
LLVM the compiler was built against, and falling back to `clang` on PATH.
`default_system_libraries` adds `kernel32 user32 shell32` on Windows. Link
warnings are forwarded. Failures include both stdout and stderr, because
MSVC's link.exe writes unresolved symbols to stdout.

### 4.3 Build cache (`driver/src/cache.rs`, `codegen/src/partition.rs`)

Phases 1, 2a and 2b of `/mnt/project-files/build-cache-design/build-cache-proposal.md`:
sema still runs over the whole program, but codegen and object emission run
per **compilation unit**, and a unit whose sources are unchanged takes its
object from `.pep/cache` without generating any code, and sema skips its
non-generic bodies.

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
  name with `<`), the `_pep_copy`/`_pep_fix_weak` methods `copy`
  synthesizes on demand (`copies::is_synthesized_method`: a program has
  them only for the types it copies, so owning them would make a unit's
  object depend on the program), and code with no location have no owner.
- **Per-unit codegen.** With `CodeGenerator::unit` set (`UnitFilter`),
  `generate` declares everything in name order (so a unit's module does not
  depend on load order), declares only the externs its input files declare
  (externs are first-wins by C name, so another file's declaration must not
  change the unit's calls), defines only globals and initializers of the
  unit's files, and `codegen_unit` emits, in name order, the unit's owned
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
  renumbered; and `symbol_name` respells every Pepper symbol except `main`
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
- **Keys.** `cache::unit_key` hashes (BLAKE3) the compiler's identity (crate
  version, LLVM version, and the running executable's path, size and
  modification time), the unit's name and files, and each input file's
  name, namespace, prelude flags and text. A record also holds the hash of
  the bitcode its object was emitted from.
- **Cache** (`cache::Cache`): `<cache>/v1/<target triple>/<unit>.o`,
  `<unit>.json` (`{"key": …, "bitcode": …, "warnings": "no"}`),
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
  and destructors stay whole. `objects` generates nothing for those units. A unit that warned is
  checked again, so its warnings print on every build. `--emit-llvm` and
  the JIT compile whole programs, never stripped.
- **Verifying** (`--verify-cache`, or `PEPPER_CACHE_VERIFY=1`, which CI
  sets): a hit generates the unit anyway and fails if its bitcode differs
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
- **Not yet** (phases 2c and 3): interfaces (`.pepi`) that skip parsing,
  and early cutoff for dependents by interface hash.

---

## 5. Reference counting: where the shared_ptr model is implemented

The model is defined in AGENTS.md ("Reference counting is
std::shared_ptr<T> passed by value"). This section maps each rule to the
code that implements it. Every rule is emitted in
`crates/pepper-codegen/src/lib.rs` as a call to `T.__acquire` or
`T.__release`. Both are synthesized by `struct_body::apply_synthesized` and
are null-safe.

| shared_ptr construct | Where |
| --- | --- |
| `make_shared` | The constructor's `return this` is an lvalue read of `this`, so the return site acquires (`Statement::Return` → `is_lvalue_read` → `acquire_ref`). A constructor result therefore arrives with one reference. This is net-identical to AGENTS.md's "construction leaves 0; the first owner acquires": the constructor's `this` local is never tracked, so nothing releases that reference. |
| `var x = expr` | `codegen_var_def_unlocated`: acquire when `expr` is an lvalue read. An owned rvalue (a call result, see `is_owned_rvalue`) moves in. The slot is registered with `track_scope_local`. |
| `x = y`, field and element stores | `store_refcount_ops`: if the new pointer equals the old one (self-assignment), do nothing; otherwise acquire the new value, then release the old. Fields use `field_refcount_ops` and indexed slots use `index_refcount_ops`. |
| By-value parameter | `codegen_function_unlocated`: acquire each struct parameter on entry (`this` excepted) and track it in the function scope. A `[Move]` parameter is not acquired: the caller hands its reference over (`pass_argument`: an owned temporary is not released after the call, an lvalue is acquired for it). |
| `move(x)` | `codegen_move`: load the reference from the place and store null there, with no count step; the result is an owned rvalue (`is_owned_rvalue`). |
| Scope exit | `scopes: Vec<Vec<(name, type, slot)>>`. `release_scope` runs at block fall-through, `release_all_scopes` at `return`, and `codegen_loop_break` releases the scopes a `break` or `continue` leaves. |
| `return` | An lvalue read is acquired before `release_all_scopes`. A call result moves. |
| Discarded temporary | `Statement::Expression` releases `owned_temp_type(expr)`. Arguments that are owned rvalues are released after the call (`owned_arg_temps` in `codegen_call`). The receiver of `f().x` or `f()[i]` goes on `deferred_temps` and is released at the end of the full expression by `flush_deferred_temps`. Ternary arms use `codegen_expr_in_arm`. |
| Tuples | Same rules, same call sites: `Tuple.__acquire`/`Tuple.__release` step each reference element (§4.3). A destructuring binding moves its element out of the hidden tuple. |
| Trait values | Same rules, same call sites: `Trait.__acquire`/`Trait.__release` are thunks into the vtable (§4.2), so the concrete type's `__release`, and at zero its `__dtor`, run. `ToTrait` does no refcount work of its own: converting an lvalue read acquires as the read would, and an owned rvalue moves. |
| Destruction | At zero, `__release` calls `__dtor`, which runs the user's `destruct` body, then the field releases added by `release_field_refs`. `__release` then drops the strong references' weak reference and frees the object if `__weakcount` reached 0. |
| Closures | `MakeClosure` is an owned rvalue like the constructor call it wraps (`make_shared`): each captured value is a constructor argument, acquired into its field. The value's type is the function type, so every other row applies through `__function<…>.__acquire`/`__release`. At zero, the function type's `__dtor` calls `__destroy`, the closure's `__dtor`, whose `release_field_refs` releases the captures. |
| `std::weak_ptr<T>` | `__weak<T>` (`passes/weak_types.rs`): a synthesized struct that is a view of `T`'s two head fields, so the rows above apply to weak slots through its `__acquire` (`++__weakcount`) and `__release` (`--__weakcount`, free at 0), atomic when `T` is `[Shared]`. `__weak_from<T>`, `__weak_upgrade<T>` and `__weak_expired<T>` are `Expression::Weak` nodes (`codegen_weak`); the first two are owned rvalues. `__weak_upgrade` is a compare-and-swap loop that increments the strong count only while it is non-zero (`weak_ptr::lock`). `check_function_types` rejects implicit `T` ↔ `__weak<T>` conversions. |
| Threads | Counts are plain by default. A `[Shared]` struct (`StructDef::is_shared`) and every `shared` function type (`shared (T) => R`) step them atomically (`CountStep`), like `std::shared_ptr`'s control block; plain function types count plainly. `passes/check_shared_types.rs` keeps non-thread-safe values (plain function values included) out of shared structs and globals, and `passes/shared_functions.rs` lets a closure become `shared` only when its captures are thread-safe, and wraps a `shared` value used as a plain one in a plain adapter that holds it (a struct holding a `shared_ptr` field). |

Debugging aids: set `PEP_CHECK_SYNC` to make every `MutexGuard.exit`
check, before it unlocks, that nothing outside the locked value refers into
it. `exit` calls the `__census<T>(slot)` intrinsic, which
`copies::synthesize_copies` lowers to `_pep_check_sync<T>` (`copy.pep`) for
a `T` that is not thread-safe and can be copied, and to nothing otherwise.
`_pep_check_sync` copies the value through a `Copies` whose `_edges`
counts, per original object, the references `_copy_object` passes through
(the slot's included), then compares each object's strong count with its
tally and panics on a difference. The flag `_PEP_CHECK_SYNC_ON` is read
once, in `internals.pep` (module constants initialize file by file, and
that file's allocation counter must exist before any `String` is built).

Set `PEP_TRACE` to make `_pep_trace_ptr` and
`_pep_trace_int` (internal runtime helpers, not part of the language's API)
print every constructor, acquire, release, and destructor with the new count. `_pep_live_allocs()` counts live
allocations (an atomic counter, since threads allocate concurrently);
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
| `internals.pep` | C externs (`malloc`, `memcpy`, `puts`, …; none exported, so a runtime file that needs one declares it itself), `assert`/`panic` (each overloaded on a `String` or `__ptr<char>` message; a string literal picks the pointer one) and the internal `char*` forms `_pep_assert`/`_pep_panic` that compiler-generated checks call, `_pep_malloc`/`_pep_free`/`_pep_realloc`/`_pep_live_allocs`, the `PEP_TRACE` helpers `_pep_trace_ptr`/`_pep_trace_int`, `_pep_swap_refs`/`_pep_move_ref` (raw slot moves for containers), `_pep_hash_bytes` (FNV-1a), UTF-8 helpers, and `_pep_print*`. |
| `string.pep` | `String` (fields `_data`, `_length`, `_size`, `_version`), `StringIterator`, `StringBuilder`, the `to_string` overloads (integers, `bool`, and the generic `to_string<T>` calling `value.to_string()`), the `ToString` trait, and `_pep_interpolate<T>`, which interpolated strings call. |
| `array.pep`, `hash.pep` | `Array<T>` (also written `T[]`), `HashMap`, `HashSet`, and their iterators. |
| `iterator.pep` | `Iterator<T>` and `Iterable<T>` traits, the `for` protocol (`next()`/`current()`, `iterate()`). |
| `scoped.pep` | `Scoped<T>`, the `with` protocol (`enter()`, and `exit()` called from the destructor). |
| `weak.pep` | `Weak<T>` over `__weak<T>`; implements `Scoped<T>` (`enter()` upgrades). |
| `result.pep` | `Error`, `None`, `Result<TValue, TError=Error>`. |
| `atomic.pep` | `Atomic<T>` over the `__atomic_*` intrinsics. `[Shared]`, so its `T` must be thread-safe. |
| `copy.pep` | `copy<T>`, the `Copyable<T>` trait and `Copies` (original-to-copy addresses, deferred weak fixes), and `_pep_check_sync<T>`, the `PEP_CHECK_SYNC` census. `Copies.copy<T>` is the `__copy<T>` intrinsic that `passes/copies.rs` lowers. `String`, `Array`, `HashMap` and `HashSet` implement `Copyable` with a `copy(Copies)` method; `io.File` is `[NotCopyable]`. |
| `process.pep` | `arguments()` and `exit(code)`, and `_pep_arguments()`, which a `main(args: String[])` receives through `entry_point` (§ pass 0a). The C `main` the compiler emits takes no `argc`/`argv`, so `arguments()` asks the platform: `/proc/self/cmdline` on Linux, `_NSGetArgc`/`_NSGetArgv` on macOS, `__p___argc`/`__p___argv` on Windows. `exit` flushes the C streams and calls `_Exit`, since the exported name takes C `exit`'s. |
| `io/` | The `io` module (`import io`): `module.pep` re-exports the public API. `types.pep`, `path.pep`, `file.pep`, `directory.pep`, `address.pep` (`IpAddress`, `SocketAddress`, `resolve`; parsing and formatting in pure Pepper) and `socket.pep` (`TcpListener`, `TcpStream`, `UdpSocket`, and the shared sockaddr encoding) implement it. `sys_posix.pep`/`sys_windows.pep` hold the file-system platform layer and `socket_posix.pep`/`socket_windows.pep` the socket layer (BSD sockets and `getaddrinfo`; Winsock through `ws2_32`, started once with `WSAStartup`, sockets created overlapped for the planned IOCP driver). |
| `async/` | The `async` module (`import async`): `thread.pep` (`Thread`, `ThreadId`, `ThreadBody`, the `_async_thread_main` entry point passed to the OS with `__function_pointer`), `thread_local.pep` (`ThreadLocal<T>` over OS thread-local keys whose destructor is its static `_release_slot`, and the `[Isolated]` `ThreadLocalGuard<T>` that `enter()` returns for `with` access), `cpus.pep` (`logical_cpus`, `physical_cpus`), the synchronization types in `mutex.pep` (`Mutex<T>`, `MutexGuard<T>`, `Condition<T>`), `once.pep` (`Once`, `Lazy<T>`) and `channel.pep` (`Channel<T>`, `ChannelIterator<T>`), and the platform layer in `sys_posix.pep` (pthreads and pthread mutexes and condition variables, `clock_gettime`, `sysconf`, sysfs topology through `io`, `sysctlbyname`) and `sys_windows.pep` (`CreateThread`, `FlsAlloc`, `SRWLOCK` and `CONDITION_VARIABLE`, `GetTickCount64`, `GetLogicalProcessorInformationEx`). The synchronization types are `[Shared]`: platform locks live in fixed heap blocks (`const __ptr<void>`), and state that changes lives in raw heap slots read and written only under the lock. `Lazy` stores its value behind a `const __ptr<T>` field, so `check_shared_types` accepts only a thread-safe `T`. `Mutex` accepts any struct `T` (its slot is a `__ptr<void>`): its `MutexGuard<T>` is `[Isolated]`, so `check_confinement` keeps the locked value apart from the rest of the program, and its constructor and `replace` take `[Move]` values and `move` them into the slot under the lock, with no copy. `Channel` accepts any `T`: its buffer is a `__ptr<__ptr<void>>`; `send` and `try_send` take `[Move]` values and move them into the buffer under the lock, and `_pop` moves them out. A Mutex records its holder's OS thread id (`_async_sys_os_thread`) to panic on a re-lock and to check `Condition.wait`'s caller. |
| `msvc.bat` | A vcvarsall helper left over from the old MSVC link path. |

- **Loading.** Every top-level `runtime/*.pep` is a prelude file. Its
  `export`s are visible in every program without an import. `runtime/io` is
  found as a module because the runtime directory is on the search path.
- **Naming convention for internals.** Names prefixed `_pep_` (core),
  `_io_` (io module) and `_async_` (async module) are internals. They are `export`ed so other runtime
  files can use them. They are exempt from the documentation standard, and
  a module does not re-export them (`io/module.pep` re-exports only the
  public types).
- **Lowered by name.** `print` → `_pep_print`/`_pep_print_int`/
  `_pep_print_float`. A name the compiler synthesizes must be exported:
  linking mangles private names per file. Every constructor calls `_pep_malloc`, and `__release`
  calls `_pep_free` once the weak count reaches 0. `__acquire` and `__release` call `_pep_trace_ptr`
  and `_pep_trace_int`. Compiler-generated checks (null function and trait
  values) call `_pep_assert`, which takes a raw `char*`.
  Codegen calls these by name after visibility has run, so `_pep_print*`
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
  (`pepper-docgen -- check`). See `docs/src/contributing/docs.md` for the
  book.

---

## 8. Language server and VS Code extension

**`tools/lsp/src/main.rs`** (`pepper-lsp`, stdio, tower-lsp):

- Document text lives in `PepperLsp.docs`. On open or change,
  `publish_diagnostics` runs these checks:
  1. `parse_source_diag` on the buffer (precise parse errors).
  2. Otherwise, `program(uri)` → `load_program(Root { unsaved text },
     Setup { mode: Lenient })`, then `sema_model_of` (build every file, run
     the platform filters, `struct_body::apply`, and `transform_pass`
     **under `catch_unwind`**), then `visibility_diagnostics`.
     Unresolved-module imports are downgraded to warnings because the
     editor does not know the compile's `-I` directories.
  3. Warnings: the parser's, then `deprecation_warnings` (the program's
     `deprecation_warnings()` and the sema model's `warnings`, in the
     document only). `code_action` recomputes them (`document_warnings`)
     and `quick_fixes` turns each fix into a code action.
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
  `DocComment::to_markdown`).
- **Implicit conversions.** `convert_to_traits` records each conversion it
  inserts whose value has a location in `Module::conversions` (string
  literals carry their `Loc` for this, and the `String` constructor call
  they become keeps it). `hover_at` runs sema once and appends a note when
  the offset is inside a converted value (`conversion_at`); `inlay_hint`
  returns `To(` / `)` around each one in the document (`conversion_hints`),
  unless the client's `inlayHints.implicitConversions` initialization option
  is `false`.
- Completion lists keywords, globals, locals, and struct members; after
  `Enum.` it lists that enum's cases alone (`enum_cases_before`, on a parse
  with a placeholder after the dot, `parse_after_dot`, since `Color.` alone
  does not parse). Document symbols come from the AST.
- Enums: hover on `Enum.Case` shows its value from the sema model
  (`enum_case_of`), or the values a case carries (`Doc.Text(text:
  String)`), or the bare case while the program does not build
  (`enum_case_in`). A `match on 'E' does not handle ...` error offers a
  quick fix that adds an empty arm per missing case before the `match`'s
  closing brace (`missing_arms_fix`, `find_match`), binding a case's values
  by their declared names.
- Runtime discovery is the same as the compiler's (section 2.2): from the
  directory the server was started in, then from the `pepper-lsp`
  executable's directory, unless `PEPPER_RUNTIME` is set. In `Lenient`
  mode a missing runtime is not an error.
- Tests: `tools/lsp/src/tests.rs` builds a module tree in a temp directory
  and asserts hover and definition results. `tools/lsp/smoke-test.mjs`
  exercises raw JSON-RPC.

**`tools/vscode-pepper`**: `src/extension.js` launches the server. It runs
a *shadow copy* of the binary because Windows locks a running exe, polls
the binary and restarts on change, and registers `pepper.restartServer`.
The server comes from `pepper.lspPath` or from the bundled
`server/<platform-arch>/` (`serverPath.js`). Syntax highlighting is
`syntaxes/pepper.tmLanguage.json`. `vsix.yml` builds the VSIX for four
targets (x64 Windows and Linux, x64 and arm64 macOS) and publishes it as
a `vsix-v*` release; it runs only for a `vX.Y.Z` tag or a manual dispatch.
`scripts/install-vscode-extension.ps1 [-Watch]` builds `pepper-lsp` in
release mode, packages the VSIX with `npx @vscode/vsce`, and runs
`code --install-extension` from the current branch.

**`tools/syntax` and `tools/pep-fmt`** are Pepper programs, built with
`pepper -I tools tools/pep-fmt/main.pep`. They are the project's largest
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
  fails there. The tool's own sources must be pep-fmt formatted.

---

## 9. Tests

`cargo test --workspace` runs everything. Without `--workspace`, only the
root package's test runs. The suite has roughly 810 `#[test]` functions.

| Kind | Where | Notes |
| --- | --- | --- |
| Parser unit | `crates/pepper-parser/src/parser/parsers.rs` (`mod tests`), `parser.rs`, `diagnostic.rs`, `doc.rs` | Helpers `parse`, `parse_expr`, and `parse_type` take the `track_source` guard. `parser.rs` tests pin exact rendered parse errors. |
| Sema model | `crates/pepper-sema/src/model_tests.rs`, `visibility.rs` tests | `compile()` = parse → `build` → filters → `struct_body::apply` → `transform_pass`, then assertions on the model. |
| Codegen JIT | `crates/pepper-codegen/tests/codegen_tests.rs`; `target.rs` unit test | JIT `test()`, check the returned `i32`. |
| Driver integration | `crates/pepper-driver/tests/integration/*_tests.rs` (arrays, strings, hashes, io, modules, visibility, platform, atomics, function values, iterators, `with` blocks, shared_ptr semantics, C arithmetic semantics, store types (`store_type_tests.rs`), edge cases, docs-audit regressions in `audit_fixes_tests.rs`, …) | Usual shape: `compiler::compile_with_runtime("test.pep", src)` → `CodeGenerator::jit_execute(&mut m, "test")`, asserting 0 (each check returns a distinct negative code). Multi-file tests (`module_tests.rs`, `diagnostic_tests.rs`) write a tree to `temp_dir()` and compile through `Options::parse_from` + `compiler::compile`. `platform_tests.rs` uses `with_simulated_host`. `compile_tests.rs::full_pipeline_link_and_spawn` and `link_tests.rs` link real executables. |
| Diagnostics | `crates/pepper-driver/tests/integration/diagnostic_tests.rs` | `error_of(name, src)` returns the full rendered error (header, source line, caret). Add one for every new error. |
| Corpus | `tests/**/*.pep` | `tests/parser_corpus.rs` requires every file to parse. `corpus_tests.rs::corpus_files_respect_visibility` checks every `tests/*/test.pep` (runs), and `corpus_files_compile_and_run` compiles, links, and runs each fixture with `-I tests`. |
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
   it in `model.rs`, `passes/mod.rs::walk_expression`, the passes that must
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
re-exports, and blocks, and sema carries it on `attributes`. Attributes
nobody reads are ignored silently. To give one meaning, read it where it
applies:

- `[Link("lib")]` → `pepper_driver::link_libraries`
- `[LinkName("sym")]` → `ExternDef::link_name`, used by
  `instantiate_extern`
- `[Target(...)]` → `passes/platform.rs`
- `[Deprecated("message", "replacement")]` → `deprecation.rs` (checked by
  the builder, read by `check_uses` and `check_deprecated_members`)
- `[Shared]` → `StructDef::is_shared`
- `[Isolated]` (structs), `[Move]` (parameters; the parser accepts
  attributes before any parameter) and `[MoveSource]` (the parameter of the
  runtime's `move<T>`; runtime free functions only) →
  `passes/check_confinement.rs`, which reports any other parameter
  attribute (`check_parameter_attributes`) and wraps each `[MoveSource]`
  argument in `Expression::Move` (`lower_moved_arguments`); codegen reads
  both (`check_confinement::takes_over`, `sending_params`)
- `[NotCopyable("why")]` → `passes/copies.rs`
- `[Implicit]` → `StructDef::implicit_from`, checked in `builder.rs` and
  applied by `convert_to_traits`

Validate the arguments and report a located error. Add driver tests (see
`link_tests.rs`, `platform_tests.rs`).

### Add a platform-specific runtime function

Write twin declarations with the same name and signature, guarded
`[Target(OS(Windows))]` and `[Target(!OS(Windows))]` (see
`runtime/io/path.pep`, `sys_posix.pep`, and `sys_windows.pep`). Dropped
twins are never compiled together. Use `[LinkName]` when the
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
there.

- **`ci.yml`** (push to `main`, PRs):
  - `test` is the required check. It runs on the self-hosted
    **`pepper-windows`** runner: provision LLVM (`ci-provision-llvm.sh`,
    cached), `cargo build --workspace --locked`, `cargo test --workspace
    --locked`, and `pepper-docgen -- check`.
  - `llvm-matrix` and `llvm-versions` run on self-hosted **`pepper-linux`**
    and test against every LLVM major that apt offers.
  - `changes` runs first and diffs the PR against its base. When only prose
    changed (`*.md` other than `docs/src/SUMMARY.md` and
    `docs/src/reference/`, or `.agents/`/`.claude/`), every other job is
    skipped, and a skipped `test` counts as passing.
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
  (`_pep_print_int`) can reach only a declaration that keeps its name, so
  it must be exported. Exported names still share one namespace across
  modules. `SymbolTable` lets a later declaration overwrite an earlier one.
- **Trait values are one level deep.** There are no supertraits, so one
  trait type never converts to another, and there is no downcast from a
  trait value back to its struct. Generic parameters cannot require a
  trait (`<T: Shape>`). `Atomic<T>` of a trait type is rejected: two
  pointers do not swap atomically. `Weak<T>`/`__weak<T>` of a trait type is rejected by
  `convert_to_traits`: the weak view needs the concrete struct's head. `for` and `with` still choose their
  protocol by the methods a type has (`ForIterator`), statically for a
  struct and through the vtable for a trait value.
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
  `_pep_move_ref` are the code's own promise. A reference read through a
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
- **`copy` of a trait value** is an error: it needs a vtable slot.
- **Only the first sema error is reported** per compile
  (`errors::report`).
- **Specialization fixpoint is capped at 16 rounds.** A type that nests
  itself through generics stops there instead of looping forever.
- **Unused CLI flags**: `-g`, `-v`, and `-T` channels other than `time`; `--MSVC` returns an
  error. Only the first source file is compiled.
