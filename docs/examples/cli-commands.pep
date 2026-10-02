# Subcommands, and handling the outcome yourself with try_parse.
import cli;

main(): int {
    var parser = cli.Parser("pkg", "Manages packages");
    var verbose = parser.flag("verbose", "v", "say more");
    var add = parser.command("add", "Adds a dependency");
    var name = add.positional("name", "the package to add");
    var dev = add.flag("dev", "d", "only for development");
    var update = parser.command("update", "Updates dependencies");
    var packages = update.positionals("packages", "what to update; everything when none");

    # The arguments as `main(args: String[])` would receive them.
    var parsed = parser.try_parse(["pkg", "-v", "add", "--dev", "yaml"]);
    assert(parsed.is_ok() && parsed.value().is_none(), "parsed, no help asked for");
    assert(add.is_selected && !update.is_selected, "the add command");
    assert(verbose.is_set && dev.is_set && name.value() == "yaml", "its values");

    # A mistake is an error with a clang-style message.
    parsed = parser.try_parse(["pkg", "updat"]);
    assert(parsed.error().message == "unknown command 'updat'; did you mean 'update'?", "a suggestion");

    # --help gives the text to print, for the command it follows.
    parsed = parser.try_parse(["pkg", "update", "--help"]);
    print(parsed.value().value());
    return 0;
}
