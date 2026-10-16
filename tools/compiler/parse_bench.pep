# The parser benchmark (#601): every `.pep` file of the repository, read
# into memory once, then lexed (`lex`), parsed to the compiler's AST
# (`ast`, `parse.parse`), and parsed to the AST as written, tokens and
# comments kept (`written`, `parse.parse_written`, what pep-fmt reads),
# several passes each. Prints the best pass of each phase.
#
# Then the broken inputs of #225's step 1, each file with its last `}`
# removed, a `;` in its second half removed, or the rest of a line after
# ` = ` in its second half removed: parsed (`broken`, `parse.parse`, which
# stops at the first error) and parsed past their errors (`recover`,
# `parse.parse_recovering`, what the language server reads), and the
# intact files through `parse_recovering` (`recover-intact`).
#
#     pep-build -O tools/compiler/parse_bench.pep -o parse_bench
#     ./parse_bench [repository root] [lex|ast|written|broken|recover|recover-intact|all] [passes]

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
    var broken = Array<String>();
    for (var s in sources) {
        broken.append(unclosed(s));
        broken.append(missing_semicolon(s));
        broken.append(unfinished(s));
    }
    for (var name in ["lex", "ast", "written", "broken", "recover", "recover-intact"]) {
        if (phase != "all" and phase != name) {
            continue;
        }
        ulong best = 0xFFFFFFFFFFFFFFFF;
        for (var pass in 0..passes) {
            var start = os.Instant.now();
            ulong failures = 0;
            var inputs = name == "broken" or name == "recover" ? broken : sources;
            for (var source in inputs) {
                if (name == "broken") {
                    if (parse.parse(source).is_err()) {
                        failures += 1;
                    }
                } else if (name == "recover" or name == "recover-intact") {
                    if (!parse.parse_recovering(source).errors.is_empty) {
                        failures += 1;
                    }
                } else if (name == "lex") {
                    if (syntax.lex(source).is_err()) {
                        failures += 1;
                    }
                } else if (name == "ast") {
                    if (parse.parse(source).is_err()) {
                        failures += 1;
                    }
                } else {
                    if (parse.parse_written(source).is_err()) {
                        failures += 1;
                    }
                }
            }
            var took = (os.Instant.now() - start).nanoseconds();
            if (took < best) {
                best = took;
            }
            if (pass == 0 and failures > 0) {
                print($"  {name}: {failures} of {inputs.count} inputs fail");
            }
        }
        print($"{name}: {best / 1000000} ms");
    }
    return 0;
}

# `source` without bytes `start` to `end`.
cut(source: String, start: ulong, end: ulong): String {
    return source.substr_bytes(0, start) + source.substr_bytes(end, source.size - end);
}

# `source` without its last `}`.
unclosed(source: String): String {
    var i = source.rfind("}");
    return i < 0 ? source : cut(source, i as ulong, i as ulong + 1);
}

# `source` without the first `;` in its second half.
missing_semicolon(source: String): String {
    var i = source.find(";", source.size / 2);
    return i < 0 ? source : cut(source, i as ulong, i as ulong + 1);
}

# `source` without the rest of the line after the first ` = ` in its
# second half.
unfinished(source: String): String {
    var at = source.find(" = ", source.size / 2);
    if (at < 0) {
        return source;
    }
    var start = at as ulong + 3;
    var line_end = source.find("\n", start);
    return line_end < 0 ? source.substr_bytes(0, start) : cut(source, start, line_end as ulong);
}
