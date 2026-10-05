# The parser benchmark (#601): every `.pep` file of the repository, read
# into memory once, then lexed (`lex`), parsed to the lossless syntax tree
# (`tree`), and parsed to the compiler's AST (`ast`), several passes each.
# Prints the best pass of each phase.
#
#     pep-build -O -I tools tools/compiler/parse_bench.pep -o parse_bench
#     ./parse_bench [repository root] [lex|tree|ast|all] [passes]

import io;
import [Directory, File, Path] from io;
import os;
import compiler.parse;
import syntax;

collect(folder: Path, out: String[]) {
    var listing = Directory.open(folder);
    if (listing.is_err()) {
        return;
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return;
    }
    for (var entry in entries.value()) {
        if (entry.is_directory and !entry.name.starts_with(".")) {
            collect(entry.path, out);
        } else if (entry.name.ends_with(".pep")) {
            var text = File.read_to_string(entry.path);
            if (text.is_ok()) {
                out.append(text.value());
            }
        }
    }
}

main(args: String[]): int {
    var root = args.count > 1 ? args[1] : ".";
    var phase = args.count > 2 ? args[2] : "all";
    long passes = args.count > 3 ? long.parse(args[3]).value() : 5;
    var sources = Array<String>();
    for (var folder in ["runtime", "tools", "tests", "docs/examples"]) {
        collect(Path(root).join(folder), sources);
    }
    ulong bytes = 0;
    for (var s in sources) {
        bytes += s.size;
    }
    print($"{sources.count} files, {bytes} bytes");
    for (var name in ["lex", "tree", "ast"]) {
        if (phase != "all" and phase != name) {
            continue;
        }
        ulong best = 0xFFFFFFFFFFFFFFFF;
        for (var pass in 0..passes) {
            var start = os.Instant.now();
            ulong failures = 0;
            for (var source in sources) {
                if (name == "lex") {
                    if (syntax.lex(source).is_err()) {
                        failures += 1;
                    }
                } else if (name == "tree") {
                    if (syntax.parse(source).is_err()) {
                        failures += 1;
                    }
                } else {
                    if (parse.parse(source).is_err()) {
                        failures += 1;
                    }
                }
            }
            var took = (os.Instant.now() - start).nanoseconds();
            if (took < best) {
                best = took;
            }
            if (pass == 0 and failures > 0) {
                print($"  {name}: {failures} files fail");
            }
        }
        print($"{name}: {best / 1000000} ms");
    }
    return 0;
}
