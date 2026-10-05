# pepc: the Pepper compiler written in Pepper (#225). For now it parses and
# links:
#
#     pepc --emit-ast=json file.pep
#     pepc --emit-linked [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] file.pep
#     pepc --emit-checked [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] file.pep
#
#     pepc --emit-model [--emit-model-step N] [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] file.pep
#     pepc --emit-llvm [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] file.pep
#     pepc [-O0|-O1|-O2|-O3] [-o out] [-l lib] [-L dir] [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] file.pep
#
# print the file's syntax tree, or the whole program after linking, as the
# JSON that `pep-build` prints with the same options, or what the checks
# after linking report, or the sema model before any pass (or after the
# first N steps of the passes, or the error one reports), as `pep-build`
# prints it, or the LLVM IR of the whole program, unoptimized, as
# `pep-build --emit-llvm -O0` writes it, so the two can be compared. With
# no `--emit-*` option it builds the program into an executable, as
# `pep-build` does: `out`, else the file's stem in the current directory.

import compiler.codegen;
import [render_all] from compiler.diagnostic;
import compiler.driver;
import io;
import [File, Path] from io;
import compiler.link;
import compiler.parse;
import process;
import compiler.sema;

main(args: String[]): int {
    String? path;
    bool linked = false;
    bool checked = false;
    bool model = false;
    bool ir = false;
    bool ast = false;
    uint opt_level = 0;
    String? output;
    var libraries = Array<String>();
    var library_dirs = Array<Path>();
    var step = Optional<ulong>.Empty;
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
        } else if (arg == "--emit-ast=json") {
            ast = true;
        } else if (arg == "-O" or arg == "-O0" or arg == "-O1" or arg == "-O2" or arg == "-O3") {
            # `-O` alone is `-O2`, as in pep-build.
            opt_level = arg == "-O" ?
                2 :
                arg.substr_bytes(2, 1) == "0" ?
                    0 :
                    arg.substr_bytes(2, 1) == "1" ? 1 : arg.substr_bytes(2, 1) == "2" ? 2 : 3;
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
            path = Optional<String>.Value(arg);
        }
        i += 1;
    }
    if (!path.is_value()) {
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
    if (!ast) {
        var program = link.load_program(Path(path.value()), setup);
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
            var generated = codegen.generate_ir(
                built.value(), ran.value(), namespaces, Path(path.value()).file_stem().value()
            );
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
            var stem = Path(path.value()).file_stem();
            var out = output.is_value() ?
                Path(output.value()) :
                here.join(Path(stem.is_value() ? stem.value() : "main"));
            var options = driver.BuildOptions(out, here.join(Path(".pep")).join(Path("build")));
            options.opt_level = opt_level;
            options.libraries = libraries;
            options.library_dirs = library_dirs;
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
