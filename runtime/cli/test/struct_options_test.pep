# The cli module's options declared by the fields of a struct
# (`add_options`, `cli.Option`, `cli.Positional`), alone and mixed with
# builder calls and commands.

import cli;

struct BuildOptions {
    [cli.Option("o", "the executable to write")]
    var output: String = "a.out";
    [cli.Option("v", "say more")]
    var verbose: bool;
    [cli.Option("I", "a directory to search")]
    var import_path: String[];
    [cli.Option(name = "opt-level", value_name = "LEVEL")]
    var level: String?;
    [cli.Option(required = true)]
    var target: String;
    [cli.Positional("the entry file")]
    var source: String;
    [cli.Positional("everything else")]
    var rest: String[];
}

[Test]
declares_options_from_a_struct() {
    var options = BuildOptions();
    var parser = cli.Parser("pepper", "Compiles a Pepper program");
    parser.add_options(options);
    var expected = "Compiles a Pepper program\n\n"
        + "usage: pepper [OPTIONS] --target <TARGET> <source> [rest]...\n\n"
        + "Arguments:\n"
        + "  <source>   the entry file\n"
        + "  <rest>...  everything else\n\n"
        + "Options:\n"
        + "  -o, --output <OUTPUT>            the executable to write [default: a.out]\n"
        + "  -v, --verbose                    say more\n"
        + "  -I, --import-path <IMPORT_PATH>  a directory to search [repeatable]\n"
        + "      --opt-level <LEVEL>\n"
        + "      --target <TARGET>            [required]\n"
        + "  -h, --help                       show this help\n";
    expect_equal(parser.help(), expected);

    var parsed = parser.try_parse(
        ["pepper", "--target", "x86", "-v", "-I", "a", "-Ib", "--opt-level=2", "main.pep", "p", "q"]
    );
    expect_false(parsed.is_err());
    expect_false(parsed.value().is_value());
    expect_equal(options.output, "a.out");
    expect_true(options.verbose);
    expect_equal(options.target, "x86");
    expect_equal(options.import_path.count, 2);
    expect_equal(options.import_path[1], "b");
    expect_equal(options.level.value_or(""), "2");
    expect_equal(options.source, "main.pep");
    expect_equal(options.rest.count, 2);

    # Every parse sets every field: what was left out goes back to its default.
    parsed = parser.try_parse(["pepper", "--target", "arm", "-o", "x", "s.pep"]);
    expect_false(parsed.is_err());
    expect_false(parsed.value().is_value());
    expect_equal(options.output, "x");
    expect_false(options.verbose);
    expect_equal(options.target, "arm");
    expect_true(options.import_path.is_empty);
    expect_false(options.level.is_value());
    expect_true(options.rest.is_empty);
    parser.try_parse(["pepper", "--target", "arm", "s.pep"]);
    expect_equal(options.output, "a.out");

    # Errors, help and a failed parse leave the fields as they were.
    expect_equal(parser.try_parse(["pepper", "s.pep"]).error().message, "missing required option '--target'");
    expect_equal(
        parser.try_parse(["pepper", "--verbos"]).error().message, "unknown option '--verbos'; did you mean '--verbose'?"
    );
    expect_true(parser.try_parse(["pepper", "--help"]).value().is_value());
    expect_equal(options.target, "arm");
    expect_equal(options.source, "s.pep");
}

struct Global {
    [cli.Option("v")]
    var verbose: bool;
}

struct AddOptions {
    [cli.Option("D", "a development dependency")]
    var dev: bool;
    [cli.Positional("the package", name = "package")]
    var name: String;
    [cli.Positional("the version")]
    var version: String = "latest";
}

[Test]
struct_options_mix_with_builder_calls_and_commands() {
    var global = Global();
    var add = AddOptions();
    var parser = cli.Parser("pkg");
    parser.add_options(global);
    var quiet = parser.flag("quiet", "q");
    var add_parser = parser.command("add", "Adds a dependency");
    add_parser.add_options(add);
    parser.command("update", "Updates the lock file");

    expect_equal(add_parser.usage(), "usage: pkg add [OPTIONS] <package> [version]");
    var parsed = parser.try_parse(["pkg", "-vq", "add", "-D", "yaml"]);
    expect_false(parsed.is_err());
    expect_false(parsed.value().is_value());
    expect_true(global.verbose);
    expect_true(quiet.is_set);
    expect_true(add.dev);
    expect_equal(add.name, "yaml");
    expect_equal(add.version, "latest");

    # A command that was not given leaves its struct alone.
    parsed = parser.try_parse(["pkg", "update"]);
    expect_false(parsed.is_err());
    expect_false(global.verbose);
    expect_equal(add.name, "yaml");
    expect_equal(parser.try_parse(["pkg", "add"]).error().message, "missing required argument '<package>'");
}
