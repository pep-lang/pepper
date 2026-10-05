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
import "linker";

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

## Builds `program` into an executable: merge, the sema passes, code
## generation for the host, LLVM's standard pipeline at the `-O` level, an
## object file, then the link. Warnings print on standard error whether or
## not the build succeeds.
##
## @param program the loaded and linked program
## @param options where the output goes, and how it is built
## @returns nothing, or the error, rendered
export build(program: link.Program, options: BuildOptions): Result<void, String> {
    var sources = program.sources();
    var warnings = program.warnings();
    var built = sema.merge(program);
    if (built.is_err()) {
        report_warnings(warnings, sources);
        return Result<void, String>.err(built.error());
    }
    var module = built.value();
    var state = sema.PassState(program.target);
    state.sources = sources;
    var ran = sema.run_steps_with(module, state, 0xffffffffffffffff);
    for (var note in state.notes) {
        warnings.append(note);
    }
    report_warnings(warnings, sources);
    if (ran.is_err()) {
        return Result<void, String>.err(render_all([ran.error()], sources));
    }

    var triple = llvm.default_triple();
    var cpu = codegen.Cpu.default_for(triple);
    var level = [llvm.OptLevel.O0, llvm.OptLevel.O1, llvm.OptLevel.O2, llvm.OptLevel.O3][options.opt_level];
    var machine = llvm.TargetMachine.create(triple, cpu.name, cpu.features, level);
    if (machine.is_err()) {
        return Result<void, String>.err(machine.error().message);
    }
    var setup = codegen.Build(machine.value(), cpu);
    setup.opt_level = options.opt_level;
    var namespaces = Array<String>();
    for (var f in program.files) {
        namespaces.append(f.namespace);
    }
    var name = options.output.file_stem();
    var generated = codegen.generate(module, state, namespaces, name.is_value() ? name.value() : "main", setup);
    if (generated.is_err()) {
        return Result<void, String>.err(render_all([generated.error()], sources));
    }
    var ir = generated.value();
    if (options.opt_level > 0) {
        var optimized = ir.run_passes($"default<O{options.opt_level}>", machine.value());
        if (optimized.is_err()) {
            return Result<void, String>.err($"cannot optimize: {optimized.error().message}");
        }
    }
    if (!triple.contains("-windows") and !triple.contains("-apple-") and !triple.starts_with("wasm")) {
        use_init_array(ir, ir.context);
    }

    var created = Directory.create_all(options.build_dir);
    if (created.is_err()) {
        return Result<void, String>.err($"cannot create build dir: {created.error().message}");
    }
    var extension = triple.contains("-windows") ? "obj" : "o";
    var stem = name.is_value() ? name.value() : "main";
    var object = options.build_dir.join(Path($"{stem}.{extension}"));
    var emitted = machine.value().emit_to_file(ir, object.to_string());
    if (emitted.is_err()) {
        return Result<void, String>.err($"cannot write {object}: {emitted.error().message}");
    }

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
    return link_objects([object], options.output, libraries, dirs);
}
