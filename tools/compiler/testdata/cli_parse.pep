# Parses a command line with a subcommand: `parse` prints the help or an
# error itself (programs_test.pep).

import cli;

main(args: String[]): int {
    var parser = cli.Parser("pkg", "Manages packages");
    var add = parser.command("add", "Adds a dependency");
    var name = add.positional("name", "the package");
    if (!parser.parse(args)) {
        return 2;
    }
    print($"adding {name.value()}");
    return 0;
}
