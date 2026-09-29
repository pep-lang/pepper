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
| `crates/pepper-sema` | Program loading and module linking (`program.rs`, `modules.rs`, `visibility.rs`), AST → model builder (`builder.rs`), the sema model (`model.rs`), struct synthesis (`struct_body.rs`), and the transform passes (`passes/`). No LLVM. |
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
    runtime::discover()           cwd-relative runtime/ search → prelude files
    imports::search_paths         -I dirs, then runtime dirs
    resolve_forced                --import NAME → prelude, ahead of the runtime
    program::load                 parse_source every reachable file; resolve imports
    modules::link                 bind imports/exports; rewrite m.x, aliases → FileScope
  compiler::merge
    Program::check                linking errors, then visibility::check_visibility
    builder::build_file(i)        AST → sema model, locations carry FileId(i)
    Module::merge                 all files into ONE sema Module (one namespace)
  compiler::run_passes
    apply_platform_filters        drop [Target(...)] that is false on the host
    struct_body::apply            resolve_type_aliases; __refcount, ctor, dtor,
                                  __acquire/__release bodies
    passes::transform_pass        ~30 ordered steps (section 3)
    check_function_types          function-value signature check
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

- **Runtime discovery** (`pepper_files::runtime::discover`) checks
  `<cwd>/runtime`, then `<cwd>/.pep/runtime`, then `../runtime` up to five
  levels up. The **first** directory containing `.pep` files wins. Only that
  directory's top-level `.pep` files join the prelude (`runtime/io/` does
  not). Any `.a` files there are linked. Every directory scanned before the
  winner is also returned, and those become import search paths. This lookup
  is relative to the **current directory**, not to the compiler binary.
  Tests `set_current_dir` to the repository root for this reason.
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
  declaration it denotes. After this step every reference is spelled the way
  the single-namespace model resolves it. For each file it records a
  `FileScope`: `imported` (span start → declaration, used by visibility) and
  `named` (used by the LSP). Errors are `ModuleError { file, span, message,
  unresolved }`.
- **`Program::check`** reports link errors first and then
  `visibility::check_visibility`. That check covers private symbols, symbols
  that were not imported, private names declared in several files (they
  would silently merge), and duplicate exports. Extern redeclarations and
  concrete generic overrides (`hash<String>` of `hash<T>`, see
  `type_name::is_concrete_override`) are exempt.

### 2.3 Parsing (`crates/pepper-parser`)

- **Entry points** (`parser.rs`): `parse_source(name, text) ->
  Result<ast::Module, String>` returns a rendered error.
  `parse_source_diag(text) -> Result<_, Diagnostic>` returns a structured
  one; the LSP uses it. `parse_file` reads from disk. After a successful
  parse, two checks run on the finished AST: `check_pointer_syntax`
  (`T*` is legal only in `extern` declarations; elsewhere the message
  suggests `__ptr<T>`) and `check_import_order` (imports come before every
  declaration).
- **Grammar** (`parser/parsers.rs`): hand-written winnow combinators over
  `&mut &str`. The precedence ladder is documented at the top of the file
  (`assignment → ternary → … → postfix → atom`, with `cast` for `as`).
  `parse_module` is the top-level loop: imports, `export` re-exports, then
  `declaration`. Rules return `ErrMode::Backtrack` (via `bt`) to let an
  alternative try, or `ErrMode::Cut` (via `cut`/`cut_expecting`) to commit.
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
  import), and `EXPRESSION_PROBE`.
  `track_source(len)` returns a `SourceGuard` that resets all of it for one
  parse. **Any code that calls a grammar rule directly (the unit tests do)
  must hold that guard.** Parsing is not reentrant on one thread.
- **Spans and errors.** `pos(input)` converts the remaining slice into a
  byte offset in the source. A rule that gives up calls `expected(input,
  "')'")` or `cut_expecting`, or `expected_with_note` to add a note such as
  "to match this '{'". `parse_error` reports the expectation recorded at the
  furthest offset (`expected ')'`), or `unexpected 'x'` when none was
  recorded. `token_at` sizes the caret.
- **AST** (`ast.rs`): `Module { imports, exports, declarations }`.
  `Declaration` is `Variable | Function | Struct | Trait | Extend |
  TypeAlias`. The file also defines `Statement`, `Expression`, `TypeName {
  name, generic_types, span }`, `Attribute { body: Expression, span }`,
  `Import`, and `ExportAlias`. Every node carries a byte `Span`; named nodes
  also carry `name_span`. Externs are `FunctionDecl { external: true, … }`.
  Every node implements `Display`; `--emit-ast` prints through it.
  Function types `(P…) => R` are parsed directly into
  `__function<R, P…>`.

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
  - `t.m(args)` becomes `MethodCall`, and a named callee becomes
    `FunctionCall { function }`. A type literal callee (`Box<int>(…)`)
    becomes a constructor call named `"Box<int>"`. Any other callee becomes
    `Invoke`.
  - Member names that start with `__` are rejected, except `__acquire` and
    `__release`, which source code may call.
  - Structs get `constructor`, `destructor` (`__dtor`), and empty `acquire`
    and `release` shells. Top-level `var`s go to `module.globals`. Externs
    go to `module.externs`.
- **Model** (`model.rs`): `Module { structs, traits, extensions, functions,
  externs, globals, type_aliases, struct_specs, func_specs, imports,
  sources: SourceMap }`. Nodes are owned enum trees with no `Rc`/`RefCell`;
  passes mutate `&mut Module` in place. The main node types are `StructDef`,
  `FunctionDef` (methods have `parent: Some(struct)`), `ExternDef` (with
  `link_name()`), `VariableDef { kind: Variable|Field|Param, loc, type_loc
  }`, `Expression` (includes intrinsic nodes: `SizeOf`, `Default`, `IsPod`,
  `RefCount`, `Address`, `Atomic*`, `FunctionRef`, `Invoke`,
  `ForIterator`), and `Statement`. Each node that names something has a
  `Loc`; `Expression::loc()` returns it (`Loc::NONE` for literals and
  synthesized nodes).
- **Types**: `type_name::TypeName { name, sub_types, flags }`, with
  constants `AUTO` (`__auto`), `VOID`, and `FUNCTION` (`__function`),
  primitive alias sets, `widest`, and `replace_map` (generic substitution).
  `symbols::SymbolTable` maps names to indices. When a name is declared
  twice, the later entry overwrites the earlier one. `static_type::of`
  gives a best-effort static type for operator resolution and print
  conversion.
- `Module::merge` concatenates vectors. **There is one global namespace**:
  modules exist only up to `modules::link`.

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

`struct_body::apply` runs `resolve_type_aliases` first, so no alias
survives into later stages. Then, for each struct:

- `apply_synthesized` inserts a `u32 __refcount` head field (default 0). It
  fills the `__acquire` body (null check, `++__refcount`, `trace_*` calls)
  and the `__release` body (null check, `--`, and at 0 a call to `__dtor`).
- `finish` builds the constructor. A hidden `size` local is patched with the
  real ABI size in codegen by `patched_ctor`. The constructor calls `this =
  _pep_malloc(size)`, initializes each field (explicit default or zero),
  assigns `this.field` constructor parameters (renamed `__init_<field>`),
  runs the user body, and ends with `return this`. The destructor ends with
  `_pep_free(this)`. The pass appends `__release`, `__acquire`, and `__dtor`
  to `method_members`.

---

## 3. Sema transform passes (`crates/pepper-sema/src/passes/`)

`transform_pass(&mut Module) -> Result<(), Diagnostic>` runs the steps below
in order. Each call is wrapped in `step!`, which stops at the first pass
that reported an error. The order came from the C++ implementation, and
several passes run more than once on purpose.

| # | Step | What it does |
| --- | --- | --- |
| 1 | `synthesize_function_types` (`function_types.rs`) | Each distinct `__function<R, P…>` becomes a synthesized refcounted struct (`__refcount`, `__invoke`, `__destroy`). |
| 2 | `resolve_literals` | Folds unary minus into numeric literals. |
| 3 | `tag_generics` | Renames concrete overrides of generic functions to their spelled type (`hash<int>`). |
| 4 | `convert_string_literals` | `"abc"` → `String(raw, size, length)` constructor call. The raw literal stays a `char*` global. |
| 5 | `gather_generics` | Records generic uses as `struct_specs` and `func_specs`. |
| 6 | `resolve_implicit_types` | Infers `auto` locals and symbol types by scoped lookup. |
| 7 | `resolve_resolvables(false)` | Resolves struct, function, and method references against the symbol table. |
| 8 | `apply_extensions(false)` | Clones `extend` methods onto their target and records traits. |
| 9–10 | `specialize_structs`, `specialize_functions` | Clones generic bases into `Name<args>` instances with substituted types. |
| 11 | `synthesize_function_types` | For function types that specialization exposed. |
| 12 | `convert_intrinsics` | Rewrites `__ptr<T>` to `T*`. Turns `__is_pod`, `__default`, `__refcount`, `__address`, `__atomic_load/store/cmpxchg/fetch_*` calls into intrinsic nodes. |
| 13–14 | `resolve_resolvables`, `apply_extensions(true)` | Resolves what remains and applies specialized extensions. |
| 15 | `convert_member_refs` | In methods, a bare field becomes `this.field` and a bare call becomes a method call (parameters are exempt). |
| 16–17 | `resolve_implicit_types`, `resolve_operators` | `x[i]` → `__index_get`/`__index_set` or POD `ArrayIndex`. An overloaded binary operator becomes a method call. |
| loop ≤16× | `gather_generics`, `specialize_structs`, `specialize_functions` | Repeats until the counts of structs and functions stop growing (specializing exposes new uses). Bounded because a self-nesting generic never converges. |
| then | `convert_intrinsics`, `resolve_resolvables`, `convert_member_refs`, `synthesize_function_types` | Covers what the loop created. |
| final | `release_field_refs` | Inserts `__release` calls for struct-typed fields, in reverse declaration order, before the destructor's `_pep_free`. |
| final | `resolve_implicit_types`, `resolve_operators`, `convert_print_calls`, `resolve_resolvables(true)`, `synthesize_function_types` | `convert_print_calls` turns a `String` argument of `print` into `arg.Data`. `resolve_resolvables(true)` is the step that reports `use of undeclared identifier`, `call to undeclared function`, and similar. |

Shared helpers in `passes/mod.rs` are `walk_block`, `walk_statement`,
`walk_expression`, `walk_function`, `walk_global`, and
`replace_expression`. **When you add a model `Expression` variant, add it to
`walk_expression`.**

After `transform_pass`, the driver calls
`passes::check_function_types::check_function_types`, which rejects a
function value flowing into a slot of a different signature. The LSP skips
this pass.

Error reporting inside passes goes through `crate::errors::report(diag)`, a
thread-local that keeps only the **first** diagnostic of a run. Other
per-run state is thread-local too and is reset at the start of each run:
`apply_extensions::reset_applied`, the builder's `FOR_LOOPS` counter, and
`platform::SIMULATED_HOST`. This lets tests compile concurrently on
separate threads.

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
   `__pep_global_init`, registered in `llvm.global_ctors`.
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
  by argument type), `assert(cond, msg)` (a literal message is passed as
  its raw global, anything else through `String.c_str`), `release<T>(v)`,
  `__is_pod`, and `__default<T>`. `call_function` declares unknown
  runtime helpers such as `_pep_malloc` on demand.
- **Intrinsic nodes** in `codegen_expr_unlocated`: `SizeOf`, `Default` (zero
  or null), `IsPod`, `RefCount`, `Address` (FNV-folds POD values),
  `AtomicLoad` (acquire), `AtomicStore` (release, via `xchg`),
  `AtomicCmpXchg` (acq_rel/monotonic; floats are bitcast), and `AtomicFetch`
  (`atomicrmw` acq_rel).
- **Function values**: `FunctionRef` produces a static function object
  (`__function_object.<name>`) whose `__invoke` points at a thunk
  (`__function_thunk.<name>`). `codegen_invoke` loads `__invoke` and calls
  it with the signature of the static type.
- **Default arguments**: `param_defaults` stores each callable's default
  expressions. `missing_args` pads trailing arguments at the call site and
  reports `too many/too few arguments to 'f'`.
- **Control flow**: nested blocks, branches, and loops get their own basic
  blocks. `frame.exited` suppresses dead code after
  `return`/`break`/`continue`. Every unterminated block is patched to branch
  to the function's return block. Return values go through a `retval`
  alloca in the entry block.
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
| Destruction | At zero, `__release` calls `__dtor`. `__dtor` runs the user's `destruct` body, then the field releases added by `release_field_refs`, then `_pep_free(this)`. |

Debugging aids: set `PEP_TRACE` to make the runtime's `trace_ptr`,
`trace_int`, and `trace_region` print. `_pep_live_allocs()` counts live
allocations; leak-census tests
(`crates/pepper-driver/tests/shared_ptr_semantics_tests.rs`) read it through
the JIT. The counter is process-wide, so those tests have to account for
concurrency.

---

## 6. Diagnostics (`crates/pepper-parser/src/diagnostic.rs`)

The standard is in AGENTS.md ("Compiler errors are clang-style
diagnostics"). The mechanics:

- `FileId(u32)` indexes a `SourceMap`. `Loc { file, span }` has a
  `Loc::NONE` value for nodes the compiler synthesized.
- `Diagnostic { severity, message, loc, notes }` has the builders
  `Diagnostic::error(msg).at(loc).with_note(msg, Some(loc))` and `or_at`.
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
| `internals.pep` | C externs (`malloc`, `memcpy`, `puts`, …), `assert`, `panic`, `_pep_malloc`/`_pep_free`/`_pep_realloc`/`_pep_live_allocs`, the trace functions, `_pep_swap_refs`/`_pep_move_ref` (raw slot moves for containers), `_pep_hash_bytes` (FNV-1a), UTF-8 helpers, and `_pep_print*`. |
| `string.pep` | `String` (fields `Data`, `Length`, `Size`, `Version`) and `StringIterator`. |
| `array.pep`, `hash.pep` | `Array<T>` (also written `T[]`), `HashMap`, `HashSet`, and their iterators. |
| `iterator.pep` | `Iterator<T>` and `Iterable<T>` traits, the `for` protocol (`next()`/`current()`, `iterate()`). |
| `result.pep` | `Error`, `None`, `Result<TValue, TError=Error>`. |
| `atomic.pep` | `Atomic<T>` over the `__atomic_*` intrinsics. |
| `io/` | The `io` module (`import io`): `module.pep` re-exports the public API. `types.pep`, `path.pep`, `file.pep`, and `directory.pep` implement it, and `sys_posix.pep`/`sys_windows.pep` hold the platform layer. |
| `msvc.bat` | A vcvarsall helper left over from the old MSVC link path. |

- **Loading.** Every top-level `runtime/*.pep` is a prelude file. Its
  `export`s are visible in every program without an import. `runtime/io` is
  found as a module because the runtime directory is on the search path.
- **Naming convention for internals.** Names prefixed `_pep_` (core) and
  `_io_` (io module) are internals. They are `export`ed so other runtime
  files can use them. They are exempt from the documentation standard, and
  a module does not re-export them (`io/module.pep` re-exports only the
  public types).
- **Lowered by name.** `print` → `_pep_print`/`_pep_print_int`/
  `_pep_print_float`. Every constructor calls `_pep_malloc`, and every
  destructor calls `_pep_free`. `__acquire` and `__release` call `trace_ptr`
  and `trace_int`. `assert` (a runtime function) receives a raw `char*`.
  Codegen calls these by name after visibility has run, so `_pep_print*`
  need not be exported.
- **Intrinsics available to runtime code**: `__ptr<T>` (a raw pointer, the
  only pointer spelling allowed outside `extern`), `__null`, `sizeof(T)`,
  `__default<T>()`, `__is_pod<T>()`, `__refcount<T>(x)`, `__address<T>(x)`,
  and `__atomic_load/store/cmpxchg/fetch_{add,sub,and,or,xor}<T>(…)`.
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
- Completion lists keywords, globals, locals, and struct members.
  Document symbols come from the AST.
- Runtime discovery is cwd-relative here too, so it depends on the
  directory the server was started in.
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
root package's test runs. The suite has roughly 750 `#[test]` functions;
the counts in `.agents/skills/test/SKILL.md` are out of date.

| Kind | Where | Notes |
| --- | --- | --- |
| Parser unit | `crates/pepper-parser/src/parser/parsers.rs` (`mod tests`), `parser.rs`, `diagnostic.rs`, `doc.rs` | Helpers `parse`, `parse_expr`, and `parse_type` take the `track_source` guard. `parser.rs` tests pin exact rendered parse errors. |
| Sema model | `crates/pepper-sema/src/model_tests.rs`, `visibility.rs` tests | `compile()` = parse → `build` → filters → `struct_body::apply` → `transform_pass`, then assertions on the model. |
| Codegen JIT | `crates/pepper-codegen/tests/codegen_tests.rs`; `target.rs` unit test | JIT `test()`, check the returned `i32`. |
| Driver integration | `crates/pepper-driver/tests/*_tests.rs` (arrays, strings, hashes, io, modules, visibility, platform, atomics, function values, iterators, shared_ptr semantics, C arithmetic semantics, edge cases, …) | Usual shape: `compiler::compile_with_runtime("test.pep", src)` → `CodeGenerator::jit_execute(&mut m, "test")`, asserting 0 (each check returns a distinct negative code). Multi-file tests (`module_tests.rs`, `diagnostic_tests.rs`) write a tree to `temp_dir()` and compile through `Options::parse_from` + `compiler::compile`. `platform_tests.rs` uses `with_simulated_host`. `compile_tests.rs::full_pipeline_link_and_spawn` and `link_tests.rs` link real executables. |
| Diagnostics | `crates/pepper-driver/tests/diagnostic_tests.rs` | `error_of(name, src)` returns the full rendered error (header, source line, caret). Add one for every new error. |
| Corpus | `tests/**/*.pep` | `tests/parser_corpus.rs` requires every file to parse. `corpus_tests.rs::corpus_files_respect_visibility` checks every `tests/*/test.pep` (runs), and `corpus_files_compile_and_run` compiles, links, and runs each fixture with `-I tests` (**ignored**). |
| Runtime docs | `crates/pepper-driver/tests/runtime_docs_tests.rs` | `check_documented` over every `runtime/**/*.pep`. |
| Docs examples | `crates/pepper-driver/tests/docs_examples_tests.rs` | Compiles and runs every `docs/examples/*.pep` (or `name/main.pep`) through `pepper_driver::run`. Filter with `PEPPER_DOCS_EXAMPLE=prefix`. |
| LSP | `tools/lsp/src/tests.rs` | See section 8. |
| xtask, docgen | `xtask/src/main.rs`, `tools/docgen/src/site.rs` | Unit tests. |

To run a subset:

```bash
cargo test --workspace --test module_tests            # one integration binary
cargo test --workspace utf8                           # name substring
cargo test -p pepper-parser                           # one crate
cargo test --workspace -- --ignored                   # the known gaps
cargo test --workspace --no-default-features --features llvm19-1
```

Known ignored tests (ignored does not mean passing):

- `corpus_tests::corpus_files_compile_and_run`: `tests/Trait.Generic`
  fails. It uses a generic trait with a `static this from(T)` method
  implemented through `extend … with Convert<Bar>`.
- `edge_case_tests::destructor_runs`: "destructors are not invoked on
  scope exit under the JIT".

Harness gotchas: runtime discovery and several harnesses `chdir` to the
repository root (a process-wide change; every test sets the same
directory). Temp directories are named after the test, so give new tests
unique names.

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
   `check_pointer_syntax` (`ptr_check_*`), `modules.rs` (`Rewriter`, so
   imported names inside it are rewritten), `visibility.rs`, and the LSP's
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

Validate the arguments and report a located error. Add driver tests (see
`link_tests.rs`, `platform_tests.rs`).

### Add a platform-specific runtime function

Write twin declarations with the same name and signature, guarded
`[Target(OS(Windows))]` and `[Target(!OS(Windows))]` (see
`runtime/io/path.pep`, `sys_posix.pep`, and `sys_windows.pep`). Dropped
twins do not count as duplicates for visibility. Use `[LinkName]` when the
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
  invariants, such as `expect("unknown binary operator")` in the builder,
  which only fires if the parser and builder operator tables disagree. The
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

- **Single global namespace.** Module linking rewrites names, and then
  every file merges into one `Module`. Two private declarations with the
  same name in different files are rejected by visibility rather than kept
  apart. `SymbolTable` lets a later declaration overwrite an earlier one.
- **Traits have no dynamic dispatch.** Codegen has no trait awareness at
  all. Traits are recorded on structs by `apply_extensions`, and calls
  resolve statically by type. `for` chooses `iterate()` or
  `next()`/`current()` by type (`ForIterator`), not through the trait. See
  the ignored `Trait.Generic` fixture.
- **Runtime discovery is cwd-relative.** Running `pepper` from outside the
  repository (more than five levels away from a `runtime/`) silently
  compiles without a prelude. The LSP depends on where the editor started
  it.
- **Host-only targets.** `[Target]` evaluates against the host, and the
  triple is always the host's. 32-bit x86 is unreachable by construction
  (see `crates/pepper-codegen/Cargo.toml`).
- **`check_function_types` returns unlocated `String` errors.** It predates
  the diagnostic standard; move it onto `Diagnostic` when you touch it.
  Some passes also leave unresolved nodes for codegen to report as
  `unknown …`.
- **Only the first sema error is reported** per compile
  (`errors::report`).
- **Specialization fixpoint is capped at 16 rounds.** A type that nests
  itself through generics stops there instead of looping forever.
- **`^=` quirk.** `builder::binary_op` maps `"^="` to
  `BinaryOp::BitOrAssign`, a behavior inherited from the C++ implementation
  and commented as such. There is no xor-assign operator.
- **Unused CLI flags**: `-g`, `-v`, `-T`, `--Tall`; `--MSVC` returns an
  error. Only the first source file is compiled.
- **The destructor-on-scope-exit test is ignored under the JIT**
  (`edge_case_tests::destructor_runs`).
- **Stale guidance**: `.agents/skills/test/SKILL.md` test counts and its
  claim that "most" corpus fixtures fail are out of date. Only
  `Trait.Generic` fails.
