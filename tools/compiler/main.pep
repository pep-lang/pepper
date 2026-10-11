# pepc: the Pepper compiler written in Pepper (#225), built and shipped as
# `pep-build`: the same command line, `pep-build --help` for the options.
# `pep-build --help` lists every option, with its meaning. `--target`
# compiles for another platform, `--sysroot` names its system libraries for
# the link, and `-march`, `-mcpu`, `-mtune`, `-m<feature>` choose the CPU
# (`codegen.Cpu.from_options`). `-g` emits debug info (`codegen/debug.pep`),
# and `--debug-static` picks where the debugger shows a `static` block's
# code.
#
# With no `--emit-*` option it builds the program into an executable: `-o
# out`, else the file's stem in the current directory, or the project of
# the current directory with no file. `--lib static|shared` builds a
# library for C instead, with the header of its `[Export]`ed functions
# beside it (`driver/library.pep`), and `--lto=full` (the default at `-O2`
# and `-O3`) optimizes the program as one module before the link
# (`driver/lto.pep`). `--test` builds the test program of the file (or of
# several files of one folder) instead (`driver/test_main.pep`). A build
# keeps each unit's object in the build cache (`driver/cache.pep`): `--cache
# dir`, else `$PEPPER_CACHE_DIR`, else `.pep/cache`; `--no-cache` compiles
# everything, and `--verify-cache` builds again with an empty cache and
# compares the objects (`driver/verify.pep`). `-T time` prints how long
# each stage took, `-T passes` each sema pass, `-T cache` whether each
# unit's object came from the cache, `--Tall` all three.
#
# `--emit-ast[=text|json]`, `--emit-linked`, `--emit-checked`,
# `--emit-model [--emit-model-step N]` and `--emit-steps` print the file's
# syntax tree (`ast/text.pep`), the program after linking, what the checks
# after linking report, the sema model, or the names of the sema steps,
# instead; `--emit-llvm` writes the program's LLVM IR, optimized at the
# `-O` level, to `<build>/<name>.ll`, and `--emit-static` the program's
# source with its `static` blocks expanded (`driver/emit_static.pep`).

import compiler.ast;
import compiler.codegen;
import [render_all] from compiler.diagnostic;
import compiler.driver;
import compiler.incremental;
import io;
import [Directory, File, Path] from io;
import compiler.link;
import os;
import compiler.parse;
import process;
import compiler.sema;

main(args: String[]): int {
    # Parts of a build this compiler split (`driver/parts.pep`): a folder,
    # then each part's number and object.
    if (args.count >= 5 and args.count % 2 == 1 and args[1] == "--compile-part") {
        var jobs = Array<driver.PartJob>();
        for (var at in 0..((args.count - 3) / 2)) {
            var number = args[3 + 2 * at];
            var part = uint.parse(number);
            if (!part.is_value()) {
                File.stderr().write_all($"pepc: --compile-part needs a part number, not '{number}'\n");
                return 1;
            }
            jobs.append(driver.PartJob(part.value(), Path(args[4 + 2 * at])));
        }
        var compiled = driver.compile_part(Path(args[2]), jobs);
        if (compiled.is_err()) {
            File.stderr().write_all($"pepc: {compiled.error()}\n");
            return 1;
        }
        return 0;
    }
    String? path;
    bool linked = false;
    bool checked = false;
    bool model = false;
    bool steps = false;
    bool ast_json = false;
    bool verify_cache = false;
    bool no_verify_cache = false;
    bool msvc = false;
    bool ir = false;
    bool emit_ast = false;
    bool test = false;
    var paths = Array<String>();
    uint? opt_level;
    String? output;
    var libraries = Array<String>();
    var library_dirs = Array<Path>();
    var step = Optional<ulong>.Empty;
    bool no_cache = false;
    String? cache_dir;
    var traces = Array<String>();
    var setup = link.Setup();
    String? build_dir;
    bool frame_pointers = false;
    String? without_checks;
    String? triple;
    String? sysroot;
    # `--compilation-unit-worker dir`, which `driver.build` adds when it checks
    # compilation units in child processes: check the compilation units it is
    # given (`driver.compilation_unit_worker`).
    String? compilation_unit_worker;
    String? library;
    String? lto;
    # What follows each `-m` (`arch=x86-64-v3`, `avx2`), in order.
    var machine = Array<String>();
    bool debug = false;
    String? debug_static;
    String? emit_static;
    # Options are matched as `pep-build` matches them: a value after a
    # space or `=` (`--cache dir`, `--cache=dir`), or attached to a short
    # option (`-Idir`); after `--`, every argument is a file.
    bool files_only = false;
    ulong i = 1;
    while (i < args.count) {
        var arg = args[i];
        i += 1;
        if (files_only or arg == "-" or !arg.starts_with("-")) {
            if (!path.is_value()) {
                path = Optional<String>.Value(arg);
            }
            paths.append(arg);
            continue;
        }
        if (arg == "--") {
            files_only = true;
            continue;
        }
        # `--name=value` is `--name value`.
        String? attached;
        var name = arg;
        if (arg.starts_with("--")) {
            var parts = arg.split_once("=");
            if (parts.is_value()) {
                var (before, after) = parts.value();
                name = before;
                attached = Optional<String>.Value(after);
            }
        } else if (arg.size > 2 and !arg.starts_with("-O") and !arg.starts_with("-m")) {
            name = arg.substr_bytes(0, 2);
            attached = Optional<String>.Value(arg.substr_bytes(2, arg.size - 2));
        }
        # `-march=x86-64-v3`, `-mavx2`, or `-m avx2`.
        if (arg.starts_with("-m") and arg.size > 2) {
            name = "-m";
            attached = Optional<String>.Value(arg.substr_bytes(2, arg.size - 2));
        }
        if (_value_name(name).is_value() and !attached.is_value()) {
            if (i >= args.count) {
                return _usage_error(
                    $"a value is required for '{name} <{_value_name(name).value()}>' but none was supplied"
                );
            }
            attached = Optional<String>.Value(args[i]);
            i += 1;
        }
        var value = attached.is_value() ? attached.value() : "";
        if (name == "-h" or name == "--help") {
            File.stdout().write_all(_HELP);
            return 0;
        } else if (name == "-V" or name == "--version") {
            File.stdout().write_all($"pep-build {version()}\n");
            return 0;
        } else if (name == "-v" or name == "--verbose") {
            # Accepted for compatibility, as by pep-build.
        } else if (name == "--compilation-unit-worker" or name == "--layer-worker") {
            # `--layer-worker` is the deprecated spelling.
            compilation_unit_worker = Optional<String>.Value(value);
        } else if (name == "--emit-linked") {
            linked = true;
        } else if (name == "--emit-checked") {
            checked = true;
        } else if (name == "--emit-model") {
            model = true;
        } else if (name == "--emit-steps") {
            steps = true;
        } else if (name == "--verify-cache") {
            verify_cache = true;
        } else if (name == "--no-verify-cache") {
            no_verify_cache = true;
        } else if (name == "--MSVC") {
            msvc = true;
        } else if (name == "--emit-llvm") {
            ir = true;
        } else if (name == "--test") {
            test = true;
        } else if (name == "--emit-ast") {
            # `--emit-ast` alone is `--emit-ast=text`.
            var format = attached.is_value() ? value : "text";
            if (format != "text" and format != "json") {
                return _usage_error(
                    $"invalid value '{format}' for '--emit-ast[=<FORMAT>]'\n  [possible values: text, json]"
                );
            }
            emit_ast = true;
            ast_json = format == "json";
        } else if (name.starts_with("-O")) {
            # `-O` alone is `-O2`; `-O2`, or `-O 2`.
            var level = name.substr_bytes(2, name.size - 2);
            if (level.is_empty and i < args.count and args[i].size == 1 and uint.parse(args[i]).is_value()) {
                level = args[i];
                i += 1;
            }
            var parsed = level.is_empty ? Optional<uint>.Value(2) : uint.parse(level);
            if (!parsed.is_value() or parsed.value() > 3) {
                return _usage_error($"invalid value '{level}' for '-O <LEVEL>': expected 0, 1, 2 or 3");
            }
            opt_level = parsed;
        } else if (name == "-o") {
            output = Optional<String>.Value(value);
        } else if (name == "-l") {
            libraries.append(value);
        } else if (name == "-L") {
            library_dirs.append(Path(value));
        } else if (name == "-I") {
            setup.import_dirs.append(Path(value));
        } else if (name == "--import") {
            setup.forced_imports.append(value);
        } else if (name == "-D") {
            var option = value.split_once("=");
            if (option.is_value()) {
                var (defined_name, defined) = option.value();
                setup.target.build_options[defined_name] = defined;
            } else {
                setup.target.build_options[value] = "1";
            }
        } else if (name == "--build") {
            build_dir = Optional<String>.Value(value);
        } else if (name == "--emit-model-step") {
            var parsed = ulong.parse(value);
            if (!parsed.is_value()) {
                return _usage_error($"invalid value '{value}' for '--emit-model-step <N>': expected a number");
            }
            step = Optional<ulong>.Value(parsed.value());
        } else if (name == "--no-runtime") {
            setup.runtime = false;
        } else if (name == "--no-cache") {
            no_cache = true;
        } else if (name == "--cache") {
            cache_dir = Optional<String>.Value(value);
        } else if (name == "-T") {
            traces.append(value);
        } else if (name == "--Tall") {
            traces.append_all(TRACE_CHANNELS.split(" "));
        } else if (name == "--frame-pointers") {
            frame_pointers = true;
        } else if (name == "--no-runtime-checks") {
            without_checks = Optional<String>.Value(value);
        } else if (name == "--target") {
            triple = Optional<String>.Value(value);
        } else if (name == "--sysroot") {
            sysroot = Optional<String>.Value(value);
        } else if (name == "--lib") {
            if (value != "static" and value != "shared") {
                return _usage_error($"invalid value '{value}' for '--lib <KIND>': expected static or shared");
            }
            library = Optional<String>.Value(value);
        } else if (name == "--lto") {
            if (value != "full" and value != "off") {
                return _usage_error($"invalid value '{value}' for '--lto <MODE>': expected full or off");
            }
            lto = Optional<String>.Value(value);
        } else if (name == "-m") {
            machine.append(value);
        } else if (name == "-g" or name == "--emit-debug") {
            debug = true;
        } else if (name == "--emit-static") {
            var mode = attached.is_value() ? value : "expand";
            if (mode != "expand" and mode != "keep") {
                return _usage_error(
                    $"invalid value '{mode}' for '--emit-static[=<MODE>]'\n  [possible values: expand, keep]"
                );
            }
            emit_static = Optional<String>.Value(mode);
        } else if (name == "--debug-static") {
            if (value != "source" and value != "expanded") {
                return _usage_error(
                    $"invalid value '{value}' for '--debug-static <VIEW>'\n  [possible values: source, expanded]"
                );
            }
            debug_static = Optional<String>.Value(value);
        } else {
            return _usage_error($"unexpected argument '{arg}' found");
        }
    }
    if (debug_static.is_value() and !debug) {
        return _usage_error("the following required arguments were not provided:\n  --emit-debug");
    }
    if (!path.is_value() and (emit_ast or linked or checked or model or steps or ir or emit_static.is_value())) {
        return _usage_error("the --emit options need the program's entry file");
    }
    if (test and library.is_value()) {
        return _usage_error("the argument '--test' cannot be used with '--lib <KIND>'");
    }
    if (verify_cache and no_verify_cache) {
        return _usage_error("the argument '--verify-cache' cannot be used with '--no-verify-cache'");
    }
    # The platform to compile for, with the build options `-D` defined.
    if (triple.is_value()) {
        var target = link.Target.parse(triple.value());
        if (target.is_err()) {
            _report(target.error());
            return 1;
        }
        var parsed = target.value();
        parsed.build_options = setup.target.build_options;
        setup.target = parsed;
    }
    # Without `-O`, `PEPPER_OPT_LEVEL` picks the level, as in pep-build, so a
    # whole test suite can run optimized.
    if (!opt_level.is_value()) {
        var level = _env_opt_level();
        if (level.is_err()) {
            File.stderr().write_all($"pepc: {level.error()}\n");
            return 2;
        }
        opt_level = Optional<uint>.Value(level.value());
    }
    # The runtime checks the code keeps: every one at `-O0`, else all but
    # those `--no-runtime-checks` removes.
    var runtime_checks = codegen.RuntimeChecks.all();
    if (without_checks.is_value()) {
        var kept = codegen.RuntimeChecks.without(without_checks.value());
        if (!kept.is_value()) {
            return _usage_error(
                $"invalid value '{without_checks.value()}' for '--no-runtime-checks <CHECKS>': expected overflow, divide, shift, bounds, null or all"
            );
        }
        if (opt_level.value() > 0) {
            runtime_checks = kept.value();
        }
    }
    # The CPU the `-m` options choose for the target, else clang's default.
    var cpu = codegen.Cpu.from_options(codegen.target_triple(setup.target), machine);
    if (cpu.is_err()) {
        _report(cpu.error());
        return 1;
    }
    # Link-time optimization: `full` by default at `-O2` and `-O3`.
    bool whole = opt_level.value() >= 2;
    if (lto.is_value()) {
        if (lto.value() == "full" and opt_level.value() == 0) {
            _report("'--lto=full' needs optimization: add '-O'");
            return 1;
        }
        whole = lto.value() == "full";
    }
    # In a project, the build takes what its `pep.toml` gives: with no file,
    # the entry and output; and `[build]`'s libraries.
    var project = driver.apply_project(
        path.is_value() ? Optional<Path>.Value(Path(path.value())) : Optional<Path>.Empty, setup.target
    );
    if (project.is_err()) {
        _report(project.error());
        return 1;
    }
    var entry = project.value().entry;
    if (test) {
        # A test build keeps the `[Test]` functions, loads `testing` into
        # every file, and adds the `main` that runs them.
        setup.target.build_options[link.TEST_BUILD_OPTION] = "1";
        if (!setup.forced_imports.contains(driver.TESTING_MODULE)) {
            setup.forced_imports.append(driver.TESTING_MODULE);
        }
        if (paths.count > 1) {
            var files = Array<Path>();
            for (var p in paths) {
                files.append(Path(p));
            }
            var made = driver.test_program(files);
            if (made.is_err()) {
                _report(made.error());
                return 1;
            }
            var (generated, sources) = made.value();
            entry = generated;
            setup.sources = sources;
        } else {
            var read = File.read_to_string(entry);
            if (read.is_err()) {
                File.stderr().write_all($"cannot read {entry}: {read.error().message}\n");
                return 1;
            }
            setup.sources[link.path_key(entry)] = driver.add_test_main(entry, read.value());
        }
    }
    # Where a build writes: `-o`, else named for the entry file or the
    # project, and its intermediate files (`--build`).
    var cwd = process.working_directory();
    var here = cwd.is_ok() ? cwd.value() : Path(".");
    var stem = entry.file_stem();
    var work = project.value().dir.is_value() ? project.value().dir.value() : here;
    var kind = Optional<driver.LibraryKind>.Empty;
    if (library.is_value()) {
        kind = Optional<driver.LibraryKind>.Value(
            library.value() == "static" ? driver.LibraryKind.Static : driver.LibraryKind.Shared
        );
    }
    var out = here.join(Path(stem.is_value() ? stem.value() : "main"));
    if (output.is_value()) {
        out = Path(output.value());
    } else if (kind.is_value()) {
        # A library is named for the package, else the entry file,
        # as the target names libraries (`libmain.a`).
        var named = project.value().name.is_empty ? (stem.is_value() ? stem.value() : "main") : project.value().name;
        out = work.join(Path(driver.library_file_name(kind.value(), named, setup.target)));
    } else if (project.value().output.is_value()) {
        out = project.value().output.value();
    }
    var build_folder = build_dir.is_value() ? Path(build_dir.value()) : work.join(Path(".pep")).join(Path("build"));
    if (!emit_ast) {
        if (!(linked or checked or model or steps)) {
            # Debug builds keep every check.
            if (without_checks.is_value() and opt_level.value() == 0) {
                var kept = codegen.RuntimeChecks.without(without_checks.value()).value();
                if (!(kept.overflow and kept.divide and kept.shift and kept.bounds and kept.null)) {
                    File.stderr().write_all("warning: '--no-runtime-checks' has no effect at -O0\n");
                }
            }
            if (msvc) {
                _report("the MSVC linker path is not ported");
                return 1;
            }
        }
        if (!(linked or checked or model or steps or ir)) {
            # A project builds with what pep.lock lists: fetch what is missing.
            var fetched = driver.fetch_dependencies(entry);
            if (fetched.is_err()) {
                File.stderr().write_all(fetched.error() + "\n");
                return 1;
            }
        }
        # A build links the bodies of only the files it checks
        # (`driver.build`).
        setup.defer_bodies = !(ir or model or steps or linked or checked or emit_static.is_value());
        # A rebuild's first compilation unit worker loads the program while this
        # process does (`driver.start_compilation_unit_worker`).
        var early_worker = Optional<process.Child>.Empty;
        if (setup.defer_bodies and !compilation_unit_worker.is_value() and !no_cache and !debug) {
            var worker_args = Array<String>();
            for (var k in 1..args.count) {
                worker_args.append(args[k]);
            }
            early_worker = driver.start_compilation_unit_worker(worker_args, build_folder);
        }
        var program = link.load_program(entry, setup);
        if (program.is_err()) {
            _report(program.error());
            return 1;
        }
        if (emit_static.is_value()) {
            # The copies go into `-o`, else `<stem>.static`.
            var stem = entry.file_stem();
            var out_dir = Path(
                output.is_value() ? output.value() : $"{stem.is_value() ? stem.value() : "main"}.static"
            );
            var written = driver.emit_static(program.value(), entry, out_dir, emit_static.value() == "keep");
            if (written.is_err()) {
                _report(written.error());
                return 1;
            }
        } else if (ir) {
            # The whole program's IR, optimized at the `-O` level, in
            # `<build>/<name>.ll`.
            var built = sema.merge(program.value());
            if (built.is_err()) {
                File.stderr().write_all($"{built.error()}\n");
                return 1;
            }
            var state = sema.PassState(program.value().target);
            state.sources = program.value().sources();
            state.lazy_methods = true;
            if (traces.contains("passes")) {
                state.pass_times = Optional<sema.PassTimes>.Value(sema.PassTimes());
            }
            var ran = sema.run_steps_with(built.value(), state, 0xffffffffffffffff);
            if (ran.is_err()) {
                File.stderr().write_all(render_all([ran.error()], program.value().sources()) + "\n");
                return 1;
            }
            if (state.pass_times.is_value()) {
                File.stderr().write_all(state.pass_times.value().report());
            }
            var namespaces = Array<String>();
            for (var f in program.value().files) {
                namespaces.append(f.namespace);
            }
            var module_name = out.file_stem();
            var name = module_name.is_value() ? module_name.value() : "main";
            var generated = codegen.generate_ir(
                built.value(),
                state,
                namespaces,
                name,
                Optional<codegen.Cpu>.Value(cpu.value()),
                debug,
                opt_level.value(),
                frame_pointers,
                runtime_checks,
                debug ? driver.gdb_printers(program.value()) : ""
            );
            if (generated.is_err()) {
                File.stderr().write_all(render_all([generated.error()], program.value().sources()) + "\n");
                return 1;
            }
            Directory.create_all(build_folder);
            var ll = build_folder.join(Path($"{name}.ll"));
            var written = File.write_text(ll, generated.value());
            if (written.is_err()) {
                _report($"cannot write {ll}: {written.error().message}");
                return 1;
            }
        } else if (model or steps) {
            var built = sema.merge(program.value());
            if (built.is_err()) {
                File.stderr().write_all($"{built.error()}\n");
                return 1;
            }
            # `--emit-steps` runs every step, or the first `--emit-model-step`.
            if (steps or step.is_value()) {
                var state = sema.PassState(program.value().target);
                state.sources = program.value().sources();
                var limit = step.is_value() ? step.value() : 0xffffffffffffffff;
                var ran = sema.run_steps_with(built.value(), state, limit);
                if (ran.is_err()) {
                    File.stderr().write_all(render_all([ran.error()], program.value().sources()) + "\n");
                    return 1;
                }
                if (steps) {
                    print("\n".join(state.step_names));
                    return 0;
                }
            }
            print(sema.model_json(built.value()));
        } else if (linked) {
            print(program.value().to_json().to_string());
        } else if (checked) {
            print(program.value().check_report());
        } else {
            var options = driver.BuildOptions(out, build_folder);
            options.opt_level = opt_level.value();
            options.frame_pointers = frame_pointers;
            options.cpu = Optional<codegen.Cpu>.Value(cpu.value());
            options.lto = whole;
            options.library = kind;
            options.debug = debug;
            options.entry = Optional<Path>.Value(entry);
            options.debug_static_expanded = debug_static.is_value() and debug_static.value() == "expanded";
            options.runtime_checks = runtime_checks;
            if (traces.contains("passes")) {
                options.pass_times = Optional<sema.PassTimes>.Value(sema.PassTimes());
            }
            for (var library in project.value().libraries) {
                if (!libraries.contains(library)) {
                    libraries.append(library);
                }
            }
            options.libraries = libraries;
            options.library_dirs = library_dirs;
            options.sysroot = driver.effective_sysroot(
                setup.target, sysroot.is_value() ? Optional<Path>.Value(Path(sysroot.value())) : Optional<Path>.Empty
            );
            # A cached unit's sema is skipped, so its expansions would not be
            # written for `--debug-static=expanded`.
            if (!no_cache and !options.debug_static_expanded) {
                options.cache = Optional<incremental.Cache>.Value(
                    cache_dir.is_value() ? incremental.Cache(Path(cache_dir.value())) : incremental.default_cache(work)
                );
            }
            # `--verify-cache`, or `PEPPER_CACHE_VERIFY` set to anything but
            # empty or `0`, unless `--no-verify-cache`.
            var named_verify = os.environment("PEPPER_CACHE_VERIFY");
            bool verifying = verify_cache
                or (!no_verify_cache
                    and named_verify.is_value()
                    and !named_verify.value().is_empty
                    and named_verify.value() != "0");
            options.verify_cutoff = verifying;
            options.trace_time = traces.contains("time");
            options.trace_cache = traces.contains("cache");
            if (compilation_unit_worker.is_value()) {
                return driver.compilation_unit_worker(program.value(), options, Path(compilation_unit_worker.value()));
            }
            for (var k in 1..args.count) {
                options.worker_args.append(args[k]);
            }
            options.early_worker = early_worker;
            var made = driver.build(program.value(), options);
            if (made.is_err()) {
                # Empty: printed already (a syntax error read late).
                if (!made.error().is_empty) {
                    _report(made.error());
                }
                return 1;
            }
            if (verifying and options.cache.is_value()) {
                # The program again, as the build loaded it.
                var reloaded = link.load_program(entry, setup);
                if (reloaded.is_err()) {
                    _report(reloaded.error());
                    return 1;
                }
                var verified = driver.verify_cache(reloaded.value(), options);
                if (verified.is_err()) {
                    _report(verified.error());
                    return 1;
                }
            }
        }
        return 0;
    }
    var source = File.read_to_string(path.value());
    if (source.is_err()) {
        File.stderr().write_all($"error: cannot read '{path.value()}'\n");
        return 1;
    }
    var module = parse.parse(source.value());
    if (module.is_err()) {
        var error = module.error();
        File.stderr().write_all($"{path.value()}:{error.span.start}: error: {error.message}\n");
        return 1;
    }
    if (ast_json) {
        print(module.value().to_json().to_string());
    } else {
        # The text ends with a newline, which `print` adds.
        var text = ast.module_text(module.value());
        print(text.ends_with("\n") ? text.substr_bytes(0, text.size - 1) : text);
    }
    return 0;
}

## The level `PEPPER_OPT_LEVEL` names (`0` to `3`), or 0 when it is unset
## or empty.
_env_opt_level(): Result<uint, String> {
    var value = os.environment("PEPPER_OPT_LEVEL");
    if (!value.is_value() or value.value().is_empty) {
        return Result<uint, String>.ok(0);
    }
    var level = uint.parse(value.value());
    if (!level.is_value() or level.value() > 3) {
        return Result<uint, String>.err($"PEPPER_OPT_LEVEL is '{value.value()}'; expected 0, 1, 2 or 3");
    }
    return Result<uint, String>.ok(level.value());
}

## The release this compiler belongs to: `scripts/set-version.sh` sets it.
version(): String {
    return "0.4.0-dev";
}

# The name of the value an option takes, as its help shows it: none for an
# option that takes none.
_value_name(name: String): String? {
    match (name) {
        "-o" => {
            return Optional<String>.Value("OUT");
        }
        "-l" => {
            return Optional<String>.Value("LIB");
        }
        "-L", "-I", "--build", "--cache", "--sysroot", "--compilation-unit-worker", "--layer-worker" => {
            return Optional<String>.Value("DIR");
        }
        "--import" => {
            return Optional<String>.Value("NAME");
        }
        "-D" => {
            return Optional<String>.Value("NAME[=VALUE]");
        }
        "--emit-model-step" => {
            return Optional<String>.Value("N");
        }
        "-T" => {
            return Optional<String>.Value("CHAN");
        }
        "--no-runtime-checks" => {
            return Optional<String>.Value("CHECKS");
        }
        "--target" => {
            return Optional<String>.Value("TRIPLE");
        }
        "--lib" => {
            return Optional<String>.Value("KIND");
        }
        "--lto" => {
            return Optional<String>.Value("MODE");
        }
        "-m" => {
            return Optional<String>.Value("OPTION");
        }
        "--debug-static" => {
            return Optional<String>.Value("VIEW");
        }
        else => {
            return Optional<String>.Empty;
        }
    }
}

# Reports a command line `pep-build` cannot read, as it reports one; exits 2.
_usage_error(message: String): int {
    File.stderr().write_all(
        $"error: {message}\n\nUsage: pep-build [OPTIONS] [SOURCE_FILES]...\n\nFor more information, try '--help'.\n"
    );
    return 2;
}

# `--help`: the options this compiler has, as `pep-build --help` lists them.
## The channels `-T` names, which `--Tall` enables (`pep-doc check` reads
## them, for `docs/src/tools/pep-build.md`).
const TRACE_CHANNELS = "time passes cache";

const _HELP = "Pepper compiler\n\nUsage: pep-build [OPTIONS] [SOURCE_FILES]...\n\nArguments:\n  [SOURCE_FILES]...  The program's entry file. The files it imports are found on their own; only the first file named is compiled. With none, builds the project whose `pep.toml` is in the current directory or above it\n\nOptions:\n  -I <DIR>                          Add a directory to the import search path\n      --import <NAME>               Force an import by name\n  -l <LIB>                          Link against a library\n  -L <DIR>                          Add a directory to the linker's library search path. The folders in `$PEPPER_LIBRARY_PATH` (separated like `PATH`) are searched after these and `[Link(path = ...)]` folders\n  -D <NAME[=VALUE]>                 Define a build option: `-D NAME`, or `-D NAME=VALUE` with a value (a bare `NAME` is `NAME=1`, as in C). `[BuildOption(\"NAME\")]` and `BuildOption(NAME)` in `[Target(...)]` select code by it, and `static` blocks read it with `reflect.build_option`. Repeat for more options; of two that name one option, the later wins\n  -o <OUT>                          Output path: the executable, with `--lib` the library, or with `--emit-static` the folder for the expanded source\n      --lib <KIND>                  Build a library for C code to link instead of an executable: `static` (`libname.a`, `name.lib` on Windows) or `shared` (`libname.so`, `libname.dylib`, `name.dll`), with a C header beside it declaring the `[Export]`ed functions. No `main` is needed [possible values: static, shared]\n      --build <DIR>                 Build directory\n  -O <LEVEL>                        Optimization level: `-O0` (the default) through `-O3`; `-O` alone is `-O2`. Without it, `$PEPPER_OPT_LEVEL` when set\n      --lto <MODE>                  Link-time optimization: `full` optimizes the whole program as one module after linking every file's code, so calls between files (into the runtime, for one) inline; `off` optimizes each file alone. The default is `full` at `-O2` and `-O3`, and `off` below [possible values: full, off]\n      --target <TRIPLE>             The platform to compile for, as an LLVM target triple (`aarch64-apple-darwin`, `x86_64-pc-windows-msvc`, `x86_64-unknown-linux-gnu`). The default is the machine the compiler runs on. `[Target(...)]` selects code for it, and linking another platform's executable needs its system libraries (`--sysroot`)\n      --sysroot <DIR>               The directory holding the target's system headers and libraries, passed to the link driver. Without it, `$PEPPER_SYSROOT_<TRIPLE>` (the triple upper-cased, with `_` for `-`) when set\n  -m <OPTION>                       The CPU to generate code for, with clang's names and meanings: `-march=<cpu>` (x86: `x86-64-v3`, `native`), `-mcpu=<cpu>` (AArch64: `apple-m2`, `native`), `-march=<arch>` (AArch64: `armv8.2-a+crypto`), `-mtune=<cpu>`, and `-m<feature>` / `-mno-<feature>`. The default is clang's for the target (`x86-64`; `apple-m1` on Apple arm64)\n      --no-runtime-checks <CHECKS>  Remove kinds of runtime check from an optimized build, as a comma-separated list: `overflow` (integer overflow; arithmetic then wraps), `divide` (division by zero and `MIN / -1`; then undefined), `shift` (a count of at least the width; then masked), `bounds` (array and string indexing) and `null` (calls and matches through a null reference), or `all`. Removing `bounds` or `null` gives up memory safety. Ignored, with a warning, at `-O0`\n      --test                        Build the entry file's tests: keep its `[Test]` functions, define the build option `TEST`, and replace its `main` with one that lists or runs them (`--list`, `--run NAME`). Given several files of one folder, builds the tests of them all into one program, each file keeping the scope it has in any program. `pep-test` builds with it\n      --emit-llvm                   Emit LLVM IR (optimized at the `-O` level)\n      --emit-static[=<MODE>]        Write the program's source with each `static` block replaced by the code it emits, like C's `cc -E`, into the folder `-o` names (default `<name>.static`) instead of compiling it. `--emit-static=keep` also keeps each block, as `#` comments above its expansion [possible values: expand, keep]\n  -g, --emit-debug                  Emit debug info: DWARF on Linux and macOS, CodeView and a `.pdb` on Windows\n      --debug-static <VIEW>         With `-g`, where the debugger shows the code a `static` block emits: `source` (the default), the block as written, stopping on a loop's header once per pass; or `expanded`, a copy of each file with its blocks expanded as `--emit-static` writes them, saved beside the output as `<name>.static.pep`, stepping through the expanded statements. `expanded` builds without the build cache [possible values: source, expanded]\n      --frame-pointers              Keep the frame pointer in every function, even when optimizing, so profilers and stack walkers unwind the stack cheaply (clang's `-fno-omit-frame-pointer`). `pep-profile` builds with it\n  -v, --verbose                     Accepted for compatibility; prints nothing more yet\n      --no-runtime                  Skip runtime discovery\n      --emit-ast[=<FORMAT>]         Dump the parsed AST instead of compiling: as source-like text (`--emit-ast`, `--emit-ast=text`) or as JSON (`--emit-ast=json`) [possible values: text, json]\n      --emit-linked                 Load and link the program instead of compiling it, and print every file's syntax tree after linking, with the linking errors, as JSON\n      --emit-checked                Load, link and check the program instead of compiling it, and print what the checks before sema report: the errors (linking, then `[__BuiltIn]` misuse, then visibility), then the warnings, rendered\n      --emit-model                  Load, link, check and build the program's sema model instead of compiling it, and print the model before any sema pass, as JSON\n      --emit-model-step <N>         With `--emit-model`: run the first N sema steps (one pass each, in the order the compiler runs them) and print the model after them\n      --emit-steps                  Load, link, check and build the program, run the sema passes, and print the name of each step run, one per line, instead of compiling\n  -T <CHAN>                         Enable a trace channel. `time` prints how long each compile stage took; `passes` prints how long each sema pass took, summed over its runs; `cache` prints whether each unit's object came from the build cache; any other name is accepted and ignored\n      --Tall                        Enable all trace channels\n      --no-cache                    Compile every unit without reading or writing the build cache\n      --cache <DIR>                 Build cache directory (default: `$PEPPER_CACHE_DIR`, else `$CWD/.pep/cache`)\n      --verify-cache                Check the build cache: generate the code of every unit that hits anyway, and fail if it differs from the cached object's, or if skipping the hit units' bodies in sema changes another unit's code (also `PEPPER_CACHE_VERIFY=1`). For testing the compiler\n      --no-verify-cache             Do not check the build cache, even with `PEPPER_CACHE_VERIFY` set\n      --MSVC                        Use the MSVC linker. Not ported: always an error\n  -h, --help                        Print help\n  -V, --version                     Print version\n";

# Prints `message` on standard error as an error: with `error:` unless it is
# a rendered diagnostic that says so already.
_report(message: String) {
    var text = message.contains("error:") ? message : $"error: {message}";
    File.stderr().write_all(text.ends_with("\n") ? text : text + "\n");
}
