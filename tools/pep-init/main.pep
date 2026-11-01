# pep-init: starts a project in the current folder, like `cargo init`;
# `pepper init` runs it. It writes what `pep-new` writes: the two share
# the module `scaffold` (`tools/scaffold`).
#
#     pep-init                          # a program named after the folder
#     pep-init --lib --name geometry    # a package
#
# Build it from the repository root:
#
#     pep-build tools/pep-init/main.pep -o target/bin/pep-init

import cli;
import [Path] from io;
import [create, Options] from scaffold;

# The release this tool belongs to. `pep-doc check` keeps it equal to the
# version in VERSION.
version(): String {
    return "0.13.0-dev";
}

main(args: String[]): int {
    var options = Options();
    var parser = cli.Parser(
        "pep-init", "Starts a Pepper program or package in the current folder.", version = version()
    );
    parser.add_options(options);
    if (!parser.parse(args)) {
        return 2;
    }
    return create("pep-init", Path("."), options);
}
