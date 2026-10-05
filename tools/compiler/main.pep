# pepc: the Pepper compiler written in Pepper (#225). For now it parses and
# links:
#
#     pepc --emit-ast=json file.pep
#     pepc --emit-linked [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] file.pep
#     pepc --emit-checked [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] file.pep
#
#     pepc --emit-model [--emit-model-step N] [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] file.pep
#     pepc --emit-llvm [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] file.pep
#     pepc [--test] [-O0|-O1|-O2|-O3] [-o out] [-l lib] [-L dir] [-I dir] [--import name] [--no-runtime] [-D NAME[=value]]
#          [--cache dir | --no-cache] [-T time] [-T cache] [--Tall] file.pep
#
# print the file's syntax tree, or the whole program after linking, as the
# JSON that `pep-build` prints with the same options, or what the checks
# after linking report, or the sema model before any pass (or after the
# first N steps of the passes, or the error one reports), as `pep-build`
# prints it, or the LLVM IR of the whole program, unoptimized, as
# `pep-build --emit-llvm -O0` writes it, so the two can be compared. With
# no `--emit-*` option it builds the program into an executable, as
# `pep-build` does: `out`, else the file's stem in the current directory.
# `--test` builds the test program of the file (or of several files of one
# folder) instead, as `pep-build --test` does (`driver/test_main.pep`).
# A build keeps each unit's object in the build cache (`driver/cache.pep`):
# `--cache dir`, else `$PEPPER_CACHE_DIR`, else `.pep/cache`; `--no-cache`
# compiles everything. `-T time` prints how long each stage took, `-T
# cache` whether each unit's object came from the cache, `--Tall` both.

import compiler.codegen;
import [render_all] from compiler.diagnostic;
import compiler.driver;
import io;
import [File, Path] from io;
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
    bool ir = false;
    bool ast = false;
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
    ulong i = 1;
    while (i < args.count) {
        var arg = args[i];
        if (arg == "--emit-linked") {
            linked = true;
        } else if (arg == "--emit-checked") {
            checked = true;
        } else if (arg == "--emit-model") {
            model = true;
        } else if (arg == "--emit-llvm") {
            ir = true;
        } else if (arg == "--test") {
            test = true;
        } else if (arg == "--emit-ast=json") {
            ast = true;
        } else if (arg == "-O" or arg == "-O0" or arg == "-O1" or arg == "-O2" or arg == "-O3") {
            # `-O` alone is `-O2`, as in pep-build.
            opt_level = Optional<uint>.Value(
                arg == "-O" ?
                    2 :
                    arg.substr_bytes(2, 1) == "0" ?
                        0 :
                        arg.substr_bytes(2, 1) == "1" ? 1 : arg.substr_bytes(2, 1) == "2" ? 2 : 3
            );
        } else if (arg == "-o" or arg == "-l" or arg == "-L") {
            if (i + 1 >= args.count) {
                print($"pepc: {arg} needs a value");
                return 2;
            }
            i += 1;
            if (arg == "-o") {
                output = Optional<String>.Value(args[i]);
            } else if (arg == "-l") {
                libraries.append(args[i]);
            } else {
                library_dirs.append(Path(args[i]));
            }
        } else if (arg == "--emit-model-step") {
            if (i + 1 >= args.count) {
                print($"pepc: {arg} needs a value");
                return 2;
            }
            i += 1;
            var parsed = ulong.parse(args[i]);
            if (!parsed.is_value()) {
                print($"pepc: {arg} needs a number, not '{args[i]}'");
                return 2;
            }
            step = Optional<ulong>.Value(parsed.value());
        } else if (arg == "--no-runtime") {
            setup.runtime = false;
        } else if (arg == "--no-cache") {
            no_cache = true;
        } else if (arg == "--cache" or arg == "-T") {
            if (i + 1 >= args.count) {
                print($"pepc: {arg} needs a value");
                return 2;
            }
            i += 1;
            if (arg == "--cache") {
                cache_dir = Optional<String>.Value(args[i]);
            } else {
                traces.append(args[i]);
            }
        } else if (arg == "--Tall") {
            traces.append("time");
            traces.append("cache");
        } else if (arg == "-I" or arg == "--import" or arg == "-D" or arg.starts_with("-I") or arg.starts_with("-D")) {
            # `-I dir` or `-Idir`; `-D NAME` or `-DNAME`.
            var value = arg.size > 2 and arg != "--import" ? arg.substr_bytes(2, arg.size - 2) : "";
            if (value.is_empty) {
                if (i + 1 >= args.count) {
                    print($"pepc: {arg} needs a value");
                    return 2;
                }
                i += 1;
                value = args[i];
            }
            if (arg.starts_with("-I")) {
                setup.import_dirs.append(Path(value));
            } else if (arg == "--import") {
                setup.forced_imports.append(value);
            } else {
                var option = value.split_once("=");
                if (option.is_value()) {
                    var (name, defined) = option.value();
                    setup.target.build_options[name] = defined;
                } else {
                    setup.target.build_options[value] = "1";
                }
            }
        } else {
            if (!path.is_value()) {
                path = Optional<String>.Value(arg);
            }
            paths.append(arg);
        }
        i += 1;
    }
    if (!path.is_value() and (ast or linked or checked or model or ir)) {
        print("usage: pepc --emit-ast=json <file.pep>");
        print("       pepc --emit-linked [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] <file.pep>");
        print("       pepc --emit-checked [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] <file.pep>");
        print(
            "       pepc --emit-model [--emit-model-step N] [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] <file.pep>"
        );
        print("       pepc --emit-llvm [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] <file.pep>");
        print(
            "       pepc [-O0|-O1|-O2|-O3] [-o out] [-l lib] [-L dir] [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] <file.pep>"
        );
        return 2;
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
    # In a project, the build takes what its `pep.toml` gives: with no file,
    # the entry and output; and `[build]`'s libraries.
    var project = driver.apply_project(
        path.is_value() ? Optional<Path>.Value(Path(path.value())) : Optional<Path>.Empty
    );
    if (project.is_err()) {
        File.stderr().write_all(project.error() + "\n");
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
                File.stderr().write_all(made.error() + "\n");
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
    if (!ast) {
        if (!(linked or checked or model or ir)) {
            # A project builds with what pep.lock lists: fetch what is missing.
            var fetched = driver.fetch_dependencies(entry);
            if (fetched.is_err()) {
                File.stderr().write_all(fetched.error() + "\n");
                return 1;
            }
        }
        var program = link.load_program(entry, setup);
        if (program.is_err()) {
            print($"pepc: {program.error()}");
            return 1;
        }
        if (ir) {
            var built = sema.merge(program.value());
            if (built.is_err()) {
                print(built.error());
                return 1;
            }
            var ran = sema.run_passes(built.value(), program.value().target, program.value().sources());
            if (ran.is_err()) {
                print(render_all([ran.error()], program.value().sources()));
                return 1;
            }
            var namespaces = Array<String>();
            for (var f in program.value().files) {
                namespaces.append(f.namespace);
            }
            var generated = codegen.generate_ir(built.value(), ran.value(), namespaces, entry.file_stem().value());
            if (generated.is_err()) {
                print(render_all([generated.error()], program.value().sources()));
                return 1;
            }
            # The IR ends with a newline, which `print` adds.
            var text = generated.value();
            print(text.ends_with("\n") ? text.substr_bytes(0, text.size - 1) : text);
        } else if (model) {
            var built = sema.merge(program.value());
            if (built.is_err()) {
                print(built.error());
                return 1;
            }
            if (step.is_value()) {
                var ran = sema.run_steps(
                    built.value(), program.value().target, step.value(), program.value().sources()
                );
                if (ran.is_err()) {
                    print(render_all([ran.error()], program.value().sources()));
                    return 1;
                }
            }
            print(sema.model_json(built.value()));
        } else if (linked) {
            print(program.value().to_json().to_string());
        } else if (checked) {
            print(program.value().check_report());
        } else {
            var cwd = process.working_directory();
            var here = cwd.is_ok() ? cwd.value() : Path(".");
            var stem = entry.file_stem();
            var out = here.join(Path(stem.is_value() ? stem.value() : "main"));
            if (output.is_value()) {
                out = Path(output.value());
            } else if (project.value().output.is_value()) {
                out = project.value().output.value();
            }
            var work = project.value().dir.is_value() ? project.value().dir.value() : here;
            var options = driver.BuildOptions(out, work.join(Path(".pep")).join(Path("build")));
            options.opt_level = opt_level.value();
            for (var library in project.value().libraries) {
                if (!libraries.contains(library)) {
                    libraries.append(library);
                }
            }
            options.libraries = libraries;
            options.library_dirs = library_dirs;
            if (!no_cache) {
                options.cache = Optional<driver.Cache>.Value(
                    cache_dir.is_value() ? driver.Cache(Path(cache_dir.value())) : driver.default_cache(work)
                );
            }
            options.trace_time = traces.contains("time");
            options.trace_cache = traces.contains("cache");
            var made = driver.build(program.value(), options);
            if (made.is_err()) {
                File.stderr().write_all(made.error() + "\n");
                return 1;
            }
        }
        return 0;
    }
    var source = File.read_to_string(path.value());
    if (source.is_err()) {
        print($"pepc: cannot read '{path.value()}'");
        return 1;
    }
    var module = parse.parse(source.value());
    if (module.is_err()) {
        var error = module.error();
        print($"{path.value()}:{error.span.start}: error: {error.message}");
        return 1;
    }
    print(module.value().to_json().to_string());
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
