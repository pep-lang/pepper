//! The `cli` module (runtime/cli/): option and argument parsing, the help
//! and version text, clang-style errors, and subcommands. The JIT tests
//! call `try_parse` and return 0 on success or a distinct negative code per
//! check, leaving no allocation behind; the linked tests run `parse` for
//! what it prints and the exit status.

use crate::support;
use crate::support::{jit_census, stdout_of};

fn run(source: &str) -> i32 {
    let (result, leaked) = jit_census(source);
    assert_eq!(leaked, 0, "allocations leaked or double-released");
    result
}

#[test]
fn parses_options_and_arguments() {
    assert_eq!(
        run(r##"
import cli;

test(): int {
    var parser = cli.Parser("pepper", "Compiles a Pepper program");
    var output = parser.option("output", "o", "the executable to write", default_value = "a.out");
    var level = parser.option("level", "O", "optimization level");
    var imports = parser.multiple("import-path", "I", "a directory to search");
    var verbose = parser.flag("verbose", "v", "say more");
    var quiet = parser.flag("quiet", "q", "say less");
    var source = parser.positional("source", "the entry file");
    var rest = parser.positionals("rest", "everything else");

    # Defaults, and nothing set.
    if (parser.try_parse(["pepper", "main.pep"]).value()) { return -1; }
    if (source.value() != "main.pep") { return -2; }
    if (output.is_set or output.value() != "a.out") { return -3; }
    if (level.is_set or level.value_or("2") != "2") { return -4; }
    if (verbose.is_set or imports.is_set or rest.is_set) { return -5; }

    # Every spelling of a value.
    var parsed = parser.try_parse(["pepper", "--output", "x", "-O3", "-I", "a", "--import-path=b", "-Ic", "-I=d", "main.pep"]);
    if (parsed.is_err() or parsed.value()) { return -10; }
    if (output.value() != "x" or level.value() != "3") { return -11; }
    var paths = imports.values();
    if (paths.count != 4 or paths[0] != "a" or paths[1] != "b" or paths[2] != "c" or paths[3] != "d") { return -12; }

    # `--output=` sets an empty value; the last value wins.
    parser.try_parse(["pepper", "--output=", "s"]);
    if (!output.is_set or output.value_or("fallback") != "") { return -13; }
    parser.try_parse(["pepper", "-o", "one", "--output", "two", "s"]);
    if (output.value() != "two") { return -14; }

    # Clustered short flags, counted; a value may start with '-'.
    parser.try_parse(["pepper", "-vqv", "-o", "-weird", "s"]);
    if (verbose.occurrences != 2 or quiet.occurrences != 1) { return -20; }
    if (output.value() != "-weird") { return -21; }
    parser.try_parse(["pepper", "-vo", "out", "s"]);
    if (verbose.occurrences != 1 or output.value() != "out") { return -22; }

    # Positional lists take the rest; options mix in; '--' ends options;
    # '-' alone is positional.
    parser.try_parse(["pepper", "s", "a", "-v", "b", "--", "-c", "--d", "-"]);
    var others = rest.values();
    if (others.count != 5 or others[0] != "a" or others[1] != "b" or others[2] != "-c" or others[3] != "--d" or others[4] != "-") {
        return -30;
    }
    if (verbose.occurrences != 1) { return -31; }

    # A new parse forgets the last one.
    parser.try_parse(["pepper", "t"]);
    if (verbose.is_set or rest.is_set or imports.is_set or output.is_set or source.value() != "t") { return -40; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn reports_errors() {
    assert_eq!(
        run(r##"
import cli;

error_of(parser: cli.Parser, args: String[]): String {
    var result = parser.try_parse(args);
    if (result.is_ok()) {
        return "<ok>";
    }
    return result.error().message;
}

test(): int {
    var parser = cli.Parser("tool");
    parser.option("output", "o", "where");
    parser.option("target", "", "for what", required = true);
    parser.flag("verbose", "v", "say more");
    parser.positional("source", "the input");
    parser.positional("extra", "more", required = false);

    if (error_of(parser, ["tool", "--target", "x", "s"]) != "<ok>") { return -1; }
    if (error_of(parser, ["tool", "--target", "x", "s", "e", "f"]) != "unexpected argument 'f'") { return -2; }
    if (error_of(parser, ["tool", "--target", "x", "--outptu", "a", "s"])
        != "unknown option '--outptu'; did you mean '--output'?") { return -3; }
    if (error_of(parser, ["tool", "--target", "x", "--zzzzzz", "s"]) != "unknown option '--zzzzzz'") { return -4; }
    if (error_of(parser, ["tool", "--hlep"]) != "unknown option '--hlep'; did you mean '--help'?") { return -5; }
    if (error_of(parser, ["tool", "--target", "x", "-x", "s"]) != "unknown option '-x'") { return -6; }
    if (error_of(parser, ["tool", "--target", "x", "-vé", "s"]) != "unknown option '-é'") { return -7; }
    if (error_of(parser, ["tool", "--target", "x", "s", "-o"]) != "missing value for '-o'") { return -8; }
    if (error_of(parser, ["tool", "s", "--target"]) != "missing value for '--target'") { return -9; }
    if (error_of(parser, ["tool", "--target", "x", "--verbose=yes", "s"]) != "option '--verbose' takes no value") { return -10; }
    if (error_of(parser, ["tool", "s"]) != "missing required option '--target'") { return -11; }
    if (error_of(parser, ["tool", "--target", "x"]) != "missing required argument '<source>'") { return -12; }
    # No version declared: --version is an unknown option.
    if (error_of(parser, ["tool", "--version"]) != "unknown option '--version'") { return -13; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn generates_help_and_version() {
    assert_eq!(
        run(r##"
import cli;

test(): int {
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
    if (parser.help() != expected) {
        print(parser.help());
        return -1;
    }
    # An error before --help is reported; --help alone needs nothing else.
    var help = parser.try_parse(["pepper", "--bogus=1", "--help"]);
    if (help.is_ok()) { return -2; }
    help = parser.try_parse(["pepper", "-h"]);
    if (help.is_err() or help.value().value() != expected) { return -3; }
    var version = parser.try_parse(["pepper", "-V"]);
    if (version.is_err() or version.value().value() != "pepper 0.2.1\n") { return -4; }
    version = parser.try_parse(["pepper", "--version"]);
    if (version.is_err() or version.value().value() != "pepper 0.2.1\n") { return -5; }

    # A program's own -h and -V take the short names from help and version.
    var custom = cli.Parser("net", version = "1");
    var host = custom.option("host", "h", "the host");
    custom.flag("verbose", "V", "say more");
    if (custom.help() != "usage: net [OPTIONS]\n\nOptions:\n  -h, --host <HOST>  the host\n  -V, --verbose      say more\n      --help         show this help\n      --version      show the version\n") {
        print(custom.help());
        return -6;
    }
    var parsed = custom.try_parse(["net", "-h", "example.com"]);
    if (parsed.is_err() or parsed.value() or host.value() != "example.com") { return -7; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn dispatches_subcommands() {
    assert_eq!(
        run(r##"
import cli;

test(): int {
    var parser = cli.Parser("pep-package", "Manages packages", version = "0.1");
    var verbose = parser.flag("verbose", "v", "say more");
    var add = parser.command("add", "Adds a dependency");
    var name = add.positional("name", "the package");
    var dev = add.flag("dev", "d", "only for development");
    var update = parser.command("update", "Updates dependencies");
    var packages = update.positionals("packages", "the packages; all when none");

    var parsed = parser.try_parse(["pep-package", "-v", "add", "-d", "yaml"]);
    if (parsed.is_err() or parsed.value()) { return -1; }
    if (!parser.is_selected or !add.is_selected or update.is_selected) { return -2; }
    if (!verbose.is_set or !dev.is_set or name.value() != "yaml") { return -3; }

    parsed = parser.try_parse(["pep-package", "update", "a", "b"]);
    if (parsed.is_err() or add.is_selected or !update.is_selected) { return -4; }
    if (packages.values().count != 2 or verbose.is_set or dev.is_set) { return -5; }

    # The parent's options go before the command.
    parsed = parser.try_parse(["pep-package", "add", "-v", "x"]);
    if (parsed.is_ok() or parsed.error().message != "unknown option '-v'") { return -6; }
    parsed = parser.try_parse(["pep-package"]);
    if (parsed.is_ok() or parsed.error().message != "missing command: expected 'add' or 'update'") { return -7; }
    parsed = parser.try_parse(["pep-package", "updat"]);
    if (parsed.is_ok() or parsed.error().message != "unknown command 'updat'; did you mean 'update'?") { return -8; }
    parsed = parser.try_parse(["pep-package", "add"]);
    if (parsed.is_ok() or parsed.error().message != "missing required argument '<name>'") { return -9; }

    # A command's help, and the version from the top.
    parsed = parser.try_parse(["pep-package", "add", "--help"]);
    var expected = "Adds a dependency\n\n"
        + "usage: pep-package add [OPTIONS] <name>\n\n"
        + "Arguments:\n  <name>  the package\n\n"
        + "Options:\n  -d, --dev      only for development\n  -h, --help     show this help\n  -V, --version  show the version\n";
    if (parsed.is_err() or parsed.value().value() != expected) {
        print(parsed.value().value());
        return -10;
    }
    parsed = parser.try_parse(["pep-package", "add", "-V"]);
    if (parsed.is_err() or parsed.value().value() != "pep-package 0.1\n") { return -11; }
    if (!parser.help().contains("Commands:\n  add     Adds a dependency\n  update  Updates dependencies\n")) { return -12; }
    return 0;
}
"##),
        0
    );
}

const PARSE_PROGRAM: &str = r##"
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
"##;

/// `parse` prints the help and exits with 0, and writes an error with the
/// failing command's usage to standard error.
#[test]
fn parse_prints_help_and_errors() {
    let output = support::run_linked("cli_parse_ok", PARSE_PROGRAM, |command| {
        command.args(["add", "yaml"]);
    });
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout_of(&output), "adding yaml\n");

    let output = support::run_linked("cli_parse_help", PARSE_PROGRAM, |command| {
        command.arg("--help");
    });
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(
        stdout_of(&output),
        "Manages packages\n\nusage: pkg [OPTIONS] <COMMAND>\n\nCommands:\n  add  Adds a dependency\n\nOptions:\n  -h, --help  show this help\n"
    );

    let output = support::run_linked("cli_parse_error", PARSE_PROGRAM, |command| {
        command.args(["add"]);
    });
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(stdout_of(&output), "");
    assert_eq!(
        String::from_utf8_lossy(&output.stderr).replace('\r', ""),
        "pkg: error: missing required argument '<name>'\nusage: pkg add [OPTIONS] <name>\nRun 'pkg add --help' for more information.\n"
    );
}

#[test]
fn closest_picks_the_nearest_candidate_within_two_edits() {
    assert_eq!(
        run(r##"
import cli;

test(): int {
    var names = Array<String>();
    names.append("build");
    names.append("fmt");
    names.append("bulk");
    if (cli.closest("buidl", names).value() != "build") { return -1; }
    if (cli.closest("fm", names).value() != "fmt") { return -2; }
    # "bul" is one edit from "bulk" and two from "build": the nearer wins.
    if (cli.closest("bul", names).value() != "bulk") { return -3; }
    if (cli.closest("package", names).is_some()) { return -4; }
    if (cli.closest("x", Array<String>()).is_some()) { return -5; }
    return 0;
}
"##),
        0
    );
}
