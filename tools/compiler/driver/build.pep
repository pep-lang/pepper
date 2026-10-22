## Building a program: the checked model to object files, linked into an
## executable or a library (`--lib`).

import compiler.ast;
import async;
import compiler.codegen;
import [Diagnostic, SourceText, render_all] from compiler.diagnostic;
import [
    Cache,
    check_compilation_unit,
    check_compilation_units,
    Clock,
    compare_locations,
    every_file,
    find_checked,
    Keys,
    CompilationUnit,
    compilation_unit_key,
    CheckError,
    compilation_units,
    merged_module,
    render_warnings,
    reuse,
    reuse_after_sema,
    Reused,
    check_for_worker,
    check_in_workers,
    worker_file,
    mark,
    Defines,
    NEEDS_FILE,
    stamp_of,
    union_of,
    numbered_objects,
    serve_compilation_units,
    store_checked,
    warnings_in,
    write_record
] from compiler.incremental;
import io;
import [Directory, File, Path] from io;
import compiler.link;
import llvm;
import os;
import process;
import compiler.sema;
import "emit_static";
import "library";
import "linker";
import "lto";
import "natvis";
import "parts";

## What `build` makes.
export struct BuildOptions {
    ## The executable, or the library, to write.
    var output: Path;
    ## Where the object file goes.
    var build_dir: Path;
    ## How much the code is optimized: 0 to 3 (`-O`).
    var opt_level: uint = 0;
    ## More libraries to link, by name (`-l`).
    var libraries: String[] = Array<String>();
    ## More folders to search for them (`-L`).
    var library_dirs: Path[] = Array<Path>();
    ## The build cache, unless the build has none (`--no-cache`).
    var cache: Cache? = Optional<Cache>.Empty;
    ## Whether to print how long each stage took (`-T time`).
    var trace_time: bool = false;
    ## Whether to print where each unit's object came from (`-T cache`).
    var trace_cache: bool = false;
    ## Whether to compile every part in this process rather than in
    ## `pepc --compile-part` children (for a program other than `pepc`).
    var in_process: bool = false;
    ## The largest part a unit is compiled in (`_PART_SIZE`), for a test.
    var part_size: ulong = _PART_SIZE as ulong;
    ## Whether every function keeps its frame pointer (`--frame-pointers`).
    var frame_pointers: bool = false;
    ## Which runtime checks the code performs (`--no-runtime-checks`).
    var runtime_checks: codegen.RuntimeChecks = codegen.RuntimeChecks.all();
    ## Whether to check every compilation unit loaded by early cutoff again and
    ## fail when its record differs, as `PEPC_VERIFY_CUTOFF` does.
    var verify_cutoff: bool = false;
    ## The target's system root, which the link reads its libraries from
    ## (`--sysroot`, else `$PEPPER_SYSROOT_<TRIPLE>`).
    var sysroot: Path? = Optional<Path>.Empty;
    ## This compiler's arguments, which a `--compilation-unit-worker` child is
    ## given again (with `--compilation-unit-worker dir` after them) to load the
    ## same program; none checks every compilation unit in this process.
    var worker_args: String[] = Array<String>();
    ## How many compilation units are checked at once in worker children: 0 for
    ## one per logical CPU (`PEPC_COMPILATION_UNIT_JOBS` overrides it).
    var compilation_unit_jobs: ulong = 0;
    ## A compilation unit worker started before the program was loaded
    ## (`start_compilation_unit_worker`), which loads it at the same time: the
    ## first worker the build gives a compilation unit, else stopped.
    var early_worker: process.Child? = Optional<process.Child>.Empty;
    ## The CPU code is generated for (`-march`, `-mcpu`, `-mtune`,
    ## `-m<feature>`); clang's default for the target without one.
    var cpu: codegen.Cpu? = Optional<codegen.Cpu>.Empty;
    ## Whether the program is optimized as one module before the link
    ## (`--lto=full`); only above `-O0`.
    var lto: bool = false;
    ## The library to build for C instead of an executable (`--lib`).
    var library: LibraryKind? = Optional<LibraryKind>.Empty;
    ## With `-T passes`, where every sema pass's time adds up: the
    ## program's, and each compilation unit's, in a worker too.
    var pass_times: sema.PassTimes? = Optional<sema.PassTimes>.Empty;
    ## Whether to emit debug info (`-g`).
    var debug: bool = false;
    ## With `-g`, where the debugger shows the code a `static` block emits:
    ## in the expanded copy of its file `--debug-static=expanded` writes
    ## beside the output, rather than in the block as written.
    var debug_static_expanded: bool = false;
    ## The program's entry file, which `--debug-static=expanded` writes the
    ## expanded copies of the files below its folder for.
    var entry: Path? = Optional<Path>.Empty;

    construct(output: Path, build_dir: Path) {
        this.output = output;
        this.build_dir = build_dir;
    }
}

## Prints `warnings` on standard error, ordered by where they point, as
## clang prints them beside errors.
report_warnings(warnings: Diagnostic[], sources: SourceText[]) {
    if (warnings.is_empty) {
        return;
    }
    var ordered = Array<Diagnostic>();
    for (var w in warnings) {
        ordered.append(w);
    }
    ordered.sort((a, b) => compare_locations(a, b));
    File.stderr().write_all(render_all(ordered, sources) + "\n");
}

## The libraries `[Link("lib")]` names on the program's externs, and the
## folders `[Link(path = "dir")]` adds (relative to the file declaring the
## extern), each once, in declaration order.
##
## @param module the checked model
## @param program the program, for the files' names
## @returns the libraries and the folders
export link_inputs(module: sema.Module, program: link.Program): (String[], Path[]) {
    return _resolve_links(_link_attributes(module), program);
}

# The `[Link]` arguments on `module`'s externs, in declaration order, a line
# each: `lib\t<name>`, or `path\t<file>\t<folder>` with the index of the file
# declaring the extern. The cache keeps them with the last compilation unit's
# objects (`_store_last`), which a build that loads those links with.
_link_attributes(module: sema.Module): String {
    var out = StringBuilder();
    for (var ext in module.externs) {
        for (var attribute in ext.attributes) {
            var name = sema.attribute_name(attribute);
            if (!name.is_value() or name.value() != "Link") {
                continue;
            }
            for (var argument in sema.attribute_arguments(attribute)) {
                var key = "lib";
                if (argument.name.is_value()) {
                    var (named, _) = argument.name.value();
                    key = named;
                }
                var value = "";
                if (argument.value is Literal(literal, _)) {
                    if (literal is String(text)) {
                        value = text;
                    }
                }
                if (value.is_empty) {
                    continue;
                }
                if (key == "lib") {
                    out.append($"lib\t{value}\n");
                } else if (key == "path") {
                    out.append($"path\t{ext.loc.file}\t{value}\n");
                }
            }
        }
    }
    return out.to_string();
}

# The libraries and folders of `_link_attributes`' lines, each once: a
# folder relative to its file's, and absolute.
_resolve_links(lines: String, program: link.Program): (String[], Path[]) {
    var libraries = Array<String>();
    var dirs = Array<Path>();
    for (var line in lines.split("\n")) {
        var fields = line.split("\t");
        if (fields.count == 2 and fields[0] == "lib") {
            if (!libraries.contains(fields[1])) {
                libraries.append(fields[1]);
            }
        } else if (fields.count == 3 and fields[0] == "path") {
            var index = ulong.parse(fields[1]);
            if (!index.is_value() or index.value() >= program.files.count) {
                continue;
            }
            var file = Path(program.files[index.value()].name);
            var folder = file.parent();
            var dir = folder.is_value() ? folder.value().join(Path(fields[2])) : Path(fields[2]);
            var cwd = process.working_directory();
            if (dir.is_relative() and cwd.is_ok()) {
                dir = cwd.value().join(dir);
            }
            if (!dirs.contains(dir)) {
                dirs.append(dir);
            }
        }
    }
    return (libraries, dirs);
}

## Puts `ir`'s static constructors where the target runs them: in
## `.init_array` on ELF (see `use_init_array`). WebAssembly keeps them: its
## object format records `llvm.global_ctors` itself, and `wasm-ld` calls
## them from `__wasm_call_ctors`. There `main` is also renamed for WASI's
## startup code (see `use_wasi_main`).
##
## @param ir the optimized module
## @param triple the target triple
export place_constructors(ir: llvm.Module, triple: String) {
    if (triple.starts_with("wasm")) {
        use_wasi_main(ir);
    } else if (!triple.contains("-windows") and !triple.contains("-apple-")) {
        use_init_array(ir, ir.context);
    }
}

## Names `ir`'s `main` (Pepper's `int main()`) `__main_void`, as clang names
## a C `int main(void)` for WebAssembly: wasi-libc's `_start` calls
## `__main_void`. Under its own name LLVM would wrap it in a two-argument
## `main` that nothing calls, and the program would trap on entry.
##
## @param ir the module
export use_wasi_main(ir: llvm.Module) {
    var main = ir.function("main");
    if (main.is_value() and main.value().block_count() > 0 and main.value().param_count() == 0) {
        main.value().set_name("__main_void");
    }
}

## Moves `ir`'s static constructors from `llvm.global_ctors` into an
## `.init_array` section, as clang emits them for ELF: a machine made
## through LLVM's C API puts them in `.ctors`, which LLVM's linker does not
## fold into `.init_array`.
##
## @param ir the module
## @param context its context
export use_init_array(ir: llvm.Module, context: llvm.Context) {
    var constructors = ir.global("llvm.global_ctors");
    if (!constructors.is_value()) {
        return;
    }
    var entries = constructors.value().initializer();
    if (!entries.is_value()) {
        return;
    }
    # Each entry is `{ i32 priority, ptr function, ptr data }`.
    var functions = Array<llvm.Value>();
    uint i = 0;
    while (i < entries.value().operand_count()) {
        functions.append(entries.value().operand(i).operand(1));
        i += 1;
    }
    constructors.value().delete_global();
    if (functions.is_empty) {
        return;
    }
    var pointer = context.pointer_type();
    var array = ir.add_global(pointer.array_type(functions.count), "__pep_init_array");
    array.set_initializer(pointer.const_array(functions));
    array.set_linkage(llvm.Linkage.Private);
    array.set_section(".init_array");
    array.set_alignment(8);
}

## What a build did.
export struct Built {
    ## Whether the output already was this program, so nothing was built.
    var unchanged: bool = false;
    ## The units whose objects came from the build cache, by name.
    var hits: String[] = Array<String>();
    ## The units compiled and stored in the build cache, by name.
    var misses: String[] = Array<String>();
    ## The parts of the units compiled whose objects came from the build
    ## cache, as `<unit>#<n>`.
    var part_hits: String[] = Array<String>();
    ## The compilation units checked again from an earlier record of them,
    ## only their changed bodies checked, by name.
    var rechecked: String[] = Array<String>();

    construct() {}
}

# `error` as the build reports it, rendered.
_check_error(error: CheckError, sources: SourceText[]): String {
    match (error) {
        Unread(message) => {
            return message;
        }
        Linking(diagnostics) => {
            return render_all(diagnostics, sources);
        }
        Checking(diagnostic) => {
            return render_all([diagnostic], sources);
        }
        Failed(message) => {
            return message;
        }
    }
}

## Whether `PEPC_NO_COMPILATION_UNITS` turns checked compilation units off, for
## comparing builds with and without them.
_compilation_units_off(): bool {
    var named = os.environment("PEPC_NO_COMPILATION_UNITS");
    return named.is_value() and !named.value().is_empty;
}

# The symbols a compilation unit's parts, just compiled with `partition`,
# define for other objects (each part's `<object>.defines`, which this
# removes), a line each, by Pepper name. The cache keeps them beside the
# compilation unit's objects (`defines`), and a compilation unit above only
# declares these (`codegen.generate`'s `declared`); an instantiation the
# compilation unit's objects dropped (`linkonce_odr`, inlined everywhere) it
# defines itself, as a compiler shares the generics a library exports.
_defines(partition: codegen.Partition, objects: Path[]): Result<String, String> {
    var out = StringBuilder();
    for (var object in objects) {
        var path = Path($"{object}.defines");
        var text = File.read_to_string(path);
        if (text.is_err()) {
            return Result<String, String>.err($"cannot read {path}");
        }
        File.remove(path);
        for (var name in text.value().split("\n")) {
            if (name.is_empty) {
                continue;
            }
            var pepper = partition.names.try_get(name);
            out.append(pepper.is_value() ? pepper.value() : name);
            out.append("\n");
        }
    }
    return Result<String, String>.ok(out.to_string());
}

# Leaves the symbols compilation unit number `k`'s objects, in the cache's
# `folder`, define in `dir` as `<k>.defines`, for the workers of the
# compilation units that read it.
_copy_defines(folder: Path, dir: Path, k: ulong) {
    var text = File.read_to_string(folder.join(Path("defines")));
    var partial = worker_file(dir, k, $"defines.{process.id()}");
    File.write_text(partial, text.is_ok() ? text.value() : "");
    File.rename(partial, worker_file(dir, k, "defines"));
}

# The symbols the objects of compilation unit number `k` define (`_defines`),
# from `<k>.defines` in `dir`; read once each, into `read`.
_defined_by(k: ulong, dir: Path, read: HashMap<ulong, Defines>): Defines {
    var known = read.try_get(k);
    if (known.is_value()) {
        return known.value();
    }
    var text = File.read_to_string(worker_file(dir, k, "defines"));
    var out = Defines(text.ok_or(""));
    read[k] = out;
    return out;
}

# What the objects of each compilation unit numbered `ks` define
# (`_defined_by`).
_below(ks: ulong[], dir: Path, read: HashMap<ulong, Defines>): Defines[] {
    var out = Array<Defines>();
    for (var k in ks) {
        out.append(_defined_by(k, dir, read));
    }
    return out;
}

# What `ir`, a compilation unit's code just generated, uses that the objects
# below it define (`declared`), a name a line: its objects link only with
# objects below that still define them (`Cache.unit_objects`).
_needs(ir: llvm.Module, declared: HashSet<String>): String {
    var out = StringBuilder();
    var values = Array<llvm.Value>();
    values.append_all(ir.functions());
    values.append_all(ir.globals());
    for (var value in values) {
        if (value.is_declaration() and value.has_uses() and declared.contains(value.name())) {
            out.append($"{value.name()}\n");
        }
    }
    return out.to_string();
}

# Keeps `folder`, compilation unit `unit`'s objects just compiled on objects
# below it that define `below`, in the build cache, with what they declare of
# those (`needs`, from `_needs`), under the key `Cache.unit_store_key` gives.
# Returns the key of the objects to link, which hold `file`: those, or
# another build's under that key that also link with the objects below.
_store_unit(
    cache: Cache, unit: CompilationUnit, folder: Path, needs: String, below: Defines[], file: String
): Result<String, String> {
    if (File.write_text(folder.join(Path(NEEDS_FILE)), $"{stamp_of(below)}\n{needs}").is_err()) {
        return Result<String, String>.err($"cannot write to {folder}");
    }
    var name = $"+{unit.name}";
    var stored = cache.store(folder, name, cache.unit_store_key(name, unit.key, below));
    if (stored.is_err()) {
        return Result<String, String>.err(stored.error());
    }
    # shortcut: two builds at once with one key but other objects below
    # both find the key free and one fails here; store under the other key
    # instead if a shared cache across checkouts ever meets it.
    var key = cache.unit_objects(name, unit.key, below, file);
    if (!key.is_value()) {
        return Result<String, String>.err(
            $"the build cache's objects of compilation unit '{unit.name}' do not link with those below it; build again"
        );
    }
    return Result<String, String>.ok(key.value());
}

# How the units are compiled, as text for their keys: the target, the CPU
# (`-m`), the `-O` level, link-time optimization and the code generation
# options. A compilation unit worker keys them as the build does.
_build_text(options: BuildOptions, triple: String): String {
    var cpu = options.cpu.is_value() ? options.cpu.value() : codegen.Cpu.default_for(triple);
    bool lto = options.lto and options.opt_level > 0;
    return $"{triple} {cpu.key()} -O{options.opt_level}{lto ? " -lto" : ""}{_codegen_options(options)}";
}

# The extension of a unit's object for `triple`: with link-time
# optimization (`--lto=full` above `-O0`) its bitcode, which the cache
# keeps as it keeps an object.
_object_extension(options: BuildOptions, triple: String): String {
    if (options.lto and options.opt_level > 0) {
        return "bc";
    }
    return triple.contains("-windows") ? "obj" : "o";
}

# Keeps the last compilation unit's objects, `folder`'s parts' (`0.<ext>` and
# on) and `entry.<ext>`, in the build cache under its key (`_store_unit`), with the program's `[Link]`
# arguments (`link`) and the warnings checking it gave (`warn`), rendered: a
# later build whose last compilation unit has the same key links them, as Go
# links a `main` package from its cache, and prints the warnings again. Returns
# where the cache keeps them.
_store_last(
    cache: Cache,
    last: CompilationUnit,
    folder: Path,
    link_text: String,
    warned: String,
    needs: String,
    below: Defines[],
    extension: String
): Result<Path, String> {
    if (File.write_text(folder.join(Path("link")), link_text).is_err()
        or File.write_text(folder.join(Path("warn")), warned).is_err()) {
        return Result<Path, String>.err($"cannot write to {folder}");
    }
    var key = _store_unit(cache, last, folder, needs, below, $"entry.{extension}");
    if (key.is_err()) {
        return Result<Path, String>.err(key.error());
    }
    return Result<Path, String>.ok(cache.objects($"+{last.name}", key.value()));
}

# Compiles `module`, the compilation unit `unit` just checked, into its object
# and keeps that in the build cache (`_store_unit`): the
# compilation unit's files' own code and what it instantiated; everything else,
# what the compilation units below made (`below`, by compilation unit) and the
# other files' code, is only declared, since their objects define it. `dir`
# holds the work. Returns the cache's folder of the object.
_compile_unit(
    program: link.Program,
    unit: CompilationUnit,
    module: sema.Module,
    state: sema.PassState,
    below: Defines[],
    options: BuildOptions,
    cache: Cache,
    dir: Path
): Result<Path, String> {
    var triple = codegen.target_triple(program.target);
    var cpu = options.cpu.is_value() ? options.cpu.value() : codegen.Cpu.default_for(triple);
    var extension = _object_extension(options, triple);
    var level = [llvm.OptLevel.O0, llvm.OptLevel.O1, llvm.OptLevel.O2, llvm.OptLevel.O3][options.opt_level];
    codegen.initialize_backends();
    var machine = llvm.TargetMachine.create(triple, cpu.name, cpu.features, level);
    if (machine.is_err()) {
        return Result<Path, String>.err(machine.error().message);
    }
    var setup = codegen.Build(machine.value(), cpu);
    setup.opt_level = options.opt_level;
    setup.frame_pointers = options.frame_pointers;
    setup.runtime_checks = options.runtime_checks;
    setup.separate_locations = true;
    var namespaces = Array<String>();
    for (var f in program.files) {
        namespaces.append(f.namespace);
    }
    var own = HashSet<ulong>();
    for (var file in unit.files) {
        own.insert(file);
    }
    var others = HashSet<uint>();
    for (var i in 0..program.files.count) {
        if (!own.contains(i)) {
            others.insert(i as uint);
        }
    }
    var owners = HashMap<String, uint>();
    var declared = union_of(below);
    var generated = codegen.generate(
        module, state, namespaces, unit.name, setup, owners, others, Optional<HashSet<String>>.Value(declared)
    );
    if (generated.is_err()) {
        return Result<Path, String>.err(render_all([generated.error()], program.sources()));
    }
    var needs = _needs(generated.value(), declared);
    # The program's entry points are the last compilation unit's to compile.
    var (part_of_file, spread, parts) = _unit_parts(program, unit.files, generated.value(), owners, options.part_size);
    var partition = codegen.prepare(
        generated.value(), owners, part_of_file, parts, parts + 3, spread, Optional<uint>.Value(parts + 2)
    );
    var folder = dir.join(Path($"{unit.name.replace("/", "_")}.object"));
    Directory.remove_all(folder);
    Directory.create_all(folder);
    var compiled = compile_parts(
        generated.value(),
        partition,
        _unit_jobs(folder, parts, extension),
        machine.value(),
        cpu,
        options.opt_level,
        folder,
        options.trace_time,
        options.in_process,
        false,
        options.lto and options.opt_level > 0,
        false,
        Optional<PartCache>.Value(PartCache(cache, $"+{unit.name}"))
    );
    if (compiled.is_err()) {
        return Result<Path, String>.err(compiled.error());
    }
    var defines = _defines(partition, numbered_objects(folder, extension));
    if (defines.is_err()) {
        return Result<Path, String>.err(defines.error());
    }
    if (File.write_text(folder.join(Path("defines")), defines.value()).is_err()) {
        return Result<Path, String>.err($"cannot write to {folder}");
    }
    var kept = _store_unit(cache, unit, folder, needs, below, $"0.{extension}");
    if (kept.is_err()) {
        return Result<Path, String>.err(kept.error());
    }
    return Result<Path, String>.ok(cache.objects($"+{unit.name}", kept.value()));
}

## Starts a compilation unit worker for a build with `args` (this compiler's, as
## `BuildOptions.worker_args`) whose build folder is `build_dir`, before the
## program is loaded, so it loads the program while the build does: a rebuild's
## first compilation unit to check then waits for no worker to load it, as
## Gradle and Bazel keep workers ready. Only when `build_dir` exists, from a
## build before; a build that checks no compilation unit in workers stops it.
##
## @param args this compiler's arguments
## @param build_dir the build's folder
## @returns the worker, if started
export start_compilation_unit_worker(args: String[], build_dir: Path): process.Child? {
    if (!build_dir.is_directory() or _compilation_unit_jobs_named() == 1) {
        return Optional<process.Child>.Empty;
    }
    var executable = process.executable_path();
    if (executable.is_err()) {
        return Optional<process.Child>.Empty;
    }
    var command = process.Command(executable.value().to_string());
    for (var arg in args) {
        command.argument(arg);
    }
    command.argument(
        "--compilation-unit-worker"
    ).argument(build_dir.join(Path($"compilation-units.{process.id()}")).to_string());
    command.stdin(process.Stream.Pipe);
    var spawned = command.spawn();
    return spawned.is_ok() ? Optional<process.Child>.Value(spawned.value()) : Optional<process.Child>.Empty;
}

# Stops `options`' early worker, which no compilation unit needs: at the end of
# its input, it ends.
_stop_early_worker(options: BuildOptions) {
    if (options.early_worker.is_value()) {
        options.early_worker.value().stdin().close();
        options.early_worker = Optional<process.Child>.Empty;
    }
}

# `PEPC_COMPILATION_UNIT_JOBS` (or its deprecated spelling,
# `PEPC_LAYER_JOBS`) as a number, or 0.
_compilation_unit_jobs_named(): ulong {
    var named = os.environment("PEPC_COMPILATION_UNIT_JOBS");
    if (!named.is_value()) {
        named = os.environment("PEPC_LAYER_JOBS");
    }
    if (named.is_value() and !named.value().is_empty) {
        var n = ulong.parse(named.value());
        if (n.is_value()) {
            return n.value();
        }
    }
    return 0;
}

# How many compilation units to check at once
# (`BuildOptions.compilation_unit_jobs`).
_compilation_unit_jobs(options: BuildOptions): ulong {
    var named = _compilation_unit_jobs_named();
    if (named != 0) {
        return named;
    }
    return options.compilation_unit_jobs != 0 ? options.compilation_unit_jobs : async.logical_cpus();
}

# Checks every compilation unit but the last, the program's own, in up to `jobs`
# `--compilation-unit-worker` children (`incremental.check_in_workers`), each of
# which also compiles the compilation unit into its object, and puts in
# `prechecked` the record, own interface and warnings of every compilation unit,
# found in the cache or checked, in `object_keys` the key of the objects of
# each compilation unit the last reads (`Cache.unit_objects`), and in
# `last_below` what those objects define, by compilation unit.
_check_in_workers(
    program: link.Program,
    units: CompilationUnit[],
    options: BuildOptions,
    jobs: ulong,
    prechecked: HashMap<ulong, (u8[], String, String)>,
    object_keys: HashMap<ulong, String>,
    last_below: Defines[]
): Result<void, String> {
    # A folder of this build's own: builds in one folder at once (`pepper
    # test` builds its test programs side by side) share `build_dir`. Kept
    # with `-T time`, for the time each worker's stages took (`<k>.stages`).
    var dir = options.build_dir.join(Path($"compilation-units.{process.id()}"));
    Directory.remove_all(dir);
    var created = Directory.create_all(dir);
    if (created.is_err()) {
        return Result<void, String>.err($"cannot create {dir}: {created.error().message}");
    }
    var cache = options.cache.value();
    var extension = _object_extension(options, codegen.target_triple(program.target));
    # What each compilation unit's objects define, read once.
    var read = HashMap<ulong, Defines>();
    var checked = check_in_workers(
        program,
        units,
        units.count - 1,
        cache,
        jobs,
        prechecked,
        dir,
        options.worker_args,
        options.early_worker,
        options.trace_time,
        (k) => {
            # Reused now (`unit_objects`), so no build pruning the cache
            # removes it before this one links it. A compilation unit's object
            # goes with its record: one without it (pruned, or declaring what
            # the objects below no longer define) is checked again, which
            # compiles it.
            var key = cache.unit_objects(
                $"+{units[k].name}", units[k].key, _below(units[k].reads, dir, read), $"0.{extension}"
            );
            if (!key.is_value()) {
                return false;
            }
            _copy_defines(cache.objects($"+{units[k].name}", key.value()), dir, k);
            return true;
        }
    );
    if (checked.is_ok()) {
        var last = units[units.count - 1];
        last_below.append_all(_below(last.reads, dir, read));
        for (var k in last.reads) {
            var key = cache.unit_objects(
                $"+{units[k].name}", units[k].key, _below(units[k].reads, dir, read), $"0.{extension}"
            );
            if (!key.is_value()) {
                checked = Result<void, String>.err(
                    $"the build cache no longer holds the objects of compilation unit '{units[k].name}'; build again"
                );
                break;
            }
            object_keys[k] = key.value();
        }
    }
    # With `-T passes`, the time each worker's passes took (`<k>.passes`).
    if (options.pass_times.is_value()) {
        for (var k in 0..units.count) {
            var passes = File.read_to_string(worker_file(dir, k, "passes"));
            if (passes.is_ok()) {
                options.pass_times.value().add_all(sema.PassTimes.parse(passes.value()));
            }
        }
    }
    if (!options.trace_time) {
        Directory.remove_all(dir);
    }
    return checked;
}

## A `--compilation-unit-worker` child of a build with `options`: loads the
## compilation units as the build does, then checks each compilation unit whose
## number and key a line of standard input gives, on the records of the
## compilation units it reads (in `dir`, as `<k>.rec`), stores its record and
## object in the cache as the build would, and leaves in `dir` its record
## (`<k>.rec`), its own interface (`<k>.own`), what its object defines
## (`<k>.defines`), its warnings, rendered (`<k>.warn`), or its error
## (`<k>.err`), then `<k>.done`. It reads the bodies of each compilation
## unit's own files only.
##
## @param program the program, loaded and linked as the build loads it
## @param options the build's options
## @param dir the folder the build and its workers pass compilation units
##   through
## @returns the exit code: 0 once standard input ends
export compilation_unit_worker(program: link.Program, options: BuildOptions, dir: Path): int {
    if (!options.cache.is_value()) {
        File.stderr().write_all("pepc: a compilation unit worker needs the build cache\n");
        return 1;
    }
    var clock = Clock(options.trace_time);
    var cache = options.cache.value();
    var triple = codegen.target_triple(program.target);
    var translation_units = link.translation_units(program);
    var keys = Keys(program, translation_units, _build_text(options, triple));
    clock.lap("worker keys");
    var triple_extension = _object_extension(options, triple);
    var reused = Optional<Reused>.Value(reuse(program, translation_units, keys, cache, triple_extension));
    clock.lap("worker reuse");
    var units = compilation_units(program, keys.base());
    clock.lap("worker compilation units");
    var sources = program.sources();
    return serve_compilation_units(program, units, dir, clock, (k, records) => {
        return _work_on(program, units[k], records, cache, reused, sources, dir, k, options);
    });
}

# Checks `unit` (number `k`) for a compilation unit worker on the merged
# `records` of the compilation units it reads, stores its record and leaves it
# in `dir` (`incremental.check_for_worker`), then compiles its object: the
# error, if any.
_work_on(
    program: link.Program,
    unit: CompilationUnit,
    records: HashMap<ulong, u8[]>,
    cache: Cache,
    reused: Reused?,
    sources: SourceText[],
    dir: Path,
    k: ulong,
    options: BuildOptions
): String? {
    var stages = StringBuilder();
    var times = options.pass_times.is_value() ?
        Optional<sema.PassTimes>.Value(sema.PassTimes()) :
        Optional<sema.PassTimes>.Empty;
    var checked = check_for_worker(program, unit, records, cache, reused, sources, dir, k, stages, times);
    if (checked.is_err()) {
        return Optional<String>.Value(checked.error());
    }
    var (after, state) = checked.value();
    var t5 = os.Instant.now();
    # Its object declares what the objects of the compilation units it reads
    # define: it waits for them.
    for (var d in unit.reads) {
        while (!worker_file(dir, d, "defines").is_file()) {
            async.Thread.sleep(2);
        }
    }
    var below = _below(unit.reads, dir, HashMap<ulong, Defines>());
    var t6 = os.Instant.now();
    stages.append($"wait {(t6 - t5).milliseconds()}\n");
    mark(dir, k, "compiling");
    # Its object, which code generation of the program does not make again.
    var compiled = _compile_unit(program, unit, after, state, below, options, cache, dir);
    if (compiled.is_err()) {
        return Optional<String>.Value(compiled.error());
    }
    _copy_defines(compiled.value(), dir, k);
    var t7 = os.Instant.now();
    stages.append($"object {(t7 - t6).milliseconds()}\nreads {unit.reads.count}\n");
    if (options.trace_time) {
        File.write_text(worker_file(dir, k, "stages"), stages.to_string());
    }
    return Optional<String>.Empty;
}

## Builds `program` into an executable: merge, the sema passes, code
## generation for the target (`program.target`), LLVM's standard pipeline
## at the `-O` level, one object per compilation unit (from the build cache
## when its key hits), with link-time optimization one object for the
## whole program (`lto.pep`), then the link. With `options.library`, a
## library for C instead, with its header beside it (`library.pep`). When
## the cache records that the output is this very program, unchanged
## since, nothing is built. Warnings print on standard error whether or
## not the build succeeds.
##
## @param program the loaded and linked program
## @param options where the output goes, and how it is built
## @returns what the build did, or the error, rendered
export build(program: link.Program, options: BuildOptions): Result<Built, String> {
    var report = Built();
    var clock = Clock(options.trace_time);
    var triple = codegen.target_triple(program.target);
    var cpu = options.cpu.is_value() ? options.cpu.value() : codegen.Cpu.default_for(triple);
    # Link-time optimization needs an optimized build.
    bool lto = options.lto and options.opt_level > 0;
    var translation_units = link.translation_units(program);
    var keys = Optional<Keys>.Empty;
    String program_key = "";
    # A library's header is written beside it, and must still be there.
    var header = options.library.is_value() ?
        Optional<Path>.Value(header_path(options.output, program.target)) :
        Optional<Path>.Empty;
    if (options.cache.is_value()) {
        keys = Optional<Keys>.Value(Keys(program, translation_units, _build_text(options, triple)));
        # A unit's code holds the line numbers of the generics it
        # instantiates from other files, which interface hashes leave out.
        keys.value().exact_positions = options.debug;
        program_key = keys.value().program(program, _link_text(options));
        if (options.cache.value().is_built(options.output, program_key)
            and (!header.is_value() or header.value().is_file())) {
            if (options.trace_cache) {
                File.stderr().write_all($"cache: {options.output} is up to date\n");
            }
            clock.lap("unchanged");
            report.unchanged = true;
            return Result<Built, String>.ok(report);
        }
        clock.lap("keys");
    }

    # With LTO each part is bitcode, which the cache keeps as it keeps an
    # object.
    var triple_extension = _object_extension(options, triple);
    # The units whose objects the cache has: sema skips their bodies.
    var reused = Optional<Reused>.Empty;
    if (keys.is_value()) {
        reused = Optional<Reused>.Value(
            reuse(program, translation_units, keys.value(), options.cache.value(), triple_extension)
        );
        clock.lap("reuse");
    }

    var sources = program.sources();
    var units = Array<CompilationUnit>();
    # Debug info holds the positions a compilation unit's key leaves out, so a
    # build with `-g` keys each unit by its text (`Keys.exact_positions`)
    # instead.
    if (options.cache.is_value() and !_compilation_units_off() and !options.debug) {
        units = compilation_units(program, keys.value().base());
    }
    # Checking compilation units links the bodies it needs when it gets to them.
    var warnings = Array<Diagnostic>();
    if (units.count <= 1) {
        var unread = program.link_bodies(every_file(program));
        if (unread.is_value()) {
            return Result<Built, String>.err(unread.value());
        }
        warnings = program.warnings();
    }
    var module = sema.Module();
    var state = sema.PassState(program.target);
    # Whether compilation unit workers compiled every compilation unit but the
    # last into its object (`_store_unit`), and what those
    # compilation units made.
    bool unit_objects = false;
    # The keys of the objects of the compilation units the last reads, and
    # what those define, by compilation unit (`_check_in_workers`).
    var object_keys = HashMap<ulong, String>();
    var last_below = Array<Defines>();
    # The cache's folder of the last compilation unit's objects, when it has
    # them (`_store_last`).
    var last_folder = Optional<Path>.Empty;
    if (units.count > 1) {
        var prechecked = HashMap<ulong, (u8[], String, String)>();
        var jobs = _compilation_unit_jobs(options);
        if (jobs > 1 and units.count > 2 and !options.in_process and !options.worker_args.is_empty) {
            var parallel = _check_in_workers(program, units, options, jobs, prechecked, object_keys, last_below);
            if (parallel.is_err()) {
                return Result<Built, String>.err(parallel.error());
            }
            clock.lap("compilation units in workers");
            unit_objects = true;
        } else {
            _stop_early_worker(options);
        }
        var replayed = Array<String>();
        var checked = check_compilation_units(
            program,
            units,
            options.cache.value(),
            reused,
            sources,
            warnings,
            replayed,
            clock,
            options.trace_cache,
            options.verify_cutoff,
            prechecked,
            unit_objects ? triple_extension : "",
            last_below = last_below,
            times = options.pass_times
        );
        # The warnings of the compilation units loaded, as checking them gave
        # them.
        for (var warned in replayed) {
            File.stderr().write_all(warned);
        }
        if (checked.is_err()) {
            report_warnings(warnings, sources);
            return Result<Built, String>.err(_check_error(checked.error(), sources));
        }
        module = checked.value().module;
        state = checked.value().state;
        last_folder = checked.value().last;
        report.rechecked = checked.value().rechecked;
        report_warnings(warnings, sources);
    } else {
        _stop_early_worker(options);
        var built = sema.merge(program);
        if (built.is_err()) {
            report_warnings(warnings, sources);
            return Result<Built, String>.err(built.error());
        }
        module = built.value();
        if (reused.is_value()) {
            module.record_summaries = true;
            module.cached_files = reused.value().files;
            module.recorded_summaries = reused.value().summaries;
        }
        state.sources = sources;
        state.lazy_methods = true;
        state.pass_times = options.pass_times;
        if (options.debug_static_expanded) {
            state.static_recording = Optional<sema.StaticRecording>.Value(sema.StaticRecording());
        }
        var ran = sema.run_steps_with(module, state, 0xffffffffffffffff);
        for (var note in state.notes) {
            warnings.append(note);
        }
        report_warnings(warnings, sources);
        if (ran.is_err()) {
            return Result<Built, String>.err(render_all([ran.error()], sources));
        }
    }
    # `--debug-static=expanded`: the expanded copies of the files, which
    # the debug info places the `static` blocks' code in.
    var static_locations = HashMap<uint, sema.Loc>();
    if (options.debug and state.static_recording.is_value()) {
        var entry = options.entry.is_value() ? options.entry.value() : Path(program.files[0].name);
        var written = write_debug_sources(program, state.static_recording.value().expansions, entry, options.output);
        if (written.is_err()) {
            return Result<Built, String>.err(written.error());
        }
        for (var file in written.value()) {
            var index = state.sources.count as uint;
            state.sources.append(file.source);
            for (var (id, offset) in file.placed) {
                static_locations[id] = sema.Loc.at(index, ast.Span(offset, offset));
            }
        }
    }
    clock.lap("sema");
    if (options.pass_times.is_value()) {
        File.stderr().write_all(options.pass_times.value().report());
    }
    if (reused.is_value() and !unit_objects) {
        reuse_after_sema(
            reused.value(),
            program,
            translation_units,
            keys.value(),
            options.cache.value(),
            triple_extension,
            sema.function_facts(module, state)
        );
        clock.lap("interfaces");
    }

    var level = [llvm.OptLevel.O0, llvm.OptLevel.O1, llvm.OptLevel.O2, llvm.OptLevel.O3][options.opt_level];
    codegen.initialize_backends();
    var machine = llvm.TargetMachine.create(triple, cpu.name, cpu.features, level);
    if (machine.is_err()) {
        return Result<Built, String>.err(machine.error().message);
    }
    var setup = codegen.Build(machine.value(), cpu);
    setup.opt_level = options.opt_level;
    setup.frame_pointers = options.frame_pointers;
    setup.runtime_checks = options.runtime_checks;
    setup.debug_info = options.debug;
    setup.static_locations = static_locations;
    var runtime = _runtime_dir(program);
    if (options.debug) {
        setup.gdb_printers = gdb_printers(program);
    }
    var namespaces = Array<String>();
    for (var f in program.files) {
        namespaces.append(f.namespace);
    }
    var name = options.output.file_stem();
    var owners = HashMap<String, uint>();
    var stem = name.is_value() ? name.value() : "main";
    # A folder of this build's own, so builds running at once do not meet.
    var work = options.build_dir.join(Path($"{stem}.{process.id()}"));
    var created = Directory.create_all(work);
    if (created.is_err()) {
        return Result<Built, String>.err($"cannot create {work}: {created.error().message}");
    }
    var extension = triple_extension;
    var objects = Array<Path>();
    # The `[Link]` arguments the link takes (`_link_attributes`).
    var link_text = "";
    if (unit_objects) {
        var last = units[units.count - 1];
        if (last_folder.is_value()) {
            # The cache has the last compilation unit's objects: its warnings
            # and `[Link]` arguments are kept beside them.
            var warned = File.read_to_string(last_folder.value().join(Path("warn")));
            if (warned.is_ok() and !warned.value().is_empty) {
                File.stderr().write_all(warned.value());
            }
            var links = File.read_to_string(last_folder.value().join(Path("link")));
            link_text = links.is_ok() ? links.value() : "";
            options.cache.value().used(last_folder.value());
        } else {
            # The compilation unit workers compiled every compilation unit but
            # the last: only the last compilation unit's files and the entry
            # points are generated here, and what the compilation units below
            # defined is only declared.
            var own = HashSet<ulong>();
            for (var file in last.files) {
                own.insert(file);
            }
            var others = HashSet<uint>();
            for (var i in 0..program.files.count) {
                if (!own.contains(i)) {
                    others.insert(i as uint);
                }
            }
            var below = union_of(last_below);
            setup.separate_locations = true;
            var generated = codegen.generate(
                module, state, namespaces, stem, setup, owners, others, Optional<HashSet<String>>.Value(below)
            );
            if (generated.is_err()) {
                return Result<Built, String>.err(render_all([generated.error()], sources));
            }
            clock.lap("codegen");
            var needs = _needs(generated.value(), below);
            var (
                part_of_file, spread, parts
            ) = _unit_parts(program, last.files, generated.value(), owners, options.part_size);
            var partition = codegen.prepare(
                generated.value(), owners, part_of_file, parts, parts + 3, spread, Optional<uint>.Value(parts + 2)
            );
            var folder = work.join(Path("last"));
            Directory.create_all(folder);
            var jobs = _unit_jobs(folder, parts, extension);
            jobs.append(PartJob(parts, folder.join(Path($"entry.{extension}"))));
            var compiled = compile_parts(
                generated.value(),
                partition,
                jobs,
                machine.value(),
                cpu,
                options.opt_level,
                work,
                options.trace_time,
                options.in_process,
                true,
                lto,
                false,
                Optional<PartCache>.Value(PartCache(options.cache.value(), $"+{last.name}"))
            );
            if (compiled.is_err()) {
                return Result<Built, String>.err($"{compiled.error()}\n  (kept {work})");
            }
            _drop_defines(jobs);
            link_text = _link_attributes(module);
            var stored = _store_last(
                options.cache.value(),
                last,
                folder,
                link_text,
                render_warnings(warnings_in(warnings, last), sources),
                needs,
                last_below,
                extension
            );
            if (stored.is_err()) {
                Directory.remove_all(work);
                return Result<Built, String>.err(stored.error());
            }
            last_folder = Optional<Path>.Value(stored.value());
        }
        # Only the compilation units the program's own reads: others, files of
        # the entry's module it never reaches, are not linked.
        for (var k in last.reads) {
            var found = options.cache.value().reused_objects($"+{units[k].name}", object_keys[k], extension);
            if (found.is_err()) {
                Directory.remove_all(work);
                return Result<Built, String>.err(found.error());
            }
            objects.append_all(found.value());
        }
        objects.append_all(numbered_objects(last_folder.value(), extension));
        objects.append(last_folder.value().join(Path($"entry.{extension}")));
        clock.lap("objects");
    } else {
        # The bodies of units whose objects the cache holds are only declared.
        var cached_files = HashSet<uint>();
        if (reused.is_value()) {
            for (var u in 0..translation_units.count) {
                if (reused.value().objects[u].count > 0) {
                    for (var file in translation_units[u].files) {
                        cached_files.insert(file as uint);
                    }
                }
            }
        }
        var generated = codegen.generate(module, state, namespaces, stem, setup, owners, cached_files);
        if (generated.is_err()) {
            return Result<Built, String>.err(render_all([generated.error()], sources));
        }
        var ir = generated.value();
        clock.lap("codegen");

        # Each unit is one part or more; the program's entry points are the
        # last part.
        var sizes = codegen.file_sizes(ir, owners, program.files.count);
        var part_of_file = Array<uint>();
        for (var _ in program.files) {
            part_of_file.append(0);
        }
        var unit_parts = Array<uint[]>();
        uint parts = 0;
        for (var translation_unit in translation_units) {
            var split = _split(program, translation_unit.files, sizes, parts, options.part_size);
            var own = Array<uint>();
            for (var part in split) {
                if (!own.contains(part)) {
                    own.append(part);
                }
            }
            for (var i in 0..translation_unit.files.count) {
                part_of_file[translation_unit.files[i]] = split[i];
            }
            unit_parts.append(_files_size(translation_unit.files, sizes) == 0 ? Array<uint>() : own);
            parts += own.count as uint;
        }
        var entry_part = parts;
        var partition = codegen.prepare(ir, owners, part_of_file, entry_part, entry_part + 1);
        var jobs = Array<PartJob>();
        # The units compiled, with their keys and their parts' objects, to
        # store in the cache.
        var stored = Array<(ulong, String, Path[])>();
        # The parts compiled, with their places in their units and keys, to
        # store in the cache.
        var stored_parts = Array<(ulong, ulong, String)>();
        for (var u in 0..translation_units.count) {
            if (reused.is_value() and reused.value().objects[u].count > 0) {
                if (options.trace_cache) {
                    File.stderr().write_all($"cache: hit {translation_units[u].name}\n");
                }
                objects.append_all(reused.value().objects[u]);
                report.hits.append(translation_units[u].name);
                continue;
            }
            var own = unit_parts[u];
            if (own.is_empty) {
                continue;
            }
            var folder = work.join(Path($"{u}"));
            Directory.create_all(folder);
            if (!reused.is_value()) {
                for (var i in 0..own.count) {
                    jobs.append(PartJob(own[i], folder.join(Path($"{i}.{extension}"))));
                }
                continue;
            }
            var key = reused.value().keys[u].value();
            report.misses.append(translation_units[u].name);
            # Each part's object from the cache when its key hits: its files and
            # what they read are as when it was compiled.
            var parts = Array<Path>();
            ulong hits = 0;
            for (var i in 0..own.count) {
                var files = Array<ulong>();
                for (var file in translation_units[u].files) {
                    if (part_of_file[file] == own[i]) {
                        files.append(file);
                    }
                }
                var part_key = keys.value().part(program, translation_units, u, files, reused.value().interfaces);
                var cached = options.cache.value().part(translation_units[u].name, i, part_key);
                var object = cached.join(Path($"0.{extension}"));
                parts.append(object);
                if (options.cache.value().used(cached) and object.is_file()) {
                    report.part_hits.append($"{translation_units[u].name}#{i}");
                    hits += 1;
                    continue;
                }
                var built = folder.join(Path($"{i}"));
                Directory.create_all(built);
                jobs.append(PartJob(own[i], built.join(Path($"0.{extension}"))));
                stored_parts.append((u, i, part_key));
            }
            if (options.trace_cache) {
                File.stderr().write_all(
                    $"cache: miss {translation_units[u].name} ({own.count - hits} of {own.count} parts)\n"
                );
            }
            stored.append((u, key, parts));
        }
        var entry_object = work.join(Path($"{stem}.{extension}"));
        jobs.append(PartJob(entry_part, entry_object));
        var compiled = compile_parts(
            ir,
            partition,
            jobs,
            machine.value(),
            cpu,
            options.opt_level,
            work,
            options.trace_time,
            options.in_process,
            !cached_files.is_empty or !stored_parts.is_empty,
            lto
        );
        if (compiled.is_err()) {
            # The bitcode and plan stay, so the failed part can be run again.
            return Result<Built, String>.err($"{compiled.error()}\n  (kept {work})");
        }
        _drop_defines(jobs);
        if (keys.is_value()) {
            for (var (u, i, part_key) in stored_parts) {
                var kept = options.cache.value().store(
                    work.join(Path($"{u}")).join(Path($"{i}")), $"{translation_units[u].name}#{i}", part_key
                );
                if (kept.is_err()) {
                    Directory.remove_all(work);
                    return Result<Built, String>.err(kept.error());
                }
            }
            for (var (u, key, parts) in stored) {
                var folder = work.join(Path($"{u}"));
                for (var i in 0..parts.count) {
                    Directory.remove_all(folder.join(Path($"{i}")));
                }
                write_record(
                    folder,
                    reused.value(),
                    module,
                    program,
                    translation_units[u],
                    warnings,
                    parts,
                    options.cache.value()
                );
                var kept = options.cache.value().store(folder, translation_units[u].name, key);
                if (kept.is_err()) {
                    Directory.remove_all(work);
                    return Result<Built, String>.err(kept.error());
                }
                objects.append_all(parts);
            }
        } else {
            for (var job in jobs) {
                if (job.part != entry_part) {
                    objects.append(job.object);
                }
            }
        }
        objects.append(entry_object);
        clock.lap("objects");
    }
    if (lto) {
        var optimized = optimize_whole(
            objects,
            work,
            triple.contains("-windows") ? "obj" : "o",
            machine.value(),
            cpu,
            options.opt_level,
            options.in_process,
            clock
        );
        if (optimized.is_err()) {
            Directory.remove_all(work);
            return Result<Built, String>.err(optimized.error());
        }
        objects = optimized.value();
    }

    # Search order: `-L`, then `[Link(path = ...)]`.
    if (!unit_objects) {
        link_text = _link_attributes(module);
    }
    var (linked, linked_dirs) = _resolve_links(link_text, program);
    var libraries = Array<String>();
    for (var library in options.libraries) {
        libraries.append(library);
    }
    for (var library in linked) {
        libraries.append(library);
    }
    var dirs = Array<Path>();
    for (var dir in options.library_dirs) {
        dirs.append(dir);
    }
    for (var dir in linked_dirs) {
        dirs.append(dir);
    }
    # Then `$PEPPER_LIBRARY_PATH`'s folders, separated as in `PATH`.
    var library_path = os.environment("PEPPER_LIBRARY_PATH");
    if (library_path.is_value()) {
        var separator = os.system_os() == os.OperatingSystem.Windows ? ";" : ":";
        for (var dir in library_path.value().split(separator)) {
            if (!dir.is_empty) {
                dirs.append(Path(dir));
            }
        }
    }
    # A library gets its C header; a static one is an archive, not linked.
    if (options.library.is_value()) {
        var written = write_header(
            header.value(),
            state.exports,
            state.enum_representations,
            options.library.value(),
            libraries,
            program.target
        );
        if (written.is_err()) {
            Directory.remove_all(work);
            return Result<Built, String>.err(written.error());
        }
    }
    # Windows debuggers read the visualizers from the `.pdb`: the runtime's,
    # and the program's enums with payloads' (`enum_natvis`).
    var natvis = Array<Path>();
    if (options.debug and program.target.os == "windows") {
        if (runtime.is_value()) {
            var found = runtime.value().join(Path("debuggers")).join(Path("pepper.natvis"));
            if (found.is_file()) {
                natvis.append(found);
            }
        }
        var enums = work.join(Path("enums.natvis"));
        if (File.write_text(enums, enum_natvis(module)).is_ok()) {
            natvis.append(enums);
        }
    }
    var made = Result<void, String>.ok();
    if (options.library.is_value() and options.library.value() == LibraryKind.Static) {
        made = write_archive(objects, options.output, program.target);
    } else {
        made = link_objects(
            objects,
            options.output,
            libraries,
            dirs,
            program.target,
            options.sysroot,
            options.library.is_value(),
            options.debug,
            natvis
        );
    }
    Directory.remove_all(work);
    if (made.is_err()) {
        return Result<Built, String>.err(made.error());
    }
    clock.lap(options.library.is_value() and options.library.value() == LibraryKind.Static ? "archive" : "link");
    if (options.cache.is_value()) {
        options.cache.value().record(options.output, program_key, !warnings.is_empty);
    }
    return Result<Built, String>.ok(report);
}

## The runtime's folder: the one beside the program's runtime files that
## holds `debuggers/`, if any.
## The text of the runtime's gdb pretty-printers
## (`runtime/debuggers/gdb_printers.py`), which a Linux program built with
## `-g` carries; empty without the runtime.
##
## @param program the program
## @returns the printers' Python source, or empty
export gdb_printers(program: link.Program): String {
    var runtime = _runtime_dir(program);
    if (!runtime.is_value()) {
        return "";
    }
    var printers = File.read_to_string(runtime.value().join(Path("debuggers")).join(Path("gdb_printers.py")));
    return printers.ok_or("");
}

_runtime_dir(program: link.Program): Path? {
    for (var file in program.files) {
        if (!file.prelude) {
            continue;
        }
        var folder = Path(file.name).parent();
        if (folder.is_value() and folder.value().join(Path("debuggers")).is_directory()) {
            return folder;
        }
    }
    return Optional<Path>.Empty;
}

# What else changes the code generated, for the cache's keys.
_codegen_options(options: BuildOptions): String {
    var out = options.frame_pointers ? " --frame-pointers" : "";
    if (options.debug) {
        out = $"{out} -g";
    }
    var checks = options.runtime_checks;
    if (!(checks.overflow and checks.divide and checks.shift and checks.bounds and checks.null)) {
        out = $"{out} --no-runtime-checks {checks.overflow} {checks.divide} {checks.shift} {checks.bounds} {checks.null}";
    }
    return out;
}

## Each file's part when compilation unit `files` alone is compiled
## (`_compile_unit`): its own files' parts from 0 (`_split`), so a large
## unit's object is compiled on several CPUs; the program's entry points
## the next part; every other file, only declared, the one after; the
## location strings (`codegen.Build.separate_locations`) the one after
## that. A part `_split` gave one file alone spreads its symbols over
## several parts (`_spread`), so an edit to that file compiles one of them
## again. Returns each file's first part, how many parts it spreads over,
## and how many parts are the unit's own.
_unit_parts(
    program: link.Program, files: ulong[], ir: llvm.Module, owners: HashMap<String, uint>, part_size: ulong
): (uint[], uint[], uint) {
    var sizes = codegen.file_sizes(ir, owners, program.files.count);
    var split = _split(program, files, sizes, 0, part_size);
    uint count = 1;
    for (var part in split) {
        count = part + 1 > count ? part + 1 : count;
    }
    # How many files each part `_split` made holds.
    var held = Array<uint>();
    for (var _ in 0..count) {
        held.append(0);
    }
    for (var part in split) {
        held[part] += 1;
    }
    # Each part's first number once spread, in order.
    var first = Array<uint>();
    var spreads = Array<uint>();
    uint parts = 0;
    for (var part in 0..count) {
        uint over = 1;
        for (var i in 0..files.count) {
            if (split[i] == part and held[part] == 1) {
                over = _spread(sizes[files[i]]);
            }
        }
        first.append(parts);
        spreads.append(over);
        parts += over;
    }
    var part_of_file = Array<uint>();
    var spread = Array<uint>();
    for (var _ in program.files) {
        part_of_file.append(parts + 1);
        spread.append(1);
    }
    for (var i in 0..files.count) {
        part_of_file[files[i]] = first[split[i]];
        spread[files[i]] = spreads[split[i]];
    }
    return (part_of_file, spread, parts);
}

## How many parts a file of `size` (`codegen.file_sizes`) spreads its
## symbols over: a power of two, so an edit that changes its size a little
## leaves every symbol in its part.
_spread(size: ulong): uint {
    uint over = 1;
    while (over < _MAX_SPREAD and size > (over as ulong) * _SPREAD_SIZE) {
        over *= 2;
    }
    return over;
}

## About how much code (`codegen.file_sizes`) each part of a file spread
## over several holds (`_spread`), and the most parts a file spreads over.
const _SPREAD_SIZE: ulong = 2500;
const _MAX_SPREAD: uint = 16;

## The jobs compiling a compilation unit's own `parts` into `folder`, as
## `<part>.<extension>`, and its location strings' part (`_unit_parts`)
## after them, as `<parts>.<extension>`.
_unit_jobs(folder: Path, parts: uint, extension: String): PartJob[] {
    var jobs = Array<PartJob>();
    for (var part in 0..parts) {
        jobs.append(PartJob(part, folder.join(Path($"{part}.{extension}"))));
    }
    jobs.append(PartJob(parts + 2, folder.join(Path($"{parts}.{extension}"))));
    return jobs;
}

## Removes what each of `jobs` defines (`<object>.defines`), which only a
## compilation unit worker's `_defines` reads.
_drop_defines(jobs: PartJob[]) {
    for (var job in jobs) {
        File.remove(Path($"{job.object}.defines"));
    }
}

## The largest part a unit is compiled in, in `codegen.file_sizes`'s
## measure (blocks and definitions): a larger unit is split into parts of
## about this size, so one large unit does not keep the build waiting on
## one process. The split depends only on the unit's own code, so its
## objects stay the same from one program to the next.
const _PART_SIZE = 10000;

## The part of each of a unit's `files`: as many parts as the unit's size
## needs (`part_size`), no more than its files, each a run of the unit's
## files in namespace order, a file in the part its middle falls in. Each
## part's object is cached under its files (`Keys.part`), so the split
## must stay as it is when an edit changes a file's size: a run moves
## only the files at its ends, and only when the edit is large, where
## filling the least loaded part first moved files all over the unit. The
## parts are numbered from `first`, with no gaps.
_split(program: link.Program, files: ulong[], sizes: ulong[], first: uint, part_size: ulong): uint[] {
    var total = _files_size(files, sizes);
    var count = (total + part_size - 1) / part_size;
    if (count > files.count) {
        count = files.count;
    }
    if (count < 1) {
        count = 1;
    }
    var order = Array<ulong>();
    for (var i in 0..files.count) {
        order.append(i);
    }
    order.sort((a, b) => {
        var x = program.files[files[a]].namespace;
        var y = program.files[files[b]].namespace;
        return x < y ? -1 : (x > y ? 1 : 0);
    });
    var split = Array<uint>();
    for (var _ in files) {
        split.append(0);
    }
    ulong before = 0;
    for (var i in order) {
        var size = sizes[files[i]];
        # Twice the file's middle, against twice each part's share, in
        # whole numbers.
        var part = total == 0 ? 0 : ((before * 2 + size) * count) / (total * 2);
        split[i] = (part < count ? part : count - 1) as uint;
        before += size;
    }
    # Numbered in the order the parts first appear, from `first`, so a
    # part no file went to takes no number.
    var number = HashMap<uint, uint>();
    for (var i in order) {
        if (!number.contains(split[i])) {
            number[split[i]] = first + number.count as uint;
        }
    }
    for (var i in 0..split.count) {
        split[i] = number[split[i]];
    }
    return split;
}

## How much code `files` own.
_files_size(files: ulong[], sizes: ulong[]): ulong {
    ulong total = 0;
    for (var file in files) {
        total += sizes[file];
    }
    return total;
}

## What linking a program takes beyond its files, as text for its key: the
## output and the library kind, the `-l` libraries, the `-L` folders, the
## system root, and the current folder (`[Link(path = ...)]` folders are
## relative to it).
_link_text(options: BuildOptions): String {
    var cwd = process.working_directory();
    var here = cwd.is_ok() ? cwd.value().to_string() : "";
    var text = StringBuilder();
    text.append($"output {options.output}\ncwd {here}\n");
    if (options.library.is_value()) {
        text.append(options.library.value() == LibraryKind.Static ? "--lib static\n" : "--lib shared\n");
    }
    for (var library in options.libraries) {
        text.append($"-l {library}\n");
    }
    for (var dir in options.library_dirs) {
        text.append($"-L {dir}\n");
    }
    if (options.sysroot.is_value()) {
        text.append($"--sysroot {options.sysroot.value()}\n");
    }
    return text.to_string();
}
