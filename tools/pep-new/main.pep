# pep-new: starts a project in a new folder, like `cargo new`; `pepper
# new` runs it. `pep-init` does the same in the current folder.
#
#     pep-new hello                     # a program: pep.toml, main.pep, ...
#     pep-new geometry --lib            # a package, laid out as
#                                       # pep-lang/pepper-package-template
#     pep-new pepper-geometry --lib --name geometry --license MIT
#
# Build it from the repository root:
#
#     pep-build tools/pep-new/main.pep -o target/bin/pep-new

import cli;
import [Path] from io;
import [create, Options] from scaffold;

# The release this tool belongs to. `pep-doc check` keeps it equal to the
# version in VERSION.
version(): String {
    return "0.12.0";
}

main(args: String[]): int {
    var options = Options();
    var parser = cli.Parser("pep-new", "Starts a Pepper program or package in a new folder.", version = version());
    var folder = parser.positional<Path>("path", "the folder to create, which also names the project");
    parser.add_options(options);
    if (!parser.parse(args)) {
        return 2;
    }
    return create("pep-new", folder.value(), options);
}
