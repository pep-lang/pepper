//! The `cli` module (runtime/cli/) in what a whole program shows: what
//! `parse` prints and the exit status, and the compile error for a struct
//! field `add_options` cannot declare. The parser itself is tested by the
//! `[Test]` functions in `runtime/cli/test/`.

use crate::support;
use crate::support::stdout_of;

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
fn struct_options_name_an_unsupported_field() {
    let error = support::compile_error(
        "import cli;\n\nstruct Options {\n    var count: int;\n}\n\ntest(): int {\n    cli.Parser(\"x\").add_options(Options());\n    return 0;\n}\n",
    );
    assert!(
        error.contains("error: 'add_options' cannot declare field 'count' of type 'int'; use bool, String, String? or String[]"),
        "{}",
        error
    );
}
