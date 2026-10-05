# pep-lsp: the Pepper language server, written in Pepper on the `lsp`
# package (github.com/justinboswell/pepper-lsp). Editors start it, through
# `pepper lsp`, and talk to it over standard input and output.
#
# It replaces the Rust server in tools/lsp once it does all that one does
# (#225). Build it from the repository root, next to the compiler:
#
#     target/release/pep-build -O -I tools tools/pep-lsp/main.pep -o pep-lsp

import [File] from io;
import lsp;
import "server";

# The release this tool belongs to, as the other Pepper tools give it.
version(): String {
    return "0.3.0";
}

# What `pep-lsp --help` prints.
const HELP = "The Pepper language server. Editors start it and talk to it over standard
input and output; its settings arrive as LSP initialization options.

usage: pep-lsp [options]

Options:
  --stdio        talk over standard input and output (the default; accepted
                 for editors that pass it)
  -h, --help     show this help
  -V, --version  show pep-lsp's version
";

main(args: String[]): int {
    for (var i in 1..args.count) {
        var arg = args[i];
        if (arg == "--stdio") {
            continue;
        }
        if (arg == "-h" or arg == "--help") {
            File.stdout().write_all(HELP);
            return 0;
        }
        if (arg == "-V" or arg == "--version") {
            File.stdout().write_all($"pep-lsp {version()}\n");
            return 0;
        }
        File.stderr().write_all(
            $"pep-lsp: error: unknown argument '{arg}'\nusage: pep-lsp [--stdio]; pep-lsp --help lists the options\n"
        );
        return 2;
    }
    String current = version();
    return lsp.serve_stdio<PepperServer>((client) => PepperServer(client, current));
}
