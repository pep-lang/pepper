# The cli module's global options: given before or after a command's
# name, listed in the command's help, required across commands, and
# checked for names a command declares too.

import cli;

struct Shared {
    [cli.Option("q", "say less", global = true)]
    var quiet: bool;
}

[Test]
global_options_apply_after_a_command() {
    var parser = cli.Parser("pkg", "Manages packages");
    var verbose = parser.flag("verbose", "v", "say more", global = true);
    var color = parser.option("color", help = "when to color", global = true);
    var local = parser.flag("local", "l");
    var add = parser.command("add", "Adds a dependency");
    var name = add.positional("name");
    var tool = parser.command("tool", "Runs a tool");
    var nested = tool.command("dev", "Runs a development tool");
    nested.positional("package");

    expect_false(parser.try_parse(["pkg", "-v", "add", "x"]).is_err());
    expect_equal(verbose.occurrences, 1);
    expect_false(parser.try_parse(["pkg", "add", "-v", "x", "--color=never"]).is_err());
    expect_true(verbose.is_set);
    expect_equal(color.value(), "never");
    expect_equal(name.value(), "x");
    expect_false(parser.try_parse(["pkg", "-v", "tool", "dev", "-vv", "y"]).is_err());
    expect_equal(verbose.occurrences, 3);

    # An option that is not global still belongs to its parser only.
    expect_equal(parser.try_parse(["pkg", "add", "-l", "x"]).error().message, "unknown option '-l'");
    expect_equal(
        parser.try_parse(["pkg", "add", "--colour", "x"]).error().message,
        "unknown option '--colour'; did you mean '--color'?"
    );

    var expected = "Adds a dependency\n\n"
        + "usage: pkg add [OPTIONS] <name>\n\n"
        + "Arguments:\n"
        + "  <name>\n\n"
        + "Options:\n"
        + "  -v, --verbose        say more\n"
        + "      --color <COLOR>  when to color\n"
        + "  -h, --help           show this help\n";
    expect_equal(add.help(), expected);
}

[Test]
a_required_global_option_may_come_after_the_command() {
    var parser = cli.Parser("pkg");
    var target = parser.option("target", required = true, global = true);
    var add = parser.command("add");
    expect_false(parser.try_parse(["pkg", "add", "--target", "x86"]).is_err());
    expect_equal(target.value(), "x86");
    expect_equal(parser.try_parse(["pkg", "add"]).error().message, "missing required option '--target'");
}

[Test]
struct_options_can_be_global() {
    var shared = Shared();
    var parser = cli.Parser("pkg");
    parser.add_options(shared);
    var add = parser.command("add");
    expect_false(parser.try_parse(["pkg", "add", "-q"]).is_err());
    expect_true(shared.quiet);
}
