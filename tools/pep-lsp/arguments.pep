# pep-lsp's command line: the options that answer without starting the
# server.

import [File] from io;
import [Path] from io;
import "analysis";

## The release this tool belongs to, as the other Pepper tools give it.
##
## @returns the version, such as `0.4.0-dev`
export version(): String {
    return "0.11.1";
}

# What `pep-lsp --help` prints.
const HELP = "The Pepper language server. Editors start it and talk to it over standard
input and output; its settings arrive as LSP initialization options.

usage: pep-lsp [options]

Options:
  --stdio        talk over standard input and output (the default; accepted
                 for editors that pass it)
  --serve        run the server in this process, without a supervisor
                 (internal: the supervisor starts it so)
  --compilation-unit-worker <dir>
                 check compilation units for the server that started it (internal: the
                 server starts these itself)
  --fill-cache <dir>
                 check the compilation units the build cache lacks, in
                 compilation unit workers, for the server that started it
                 (internal: the server starts it itself)
  -h, --help     show this help
  -V, --version  show pep-lsp's version
";

## Handles the command line: prints the help or the version, runs a compilation
## unit worker or a cache filler, or rejects an unknown argument.
##
## @param args the arguments, the program's name first
## @returns Empty when the server should start, else the exit code of what
##   the arguments asked for instead (2 for an unknown argument)
export handle_arguments(args: String[]): int? {
    for (var i in 1..args.count) {
        var arg = args[i];
        if (arg == "--stdio" or arg == "--serve") {
            continue;
        }
        # `--layer-worker` is the deprecated spelling.
        if ((arg == "--compilation-unit-worker" or arg == "--layer-worker") and i + 1 < args.count) {
            return Optional<int>.Value(compilation_unit_worker(Path(args[i + 1])));
        }
        if (arg == "--fill-cache" and i + 1 < args.count) {
            return Optional<int>.Value(fill_cache(Path(args[i + 1])));
        }
        if (arg == "-h" or arg == "--help") {
            File.stdout().write_all(HELP);
            return Optional<int>.Value(0);
        }
        if (arg == "-V" or arg == "--version") {
            File.stdout().write_all($"pep-lsp {version()}\n");
            return Optional<int>.Value(0);
        }
        File.stderr().write_all(
            $"pep-lsp: error: unknown argument '{arg}'\nusage: pep-lsp [--stdio]; pep-lsp --help lists the options\n"
        );
        return Optional<int>.Value(2);
    }
    return Optional<int>.Empty;
}
