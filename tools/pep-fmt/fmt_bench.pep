# The pep-fmt benchmark: every `.pep` file under the folders given (by
# default runtime and tools, what `pep-fmt --check runtime tools` reads),
# read into memory once, then taken through pep-fmt's pipeline one phase
# further at a time, several passes each:
#
#     lex      the tokens, with comments (`syntax.lex`)
#     parse    the tree pep-fmt lays out (`parse.parse_written`, which lexes)
#     layout   parse, then the layout `Doc` (`Formatter.format`)
#     render   layout, then the text (`render`)
#     format   the whole of `format_source` (render, then trailing comments
#              aligned), as `pep-fmt --check` runs it per file
#
# Prints the best pass of each phase and its cost beyond the phase before
# it (`format` beyond `render`, `layout` beyond `parse`, ...). Reading the
# files is timed once.
#
#     pepper build -O -I tools tools/pep-fmt/fmt_bench.pep -o fmt_bench
#     ./fmt_bench [repository root] [passes] [folder...]

import [Directory, File, Path] from io;
import os;
import compiler.parse;
import syntax;
import "doc";
import "format";

# Appends the text of every `.pep` file under `folder` to `out`.
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

# Takes `source` through the pipeline up to `phase`; returns whether it
# failed on the way.
run(phase: String, source: String): bool {
    if (phase == "lex") {
        return syntax.lex(source, true).is_err();
    }
    if (phase == "format") {
        return format_source(source).is_err();
    }
    var parsed = parse.parse_written(source, false);
    if (parsed.is_err() or phase == "parse") {
        return parsed.is_err();
    }
    var module = parsed.value();
    var formatter = Formatter(module.tokens.value());
    var layout = formatter.format(module);
    if (phase == "render") {
        render(layout, LINE_WIDTH);
    }
    return !formatter.error.is_empty;
}

main(args: String[]): int {
    var root = args.count > 1 ? args[1] : ".";
    long passes = args.count > 2 ? long.parse(args[2]).value() : 7;
    var folders = Array<String>();
    ulong argument = 3;
    while (argument < args.count) {
        folders.append(args[argument]);
        argument += 1;
    }
    if (folders.is_empty) {
        folders.append("runtime");
        folders.append("tools");
    }
    var read_start = os.Instant.now();
    var sources = Array<String>();
    for (var folder in folders) {
        collect(Path(root).join(folder), sources);
    }
    var read_ms = (os.Instant.now() - read_start).nanoseconds() / 1000000;
    ulong bytes = 0;
    for (var s in sources) {
        bytes += s.size;
    }
    print($"{sources.count} files, {bytes} bytes, read in {read_ms} ms");
    ulong previous = 0;
    for (var phase in ["lex", "parse", "layout", "render", "format"]) {
        ulong best = 0xFFFFFFFFFFFFFFFF;
        for (var pass in 0..passes) {
            var start = os.Instant.now();
            ulong failures = 0;
            for (var source in sources) {
                if (run(phase, source)) {
                    failures += 1;
                }
            }
            var took = (os.Instant.now() - start).nanoseconds();
            if (took < best) {
                best = took;
            }
            if (pass == 0 and failures > 0) {
                print($"  {phase}: {failures} files fail");
            }
        }
        # `parse` lexes again, so its cost beyond `lex` is the parser's.
        var beyond = best > previous ? best - previous : 0;
        print($"{phase}: {best / 1000000} ms (+{beyond / 1000000} ms)");
        previous = best;
    }
    return 0;
}
