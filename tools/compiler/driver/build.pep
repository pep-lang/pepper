## Building a program: the checked model to object files, linked into an
## executable or a library (`--lib`).

import compiler.ast;
import async;
import compiler.codegen;
import [Diagnostic, SourceText, render_all] from compiler.diagnostic;
import io;
import [Directory, File, Path] from io;
import compiler.link;
import llvm;
import os;
import process;
import compiler.sema;
import "cache";
import "emit_static";
import "layers";
import "library";
import "linker";
import "lto";
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
    ## Whether to check every layer loaded by early cutoff again and fail
    ## when its record differs, as `PEPC_VERIFY_CUTOFF` does.
    var verify_cutoff: bool = false;
    ## The target's system root, which the link reads its libraries from
    ## (`--sysroot`, else `$PEPPER_SYSROOT_<TRIPLE>`).
    var sysroot: Path? = Optional<Path>.Empty;
    ## This compiler's arguments, which a `--layer-worker` child is given
    ## again (with `--layer-worker dir` after them) to load the same
    ## program; none checks every layer in this process.
    var worker_args: String[] = Array<String>();
    ## How many layers are checked at once in worker children: 0 for one
    ## per logical CPU (`PEPC_LAYER_JOBS` overrides it).
    var layer_jobs: ulong = 0;
    ## A layer worker started before the program was loaded
    ## (`start_layer_worker`), which loads it at the same time: the first
    ## worker the build gives a layer, else stopped.
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
    ## program's, and each layer's, in a worker too.
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
    ordered.sort((a, b) => _compare_locations(a, b));
    File.stderr().write_all(render_all(ordered, sources) + "\n");
}

## Orders diagnostics by file, then by where in it they start; those
## without a location first.
_compare_locations(a: Diagnostic, b: Diagnostic): int {
    if (!a.location.is_value() or !b.location.is_value()) {
        return (a.location.is_value() ? 1 : 0) - (b.location.is_value() ? 1 : 0);
    }
    var x = a.location.value();
    var y = b.location.value();
    if (x.file != y.file) {
        return x.file < y.file ? -1 : 1;
    }
    if (x.span.start != y.span.start) {
        return x.span.start < y.span.start ? -1 : 1;
    }
    return 0;
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

# The `[Link]` arguments on `module`'s externs, in declaration order, a
# line each: `lib\t<name>`, or `path\t<file>\t<folder>` with the index of
# the file declaring the extern. The cache keeps them with the last layer's
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

    construct() {}
}

## Whether `PEPC_VERIFY_CUTOFF` checks every layer loaded by early cutoff
## again and compares: its record, written on an earlier check of the
## layers below, must be what checking it on them now gives.
_verify_cutoff(): bool {
    var named = os.environment("PEPC_VERIFY_CUTOFF");
    return named.is_value() and !named.value().is_empty;
}

## Whether `PEPC_TRACE_LAYERS` prints, for each layer, the layers it
## reads and the hash of what it changed in the interface
## (`sema.DeltaBase.own_hash`).
_trace_layers(): bool {
    var named = os.environment("PEPC_TRACE_LAYERS");
    return named.is_value() and !named.value().is_empty;
}

## Whether `PEPC_RECORD_STATS` prints the bytes each field of the module
## took in each delta record stored.
_record_stats(): bool {
    var named = os.environment("PEPC_RECORD_STATS");
    return named.is_value() and !named.value().is_empty;
}

## Whether `PEPC_NO_LAYERS` turns checked layers off, for comparing
## builds with and without them.
# `program.link_bodies(bodies)`; a syntax error it reads is printed as pepc
# prints one loading the program, which it would have been then, and the
# error returned is empty: printed already.
_link_bodies(program: link.Program, bodies: bool[]): String? {
    var error = program.link_bodies(bodies);
    if (error.is_value()) {
        print($"pepc: {error.value()}");
        return Optional<String>.Value("");
    }
    return Optional<String>.Empty;
}

# Every file of `program`, for `Program.link_bodies`.
_every_file(program: link.Program): bool[] {
    var out = Array<bool>();
    for (var _ in program.files) {
        out.append(true);
    }
    return out;
}

# The ones of `warnings` in a file of `layer`.
_warnings_in(warnings: Diagnostic[], layer: Layer): Diagnostic[] {
    var files = HashSet<ulong>();
    for (var file in layer.files) {
        files.insert(file);
    }
    var out = Array<Diagnostic>();
    for (var w in warnings) {
        if (w.location.is_value() and files.contains(w.location.value().file)) {
            out.append(w);
        }
    }
    return out;
}

# `warnings` in order of their places, rendered as the build prints them,
# or empty: what a layer's record keeps to print again when it is loaded.
_render_warnings(warnings: Diagnostic[], sources: SourceText[]): String {
    if (warnings.is_empty) {
        return "";
    }
    var ordered = Array<Diagnostic>();
    ordered.append_all(warnings);
    ordered.sort((a, b) => _compare_locations(a, b));
    return render_all(ordered, sources) + "\n";
}

_layers_off(): bool {
    var named = os.environment("PEPC_NO_LAYERS");
    return named.is_value() and !named.value().is_empty;
}

# What `_check_layers` gives: the module checked and the state of the last
# layer's passes; or, when the cache has the last layer's objects
# (`_store_last`), only their folder.
struct _Checked {
    var module: sema.Module;
    var state: sema.PassState;
    var last: Path? = Optional<Path>.Empty;

    construct(module: sema.Module, state: sema.PassState) {
        this.module = module;
        this.state = state;
    }
}

## Checks `program` layer by layer (`layers.pep`). Each layer is keyed on
## its files and the own interfaces of the layers it reads; the cache's
## record under that key is loaded, else the layer is checked on the module
## of the layers it reads, their records merged, and its record stored. The
## last layer, the program's own, has no record: it is checked unless, with
## `last_extension`, the cache has its objects under its key. A layer loaded
## prints the warnings its check gave, which its record keeps.
##
## @param last_extension the objects' extension when the cache may hold the
##   last layer's objects (`_store_last`), else empty
## @returns what was checked (`_Checked`), or the error, rendered
_check_layers(
    program: link.Program,
    layered: Layer[],
    cache: Cache,
    reused: Reused?,
    sources: SourceText[],
    warnings: Diagnostic[],
    clock: _Clock,
    trace: bool,
    verify: bool,
    prechecked: HashMap<ulong, (u8[], String, String)> = HashMap<ulong, (u8[], String, String)>(),
    last_extension: String = "",
    times: sema.PassTimes? = Optional<sema.PassTimes>.Empty
): Result<_Checked, String> {
    var module = sema.Module();
    var state = sema.PassState(program.target);
    # Each layer's own interface and record, as loaded or checked.
    var owns = Array<String>();
    for (var _ in 0..layered.count) {
        owns.append("");
    }
    var records = HashMap<ulong, u8[]>();
    # The layers loaded, whose files' bodies are not linked.
    var loaded = HashSet<ulong>();
    bool checked_any = false;
    bool verify_cutoff = verify or _verify_cutoff();
    bool trace_layers = _trace_layers();
    for (var k in 0..layered.count) {
        layered[k].key = layer_key(layered[k], owns);
        var layer = layered[k];
        # The last layer is the program's own, checked on every build that
        # gets this far.
        if (k + 1 < layered.count) {
            # What this build's workers found or made, else the cache's: the
            # cache may have changed since, as builds share it.
            var found = prechecked.contains(k) ?
                Optional<(u8[], String, String)>.Value(prechecked[k]) :
                find_checked(cache, program, layer);
            if (found.is_value()) {
                var (bytes, own, warned) = found.value();
                # Its warnings, as checking it gave them.
                if (!warned.is_empty) {
                    File.stderr().write_all(warned);
                }
                if (verify_cutoff and checked_any) {
                    var wrong = _verify_reuse_merged(program, layered, records, k, bytes, reused, sources, warnings);
                    if (wrong.is_value()) {
                        return Result<_Checked, String>.err($"PEPC_VERIFY_CUTOFF: {wrong.value()}");
                    }
                }
                owns[k] = own;
                records[k] = bytes;
                loaded.insert(k);
                clock.lap($"find {layer.name}");
                if (trace_layers) {
                    File.stderr().write_all($"layers: {layer.name} own {own.substr(0, 16)} loaded\n");
                }
                if (trace) {
                    var how = checked_any ? "unchanged interface below" : "checked already";
                    File.stderr().write_all($"cache: layer {layer.name} {how}\n");
                }
                continue;
            }
        }
        # The last layer's objects, when a build compiled them under its key
        # (`_store_last`): nothing is checked or generated, as Go links a
        # `main` package whose inputs did not change from its cache.
        if (k + 1 == layered.count and !last_extension.is_empty) {
            var folder = cache.objects($"layer {layer.name}", layer.key);
            if (folder.join(Path($"entry.{last_extension}")).is_file()) {
                var out = _Checked(module, state);
                out.last = Optional<Path>.Value(folder);
                return Result<_Checked, String>.ok(out);
            }
        }
        # The first layer to check: the files of the layers not loaded are
        # linked and checked before it. Those of the layers loaded are as
        # they were when checked, without an error or a warning (see
        # `store`).
        if (!checked_any) {
            var bodies = _every_file(program);
            for (var j in loaded) {
                for (var file in layered[j].files) {
                    bodies[file] = false;
                }
            }
            var unread = _link_bodies(program, bodies);
            if (unread.is_value()) {
                return Result<_Checked, String>.err(unread.value());
            }
            var errors = program.check();
            if (errors.is_value()) {
                return Result<_Checked, String>.err(errors.value());
            }
            warnings.append_all(program.warnings());
            clock.lap("link bodies");
        }
        # The layers it reads, their records merged.
        var merged = merged_module(program, records, layer.reads);
        if (merged.is_err()) {
            return Result<_Checked, String>.err($"the layers layer {layer.name} reads do not merge: {merged.error()}");
        }
        module = merged.value();
        clock.lap($"merge {layer.name}");
        # What its record is a delta on, indexed before the layer changes it.
        var base = sema.DeltaBase();
        if (k + 1 < layered.count) {
            sema.index_module(module, base);
            clock.lap("index");
        }
        var checked = _check_layer(program, module, layer, reused, sources, warnings, times);
        if (checked.is_err()) {
            return Result<_Checked, String>.err(checked.error());
        }
        var (after, ran_state, aliases) = checked.value();
        module = after;
        state = ran_state;
        checked_any = true;
        clock.lap($"layer {layer.name}");
        if (k + 1 == layered.count) {
            break;
        }
        var unit = sema.finish_checked(module, state, aliases);
        # A layer with a warning is checked again on each build, which
        # reports it again; so a layer loaded had none.
        var (
            bytes, own
        ) = store_checked(cache, program, layer, unit, base, _render_warnings(_warnings_in(warnings, layer), sources));
        owns[k] = own;
        records[k] = bytes;
        clock.lap("store");
        if (_record_stats()) {
            _print_record_stats(layer.name, base);
        }
        if (trace_layers) {
            File.stderr().write_all($"layers: {layer.name} own {own.substr(0, 16)} checked\n");
        }
    }
    if (trace) {
        File.stderr().write_all($"cache: {loaded.count} of {layered.count} layers checked already\n");
    }
    var out = _Checked(module, state);
    return Result<_Checked, String>.ok(out);
}

# The symbols `ir`, a layer's module just compiled with `partition`,
# defines for other objects, a line each, by Pepper name: what survived
# optimization, not local. The cache
# keeps them beside the layer's object (`defines`), and a layer above only
# declares these (`codegen.generate`'s `declared`); an instantiation the
# layer's object dropped (`linkonce_odr`, inlined everywhere) it defines
# itself, as a compiler shares the generics a library exports.
_defines(ir: llvm.Module, partition: codegen.Partition): String {
    var out = StringBuilder();
    var values = ir.functions();
    for (var global in ir.globals()) {
        values.append(global);
    }
    for (var value in values) {
        var linkage = value.linkage();
        if (value.is_declaration() or linkage == llvm.Linkage.Internal or linkage == llvm.Linkage.Private) {
            continue;
        }
        var name = value.name();
        var pepper = partition.names.try_get(name);
        out.append(pepper.is_value() ? pepper.value() : name);
        out.append("\n");
    }
    return out.to_string();
}

# Leaves the symbols layer `layer` (number `k`)'s object defines, which the
# cache keeps, in `dir` as `<k>.defines`, for the workers of the layers that
# read it.
_copy_defines(cache: Cache, layer: Layer, dir: Path, k: ulong) {
    var text = File.read_to_string(cache.objects($"layer {layer.name}", layer.key).join(Path("defines")));
    var partial = _layer_file(dir, k, $"defines.{process.id()}");
    File.write_text(partial, text.is_ok() ? text.value() : "");
    File.rename(partial, _layer_file(dir, k, "defines"));
}

# The symbols the objects of the layers numbered `ks` define (`_defines`),
# from `<k>.defines` in `dir` or, with no `dir`, from the cache.
_defined_by(cache: Cache, layered: Layer[], ks: ulong[], dir: Path?): HashSet<String> {
    var out = HashSet<String>();
    for (var k in ks) {
        var path = dir.is_value() ?
            _layer_file(dir.value(), k, "defines") :
            cache.objects($"layer {layered[k].name}", layered[k].key).join(Path("defines"));
        var text = File.read_to_string(path);
        if (text.is_err()) {
            continue;
        }
        for (var line in text.value().split("\n")) {
            if (!line.is_empty) {
                out.insert(line);
            }
        }
    }
    return out;
}

# How the units are compiled, as text for their keys: the target, the CPU
# (`-m`), the `-O` level, link-time optimization and the code generation
# options. A layer worker keys them as the build does.
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

# The object of `layer` in the build cache, under its key: its files' code
# and what it instantiated, as a layer worker compiles it.
_layer_object(cache: Cache, layer: Layer, extension: String): Path {
    return cache.objects($"layer {layer.name}", layer.key).join(Path($"0.{extension}"));
}

# Keeps the last layer's objects, `folder`'s `0.<ext>` and `entry.<ext>`,
# in the build cache under its key, with the program's `[Link]` arguments
# (`link`) and the warnings checking it gave (`warn`), rendered: a later
# build whose last layer has the same key links them, as Go links a `main`
# package from its cache, and prints the warnings again. Returns where the
# cache keeps them.
_store_last(cache: Cache, last: Layer, folder: Path, link_text: String, warned: String): Result<Path, String> {
    if (File.write_text(folder.join(Path("link")), link_text).is_err()
        or File.write_text(folder.join(Path("warn")), warned).is_err()) {
        return Result<Path, String>.err($"cannot write to {folder}");
    }
    return cache.store(folder, $"layer {last.name}", last.key);
}

# Compiles `module`, the layer `layer` just checked, into its object and
# keeps that in the build cache (`_layer_object`): the layer's files' own
# code and what it instantiated; everything else, what the layers below
# made (`below`) and the other files' code, is only declared, since their
# objects define it. `dir` holds the work.
_compile_layer(
    program: link.Program,
    layer: Layer,
    module: sema.Module,
    state: sema.PassState,
    below: HashSet<String>,
    options: BuildOptions,
    cache: Cache,
    dir: Path
): String? {
    var triple = codegen.target_triple(program.target);
    var cpu = options.cpu.is_value() ? options.cpu.value() : codegen.Cpu.default_for(triple);
    var extension = _object_extension(options, triple);
    var level = [llvm.OptLevel.O0, llvm.OptLevel.O1, llvm.OptLevel.O2, llvm.OptLevel.O3][options.opt_level];
    codegen.initialize_backends();
    var machine = llvm.TargetMachine.create(triple, cpu.name, cpu.features, level);
    if (machine.is_err()) {
        return Optional<String>.Value(machine.error().message);
    }
    var setup = codegen.Build(machine.value(), cpu);
    setup.opt_level = options.opt_level;
    setup.frame_pointers = options.frame_pointers;
    setup.runtime_checks = options.runtime_checks;
    var namespaces = Array<String>();
    for (var f in program.files) {
        namespaces.append(f.namespace);
    }
    var own = HashSet<ulong>();
    for (var file in layer.files) {
        own.insert(file);
    }
    var others = HashSet<uint>();
    var part_of_file = Array<uint>();
    for (var i in 0..program.files.count) {
        if (!own.contains(i)) {
            others.insert(i as uint);
        }
        part_of_file.append(own.contains(i) ? 0 : 2);
    }
    var owners = HashMap<String, uint>();
    var generated = codegen.generate(
        module, state, namespaces, layer.name, setup, owners, others, Optional<HashSet<String>>.Value(below)
    );
    if (generated.is_err()) {
        return Optional<String>.Value(render_all([generated.error()], program.sources()));
    }
    # Part 0 is the layer's; the program's entry points (part 1) are the
    # last layer's to compile.
    var partition = codegen.prepare(generated.value(), owners, part_of_file, 1, 3);
    var folder = dir.join(Path($"{layer.name.replace("/", "_")}.object"));
    Directory.remove_all(folder);
    Directory.create_all(folder);
    var compiled = compile_parts(
        generated.value(),
        partition,
        [PartJob(0, folder.join(Path($"0.{extension}")))],
        machine.value(),
        cpu,
        options.opt_level,
        folder,
        options.trace_time,
        true,
        false,
        options.lto and options.opt_level > 0
    );
    if (compiled.is_err()) {
        return Optional<String>.Value(compiled.error());
    }
    if (File.write_text(folder.join(Path("defines")), _defines(generated.value(), partition)).is_err()) {
        return Optional<String>.Value($"cannot write to {folder}");
    }
    var kept = cache.store(folder, $"layer {layer.name}", layer.key);
    if (kept.is_err()) {
        return Optional<String>.Value(kept.error());
    }
    return Optional<String>.Empty;
}

## Starts a layer worker for a build with `args` (this compiler's, as
## `BuildOptions.worker_args`) whose build folder is `build_dir`, before the
## program is loaded, so it loads the program while the build does: a
## rebuild's first layer to check then waits for no worker to load it, as
## Gradle and Bazel keep workers ready. Only when `build_dir` exists, from a
## build before; a build that checks no layer in workers stops it.
##
## @param args this compiler's arguments
## @param build_dir the build's folder
## @returns the worker, if started
export start_layer_worker(args: String[], build_dir: Path): process.Child? {
    if (!build_dir.is_directory() or _layer_jobs_named() == 1) {
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
    command.argument("--layer-worker").argument(build_dir.join(Path($"layers.{process.id()}")).to_string());
    command.stdin(process.Stream.Pipe);
    var spawned = command.spawn();
    return spawned.is_ok() ? Optional<process.Child>.Value(spawned.value()) : Optional<process.Child>.Empty;
}

# Stops `options`' early worker, which no layer needs: at the end of its
# input, it ends.
_stop_early_worker(options: BuildOptions) {
    if (options.early_worker.is_value()) {
        options.early_worker.value().stdin().close();
        options.early_worker = Optional<process.Child>.Empty;
    }
}

# `PEPC_LAYER_JOBS` as a number, or 0.
_layer_jobs_named(): ulong {
    var named = os.environment("PEPC_LAYER_JOBS");
    if (named.is_value() and !named.value().is_empty) {
        var n = ulong.parse(named.value());
        if (n.is_value()) {
            return n.value();
        }
    }
    return 0;
}

# How many layers to check at once (`BuildOptions.layer_jobs`).
_layer_jobs(options: BuildOptions): ulong {
    var named = _layer_jobs_named();
    if (named != 0) {
        return named;
    }
    return options.layer_jobs != 0 ? options.layer_jobs : async.logical_cpus();
}

# The files a layer worker and the build pass layer `k` through, in `dir`.
_layer_file(dir: Path, k: ulong, what: String): Path {
    return dir.join(Path($"{k}.{what}"));
}

# A layer worker child: its process, and the layer it checks, if any.
struct _Worker {
    var child: process.Child;
    var layer: long = -1;
    ## Whether it was told which layers were done (its first line).
    var told: bool = false;

    construct(child: process.Child) {
        this.child = child;
    }
}

# Checks every layer but the last, the program's own, in up to `jobs`
# `--layer-worker` children, each layer once the layers it reads are done,
# and puts in `prechecked` the record, own interface and warnings of every
# layer, found in the cache or checked: `_check_layers` takes them from
# there, not from the cache again, which builds running at once may have
# changed since, so its keys are the ones the objects were found or stored
# under.
_check_in_workers(
    program: link.Program,
    layered: Layer[],
    options: BuildOptions,
    jobs: ulong,
    prechecked: HashMap<ulong, (u8[], String, String)>
): Result<void, String> {
    # A folder of this build's own: builds in one folder at once (`pepper
    # test` builds its test programs side by side) share `build_dir`. Kept
    # with `-T time`, for the time each worker's stages took (`<k>.stages`).
    var dir = options.build_dir.join(Path($"layers.{process.id()}"));
    Directory.remove_all(dir);
    var created = Directory.create_all(dir);
    if (created.is_err()) {
        return Result<void, String>.err($"cannot create {dir}: {created.error().message}");
    }
    var checked = _check_in_workers_at(program, layered, options, jobs, prechecked, dir);
    # With `-T passes`, the time each worker's passes took (`<k>.passes`).
    if (options.pass_times.is_value()) {
        for (var k in 0..layered.count) {
            var passes = File.read_to_string(_layer_file(dir, k, "passes"));
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

# `_check_in_workers`, passing the layers through `dir`.
_check_in_workers_at(
    program: link.Program,
    layered: Layer[],
    options: BuildOptions,
    jobs: ulong,
    prechecked: HashMap<ulong, (u8[], String, String)>,
    dir: Path
): Result<void, String> {
    var cache = options.cache.value();
    var extension = _object_extension(options, codegen.target_triple(program.target));
    var executable = process.executable_path();
    if (executable.is_err()) {
        return Result<void, String>.err($"cannot find this compiler: {executable.error().message}");
    }
    var count = layered.count - 1;
    var owns = Array<String>();
    # A layer's record is ready (`checked`), then its object (`done`).
    var checked = Array<bool>();
    var done = Array<bool>();
    var started = Array<bool>();
    # With `-T time`, when each layer a worker checked began and ended, in
    # milliseconds from the start, with the layers it reads (`schedule`, as
    # Ninja's `.ninja_log`): the chain of layers that bounds the build.
    var clock_start = os.Instant.now();
    var schedule = StringBuilder();
    var began = HashMap<ulong, ulong>();
    for (var _ in 0..layered.count) {
        owns.append("");
        checked.append(false);
        done.append(false);
        started.append(false);
    }
    var ready = Array<ulong>();
    var workers = Array<_Worker>();
    if (options.early_worker.is_value()) {
        workers.append(_Worker(options.early_worker.value()));
    }
    ulong left = count;
    var failure = Optional<String>.Empty;
    while (left > 0 and !failure.is_value()) {
        bool progressed = false;
        for (var k in 0..count) {
            if (started[k]) {
                continue;
            }
            # A layer is checked on the records of the layers it reads.
            bool reads_done = true;
            for (var d in layered[k].reads) {
                reads_done = reads_done and checked[d];
            }
            if (!reads_done) {
                continue;
            }
            started[k] = true;
            progressed = true;
            layered[k].key = layer_key(layered[k], owns);
            var found = find_checked(cache, program, layered[k]);
            # A layer's object goes with its record: one without it (pruned,
            # say) is checked again, which compiles it.
            if (found.is_value() and _layer_object(cache, layered[k], extension).is_file()) {
                # Reused now: no build pruning the cache removes it before
                # this one links it.
                cache.used(cache.objects($"layer {layered[k].name}", layered[k].key));
                var (bytes, own, warned) = found.value();
                File.write_bytes(_layer_file(dir, k, "rec"), bytes);
                _copy_defines(cache, layered[k], dir, k);
                owns[k] = own;
                prechecked[k] = (bytes, own, warned);
                checked[k] = true;
                done[k] = true;
                left -= 1;
            } else {
                ready.append(k);
            }
        }
        # Each ready layer to an idle worker, starting one while fewer than
        # `jobs` are checking or compiling: one waiting for the objects of
        # the layers it reads uses no processor, but holds the program in
        # memory (at most half again as many workers, and two more).
        while (!ready.is_empty) {
            var idle = Optional<ulong>.Empty;
            ulong active = 0;
            for (var w in 0..workers.count) {
                var at = workers[w].layer;
                if (at < 0) {
                    if (!idle.is_value()) {
                        idle = Optional<ulong>.Value(w);
                    }
                } else if (!checked[at as ulong] or _layer_file(dir, at as ulong, "compiling").is_file()) {
                    active += 1;
                }
            }
            if (active >= jobs) {
                break;
            }
            if (!idle.is_value()) {
                if (workers.count as ulong >= jobs + jobs / 2 + 2) {
                    break;
                }
                var command = process.Command(executable.value().to_string());
                for (var arg in options.worker_args) {
                    command.argument(arg);
                }
                command.argument("--layer-worker").argument(dir.to_string());
                command.stdin(process.Stream.Pipe);
                var spawned = command.spawn();
                if (spawned.is_err()) {
                    failure = Optional<String>.Value($"cannot run {executable.value()}: {spawned.error().message}");
                    break;
                }
                workers.append(_Worker(spawned.value()));
                idle = Optional<ulong>.Value(workers.count - 1);
            }
            var k = ready.remove_at(0);
            var worker = workers[idle.value()];
            var line = StringBuilder();
            if (!worker.told) {
                # The layers done already, whose files' bodies the worker
                # need not read, as the build's own process does not.
                line.append("done");
                for (var d in 0..layered.count) {
                    if (checked[d]) {
                        line.append($" {d}");
                    }
                }
                line.append("\n");
                worker.told = true;
            }
            line.append($"{k} {layered[k].key}\n");
            var sent = worker.child.stdin().write_all(line.to_string());
            if (sent.is_err()) {
                failure = Optional<String>.Value($"a layer worker stopped: {sent.error().message}");
                break;
            }
            worker.layer = k as long;
            began[k] = (os.Instant.now() - clock_start).milliseconds() as ulong;
            progressed = true;
        }
        for (var worker in workers) {
            if (worker.layer < 0) {
                continue;
            }
            var k = worker.layer as ulong;
            if (!checked[k] and _layer_file(dir, k, "checked").is_file()) {
                var record = _read_worker_record(dir, k, layered[k]);
                if (record.is_err()) {
                    failure = Optional<String>.Value(record.error());
                    continue;
                }
                var (bytes, own, warned) = record.value();
                owns[k] = own;
                prechecked[k] = (bytes, own, warned);
                checked[k] = true;
                progressed = true;
            }
            if (!_layer_file(dir, k, "done").is_file()) {
                var ended = worker.child.try_wait();
                if (ended.is_err() or ended.value().is_value()) {
                    failure = Optional<String>.Value($"the worker checking layer {layered[k].name} ended");
                }
                continue;
            }
            worker.layer = -1;
            progressed = true;
            if (options.trace_time) {
                var reads = StringBuilder();
                for (var d in layered[k].reads) {
                    reads.append($" {d}");
                }
                var ended = (os.Instant.now() - clock_start).milliseconds();
                schedule.append($"{k} {layered[k].name} {began[k]} {ended}{reads.to_string()}\n");
            }
            var error = File.read_to_string(_layer_file(dir, k, "err"));
            if (error.is_ok()) {
                failure = Optional<String>.Value(error.value());
                continue;
            }
            if (!checked[k]) {
                failure = Optional<String>.Value($"the worker checking layer {layered[k].name} left no record");
                continue;
            }
            done[k] = true;
            left -= 1;
        }
        if (!progressed and !failure.is_value()) {
            async.Thread.sleep(2);
        }
    }
    if (options.trace_time) {
        File.write_text(dir.join(Path("schedule")), schedule.to_string());
    }
    for (var worker in workers) {
        worker.child.stdin().close();
    }
    for (var worker in workers) {
        if (failure.is_value()) {
            worker.child.kill();
        }
        worker.child.wait();
    }
    if (failure.is_value()) {
        return Result<void, String>.err(failure.value());
    }
    return Result<void, String>.ok();
}

## A `--layer-worker` child of a build with `options`: loads the layers as
## the build does, then checks each layer whose number and key a line of
## standard input gives, on the records of the layers it reads (in `dir`,
## as `<k>.rec`), stores its record and object in the cache as the build
## would, and leaves in `dir` its record (`<k>.rec`), its own interface
## (`<k>.own`), what its object defines (`<k>.defines`), its warnings,
## rendered (`<k>.warn`), or its error (`<k>.err`), then `<k>.done`. Its
## first line (`done k...`) names the layers done when it started, whose
## files' bodies it does not read.
##
## @param program the program, loaded and linked as the build loads it
## @param options the build's options
## @param dir the folder the build and its workers pass layers through
## @returns the exit code: 0 once standard input ends
export layer_worker(program: link.Program, options: BuildOptions, dir: Path): int {
    if (!options.cache.is_value()) {
        File.stderr().write_all("pepc: a layer worker needs the build cache\n");
        return 1;
    }
    var clock = _Clock(options.trace_time);
    var cache = options.cache.value();
    var triple = codegen.target_triple(program.target);
    var units = link.units(program);
    var keys = Keys(program, units, _build_text(options, triple));
    clock.lap("worker keys");
    var triple_extension = _object_extension(options, triple);
    var reused = Optional<Reused>.Value(reuse(program, units, keys, cache, triple_extension));
    clock.lap("worker reuse");
    var layered = layers(program, link.layer_units(program), keys.base());
    clock.lap("worker layers");
    # The files whose bodies are read: all but those of the layers done
    # when the worker started (its first line, `done k...`), which it is
    # never given; linked at the first layer it is.
    var bodies = _every_file(program);
    bool linked = false;
    var sources = program.sources();
    for (var read in File.stdin().lines()) {
        if (read.is_err()) {
            break;
        }
        var parts = read.value().trim().split(" ");
        if (parts.count > 0 and parts[0] == "done") {
            for (var i in 1..parts.count) {
                var d = ulong.parse(parts[i]);
                if (d.is_value() and d.value() < layered.count) {
                    for (var file in layered[d.value()].files) {
                        bodies[file] = false;
                    }
                }
            }
            continue;
        }
        if (parts.count != 2) {
            continue;
        }
        if (!linked) {
            var unread = _link_bodies(program, bodies);
            if (unread.is_value()) {
                File.stderr().write_all($"{unread.value()}\n");
                return 1;
            }
            linked = true;
            clock.lap("worker link bodies");
        }
        var number = ulong.parse(parts[0]);
        if (!number.is_value() or number.value() >= layered.count) {
            continue;
        }
        var k = number.value();
        var layer = layered[k];
        layer.key = parts[1];
        var records = HashMap<ulong, u8[]>();
        String? error;
        for (var d in layer.reads) {
            var bytes = File.read_bytes(_layer_file(dir, d, "rec"));
            if (bytes.is_err()) {
                error = Optional<String>.Value($"no record of layer {layered[d].name} for layer {layer.name}");
                break;
            }
            records[d] = bytes.value();
        }
        if (!error.is_value()) {
            error = _work_on(program, layer, records, cache, reused, sources, dir, k, options);
        }
        if (error.is_value()) {
            File.write_text(_layer_file(dir, k, "err"), error.value());
        }
        var partial = _layer_file(dir, k, $"done.{process.id()}");
        File.write_text(partial, "");
        File.rename(partial, _layer_file(dir, k, "done"));
    }
    return 0;
}

# Checks `layer` (number `k`) for a layer worker on the merged `records`
# of the layers it reads, stores its record and leaves it in `dir`: the
# error, if any.

_work_on(
    program: link.Program,
    layer: Layer,
    records: HashMap<ulong, u8[]>,
    cache: Cache,
    reused: Reused?,
    sources: SourceText[],
    dir: Path,
    k: ulong,
    options: BuildOptions
): String? {
    bool trace = options.trace_time;
    var t0 = os.Instant.now();
    var stages = "";
    var merged = merged_module(program, records, layer.reads);
    if (merged.is_err()) {
        return Optional<String>.Value($"the layers layer {layer.name} reads do not merge: {merged.error()}");
    }
    var module = merged.value();
    var t1 = os.Instant.now();
    stages = stages + $"merge {(t1 - t0).milliseconds()}\n";
    var base = sema.DeltaBase();
    sema.index_module(module, base);
    var t2 = os.Instant.now();
    stages = stages + $"index {(t2 - t1).milliseconds()}\n";
    var warnings = Array<Diagnostic>();
    var times = options.pass_times.is_value() ?
        Optional<sema.PassTimes>.Value(sema.PassTimes()) :
        Optional<sema.PassTimes>.Empty;
    var checked = _check_layer(program, module, layer, reused, sources, warnings, times);
    if (checked.is_err()) {
        return Optional<String>.Value(checked.error());
    }
    if (times.is_value()) {
        File.write_text(_layer_file(dir, k, "passes"), times.value().to_text());
    }
    var t3 = os.Instant.now();
    stages = stages + $"check {(t3 - t2).milliseconds()}\n";
    var (after, state, aliases) = checked.value();
    var unit = sema.finish_checked(after, state, aliases);
    var t4 = os.Instant.now();
    stages = stages + $"finish {(t4 - t3).milliseconds()}\n";
    var warned = _render_warnings(warnings, sources);
    var (bytes, own) = store_checked(cache, program, layer, unit, base, warned);
    var t5 = os.Instant.now();
    stages = stages + $"store {(t5 - t4).milliseconds()}\n";
    # The record first: the layers that read this one are checked on it
    # while its object compiles (pipelining, as a build system starts a
    # library's dependents on its interface while its code generates).
    File.write_bytes(_layer_file(dir, k, "rec"), bytes);
    File.write_text(_layer_file(dir, k, "own"), own);
    if (!warned.is_empty) {
        File.write_text(_layer_file(dir, k, "warn"), warned);
    }
    _mark(dir, k, "checked");
    # Its object declares what the objects of the layers it reads define:
    # it waits for them.
    for (var d in layer.reads) {
        while (!_layer_file(dir, d, "defines").is_file()) {
            async.Thread.sleep(2);
        }
    }
    var below = _defined_by(cache, Array<Layer>(), layer.reads, Optional<Path>.Value(dir));
    var t6 = os.Instant.now();
    stages = stages + $"wait {(t6 - t5).milliseconds()}\n";
    _mark(dir, k, "compiling");
    # Its object, which code generation of the program does not make again.
    var compiled = _compile_layer(program, layer, after, state, below, options, cache, dir);
    if (compiled.is_value()) {
        return compiled;
    }
    _copy_defines(cache, layer, dir, k);
    var t7 = os.Instant.now();
    stages = stages + $"object {(t7 - t6).milliseconds()}\nreads {layer.reads.count}\n";
    if (trace) {
        File.write_text(_layer_file(dir, k, "stages"), stages);
    }
    return Optional<String>.Empty;
}

# The record, own interface and warnings a worker left for layer `k` in
# `dir`.
_read_worker_record(dir: Path, k: ulong, layer: Layer): Result<(u8[], String, String), String> {
    var bytes = File.read_bytes(_layer_file(dir, k, "rec"));
    var own = File.read_to_string(_layer_file(dir, k, "own"));
    if (bytes.is_err() or own.is_err()) {
        return Result<(u8[], String, String), String>.err($"the worker checking layer {layer.name} left no record");
    }
    # Its warnings `_check_layers` prints, with the record.
    var warned = File.read_to_string(_layer_file(dir, k, "warn"));
    return Result<(u8[], String, String), String>.ok(
        (bytes.value(), own.value(), warned.is_ok() ? warned.value() : "")
    );
}

# Leaves the empty file `<k>.<what>` in `dir`, whole, by a rename.
_mark(dir: Path, k: ulong, what: String) {
    var partial = _layer_file(dir, k, $"{what}.{process.id()}");
    File.write_text(partial, "");
    File.rename(partial, _layer_file(dir, k, what));
}

# Checks layer `layer`'s files on top of `module`, the layers before it:
# the module after, the passes' state and the type aliases as built.
_check_layer(
    program: link.Program,
    module: sema.Module,
    layer: Layer,
    reused: Reused?,
    sources: SourceText[],
    warnings: Diagnostic[],
    times: sema.PassTimes? = Optional<sema.PassTimes>.Empty
): Result<(sema.Module, sema.PassState, sema.TypeAliasDef[]), String> {
    # The specializations the checked layers asked for met their
    # constraints when they were checked.
    var checked_specs = (module.struct_specs.count, module.func_specs.count);
    var built = sema.build_on(program, module, layer.files);
    if (built.is_err()) {
        return Result<(sema.Module, sema.PassState, sema.TypeAliasDef[]), String>.err(
            render_all([built.error()], sources)
        );
    }
    var after = built.value();
    var aliases = Array<sema.TypeAliasDef>();
    for (var alias in after.type_aliases) {
        aliases.append(alias.copy());
    }
    # Summaries for the build cache's skipped bodies; a layer records the
    # ones it makes either way (`settled_summaries`).
    after.record_summaries = reused.is_value();
    if (reused.is_value()) {
        after.cached_files = reused.value().files;
        for (var (loc, text) in reused.value().summaries) {
            after.recorded_summaries[loc] = text;
        }
    }
    var state = sema.PassState(program.target);
    state.sources = sources;
    state.checked_specs = checked_specs;
    state.pass_times = times;
    # No lazy methods: a later layer may use a method this one would drop
    # from a specialization it made.
    var ran = sema.run_steps_with(after, state, 0xffffffffffffffff);
    for (var note in state.notes) {
        warnings.append(note);
    }
    if (ran.is_err()) {
        return Result<(sema.Module, sema.PassState, sema.TypeAliasDef[]), String>.err(
            render_all([ran.error()], sources)
        );
    }
    return Result<(sema.Module, sema.PassState, sema.TypeAliasDef[]), String>.ok((after, state, aliases));
}

# For `PEPC_VERIFY_CUTOFF`: checks layer `k`, loaded by early cutoff, again
# on the layers it reads, merged, and compares the result with its record.
_verify_reuse_merged(
    program: link.Program,
    layered: Layer[],
    records: HashMap<ulong, u8[]>,
    k: ulong,
    bytes: u8[],
    reused: Reused?,
    sources: SourceText[],
    warnings: Diagnostic[]
): String? {
    var merged = merged_module(program, records, layered[k].reads);
    if (merged.is_err()) {
        return Optional<String>.Value($"the layers layer {layered[k].name} reads do not merge: {merged.error()}");
    }
    var reads = Array<ulong>();
    reads.append_all(layered[k].reads);
    reads.append(k);
    var all = HashMap<ulong, u8[]>();
    for (var (d, b) in records) {
        all[d] = b;
    }
    all[k] = bytes;
    var loaded = merged_module(program, all, reads);
    if (loaded.is_err()) {
        return Optional<String>.Value($"the record of layer {layered[k].name} does not merge: {loaded.error()}");
    }
    # Checked again, then resumed and settled as merging leaves a module.
    var checked = _check_layer(program, merged.value(), layered[k], reused, sources, warnings);
    if (checked.is_err()) {
        return Optional<String>.Value($"layer {layered[k].name} does not check again: {checked.error()}");
    }
    var (after, state, aliases) = checked.value();
    var again = sema.resume_checked(sema.finish_checked(after, state, aliases));
    sema.settle_merged(again);
    sema.sort_globals(program, again);
    # Which files' objects the cache holds is this build's, not the layer's.
    again.cached_files = loaded.value().cached_files;
    return _differ(layered[k], sema.CheckedUnit(loaded.value()), sema.CheckedUnit(again));
}

# What differs between `unit`, layer `layer`'s record as loaded, and
# `again`, the layer checked again; none when nothing does.
_differ(layer: Layer, unit: sema.CheckedUnit, again: sema.CheckedUnit): String? {
    var expected = sema.RecordOut();
    again.write(expected);
    var actual = sema.RecordOut();
    unit.write(actual);
    if (!(expected.finish() == actual.finish())) {
        # Name what differs: the fields, structs and functions.
        var was = HashMap<String, String>();
        for (var (what, hash) in sema.interface_fields(again.module, false)) {
            was[what] = hash;
        }
        var differ = Array<String>();
        for (var (what, hash) in sema.interface_fields(unit.module, false)) {
            var had = was.try_get(what);
            if (!had.is_value() or had.value() != hash) {
                differ.append(what);
            }
            was.remove(what);
        }
        for (var (what, _) in was) {
            differ.append(what + " (only checked again)");
        }
        # The checked summaries that differ, by key: as loaded, then as
        # checked again.
        var fresh = again.module.checked.summaries;
        var kept = unit.module.checked.summaries;
        ulong told = 0;
        for (var (key, (loc, text)) in kept) {
            var other = fresh.try_get(key);
            var same = false;
            if (other.is_value()) {
                var (other_loc, other_text) = other.value();
                same = other_loc == loc and other_text == text;
            }
            if (!same and told < 8) {
                var shown_other = "none";
                if (other.is_value()) {
                    var (other_loc, other_text) = other.value();
                    shown_other = $"{other_loc.file}:{other_loc.span.start} {other_text}";
                }
                differ.append($"summary {key}: {loc.file}:{loc.span.start} {text} / {shown_other}");
                told += 1;
            }
        }
        for (var (key, _) in fresh) {
            if (!kept.contains(key) and told < 8) {
                differ.append($"summary {key} only checked again");
                told += 1;
            }
        }
        for (var name in again.module.checked.functions) {
            if (!unit.module.checked.functions.contains(name) and told < 12) {
                differ.append($"checked function {name} only checked again");
                told += 1;
            }
        }
        for (var name in unit.module.checked.functions) {
            if (!again.module.checked.functions.contains(name) and told < 16) {
                differ.append($"checked function {name} only loaded");
                told += 1;
            }
        }
        if (unit.module.checked.extensions != again.module.checked.extensions) {
            differ.append($"checked extensions {unit.module.checked.extensions} / {again.module.checked.extensions}");
        }
        var shown = Array<String>();
        for (var i in 0..(differ.count < 40 ? differ.count : 40)) {
            shown.append(differ[i]);
        }
        return Optional<String>.Value(
            $"the record of layer {layer.name} loaded by early cutoff differs from the layer checked again in {differ.count} parts: {", ".join(shown)}"
        );
    }
    return Optional<String>.Empty;
}

# Prints the bytes and counts `PEPC_RECORD_STATS` gathered for one record.
_print_record_stats(name: String, base: sema.DeltaBase) {
    var sizes = Array<(String, ulong)>();
    for (var (field, bytes) in base.stats) {
        sizes.append((field, bytes));
    }
    sizes.sort((a, b) => {
        var (_, x) = a;
        var (_, y) = b;
        return x > y ? -1 : (x < y ? 1 : 0);
    });
    for (var (field, bytes) in sizes) {
        if (field.ends_with(" count")) {
            File.stderr().write_all($"record: {name} {field} {bytes}\n");
        } else if (bytes >= 1024) {
            File.stderr().write_all($"record: {name} {field} {bytes / 1024} KB\n");
        }
    }
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
    var clock = _Clock(options.trace_time);
    var triple = codegen.target_triple(program.target);
    var cpu = options.cpu.is_value() ? options.cpu.value() : codegen.Cpu.default_for(triple);
    # Link-time optimization needs an optimized build.
    bool lto = options.lto and options.opt_level > 0;
    var units = link.units(program);
    var keys = Optional<Keys>.Empty;
    String program_key = "";
    # A library's header is written beside it, and must still be there.
    var header = options.library.is_value() ?
        Optional<Path>.Value(header_path(options.output, program.target)) :
        Optional<Path>.Empty;
    if (options.cache.is_value()) {
        keys = Optional<Keys>.Value(Keys(program, units, _build_text(options, triple)));
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
        reused = Optional<Reused>.Value(reuse(program, units, keys.value(), options.cache.value(), triple_extension));
        clock.lap("reuse");
    }

    var sources = program.sources();
    var layered = Array<Layer>();
    # Debug info holds the positions a layer's key leaves out, so a build
    # with `-g` keys each unit by its text (`Keys.exact_positions`) instead.
    if (options.cache.is_value() and !_layers_off() and !options.debug) {
        layered = layers(program, link.layer_units(program), keys.value().base());
    }
    # Checking layers links the bodies it needs when it gets to them.
    var warnings = Array<Diagnostic>();
    if (layered.count <= 1) {
        var unread = _link_bodies(program, _every_file(program));
        if (unread.is_value()) {
            return Result<Built, String>.err(unread.value());
        }
        warnings = program.warnings();
    }
    var module = sema.Module();
    var state = sema.PassState(program.target);
    # Whether layer workers compiled every layer but the last into its
    # object (`_layer_object`), and what those layers made.
    bool layer_objects = false;
    # The cache's folder of the last layer's objects, when it has them
    # (`_store_last`).
    var last_folder = Optional<Path>.Empty;
    if (layered.count > 1) {
        var prechecked = HashMap<ulong, (u8[], String, String)>();
        var jobs = _layer_jobs(options);
        if (jobs > 1 and layered.count > 2 and !options.in_process and !options.worker_args.is_empty) {
            var parallel = _check_in_workers(program, layered, options, jobs, prechecked);
            if (parallel.is_err()) {
                return Result<Built, String>.err(parallel.error());
            }
            clock.lap("layers in workers");
            layer_objects = true;
        } else {
            _stop_early_worker(options);
        }
        var checked = _check_layers(
            program,
            layered,
            options.cache.value(),
            reused,
            sources,
            warnings,
            clock,
            options.trace_cache,
            options.verify_cutoff,
            prechecked,
            layer_objects ? triple_extension : "",
            options.pass_times
        );
        if (checked.is_err()) {
            report_warnings(warnings, sources);
            return Result<Built, String>.err(checked.error());
        }
        module = checked.value().module;
        state = checked.value().state;
        last_folder = checked.value().last;
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
    if (reused.is_value() and !layer_objects) {
        reuse_after_sema(
            reused.value(),
            program,
            units,
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
    if (layer_objects) {
        var last = layered[layered.count - 1];
        if (last_folder.is_value()) {
            # The cache has the last layer's objects: its warnings and
            # `[Link]` arguments are kept beside them.
            var warned = File.read_to_string(last_folder.value().join(Path("warn")));
            if (warned.is_ok() and !warned.value().is_empty) {
                File.stderr().write_all(warned.value());
            }
            var links = File.read_to_string(last_folder.value().join(Path("link")));
            link_text = links.is_ok() ? links.value() : "";
            options.cache.value().used(last_folder.value());
        } else {
            # The layer workers compiled every layer but the last: only the
            # last layer's files and the entry points are generated here,
            # and what the layers below defined is only declared.
            var own = HashSet<ulong>();
            for (var file in last.files) {
                own.insert(file);
            }
            var others = HashSet<uint>();
            var part_of_file = Array<uint>();
            for (var i in 0..program.files.count) {
                if (!own.contains(i)) {
                    others.insert(i as uint);
                }
                part_of_file.append(own.contains(i) ? 0 : 2);
            }
            var lower = Array<ulong>();
            for (var k in 0..layered.count - 1) {
                lower.append(k);
            }
            var below = _defined_by(options.cache.value(), layered, lower, Optional<Path>.Empty);
            var generated = codegen.generate(
                module, state, namespaces, stem, setup, owners, others, Optional<HashSet<String>>.Value(below)
            );
            if (generated.is_err()) {
                return Result<Built, String>.err(render_all([generated.error()], sources));
            }
            clock.lap("codegen");
            var partition = codegen.prepare(generated.value(), owners, part_of_file, 1, 3);
            var folder = work.join(Path("last"));
            Directory.create_all(folder);
            var compiled = compile_parts(
                generated.value(),
                partition,
                [PartJob(0, folder.join(Path($"0.{extension}"))), PartJob(1, folder.join(Path($"entry.{extension}")))],
                machine.value(),
                cpu,
                options.opt_level,
                work,
                options.trace_time,
                options.in_process,
                true,
                lto
            );
            if (compiled.is_err()) {
                return Result<Built, String>.err($"{compiled.error()}\n  (kept {work})");
            }
            link_text = _link_attributes(module);
            var stored = _store_last(
                options.cache.value(), last, folder, link_text, _render_warnings(_warnings_in(warnings, last), sources)
            );
            if (stored.is_err()) {
                Directory.remove_all(work);
                return Result<Built, String>.err(stored.error());
            }
            last_folder = Optional<Path>.Value(stored.value());
        }
        for (var k in 0..layered.count - 1) {
            var folder = options.cache.value().objects($"layer {layered[k].name}", layered[k].key);
            options.cache.value().used(folder);
            objects.append(folder.join(Path($"0.{extension}")));
        }
        objects.append(last_folder.value().join(Path($"0.{extension}")));
        objects.append(last_folder.value().join(Path($"entry.{extension}")));
        clock.lap("objects");
    } else {
        # The bodies of units whose objects the cache holds are only declared.
        var cached_files = HashSet<uint>();
        if (reused.is_value()) {
            for (var u in 0..units.count) {
                if (reused.value().objects[u].count > 0) {
                    for (var file in units[u].files) {
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
        for (var unit in units) {
            var split = _split(program, unit, sizes, parts, options.part_size);
            var own = Array<uint>();
            for (var part in split) {
                if (!own.contains(part)) {
                    own.append(part);
                }
            }
            for (var i in 0..unit.files.count) {
                part_of_file[unit.files[i]] = split[i];
            }
            unit_parts.append(_unit_size(unit, sizes) == 0 ? Array<uint>() : own);
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
        for (var u in 0..units.count) {
            if (reused.is_value() and reused.value().objects[u].count > 0) {
                if (options.trace_cache) {
                    File.stderr().write_all($"cache: hit {units[u].name}\n");
                }
                objects.append_all(reused.value().objects[u]);
                report.hits.append(units[u].name);
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
            report.misses.append(units[u].name);
            # Each part's object from the cache when its key hits: its files and
            # what they read are as when it was compiled.
            var parts = Array<Path>();
            ulong hits = 0;
            for (var i in 0..own.count) {
                var files = Array<ulong>();
                for (var file in units[u].files) {
                    if (part_of_file[file] == own[i]) {
                        files.append(file);
                    }
                }
                var part_key = keys.value().part(program, units, u, files, reused.value().interfaces);
                var cached = options.cache.value().part(units[u].name, i, part_key);
                var object = cached.join(Path($"0.{extension}"));
                parts.append(object);
                if (object.is_file()) {
                    options.cache.value().used(cached);
                    report.part_hits.append($"{units[u].name}#{i}");
                    hits += 1;
                    continue;
                }
                var built = folder.join(Path($"{i}"));
                Directory.create_all(built);
                jobs.append(PartJob(own[i], built.join(Path($"0.{extension}"))));
                stored_parts.append((u, i, part_key));
            }
            if (options.trace_cache) {
                File.stderr().write_all($"cache: miss {units[u].name} ({own.count - hits} of {own.count} parts)\n");
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
        if (keys.is_value()) {
            for (var (u, i, part_key) in stored_parts) {
                var kept = options.cache.value().store(
                    work.join(Path($"{u}")).join(Path($"{i}")), $"{units[u].name}#{i}", part_key
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
                write_record(folder, reused.value(), module, program, units[u], warnings, parts, options.cache.value());
                var kept = options.cache.value().store(folder, units[u].name, key);
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
        var whole = work.join(Path($"{stem}.lto.{triple.contains("-windows") ? "obj" : "o"}"));
        var optimized = optimize_whole(objects, whole, machine.value(), options.opt_level);
        if (optimized.is_err()) {
            Directory.remove_all(work);
            return Result<Built, String>.err(optimized.error());
        }
        objects = [whole];
        clock.lap("link-time optimization");
    }

    # Search order: `-L`, then `[Link(path = ...)]`.
    if (!layer_objects) {
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
    # Windows debuggers read the runtime's visualizers from the `.pdb`.
    var natvis = Optional<Path>.Empty;
    if (options.debug and program.target.os == "windows" and runtime.is_value()) {
        var found = runtime.value().join(Path("debuggers")).join(Path("pepper.natvis"));
        if (found.is_file()) {
            natvis = Optional<Path>.Value(found);
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

## The largest part a unit is compiled in, in `codegen.file_sizes`'s
## measure (blocks and definitions): a larger unit is split into parts of
## about this size, so one large unit does not keep the build waiting on
## one process. The split depends only on the unit's own code, so its
## objects stay the same from one program to the next.
const _PART_SIZE = 20000;

## The part of each of `unit`'s files: as many parts as the unit's size
## needs (`part_size`), no more than its files, each a run of the unit's
## files in namespace order, a file in the part its middle falls in. Each
## part's object is cached under its files (`Keys.part`), so the split
## must stay as it is when an edit changes a file's size: a run moves
## only the files at its ends, and only when the edit is large, where
## filling the least loaded part first moved files all over the unit. The
## parts are numbered from `first`, with no gaps.
_split(program: link.Program, unit: link.Unit, sizes: ulong[], first: uint, part_size: ulong): uint[] {
    var total = _unit_size(unit, sizes);
    var count = (total + part_size - 1) / part_size;
    if (count > unit.files.count) {
        count = unit.files.count;
    }
    if (count < 1) {
        count = 1;
    }
    var order = Array<ulong>();
    for (var i in 0..unit.files.count) {
        order.append(i);
    }
    order.sort((a, b) => {
        var x = program.files[unit.files[a]].namespace;
        var y = program.files[unit.files[b]].namespace;
        return x < y ? -1 : (x > y ? 1 : 0);
    });
    var split = Array<uint>();
    for (var _ in unit.files) {
        split.append(0);
    }
    ulong before = 0;
    for (var i in order) {
        var size = sizes[unit.files[i]];
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

## How much code `unit`'s files own.
_unit_size(unit: link.Unit, sizes: ulong[]): ulong {
    ulong total = 0;
    for (var file in unit.files) {
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

## Prints how long each stage of a build took (`-T time`).
struct _Clock {
    var on: bool;
    var start: os.Instant;

    construct(on: bool) {
        this.on = on;
        start = os.Instant.now();
    }

    ## Prints how long `stage` took, since the last stage ended.
    lap(stage: String) {
        if (!on) {
            return;
        }
        var now = os.Instant.now();
        File.stderr().write_all($"time: {stage} {(now - start).milliseconds()} ms\n");
        start = now;
    }
}
