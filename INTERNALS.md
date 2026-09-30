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
| `crates/pepper-sema` | Program loading and module linking (`program.rs`, `modules.rs`, `visibility.rs`, and the scope walk they share, `scope_walk.rs`), AST → model builder (`builder.rs`), the sema model (`model.rs`), struct synthesis (`struct_body.rs`), and the transform passes (`passes/`). No LLVM. |
| `crates/pepper-codegen` | Sema model → LLVM IR through `inkwell` (`lib.rs`, plus `types.rs`, `address.rs`, `ops.rs`, `target.rs`). Also hosts the MCJIT entry points the tests use. |
| `crates/pepper-driver` | Glues the stages together (`compiler.rs`), CLI options (`options.rs`), object emission and linking (`lib.rs`, `linker.rs`). Holds nearly all integration tests (`tests/*.rs`). |
| `xtask/` | `cargo setup` (`cargo run -p xtask -- setup`): picks and runs `scripts/setup-llvm.{sh,ps1}` and writes `.cargo/config.toml`. Has no dependencies, so it builds before LLVM exists. |
| `tools/lsp` | `pepper-lsp`, a tower-lsp language server. Parser and sema only, so it never links LLVM. |
| `tools/vscode-pepper` | VS Code extension: TextMate grammar, language configuration, and a client that launches `pepper-lsp`. |
| `tools/docgen` | `pepper-docgen`: generates `docs/src/reference/` from runtime doc comments and builds the mdBook site. |
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
    builder::build_file(i)        AST → sema model, locations carry FileId(i)
    Module::merge                 all files into ONE sema Module (names already unique)
  compiler::run_passes
    apply_platform_filters        drop [Target(...)] that is false on the host
    struct_body::apply            resolve_type_aliases; __refcount, ctor, dtor,
                                  __acquire/__release bodies
    passes::transform_pass        ~30 ordered steps (section 3)
  ▼
CodeGenerator::generate                                           (codegen/src/lib.rs)
  instantiate structs → sizes → methods → ctors → externs → functions
  emit_globals → codegen structs/functions → module.verify()
  ├─ --emit-llvm ─→ <build>/<name>.ll
  ▼
target::host_machine().write_to_file → <build>/<name>.o           (build = .pep/build)
link_libraries (from [Link]) + -l + runtime/*.a
linker::link → clang -o <out> <obj> -L… -l… (+ kernel32 user32 shell32 on Windows)
```

The CLI produces an executable and never runs it. Tests usually stop after
`generate` and JIT the module instead (see [section 9](#9-tests)).

### 2.1 CLI options (`crates/pepper-driver/src/options.rs`)

`Options` is a clap derive struct. Only these options take effect:
`source_files` (only the first is compiled; the rest are ignored), `-I`,
`--import`, `-l`, `-o`, `--build`, `--emit-llvm`, `--emit-ast`, and
`--no-runtime`. `-g`, `-v`, `-T`, and `--Tall` are parsed and ignored.
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
  `ModuleRoots::namespace_of` (module name plus path inside the module, or
  the file stem outside any module; made unique with `#2`, `#3` in load
  order). Exports, externs, and concrete overrides keep their names; so do
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
  generics of that name, and a generic beside another function of its name
  in one file is an error. The
  visibility check applies the same rule (`Decl::is_override`).
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
- **`scope_walk.rs`** is the traversal linking and visibility share: it
  tracks the names bound at each point (parameters, locals, generic
  parameters, the members of the struct being defined or extended), which
  hide top-level names. The `scope_walker!` macro writes it once as two
  traits, `ScopeWalkMut` (linking's `Rewriter`, which rewrites the AST) and
  `ScopeWalk` (visibility's `Checker`, which only reads it); each pass
  implements the hooks for references, member names, type names, visible
  members, and `extend` parameters. In `extend Box<T>`, a name equal to
  `Box`'s own parameter at that position is always the parameter, even when
  the program also declares a struct `T` (a runtime `extend ArrayIterator<T>`
  must not see a user's `struct T`).
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
  declaration). The grammar itself rejects a second constructor or
  destructor in one struct (`redefinition of the constructor of 'S'`).
- **Grammar** (`parser/parsers.rs`): hand-written winnow combinators over
  `&mut &str`. The precedence ladder is documented at the top of the file
  (`assignment → ternary → … → postfix → atom`, with `cast` for `as`).
  `parse_module` is the top-level loop: imports, `export` re-exports, then
  `declaration`. Rules return `ErrMode::Backtrack` (via `bt`) to let an
  alternative try, or `ErrMode::Cut` (via `cut`/`cut_expecting`) to commit.
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
- **Thread-local parser state** lives in `parsers.rs`: `SRC_LEN`, `MAX_POS`
  (the furthest offset any rule reached), `EXPECTATION` (what was expected
  at that furthest failure), `QUALIFIERS` (import qualifiers bound so far,
  so `q.Box<int>()` counts as a generic construction only when `q` is an
  import), `EXPRESSION_PROBE`, `WARNINGS` (deprecations), and `ERROR` (a
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
- **AST** (`ast.rs`): `Module { imports, exports, declarations }`.
  `Declaration` is `Variable | Function | Struct | Trait | Extend |
  TypeAlias`. The file also defines `Statement`, `Expression`, `TypeName {
  name, generic_types, span }`, `Attribute { body: Expression, span }`,
  `Import`, and `ExportAlias`. Every node carries a byte `Span`; named nodes
  also carry `name_span`. Externs are `FunctionDecl { external: true, … }`.
  Every node implements `Display`; `--emit-ast` prints through it.
  Function types `(P…) => R` are parsed directly into
  `__function<R, P…>`, and thread-safe ones `shared (P…) => R` into
  `__shared_function<R, P…>` (`shared_function_type_name`; `shared` is a
  contextual keyword, not in `RESERVED`).

### 2.4 Building the sema model (`crates/pepper-sema/src/builder.rs`, `model.rs`)

- `build_file(&ast::Module, FileId)` sets the thread-local `FILE`, so
  `loc(span)` stamps every `Loc` with the file being built. `build` uses
  `FileId(0)`; unit tests call it.
- `type_name_from` lowers `T[]` to `Array<T>`.
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
    declared return type is not `bool` is rejected.
  - Structs get `constructor`, `destructor` (`__dtor`), and empty `acquire`
    and `release` shells. Top-level `var`s go to `module.globals`. Externs
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
  `ForIterator`, `WithEntered`, `ToTrait`, `ClosureLiteral`, `MakeClosure`,
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
turns every closure literal into a synthesized struct `__closure_N` (generic
over the enclosing code's type parameters) and a `MakeClosure` creation
expression, so the new structs get their bodies below like any other. The
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
- `finish` builds the constructor. A hidden `size` local is patched with the
  real ABI size in codegen by `patched_ctor`. The constructor calls `this =
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
| 1 | `check_bindings` | Reports a local declared twice in one scope (`redefinition of 'x'`, with a note at the previous one) and an assignment, compound assignment, or `++`/`--` to a `const` local, global, or (outside the constructor) field (`cannot assign to const variable 'x'`). |
| 2 | `synthesize_function_types` (`function_types.rs`) | Each distinct `__function<R, P…>` and `__shared_function<R, P…>` becomes a synthesized refcounted struct (`__refcount`, `__weakcount`, `__invoke`, `__destroy`; its destructor calls `__destroy` through `CallPointer` when set, which releases a closure's captures), and each `__weak<T>` with a concrete struct `T` a weak view struct (`weak_types.rs`). A `shared` one counts atomically; a plain one counts plainly and leaves a count at or above `STATIC_REFCOUNT` alone, so the static object of a named function, which several threads may hold as plain values, is only ever read. |
| 3 | `resolve_literals` | Folds unary minus into numeric literals. |
| 4 | `tag_generics` | Renames concrete overrides of generic functions to their spelled type (`hash<int>`). |
| 5 | `convert_string_literals` | `"abc"` → `String(raw, size, length)` constructor call. The raw literal stays a `char*` global. |
| 6 | `gather_generics` | Records generic uses as `struct_specs` and `func_specs`. |
| 7 | `resolve_implicit_types` | Infers `auto` locals and symbol types by scoped lookup (`p[i]` through a `__ptr<T>` or `T*` is a `T`; a `void` pointer is left to codegen), and a function's return type from its `return` statements when it declares none (`void` when it returns no value, `int` for `main`). Runs `closures::sync_closures` in the same fixpoint loop (§2.6). A call to a generic function or method without type arguments (`larger(3, 9)`, `b.map(f)`) gets them from its arguments' types through `type_arguments::GenericSignature` (bind each parameter type against an argument type, `unify`), and is renamed to the specialization (`larger<int>`, `map<long>`); a closure argument receives the partly bound parameter type as its expected type, so inference runs across fixpoint rounds. |
| 8 | `resolve_resolvables(false)` | Resolves struct, function, and method references against the symbol table. |
| 9 | `apply_extensions(false)` | Clones `extend` methods onto their target and records traits. For `extend S with T`, checks that `S` has every method `T` declares and copies in `T`'s default methods (those with a body) that `S` lacks, reporting `'S' does not implement 'm', required by trait 'T'` otherwise. Each implementation must have the declared signature, except that a struct result may stand for a declared trait result. |
| 10–11 | `specialize_structs`, `specialize_functions` | Clones generic bases into `Name<args>` instances with substituted types. A `void` argument erases what it types (`erase_void`): fields and parameters of that type, stores of them, and a `return` of one, so `Result<void>` has no `Value` and `ok()` takes no argument. A generic struct's `generic_methods` are cloned with the struct's parameters substituted and keep their own. |
| 11b | `specialize_methods` (`generic_methods.rs`) | For each method call named `m<args>` on a struct with a generic method `m`, clones `m` into `method_members` as `m<args>` with its own parameters substituted. `apply_extensions` routes generic extension methods and generic trait default methods (`Iterator<T>.map<U>`) to `generic_methods`; `traits::is_dispatchable` excludes them, since a vtable has one slot per method. |
| 12 | `synthesize_function_types` | For function types that specialization exposed. |
| 13 | `convert_intrinsics` | Rewrites `__ptr<T>` to `T*`, including the `T` of intrinsic nodes that specialization substituted. Turns `__is_pod`, `__default`, `__refcount`, `__address`, `__atomic_load/store/cmpxchg/fetch_*` calls into intrinsic nodes, and `__function_pointer(f)` into `Expression::FunctionPointer` (a free function, or a static method of the enclosing struct, whose owner type specialization substitutes). |
| 14–15 | `resolve_resolvables`, `apply_extensions(true)` | Resolves what remains and applies specialized extensions. |
| 16 | `convert_member_refs` | In methods, a bare field becomes `this.field` and a bare call becomes a method call (parameters are exempt). In a trait's default method copied into a struct (`FunctionDef::trait_default`, set by `apply_extensions`), only the trait's methods count and no fields. |
| 17–18 | `resolve_implicit_types`, `resolve_operators` | `x[i]` → `__index_get`/`__index_set` or POD `ArrayIndex`. An overloaded binary operator becomes a method call. Without its own `!=`, `a != b` on a type with `==` becomes `!(a == b)`. `===` and `!==` are never overloaded; codegen compares their raw values (`BinaryOp::identity_as_equality`), addresses for references. |
| loop ≤16× | `gather_generics`, `specialize_structs`, `specialize_functions`, `specialize_methods` | Repeats until the counts of structs, functions and methods stop growing (specializing exposes new uses). When the module has generic methods, each round first runs `resolve_implicit_types` so calls on newly specialized structs get their type arguments. Bounded because a self-nesting generic never converges. |
| then | `convert_intrinsics`, `resolve_resolvables`, `convert_member_refs`, `synthesize_function_types` | Covers what the loop created. |
| final | `reference_functions` (`function_references.rs`) | A method, constructor or generic function specialization used as a value (`p.norm`, `Point.norm`, `Point`, `Box<int>`, `identity<int>`) becomes a `MakeClosure` of a new complete closure struct whose `__call` forwards to it; a bound method's receiver is its one capture (`__receiver`). Needs final types to tell a method from a field, so it runs here, before `release_field_refs` releases the receiver. A local inferred from the expression (`var f = Point;`) is retyped to the function type. Reports storing `this.m` in a field of `this`. |
| final | `release_field_refs` | Inserts `__release` calls for struct-typed fields, in reverse declaration order, at the end of the destructor. The object itself is freed by `__release` once `__weakcount` reaches 0, not by the destructor. |
| final | `resolve_implicit_types`, `resolve_operators`, `convert_print_calls`, `resolve_resolvables(true)`, `synthesize_function_types` | `convert_print_calls` turns a `String` argument of `print` into `arg.Data`. `resolve_resolvables(true)` is the step that reports `use of undeclared identifier`, `call to undeclared function`, and similar. |
| final | `check_type_arguments` (`type_arguments.rs`) | Reports a generic call whose type arguments the arguments did not determine (`cannot infer the type arguments of 'make' from its arguments; write them: make<T>(...)`, with a note at the declaration). |
| final | `check_closures` | Reports a closure parameter, return or capture type that nothing inferred (`cannot infer the type of parameter 'x'`). |
| final | `shared_functions`, `synthesize_function_types` | Where a function value flows into a `shared` function-typed slot, retypes a `FunctionRef` or `MakeClosure` to the `shared` type, reporting a capture that `check_shared_types::unsafe_part_in` finds not thread-safe (at its first use in the closure, with a note at the captured local). Where a `shared` value flows into a plain slot of the same signature, wraps it in a new plain adapter closure (`__inner`, `__call` forwarding to it; its destructor releases `__inner`), so plain counts never touch a shared object. Any other plain value in a `shared` slot is left for `check_function_types`. |
| final | `convert_to_traits` | Implicit constructor conversions and trait conversions, at every place a value flows into a typed slot (initializer, assignment, argument, return). A value flowing into a struct whose constructor is `[Implicit]` (`StructDef::implicit_from`) becomes a `FunctionCall` of that constructor when its type matches the parameter exactly or by promotion (integer widening, a fitting integer literal, `f32` → `f64`, struct → declared trait); the call's own argument never converts through another constructor. It wraps every struct value that flows into a trait-typed slot in `ToTrait`, checking that the struct declares the trait; rejects calls through a trait value to members it cannot dispatch, and struct results of trait methods that do not conform to the declared trait type. Records the trait types in use in `module.trait_types`. See §4.2. |
| final | `check_function_types` | Rejects a value whose type does not match the typed slot it flows into (variable initializer, assignment, argument, return): a function value of a different signature, a plain function value where a `shared` one is expected (`cannot initialize variable 'f' of type 'shared () => void' with a value of type '() => void'`), a number or a raw pointer where a struct is expected or the reverse (a struct may pass as `void*`, but `void*` is never a struct; a string literal in a pointer slot is its `char*` global), or a different struct (`cannot initialize variable 'x' of type 'int' with a value of type 'String'`). It also rejects a call returning `void` used as a value (stored, passed, returned, an operand, or a condition). Errors are located `Diagnostic`s. |
| final | `check_shared_types` | Checks every `[Shared]` struct: each field must be `const` (on the declaration) and of a thread-safe type (on each concrete struct, so `Atomic<String>` is reported at the code that names it). A `shared` function type is thread-safe; a plain one is not. Then checks every module-scope variable, exported or not, by the same two rules, as if it were a field of a `[Shared]` struct (any function can hand a global to any thread). |
| final | `lower_with_blocks` | Picks each `with` condition by `enter()`'s final type: a null test for a struct or pointer, no branch otherwise (a `void` result becomes an expression statement). Reports the `with` errors (no `enter()`, binding a `void` result, `else` on a non-nullable result, assigning to the binding). |

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
only inside `with_simulated_host`. The builder's `FOR_LOOPS` and
`WITH_BLOCKS` counters are never reset; they only keep hidden local names
unique. This lets tests compile concurrently on separate threads.

---

## 4. Codegen (`crates/pepper-codegen`)

`CodeGenerator::new(&Context, name)` sets the host data layout.
`generate(&mut Module) -> Result<(), Diagnostic>` runs `generate_module`.

1. **Instantiation.** Every concrete struct is registered as an opaque type
   first (a field may name a struct declared later). Then:
   `instantiate_struct` (LLVM struct body) → ABI sizes via
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
  `_pep_malloc` (zeroed). `sizeof(StructType)` is pointer-sized, because a
  struct occupies a pointer-sized slot. The object's ABI size is used only
  inside the constructor.
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
  by argument type), `assert(cond, message)` and `panic(message)` (a
  string-literal message to the runtime's own functions calls
  `_pep_assert`/`_pep_panic` with its raw global, so no `String` is built;
  a replacement declared with a `__ptr<char>` message gets the raw global
  itself; anything else is an ordinary call with a `String`; to revisit when
  function overrides land), `release<T>(v)`,
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
- **Function values**: `FunctionRef` produces a static function object
  (`__function_object.<name>`, or `__function_object.shared.<name>` for a
  `shared` function type) whose `__invoke` points at a thunk
  (`__function_thunk.<name>`, one per function). Its strong count starts at
  `STATIC_REFCOUNT`, so it is never freed. `codegen_invoke` loads `__invoke` and calls
  it with the signature of the static type. `MakeClosure` is its closure
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
  `run_static_constructors`.
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

### 4.1 Object emission, linking, running (`driver/src/lib.rs`, `linker.rs`)

`run` writes `<build>/<module>.o` with the host `TargetMachine`. It collects
libraries in this order: `-l` flags, then `runtime/*.a` (as
`-L<dir> -l<name>`), then `link_libraries(&module)`, which gathers the
`[Link("name")]` attributes of externs that survived platform filtering,
deduplicated. `linker::link` invokes **clang as the link driver**,
preferring `$LLVM_SYS_<NN>1_PREFIX/bin/clang` so the linker matches the
LLVM the compiler was built against, and falling back to `clang` on PATH.
`default_system_libraries` adds `kernel32 user32 shell32` on Windows. Link
warnings are forwarded. Failures include both stdout and stderr, because
MSVC's link.exe writes unresolved symbols to stdout.

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
| By-value parameter | `codegen_function_unlocated`: acquire each struct parameter on entry (`this` excepted) and track it in the function scope. |
| Scope exit | `scopes: Vec<Vec<(name, type, slot)>>`. `release_scope` runs at block fall-through, `release_all_scopes` at `return`, and `codegen_loop_break` releases the scopes a `break` or `continue` leaves. |
| `return` | An lvalue read is acquired before `release_all_scopes`. A call result moves. |
| Discarded temporary | `Statement::Expression` releases `owned_temp_type(expr)`. Arguments that are owned rvalues are released after the call (`owned_arg_temps` in `codegen_call`). The receiver of `f().x` or `f()[i]` goes on `deferred_temps` and is released at the end of the full expression by `flush_deferred_temps`. Ternary arms use `codegen_expr_in_arm`. |
| Trait values | Same rules, same call sites: `Trait.__acquire`/`Trait.__release` are thunks into the vtable (§4.2), so the concrete type's `__release`, and at zero its `__dtor`, run. `ToTrait` does no refcount work of its own: converting an lvalue read acquires as the read would, and an owned rvalue moves. |
| Destruction | At zero, `__release` calls `__dtor`, which runs the user's `destruct` body, then the field releases added by `release_field_refs`. `__release` then drops the strong references' weak reference and frees the object if `__weakcount` reached 0. |
| Closures | `MakeClosure` is an owned rvalue like the constructor call it wraps (`make_shared`): each captured value is a constructor argument, acquired into its field. The value's type is the function type, so every other row applies through `__function<…>.__acquire`/`__release`. At zero, the function type's `__dtor` calls `__destroy`, the closure's `__dtor`, whose `release_field_refs` releases the captures. |
| `std::weak_ptr<T>` | `__weak<T>` (`passes/weak_types.rs`): a synthesized struct that is a view of `T`'s two head fields, so the rows above apply to weak slots through its `__acquire` (`++__weakcount`) and `__release` (`--__weakcount`, free at 0), atomic when `T` is `[Shared]`. `__weak_from<T>`, `__weak_upgrade<T>` and `__weak_expired<T>` are `Expression::Weak` nodes (`codegen_weak`); the first two are owned rvalues. `__weak_upgrade` is a compare-and-swap loop that increments the strong count only while it is non-zero (`weak_ptr::lock`). `check_function_types` rejects implicit `T` ↔ `__weak<T>` conversions. |
| Threads | Counts are plain by default. A `[Shared]` struct (`StructDef::is_shared`) and every `shared` function type (`shared (T) => R`) step them atomically (`CountStep`), like `std::shared_ptr`'s control block; plain function types count plainly. `passes/check_shared_types.rs` keeps non-thread-safe values (plain function values included) out of shared structs and globals, and `passes/shared_functions.rs` lets a closure become `shared` only when its captures are thread-safe, and wraps a `shared` value used as a plain one in a plain adapter that holds it (a struct holding a `shared_ptr` field). |

Debugging aids: set `PEP_TRACE` to make `_pep_trace_ptr` and
`_pep_trace_int` (internal runtime helpers, not part of the language's API)
print every constructor, acquire, release, and destructor with the new count. `_pep_live_allocs()` counts live
allocations (an atomic counter, since threads allocate concurrently);
leak-census tests (`crates/pepper-driver/tests/shared_ptr_semantics_tests.rs`)
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
- Warnings exist only as deprecations: `Diagnostic::deprecated(what,
  instead, loc, fix)` builds a warning with the code `deprecated` and a
  `Fix` whose `Edit`s replace source spans. The renderer prints the fix under
  the caret, and the language server offers it as a quick fix. The book
  lists current deprecations in `docs/src/language/compiler-errors.md`.

---

## 7. Runtime (`runtime/`)

| File | Contents |
| --- | --- |
| `internals.pep` | C externs (`malloc`, `memcpy`, `puts`, …; none exported, so a runtime file that needs one declares it itself), `assert`/`panic` and their `char*` forms `_pep_assert`/`_pep_panic`, `_pep_malloc`/`_pep_free`/`_pep_realloc`/`_pep_live_allocs`, the `PEP_TRACE` helpers `_pep_trace_ptr`/`_pep_trace_int`, `_pep_swap_refs`/`_pep_move_ref` (raw slot moves for containers), `_pep_hash_bytes` (FNV-1a), UTF-8 helpers, and `_pep_print*`. |
| `string.pep` | `String` (fields `Data`, `Length`, `Size`, `Version`) and `StringIterator`. |
| `array.pep`, `hash.pep` | `Array<T>` (also written `T[]`), `HashMap`, `HashSet`, and their iterators. |
| `iterator.pep` | `Iterator<T>` and `Iterable<T>` traits, the `for` protocol (`next()`/`current()`, `iterate()`). |
| `scoped.pep` | `Scoped<T>`, the `with` protocol (`enter()`, and `exit()` called from the destructor). |
| `weak.pep` | `Weak<T>` over `__weak<T>`; implements `Scoped<T>` (`enter()` upgrades). |
| `result.pep` | `Error`, `None`, `Result<TValue, TError=Error>`. |
| `atomic.pep` | `Atomic<T>` over the `__atomic_*` intrinsics. `[Shared]`, so its `T` must be thread-safe. |
| `io/` | The `io` module (`import io`): `module.pep` re-exports the public API. `types.pep`, `path.pep`, `file.pep`, and `directory.pep` implement it, and `sys_posix.pep`/`sys_windows.pep` hold the platform layer. |
| `async/` | The `async` module (`import async`): `thread.pep` (`Thread`, `ThreadId`, `ThreadBody`, the `_async_thread_main` entry point passed to the OS with `__function_pointer`), `thread_local.pep` (`ThreadLocal<T>` over OS thread-local keys whose destructor is its static `_release_slot`), `cpus.pep` (`logical_cpus`, `physical_cpus`), and the platform layer in `sys_posix.pep` (pthreads, `sysconf`, sysfs topology through `io`, `sysctlbyname`) and `sys_windows.pep` (`CreateThread`, `FlsAlloc`, `GetLogicalProcessorInformationEx`). |
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
  `crates/pepper-driver/tests/runtime_docs_tests.rs` enforces it. The
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
- Completion lists keywords, globals, locals, and struct members.
  Document symbols come from the AST.
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
`syntaxes/pepper.tmLanguage.json`. `vsix.yml` builds the VSIX for six
targets and publishes it as a `vsix-v*` release on `main`.
`scripts/install-vscode-extension.ps1 [-Watch]` builds `pepper-lsp` in
release mode, packages the VSIX with `npx @vscode/vsce`, and runs
`code --install-extension` from the current branch.

---

## 9. Tests

`cargo test --workspace` runs everything. Without `--workspace`, only the
root package's test runs. The suite has roughly 810 `#[test]` functions.

| Kind | Where | Notes |
| --- | --- | --- |
| Parser unit | `crates/pepper-parser/src/parser/parsers.rs` (`mod tests`), `parser.rs`, `diagnostic.rs`, `doc.rs` | Helpers `parse`, `parse_expr`, and `parse_type` take the `track_source` guard. `parser.rs` tests pin exact rendered parse errors. |
| Sema model | `crates/pepper-sema/src/model_tests.rs`, `visibility.rs` tests | `compile()` = parse → `build` → filters → `struct_body::apply` → `transform_pass`, then assertions on the model. |
| Codegen JIT | `crates/pepper-codegen/tests/codegen_tests.rs`; `target.rs` unit test | JIT `test()`, check the returned `i32`. |
| Driver integration | `crates/pepper-driver/tests/*_tests.rs` (arrays, strings, hashes, io, modules, visibility, platform, atomics, function values, iterators, `with` blocks, shared_ptr semantics, C arithmetic semantics, edge cases, docs-audit regressions in `audit_fixes_tests.rs`, …) | Usual shape: `compiler::compile_with_runtime("test.pep", src)` → `CodeGenerator::jit_execute(&mut m, "test")`, asserting 0 (each check returns a distinct negative code). Multi-file tests (`module_tests.rs`, `diagnostic_tests.rs`) write a tree to `temp_dir()` and compile through `Options::parse_from` + `compiler::compile`. `platform_tests.rs` uses `with_simulated_host`. `compile_tests.rs::full_pipeline_link_and_spawn` and `link_tests.rs` link real executables. |
| Diagnostics | `crates/pepper-driver/tests/diagnostic_tests.rs` | `error_of(name, src)` returns the full rendered error (header, source line, caret). Add one for every new error. |
| Corpus | `tests/**/*.pep` | `tests/parser_corpus.rs` requires every file to parse. `corpus_tests.rs::corpus_files_respect_visibility` checks every `tests/*/test.pep` (runs), and `corpus_files_compile_and_run` compiles, links, and runs each fixture with `-I tests`. |
| Runtime discovery | `crates/pepper-files/src/runtime.rs` (`mod tests`) | Calls `discover_from` with a cwd outside the checkout and an executable directory inside it. |
| Runtime docs | `crates/pepper-driver/tests/runtime_docs_tests.rs` | `check_documented` over every `runtime/**/*.pep`. |
| Docs examples | `crates/pepper-driver/tests/docs_examples_tests.rs` | Compiles and runs every `docs/examples/*.pep` (or `name/main.pep`) through `pepper_driver::run`. Filter with `PEPPER_DOCS_EXAMPLE=prefix`. |
| LSP | `tools/lsp/src/tests.rs` | See section 8. |
| xtask, docgen | `xtask/src/main.rs`, `tools/docgen/src/site.rs` | Unit tests. |

To run a subset:

```bash
cargo test --workspace --test module_tests            # one integration binary
cargo test --workspace utf8                           # name substring
cargo test -p pepper-parser                           # one crate
cargo test --workspace --no-default-features --features llvm19-1
```

Harness gotchas: runtime discovery and several harnesses `chdir` to the
repository root (a process-wide change; every test sets the same
directory). Temp directories are named after the test, so give new tests
unique names.

Keep the suite parallel. Cargo runs test binaries one after another, so a
test that loops over many programs (every example, fixture, or simulated
host) is wall-clock time for the whole suite: spread the loop with
`support::parallel_map` (`crates/pepper-driver/tests/support/mod.rs`,
`mod support;` in the test file), giving each item its own temp directory.
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
rendered-output test in `crates/pepper-driver/tests/diagnostic_tests.rs`.

### Add a runtime API

1. Write it in Pepper in the right `runtime/*.pep` file (or a new top-level
   file, which joins the prelude automatically). Mark it `export`. Put
   internals under `_pep_`/`_io_`.
2. Document it with `##` doc comments per AGENTS.md. Run
   `cargo test --workspace --test runtime_docs_tests`.
3. For the `io` module, add it to the implementing file and re-export it
   from `runtime/io/module.pep`.
4. Regenerate the reference: `cargo run -p pepper-docgen -- reference`.
   Commit the changed `docs/src/reference/*.md` and `docs/src/SUMMARY.md`.
5. Test it with `compile_with_runtime` + JIT in the matching
   `crates/pepper-driver/tests/*_tests.rs`. For behavior the docs show, add a
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
- `[Shared]` → `StructDef::is_shared`
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

- **`ci.yml`** (push to `main`, PRs):
  - `test` is the required check. It runs on the self-hosted
    **`pepper-windows`** runner: provision LLVM (`ci-provision-llvm.sh`,
    cached), `cargo build --workspace --locked`, `cargo test --workspace
    --locked`, and `pepper-docgen -- check`.
  - `llvm-matrix` and `llvm-versions` run on self-hosted **`pepper-linux`**
    and test against every LLVM major that apt offers.
- **`platform-test.yml`**: runs on dispatch only, for any script on
  Linux/macOS/Windows (`gh workflow run platform-test.yml -f platforms=…
  -f script=…`). It has a failure/cancel diagnostics step. Read AGENTS.md's
  CI section before writing a script for it.
- **`vsix.yml`**: builds the extension and server for six targets and
  publishes the release on `main`.
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
- **Only the first sema error is reported** per compile
  (`errors::report`).
- **Specialization fixpoint is capped at 16 rounds.** A type that nests
  itself through generics stops there instead of looping forever.
- **Unused CLI flags**: `-g`, `-v`, `-T`, `--Tall`; `--MSVC` returns an
  error. Only the first source file is compiled.
