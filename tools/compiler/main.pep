# pepc: the Pepper compiler written in Pepper (#225). For now it parses and
# links:
#
#     pepc --emit-ast=json file.pep
#     pepc --emit-linked [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] file.pep
#     pepc --emit-checked [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] file.pep
#
# print the file's syntax tree, or the whole program after linking, as the
# JSON that `pep-build` prints with the same options, or what the checks
# after linking report, as `pep-build` prints it, so the two can be
# compared.

import io;
import [File, Path] from io;
import compiler.link;
import compiler.parse;

main(args: String[]): int {
    String? path;
    bool linked = false;
    bool checked = false;
    var setup = link.Setup();
    ulong i = 1;
    while (i < args.count) {
        var arg = args[i];
        if (arg == "--emit-linked") {
            linked = true;
        } else if (arg == "--emit-checked") {
            checked = true;
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
        } else if (arg != "--emit-ast=json") {
            path = Optional<String>.Value(arg);
        }
        i += 1;
    }
    if (!path.is_value()) {
        print("usage: pepc --emit-ast=json <file.pep>");
        print("       pepc --emit-linked [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] <file.pep>");
        print("       pepc --emit-checked [-I dir] [--import name] [--no-runtime] [-D NAME[=value]] <file.pep>");
        return 2;
    }
    if (linked or checked) {
        var program = link.load_program(Path(path.value()), setup);
        if (program.is_err()) {
            print($"pepc: {program.error()}");
            return 1;
        }
        if (linked) {
            print(program.value().to_json().to_string());
        } else {
            print(program.value().check_report());
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
