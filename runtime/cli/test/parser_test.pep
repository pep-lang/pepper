# The cli module's Parser: options, flags and positional arguments, every
# spelling of a value, clang-style errors with suggestions, the help and
# version text, subcommands, and `closest`. `parse`, which prints and exits,
# is tested in a whole program by tools/compiler/programs_test.pep.

import cli;

[Test]
parses_options_and_arguments() {
    var parser = cli.Parser("pepper", "Compiles a Pepper program");
    var output = parser.option("output", "o", "the executable to write", default_value = "a.out");
    var level = parser.option("level", "O", "optimization level");
    var imports = parser.multiple("import-path", "I", "a directory to search");
    var verbose = parser.flag("verbose", "v", "say more");
    var quiet = parser.flag("quiet", "q", "say less");
    var source = parser.positional("source", "the entry file");
    var rest = parser.positionals("rest", "everything else");

    # Defaults, and nothing set.
    expect_false(parser.try_parse(["pepper", "main.pep"]).value().is_value());
    expect_equal(source.value(), "main.pep");
    expect_false(output.is_set);
    expect_equal(output.value(), "a.out");
    expect_false(level.is_set);
    expect_equal(level.value_or("2"), "2");
    expect_false(verbose.is_set);
    expect_false(imports.is_set);
    expect_false(rest.is_set);

    # Every spelling of a value.
    var parsed = parser.try_parse(
        ["pepper", "--output", "x", "-O3", "-I", "a", "--import-path=b", "-Ic", "-I=d", "main.pep"]
    );
    expect_false(parsed.is_err());
    expect_false(parsed.value().is_value());
    expect_equal(output.value(), "x");
    expect_equal(level.value(), "3");
    var paths = imports.values();
    expect_equal(paths.count, 4);
    expect_equal(paths[0], "a");
    expect_equal(paths[1], "b");
    expect_equal(paths[2], "c");
    expect_equal(paths[3], "d");

    # `--output=` sets an empty value; the last value wins.
    parser.try_parse(["pepper", "--output=", "s"]);
    expect_true(output.is_set);
    expect_equal(output.value_or("fallback"), "");
    parser.try_parse(["pepper", "-o", "one", "--output", "two", "s"]);
    expect_equal(output.value(), "two");

    # Clustered short flags, counted; a value may start with '-'.
    parser.try_parse(["pepper", "-vqv", "-o", "-weird", "s"]);
    expect_equal(verbose.occurrences, 2);
    expect_equal(quiet.occurrences, 1);
    expect_equal(output.value(), "-weird");
    parser.try_parse(["pepper", "-vo", "out", "s"]);
    expect_equal(verbose.occurrences, 1);
    expect_equal(output.value(), "out");

    # Positional lists take the rest; options mix in; '--' ends options;
    # '-' alone is positional.
    parser.try_parse(["pepper", "s", "a", "-v", "b", "--", "-c", "--d", "-"]);
    var others = rest.values();
    expect_equal("|".join(others), "a|b|-c|--d|-");
    expect_equal(verbose.occurrences, 1);

    # A new parse forgets the last one.
    parser.try_parse(["pepper", "t"]);
    expect_false(verbose.is_set);
    expect_false(rest.is_set);
    expect_false(imports.is_set);
    expect_false(output.is_set);
    expect_equal(source.value(), "t");
}

error_of(parser: cli.Parser, args: String[]): String {
    var result = parser.try_parse(args);
    if (result.is_ok()) {
        return "<ok>";
    }
    return result.error().message;
}

[Test]
reports_errors() {
    var parser = cli.Parser("tool");
    parser.option("output", "o", "where");
    parser.option("target", "", "for what", required = true);
    parser.flag("verbose", "v", "say more");
    parser.positional("source", "the input");
    parser.positional("extra", "more", required = false);

    expect_equal(error_of(parser, ["tool", "--target", "x", "s"]), "<ok>");
    expect_equal(error_of(parser, ["tool", "--target", "x", "s", "e", "f"]), "unexpected argument 'f'");
    expect_equal(
        error_of(parser, ["tool", "--target", "x", "--outptu", "a", "s"]),
        "unknown option '--outptu'; did you mean '--output'?"
    );
    expect_equal(error_of(parser, ["tool", "--target", "x", "--zzzzzz", "s"]), "unknown option '--zzzzzz'");
    expect_equal(error_of(parser, ["tool", "--hlep"]), "unknown option '--hlep'; did you mean '--help'?");
    expect_equal(error_of(parser, ["tool", "--target", "x", "-x", "s"]), "unknown option '-x'");
    expect_equal(error_of(parser, ["tool", "--target", "x", "-vé", "s"]), "unknown option '-é'");
    expect_equal(error_of(parser, ["tool", "--target", "x", "s", "-o"]), "missing value for '-o'");
    expect_equal(error_of(parser, ["tool", "s", "--target"]), "missing value for '--target'");
    expect_equal(
        error_of(parser, ["tool", "--target", "x", "--verbose=yes", "s"]), "option '--verbose' takes no value"
    );
    expect_equal(error_of(parser, ["tool", "s"]), "missing required option '--target'");
    expect_equal(error_of(parser, ["tool", "--target", "x"]), "missing required argument '<source>'");
    # No version declared: --version is an unknown option.
    expect_equal(error_of(parser, ["tool", "--version"]), "unknown option '--version'");
}

[Test]
generates_help_and_version() {
    var parser = cli.Parser("pepper", "Compiles a Pepper program", version = "0.2.1");
    parser.option("output", "o", "the executable to write", default_value = "a.out");
    parser.multiple("import-path", "I", "a directory to search for modules");
    parser.option("target", help = "the target triple", value_name = "TRIPLE", required = true);
    parser.flag("no-cache", help = "skip the build cache");
    parser.positional("source", "the program's entry file");
    parser.positionals("arguments", "passed to the program");
    var expected = "Compiles a Pepper program\n\n"
        + "usage: pepper [OPTIONS] --target <TRIPLE> <source> [arguments]...\n\n"
        + "Arguments:\n"
        + "  <source>        the program's entry file\n"
        + "  <arguments>...  passed to the program\n\n"
        + "Options:\n"
        + "  -o, --output <OUTPUT>            the executable to write [default: a.out]\n"
        + "  -I, --import-path <IMPORT_PATH>  a directory to search for modules [repeatable]\n"
        + "      --target <TRIPLE>            the target triple [required]\n"
        + "      --no-cache                   skip the build cache\n"
        + "  -h, --help                       show this help\n"
        + "  -V, --version                    show the version\n";
    expect_equal(parser.help(), expected);
    # An error before --help is reported; --help alone needs nothing else.
    var help = parser.try_parse(["pepper", "--bogus=1", "--help"]);
    expect_false(help.is_ok());
    help = parser.try_parse(["pepper", "-h"]);
    expect_false(help.is_err());
    expect_equal(help.value().value(), expected);
    var version = parser.try_parse(["pepper", "-V"]);
    expect_false(version.is_err());
    expect_equal(version.value().value(), "pepper 0.2.1\n");
    version = parser.try_parse(["pepper", "--version"]);
    expect_false(version.is_err());
    expect_equal(version.value().value(), "pepper 0.2.1\n");

    # A program's own -h and -V take the short names from help and version.
    var custom = cli.Parser("net", version = "1");
    var host = custom.option("host", "h", "the host");
    custom.flag("verbose", "V", "say more");
    var custom_help = "usage: net [OPTIONS]\n\nOptions:\n  -h, --host <HOST>  the host\n  -V, --verbose      say more\n      --help         show this help\n      --version      show the version\n";
    expect_equal(custom.help(), custom_help);
    var parsed = custom.try_parse(["net", "-h", "example.com"]);
    expect_false(parsed.is_err());
    expect_false(parsed.value().is_value());
    expect_equal(host.value(), "example.com");
}

[Test]
dispatches_subcommands() {
    var parser = cli.Parser("pep-package", "Manages packages", version = "0.1");
    var verbose = parser.flag("verbose", "v", "say more");
    var add = parser.command("add", "Adds a dependency");
    var name = add.positional("name", "the package");
    var dev = add.flag("dev", "d", "only for development");
    var update = parser.command("update", "Updates dependencies");
    var packages = update.positionals("packages", "the packages; all when none");

    var parsed = parser.try_parse(["pep-package", "-v", "add", "-d", "yaml"]);
    expect_false(parsed.is_err());
    expect_false(parsed.value().is_value());
    expect_true(parser.is_selected);
    expect_true(add.is_selected);
    expect_false(update.is_selected);
    expect_true(verbose.is_set);
    expect_true(dev.is_set);
    expect_equal(name.value(), "yaml");

    parsed = parser.try_parse(["pep-package", "update", "a", "b"]);
    expect_false(parsed.is_err());
    expect_false(add.is_selected);
    expect_true(update.is_selected);
    expect_equal(packages.values().count, 2);
    expect_false(verbose.is_set);
    expect_false(dev.is_set);

    # The parent's options go before the command.
    parsed = parser.try_parse(["pep-package", "add", "-v", "x"]);
    expect_false(parsed.is_ok());
    expect_equal(parsed.error().message, "unknown option '-v'");
    parsed = parser.try_parse(["pep-package"]);
    expect_false(parsed.is_ok());
    expect_equal(parsed.error().message, "missing command: expected 'add' or 'update'");
    parsed = parser.try_parse(["pep-package", "updat"]);
    expect_false(parsed.is_ok());
    expect_equal(parsed.error().message, "unknown command 'updat'; did you mean 'update'?");
    parsed = parser.try_parse(["pep-package", "add"]);
    expect_false(parsed.is_ok());
    expect_equal(parsed.error().message, "missing required argument '<name>'");

    # A command's help, and the version from the top.
    parsed = parser.try_parse(["pep-package", "add", "--help"]);
    var expected = "Adds a dependency\n\n"
        + "usage: pep-package add [OPTIONS] <name>\n\n"
        + "Arguments:\n  <name>  the package\n\n"
        + "Options:\n  -d, --dev      only for development\n  -h, --help     show this help\n  -V, --version  show the version\n";
    expect_false(parsed.is_err());
    expect_equal(parsed.value().value(), expected);
    parsed = parser.try_parse(["pep-package", "add", "-V"]);
    expect_false(parsed.is_err());
    expect_equal(parsed.value().value(), "pep-package 0.1\n");
    expect_true(parser.help().contains("Commands:\n  add     Adds a dependency\n  update  Updates dependencies\n"));
}

[Test]
closest_picks_the_nearest_candidate_within_two_edits() {
    var names = Array<String>();
    names.append("build");
    names.append("fmt");
    names.append("bulk");
    expect_equal(cli.closest("buidl", names).value(), "build");
    expect_equal(cli.closest("fm", names).value(), "fmt");
    # "bul" is one edit from "bulk" and two from "build": the nearer wins.
    expect_equal(cli.closest("bul", names).value(), "bulk");
    expect_false(cli.closest("package", names).is_value());
    expect_false(cli.closest("x", Array<String>()).is_value());
}
