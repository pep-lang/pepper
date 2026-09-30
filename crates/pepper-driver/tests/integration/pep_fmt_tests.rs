//! pep-fmt (`tools/pep-fmt`, written in Pepper) is compiled once and run on
//! every `.pep` file in the repository. For each file it must succeed, be
//! idempotent (formatting its own output changes nothing), and keep the
//! program's meaning: the compiler's parser must read the same AST from the
//! input and the output. Golden tests pin the style itself, and the tool's
//! own sources must already be formatted.

use clap::Parser;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::OnceLock;

use crate::support;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

/// Builds pep-fmt once per test process and returns the executable.
fn pep_fmt() -> &'static Path {
    static EXECUTABLE: OnceLock<PathBuf> = OnceLock::new();
    EXECUTABLE.get_or_init(|| {
        let root = repo_root();
        // chdir so runtime discovery resolves like the CLI.
        std::env::set_current_dir(&root).unwrap();
        let build = std::env::temp_dir().join(format!("pepper_pep_fmt_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&build);
        std::fs::create_dir_all(&build).unwrap();
        let out = build.join(if cfg!(windows) { "pep-fmt.exe" } else { "pep-fmt" });
        let options = pepper_driver::Options::parse_from([
            "pepper".to_string(),
            root.join("tools").join("pep-fmt").join("main.pep").to_string_lossy().into_owned(),
            "-I".to_string(),
            root.join("tools").to_string_lossy().into_owned(),
            "-o".to_string(),
            out.to_string_lossy().into_owned(),
            "--build".to_string(),
            build.join("obj").to_string_lossy().into_owned(),
        ]);
        let code = pepper_driver::run(options).unwrap_or_else(|e| panic!("pep-fmt failed to compile:\n{}", e));
        assert_eq!(code, 0, "the compiler exited with {}", code);
        out
    })
}

/// Runs pep-fmt on `source`: Ok(stdout) on success, Err(stderr) on failure.
fn format(source: &str) -> Result<String, String> {
    let mut child = Command::new(pep_fmt())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("run pep-fmt");
    let mut stdin = child.stdin.take().unwrap();
    let input = source.to_string();
    let writer = std::thread::spawn(move || stdin.write_all(input.as_bytes()));
    let output = child.wait_with_output().expect("wait for pep-fmt");
    writer.join().unwrap().expect("write to pep-fmt");
    let stdout = String::from_utf8(output.stdout).expect("pep-fmt wrote UTF-8");
    if output.status.success() {
        Ok(stdout)
    } else {
        Err(String::from_utf8_lossy(&output.stderr).into_owned())
    }
}

/// The compiler's AST of `source`, printed, with imports sorted: pep-fmt
/// sorts imports, and their order has no meaning.
fn ast(name: &str, source: &str) -> String {
    let module = pepper_parser::parser::parse_source(name, source).unwrap_or_else(|e| panic!("{}", e));
    let printed = module.to_string();
    let (mut imports, rest): (Vec<&str>, Vec<&str>) = printed.lines().partition(|l| l.starts_with("import "));
    imports.sort();
    imports.into_iter().chain(rest).collect::<Vec<_>>().join("\n")
}

fn pep_files(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in std::fs::read_dir(dir).unwrap().flatten() {
        let path = entry.path();
        if path.is_dir() {
            pep_files(&path, out);
        } else if path.extension().is_some_and(|e| e == "pep") {
            out.push(path);
        }
    }
}

fn repo_pep_files(folders: &[&str]) -> Vec<PathBuf> {
    let root = repo_root();
    let mut files = vec![];
    for folder in folders {
        pep_files(&root.join(folder), &mut files);
    }
    files.sort();
    files
}

fn check_file(path: &Path) -> Option<String> {
    let name = path.strip_prefix(repo_root()).unwrap_or(path).display().to_string();
    let source = std::fs::read_to_string(path).unwrap();
    let formatted = match format(&source) {
        Ok(text) => text,
        Err(e) => return Some(format!("{}: pep-fmt failed: {}", name, e)),
    };
    match format(&formatted) {
        Ok(again) if again == formatted => {}
        Ok(_) => return Some(format!("{}: formatting is not idempotent", name)),
        Err(e) => return Some(format!("{}: pep-fmt cannot read its own output: {}", name, e)),
    }
    if ast(&name, &source) != ast(&name, &formatted) {
        return Some(format!("{}: formatting changed the AST", name));
    }
    None
}

#[test]
fn pep_fmt_keeps_every_repository_file_meaning_and_is_idempotent() {
    let files = repo_pep_files(&["runtime", "docs/examples", "tests", "tools"]);
    assert!(files.len() > 100, "found only {} .pep files", files.len());
    pep_fmt();
    let failures: Vec<String> = support::parallel_map(&files, |path| check_file(path)).into_iter().flatten().collect();
    assert!(failures.is_empty(), "{} of {} files failed:\n{}", failures.len(), files.len(), failures.join("\n"));
}

#[test]
fn pep_fmt_sources_are_formatted() {
    let files = repo_pep_files(&["tools"]);
    let failures: Vec<String> = support::parallel_map(&files, |path| {
        let source = std::fs::read_to_string(path).unwrap();
        (format(&source).as_deref() != Ok(source.as_str())).then(|| path.display().to_string())
    })
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "not formatted with pep-fmt:\n{}", failures.join("\n"));
}

fn assert_formats(input: &str, expected: &str) {
    let actual = format(input).unwrap_or_else(|e| panic!("pep-fmt failed: {}", e));
    assert_eq!(actual, expected, "\n--- actual ---\n{}\n--- expected ---\n{}", actual, expected);
}

#[test]
fn pep_fmt_places_braces_attributes_and_declarations() {
    assert_formats(
        "[Test] [Target(OS(Linux))] export int add(int a, int b = 2)\n{\n  return a+b;\n}\n\
         struct Point { int x; var y: int = 0; construct(int x = 0) { this.x = x; }\n bool ==(Point other) { return x == other.x; }\n\
         int [](ulong i) { return x; }\n\
         static Point origin() { return Point(); } }\n",
        "[Test]\n[Target(OS(Linux))]\nexport add(a: int, b: int = 2): int {\n    return a + b;\n}\n\n\
         struct Point {\n    int x;\n    var y: int = 0;\n    construct(x: int = 0) {\n        this.x = x;\n    }\n    ==(other: Point): bool { return x == other.x; }\n\
         \x20   [](i: ulong): int { return x; }\n\
         \x20   static origin(): Point { return Point(); }\n}\n",
    );
}

#[test]
fn pep_fmt_adds_semicolons_and_keeps_one_line_bodies_and_else_as_written() {
    assert_formats(
        "main(): int {\n    for (var x in xs) { if x > 1 { continue } else if x < 0 { break; }\n    else { print(x) } }\n    return 0\n}\n",
        "main(): int {\n    for (var x in xs) {\n        if x > 1 { continue; } else if x < 0 { break; } else {\n            print(x);\n        }\n    }\n    return 0;\n}\n",
    );
    assert_formats(
        "import io\ntype T = int\nstruct S {\n    int x\n}\nextern int puts(char* s)\nvar limit = 3  # most\n",
        "import io;\ntype T = int;\n\nstruct S {\n    int x;\n}\n\nextern int puts(char* s);\nvar limit = 3;  # most\n",
    );
}

#[test]
fn pep_fmt_wraps_long_lines_after_commas_and_before_operators() {
    let input = "main(): int {\n    call(argument_number_one, argument_number_two, argument_number_three, argument_number_four, argument_number_five_xy);\n\
                 \x20   call(argument_number_one, argument_number_two, argument_number_three, argument_number_four, argument_number_five_is_long, x);\n\
                 \x20   if (first_condition_is_long(argument_value) and second_condition_is_long(argument_value) or third_condition(value)) { return 1; }\n    return 0;\n}\n";
    let expected = "main(): int {\n    call(\n        argument_number_one, argument_number_two, argument_number_three, argument_number_four, argument_number_five_xy\n    );\n\
                    \x20   call(\n        argument_number_one,\n        argument_number_two,\n        argument_number_three,\n        argument_number_four,\n        argument_number_five_is_long,\n        x\n    );\n\
                    \x20   if (first_condition_is_long(argument_value) and second_condition_is_long(argument_value)\n        or third_condition(value)) { return 1; }\n    return 0;\n}\n";
    assert_formats(input, expected);
}

#[test]
fn pep_fmt_breaks_before_operators_and_dots() {
    // Line breaks never end a statement, so a long expression breaks before
    // each operator, and a chain of three calls or more before each `.`.
    assert_formats(
        "main(): int {\n    total = first_value_that_is_long_enough + second_value_that_is_long_enough + third_value_that_is_long_and_longer_still;\n\
         \x20   var n = words.iterate().filter((w) => w.length() > 4).map((w) => w.length() * 2).collect_all_the_things_right_now_x();\n\
         \x20   File.stderr().write_string(\"a message that is long enough to need its own line, and then some more words to be sure\");\n    return 0;\n}\n",
        "main(): int {\n    total = first_value_that_is_long_enough\n        + second_value_that_is_long_enough\n        + third_value_that_is_long_and_longer_still;\n\
         \x20   var n = words\n        .iterate()\n        .filter((w) => w.length() > 4)\n        .map((w) => w.length() * 2)\n        .collect_all_the_things_right_now_x();\n\
         \x20   File.stderr().write_string(\n        \"a message that is long enough to need its own line, and then some more words to be sure\"\n    );\n    return 0;\n}\n",
    );
}

#[test]
fn pep_fmt_sorts_imports_and_aligns_trailing_comments() {
    assert_formats(
        "import \"zeta\";\nimport \"alpha\"; # a file\nimport io;\n\nconst A = 1; # one\nconst LONGER = 2;   # two\n",
        "import io;\nimport \"alpha\";  # a file\nimport \"zeta\";\n\nconst A = 1;       # one\nconst LONGER = 2;  # two\n",
    );
}

#[test]
fn pep_fmt_spaces_export_from_and_keeps_its_order() {
    assert_formats(
        "import \"b\";\nimport \"a\";\nexport   *   from \"zeta\";\n[Target(OS(Linux))] export  [ x as y,z ]  from   \"alpha\";\nexport * from io;\n",
        "import \"a\";\nimport \"b\";\nexport * from \"zeta\";\n[Target(OS(Linux))]\nexport [x as y, z] from \"alpha\";\nexport * from io;\n",
    );
}

#[test]
fn pep_fmt_keeps_comments_blank_lines_and_line_endings() {
    assert_formats(
        "# header\n\n\n\n## Doc.\nf(): int {\n    # before\n\n\n    return 0;\n    # after\n}\n# end\n",
        "# header\n\n## Doc.\nf(): int {\n    # before\n\n    return 0;\n    # after\n}\n# end\n",
    );
    assert_formats("main(): int {\r\n  return 0;\r\n}\r\n", "main(): int {\r\n    return 0;\r\n}\r\n");
}

#[test]
fn pep_fmt_reports_syntax_errors_with_their_location() {
    let error = format("main(): int {\n    return (1;\n}\n").unwrap_err();
    assert_eq!(error, "<stdin>:2:14: error: expected ')'\n");
}

#[test]
fn pep_fmt_keeps_character_literals_as_written() {
    assert_formats(
        "main(): int {\n    var q='\"';\n    if (q=='#' or q=='\\'' or q=='\\x7F') { return 1; }\n    return 0;\n}\n",
        "main(): int {\n    var q = '\"';\n    if (q == '#' or q == '\\'' or q == '\\x7F') { return 1; }\n    return 0;\n}\n",
    );
    let error = format("main(): int {\n    var c = 'a;\n}\n").unwrap_err();
    assert_eq!(error, "<stdin>:2:13: error: missing terminating ' character\n");
}

#[test]
fn pep_fmt_reads_optional_types_and_keeps_ternaries() {
    assert_formats(
        "struct S {\n    Token?  leaf;\n}\nf(x:int?):Array<int?> {\n    Node? a=x;\n    c ? d : e;\n    var g=h?i:j;\n    return k;\n}\n",
        "struct S {\n    Token? leaf;\n}\n\nf(x: int?): Array<int?> {\n    Node? a = x;\n    c ? d : e;\n    var g = h ? i : j;\n    return k;\n}\n",
    );
}
