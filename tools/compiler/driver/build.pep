## Building a program: the checked model to an object file, linked into an
## executable, as `crates/pepper-driver/src/lib.rs` does for one unit.

import compiler.ast;
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
import "layers";
import "linker";
import "parts";

## What `build` makes.
export struct BuildOptions {
    ## The executable to write.
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
    var libraries = Array<String>();
    var dirs = Array<Path>();
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
                if (key == "lib" and !libraries.contains(value)) {
                    libraries.append(value);
                } else if (key == "path") {
                    var file = Path(program.files[ext.loc.file].name);
                    var folder = file.parent();
                    var dir = folder.is_value() ? folder.value().join(Path(value)) : Path(value);
                    var cwd = process.working_directory();
                    if (dir.is_relative() and cwd.is_ok()) {
                        dir = cwd.value().join(dir);
                    }
                    if (!dirs.contains(dir)) {
                        dirs.append(dir);
                    }
                }
            }
        }
    }
    return (libraries, dirs);
}

## Puts `ir`'s static constructors where the target runs them: in
## `.init_array` on ELF (see `use_init_array`).
##
## @param ir the optimized module
## @param triple the target triple
export place_constructors(ir: llvm.Module, triple: String) {
    if (!triple.contains("-windows") and !triple.contains("-apple-") and !triple.starts_with("wasm")) {
        use_init_array(ir, ir.context);
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

    construct() {}
}

## Whether `PEPC_NO_LAYERS` turns checked layers off, for comparing
## builds with and without them.
_layers_off(): bool {
    var named = os.environment("PEPC_NO_LAYERS");
    return named.is_value() and !named.value().is_empty;
}

## Checks `program` layer by layer (`layers.pep`): from the record of the
## longest run of unchanged layers in the cache, each layer after it on top
## of the ones before, storing each but the last as a record. A layer whose
## check warned is not stored, so the next build warns again.
##
## @returns the checked module and the state of the last layer's passes,
##   or the error, rendered
_check_layers(
    program: link.Program,
    layered: Layer[],
    cache: Cache,
    reused: Reused?,
    sources: SourceText[],
    warnings: Diagnostic[],
    clock: _Clock,
    trace: bool
): Result<(sema.Module, sema.PassState), String> {
    var errors = program.check();
    if (errors.is_value()) {
        return Result<(sema.Module, sema.PassState), String>.err(errors.value());
    }
    ulong first = 0;
    var module = sema.Module();
    var loaded = load_checked(cache, program, layered);
    if (loaded.is_value()) {
        var (covered, unit) = loaded.value();
        first = covered;
        module = sema.resume_checked(unit);
    }
    clock.lap($"load {first} layers");
    if (trace) {
        File.stderr().write_all($"cache: {first} of {layered.count} layers checked already\n");
    }
    var state = sema.PassState(program.target);
    for (var k in first..layered.count) {
        # The specializations the checked layers asked for met their
        # constraints when they were checked.
        var checked_specs = (module.struct_specs.count, module.func_specs.count);
        var built = sema.build_on(program, module, layered[k].files);
        if (built.is_err()) {
            return Result<(sema.Module, sema.PassState), String>.err(render_all([built.error()], sources));
        }
        module = built.value();
        var aliases = Array<sema.TypeAliasDef>();
        for (var alias in module.type_aliases) {
            aliases.append(alias.copy());
        }
        # Summaries for the build cache's skipped bodies; a layer records
        # the ones it makes either way (`settled_summaries`).
        module.record_summaries = reused.is_value();
        if (reused.is_value()) {
            module.cached_files = reused.value().files;
            for (var (loc, text) in reused.value().summaries) {
                module.recorded_summaries[loc] = text;
            }
        }
        state = sema.PassState(program.target);
        state.sources = sources;
        state.checked_specs = checked_specs;
        # No lazy methods: a later layer may use a method this one would
        # drop from a specialization it made.
        var ran = sema.run_steps_with(module, state, 0xffffffffffffffff);
        for (var note in state.notes) {
            warnings.append(note);
        }
        if (ran.is_err()) {
            return Result<(sema.Module, sema.PassState), String>.err(render_all([ran.error()], sources));
        }
        clock.lap($"layer {layered[k].name}");
        if (k + 1 == layered.count) {
            break;
        }
        var unit = sema.finish_checked(module, state, aliases);
        if (state.notes.is_empty) {
            store_checked(cache, program, layered[k], unit);
            clock.lap("store");
        }
        module = sema.resume_checked(unit);
    }
    return Result<(sema.Module, sema.PassState), String>.ok((module, state));
}

## Builds `program` into an executable: merge, the sema passes, code
## generation for the host, LLVM's standard pipeline at the `-O` level, one
## object per compilation unit (from the build cache when its key hits),
## then the link. When the cache records that the output is this very
## program, unchanged since, nothing is built. Warnings print on standard
## error whether or not the build succeeds.
##
## @param program the loaded and linked program
## @param options where the output goes, and how it is built
## @returns what the build did, or the error, rendered
export build(program: link.Program, options: BuildOptions): Result<Built, String> {
    var report = Built();
    var clock = _Clock(options.trace_time);
    var triple = llvm.default_triple();
    var cpu = codegen.Cpu.default_for(triple);
    var units = link.units(program);
    var keys = Optional<Keys>.Empty;
    String program_key = "";
    if (options.cache.is_value()) {
        keys = Optional<Keys>.Value(Keys(program, units, $"{triple} {cpu.name} {cpu.features} -O{options.opt_level}"));
        program_key = keys.value().program(program, _link_text(options));
        if (options.cache.value().is_built(options.output, program_key)) {
            if (options.trace_cache) {
                File.stderr().write_all($"cache: {options.output} is up to date\n");
            }
            clock.lap("unchanged");
            report.unchanged = true;
            return Result<Built, String>.ok(report);
        }
        clock.lap("keys");
    }

    var triple_extension = triple.contains("-windows") ? "obj" : "o";
    # The units whose objects the cache has: sema skips their bodies.
    var reused = Optional<Reused>.Empty;
    if (keys.is_value()) {
        reused = Optional<Reused>.Value(reuse(program, units, keys.value(), options.cache.value(), triple_extension));
        clock.lap("reuse");
    }

    var sources = program.sources();
    var warnings = program.warnings();
    var layered = Array<Layer>();
    if (options.cache.is_value() and !_layers_off()) {
        layered = layers(program, units, keys.value().base());
    }
    var module = sema.Module();
    var state = sema.PassState(program.target);
    if (layered.count > 1) {
        var checked = _check_layers(
            program, layered, options.cache.value(), reused, sources, warnings, clock, options.trace_cache
        );
        if (checked.is_err()) {
            report_warnings(warnings, sources);
            return Result<Built, String>.err(checked.error());
        }
        var (checked_module, checked_state) = checked.value();
        module = checked_module;
        state = checked_state;
        report_warnings(warnings, sources);
    } else {
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
        var ran = sema.run_steps_with(module, state, 0xffffffffffffffff);
        for (var note in state.notes) {
            warnings.append(note);
        }
        report_warnings(warnings, sources);
        if (ran.is_err()) {
            return Result<Built, String>.err(render_all([ran.error()], sources));
        }
    }
    clock.lap("sema");
    if (reused.is_value()) {
        reuse_after_sema(reused.value(), program, units, keys.value(), options.cache.value(), triple_extension, module);
        clock.lap("interfaces");
    }

    var level = [llvm.OptLevel.O0, llvm.OptLevel.O1, llvm.OptLevel.O2, llvm.OptLevel.O3][options.opt_level];
    var machine = llvm.TargetMachine.create(triple, cpu.name, cpu.features, level);
    if (machine.is_err()) {
        return Result<Built, String>.err(machine.error().message);
    }
    var setup = codegen.Build(machine.value(), cpu);
    setup.opt_level = options.opt_level;
    var namespaces = Array<String>();
    for (var f in program.files) {
        namespaces.append(f.namespace);
    }
    var name = options.output.file_stem();
    var owners = HashMap<String, uint>();
    var stem = name.is_value() ? name.value() : "main";
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
        var split = _split(unit, sizes, parts);
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
    # A folder of this build's own, so builds running at once do not meet.
    var work = options.build_dir.join(Path($"{stem}.{process.id()}"));
    var created = Directory.create_all(work);
    if (created.is_err()) {
        return Result<Built, String>.err($"cannot create {work}: {created.error().message}");
    }
    var extension = triple_extension;
    var objects = Array<Path>();
    var jobs = Array<PartJob>();
    # The units compiled, with their keys, to store in the cache.
    var stored = Array<(ulong, String)>();
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
        if (reused.is_value()) {
            var key = reused.value().keys[u].value();
            if (options.trace_cache) {
                File.stderr().write_all($"cache: miss {units[u].name} ({own.count} parts)\n");
            }
            stored.append((u, key));
            report.misses.append(units[u].name);
        }
        Directory.create_all(folder);
        if (reused.is_value()) {
            write_record(folder, reused.value(), module, program, units[u], warnings);
        }
        for (var i in 0..own.count) {
            jobs.append(PartJob(own[i], folder.join(Path($"{i}.{extension}"))));
        }
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
        !cached_files.is_empty
    );
    if (compiled.is_err()) {
        # The bitcode and plan stay, so the failed part can be run again.
        return Result<Built, String>.err($"{compiled.error()}\n  (kept {work})");
    }
    if (keys.is_value()) {
        for (var (u, key) in stored) {
            var kept = options.cache.value().store(work.join(Path($"{u}")), units[u].name, key);
            if (kept.is_err()) {
                Directory.remove_all(work);
                return Result<Built, String>.err(kept.error());
            }
            for (var i in 0..unit_parts[u].count) {
                objects.append(kept.value().join(Path($"{i}.{extension}")));
            }
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

    # Search order: `-L`, then `[Link(path = ...)]`.
    var (linked, linked_dirs) = link_inputs(module, program);
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
    var made = link_objects(objects, options.output, libraries, dirs);
    Directory.remove_all(work);
    if (made.is_err()) {
        return Result<Built, String>.err(made.error());
    }
    clock.lap("link");
    if (options.cache.is_value()) {
        options.cache.value().record(options.output, program_key, !warnings.is_empty);
    }
    return Result<Built, String>.ok(report);
}

## The largest part a unit is compiled in, in `codegen.file_sizes`'s
## measure (blocks and definitions): a larger unit is split into parts of
## about this size, so one large unit does not keep the build waiting on
## one process. The split depends only on the unit's own code, so its
## objects stay the same from one program to the next.
const _PART_SIZE = 20000;

## The part of each of `unit`'s files: as many parts as the unit's size
## needs (`_PART_SIZE`), no more than its files, each file (largest first)
## to the part with the least code so far; the parts are numbered from
## `first`, with no gaps.
_split(unit: link.Unit, sizes: ulong[], first: uint): uint[] {
    var total = _unit_size(unit, sizes);
    var count = (total + (_PART_SIZE as ulong) - 1) / (_PART_SIZE as ulong);
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
        var x = sizes[unit.files[a]];
        var y = sizes[unit.files[b]];
        return x != y ? (x > y ? -1 : 1) : (a < b ? -1 : (a > b ? 1 : 0));
    });
    var loads = Array<ulong>();
    for (var _ in 0..count) {
        loads.append(0);
    }
    var split = Array<uint>();
    for (var _ in unit.files) {
        split.append(0);
    }
    for (var i in order) {
        ulong least = 0;
        for (var part in 1..loads.count) {
            if (loads[part] < loads[least]) {
                least = part;
            }
        }
        split[i] = least as uint;
        loads[least] += sizes[unit.files[i]];
    }
    # Numbered in the order the parts first appear, from `first`, so a
    # part no file went to takes no number.
    var number = HashMap<uint, uint>();
    for (var i in 0..split.count) {
        if (!number.contains(split[i])) {
            number[split[i]] = first + number.count as uint;
        }
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
## output, the `-l` libraries, the `-L` folders, and the current folder
## (`[Link(path = ...)]` folders are relative to it).
_link_text(options: BuildOptions): String {
    var cwd = process.working_directory();
    var here = cwd.is_ok() ? cwd.value().to_string() : "";
    var text = StringBuilder();
    text.append($"output {options.output}\ncwd {here}\n");
    for (var library in options.libraries) {
        text.append($"-l {library}\n");
    }
    for (var dir in options.library_dirs) {
        text.append($"-L {dir}\n");
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
