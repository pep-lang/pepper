# Shell completion scripts, printed by a command of the program's own.
import cli;

main(): int {
    var parser = cli.Parser("pkg", "Manages packages");
    parser.flag("verbose", "v", "say more", global = true);
    var add = parser.command("add", "Adds a dependency");
    add.positional("name", "the package");
    var completions = parser.command("completions", "Prints a shell completion script");
    var shell = completions.positional<cli.Shell>("shell", "bash, zsh, fish or powershell");

    # The arguments as `main(args: String[])` would receive them.
    var parsed = parser.try_parse(["pkg", "completions", "fish"]);
    assert(parsed.is_ok() && completions.is_selected, "the completions command");
    print(parser.completions(shell.value()));
    return 0;
}
