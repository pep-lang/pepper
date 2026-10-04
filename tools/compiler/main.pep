# pepc: the Pepper compiler written in Pepper (#225). For now it parses:
#
#     pepc --emit-ast=json file.pep
#
# prints the file's syntax tree as the JSON that
# `pep-build --emit-ast=json` prints, so the two can be compared.

import io;
import [File] from io;
import os;
import compiler.parse;

main(args: String[]): int {
    String? path;
    ulong i = 1;
    while (i < args.count) {
        var arg = args[i];
        if (arg != "--emit-ast=json") {
            path = Optional<String>.Value(arg);
        }
        i += 1;
    }
    if (!path.is_value()) {
        print("usage: pepc --emit-ast=json <file.pep>");
        return 2;
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
