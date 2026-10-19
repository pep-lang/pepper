# pep-lsp: the Pepper language server, written in Pepper on the `lsp`
# package (github.com/pep-lang/pepper-lsp). Editors start it, through
# `pepper lsp`, and talk to it over standard input and output.
#
# Releases and the VS Code extension ship it. Build it from the repository
# root with a pep-build:
#
#     PEPPER_RUNTIME=$PWD/runtime pep-build -O tools/pep-lsp/main.pep -o pep-lsp

import lsp;
import "arguments";
import "server";
import "supervisor";

main(args: String[]): int {
    if (handle_arguments(args) is Value(code)) {
        return code;
    }
    # The editor talks to a supervisor, which runs the server in a child
    # (`--serve`) and starts another if it panics (`supervisor.pep`).
    if (!args.contains("--serve")) {
        return supervise();
    }
    String current = version();
    return lsp.serve_stdio<PepperServer>((client) => PepperServer(client, current));
}
