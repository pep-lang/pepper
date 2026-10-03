//! `--emit-static` (#519): the program's source with each `static` block
//! replaced by what it emits. The copies must build into the same program.

use std::path::{Path, PathBuf};
use std::process::Command;

use crate::support;
use crate::support::{build_executable, output_text, parallel_map, repo_root, run_program};

/// A scratch directory for one test, empty.
fn scratch(test: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pepper_emit_static_{}_{}", test, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// Runs the compiler on `main` with `--emit-static` and `options`, writing
/// into `out`.
fn emit(main: &Path, options: &[&str], out: &Path) -> Result<i32, String> {
    use clap::Parser;
    let mut argv = vec!["pep-build".to_string(), main.to_string_lossy().into_owned(), "-o".to_string(), out.to_string_lossy().into_owned()];
    if !options.iter().any(|o| o.starts_with("--emit-static")) {
        argv.push("--emit-static".to_string());
    }
    argv.extend(options.iter().map(|o| o.to_string()));
    pepper_driver::run(pepper_driver::Options::parse_from(argv))
}

/// `main` built into `dir` and run: its output, then its exit status.
fn build_and_run(main: &Path, dir: &Path, name: &str) -> String {
    let exe = dir.join(if cfg!(windows) { format!("{name}.exe") } else { name.to_string() });
    build_executable(main, &[], &exe, &dir.join(format!("{name}.build")));
    let source = std::fs::read_to_string(main).unwrap();
    let output = run_program(&mut Command::new(&exe), &source).unwrap();
    format!("{}\nexit: {:?}", output_text(&output), output.status.code())
}

/// Writes `files` (path, text) into `dir`.
fn write_files(dir: &Path, files: &[(&str, &str)]) {
    for (path, text) in files {
        let path = dir.join(path);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }
}

const CONCRETE: &str = r#"struct Point {
    var x: int;
    var y: int;
}

sum(p: Point): int {
    var total = 0;
    static (total, p) {
        var n = 0;
        while (n < 3) {
            total += n * 10;
            n += 1;
        }
        for (var field in reflect.properties<Point>()) {
            if (field.index == 0) {
                continue;
            }
            {
                var doubled = field.get(p) * 2;
                if (doubled > 4) {
                    total += doubled;
                } else {
                    total -= 1;
                }
            }
            reflect.print(field.name);
        }
        if (reflect.is_struct<Point>()) {
            total += $"{reflect.name<Point>()}!".length;
        } else {
            total = 0;
        }
    }
    return total;
}

main(): int {
    var p = Point();
    p.x = 1;
    p.y = 5;
    print(sum(p));
    return 0;
}
"#;

#[test]
fn expands_for_if_while_nested_blocks_and_captures() {
    let dir = scratch("concrete");
    write_files(&dir, &[("main.pep", CONCRETE)]);
    let out = dir.join("out");
    assert_eq!(emit(&dir.join("main.pep"), &[], &out), Ok(0));
    let emitted = std::fs::read_to_string(out.join("main.pep")).unwrap();
    // Each `while` iteration and `for` pass is a block; the pass `continue`
    // skipped and the compile-time steps are gone; the `if` kept one branch.
    let expected = r#"sum(p: Point): int {
    var total = 0;
    # static (total, p) expanded from main.pep:8:5
    {
        {
            total += 0;
        }
        {
            total += 10;
        }
        {
            total += 20;
        }
        {
            {
                var doubled = p.y * 2;
                if (doubled > 4) {
                    total += doubled;
                } else {
                    total -= 1;
                }
            }
        }
        {
            total += 6;
        }
    }
    # end static
    return total;
}
"#;
    assert!(emitted.contains(expected), "{}", emitted);
    // Everything else is unchanged.
    assert!(emitted.starts_with(&CONCRETE[..CONCRETE.find("sum(").unwrap()]), "{}", emitted);
    assert!(emitted.ends_with(&CONCRETE[CONCRETE.find("main(): int").unwrap()..]), "{}", emitted);
    assert_eq!(build_and_run(&dir.join("main.pep"), &dir, "original"), build_and_run(&out.join("main.pep"), &dir, "emitted"));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn keep_writes_the_block_as_comments_above_its_expansion() {
    let dir = scratch("keep");
    write_files(&dir, &[("main.pep", CONCRETE)]);
    let out = dir.join("out");
    assert_eq!(emit(&dir.join("main.pep"), &["--emit-static=keep"], &out), Ok(0));
    let emitted = std::fs::read_to_string(out.join("main.pep")).unwrap();
    let expected = "    # static (total, p) {\n    #     var n = 0;\n    #     while (n < 3) {\n";
    assert!(emitted.contains(expected), "{}", emitted);
    assert!(emitted.contains("    #     }\n    # }\n    # static (total, p) expanded from main.pep:8:5\n    {\n"), "{}", emitted);
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn generic_functions_get_a_specialized_copy_per_use() {
    let dir = scratch("generic");
    let source = r#"struct Point {
    var x: int;
    var y: int;
}

struct Size {
    var width: int;
}

names<T>(value: T): String {
    var out = "";
    static (out, value) {
        for (var field in reflect.properties<T>()) {
            var copy: field.Type = field.get(value);
            out = out + $"{field.name}={copy} ";
        }
    }
    return out;
}

struct Box<T> {
    var value: T;

    count(): int {
        var n = 0;
        static (n) {
            for (var field in reflect.properties<T>()) {
                n += 1;
            }
        }
        return n;
    }
}

main(): int {
    var p = Point();
    p.x = 1;
    var s = Size();
    s.width = 7;
    print(names(p) + names(s));
    var b = Box<Point>();
    print(b.count());
    return 0;
}
"#;
    write_files(&dir, &[("main.pep", source)]);
    let out = dir.join("out");
    assert_eq!(emit(&dir.join("main.pep"), &[], &out), Ok(0));
    let emitted = std::fs::read_to_string(out.join("main.pep")).unwrap();
    // The generic function stays, followed by one override per type.
    let point = r#"
# 'names' specialized for T = Point, with its static blocks expanded
names<Point>(value: Point): String {
    var out = "";
    # static (out, value) expanded from main.pep:12:5 for T = Point
    {
        {
            var copy: int = value.x;
            out = out + $"x={copy} ";
        }
        {
            var copy: int = value.y;
            out = out + $"y={copy} ";
        }
    }
    # end static
    return out;
}
"#;
    assert!(emitted.contains(point), "{}", emitted);
    assert!(emitted.contains("names<Size>(value: Size): String {"), "{}", emitted);
    assert!(emitted.contains("names<T>(value: T): String {\n    var out = \"\";\n    static (out, value) {"), "{}", emitted);
    // A generic method keeps its block, with each expansion as comments.
    let method = "        # static (n) at main.pep:26:9 expands in each specialization:\n        # for T = Point\n        # {\n        #     {\n        #         n += 1;\n";
    assert!(emitted.contains(method), "{}", emitted);
    assert!(emitted.contains("        # end static\n        static (n) {\n"), "{}", emitted);
    assert_eq!(build_and_run(&dir.join("main.pep"), &dir, "original"), build_and_run(&out.join("main.pep"), &dir, "emitted"));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn cases_functions_and_set_round_trip() {
    let dir = scratch("cases");
    let source = r#"enum Shape {
    Circle(radius: int),
    Rect(width: int, height: int),
}

enum Color {
    Red,
    Green,
}

[Attribute]
struct Step {}

[Step]
first(): int {
    return 1;
}

struct Counter {
    var hits: int;
}

total(shape: Shape, color: Color, counter: Counter): int {
    var sum = 0;
    static (sum, shape, color, counter) {
        for (var case in reflect.cases<Shape>()) {
            if (case.matches(shape)) {
                for (var item in case.values) {
                    sum += item.get(shape) * (item.index + 1);
                }
            }
        }
        for (var case in reflect.cases<Color>()) {
            if (case.matches(color)) {
                sum += case.value * 100;
            }
        }
        for (var step in reflect.functions_with<Step>()) {
            sum += step.call();
        }
        for (var field in reflect.properties<Counter>()) {
            field.set(counter, sum);
        }
    }
    return sum;
}

main(): int {
    var counter = Counter();
    print(total(Shape.Rect(3, 4), Color.Green, counter));
    print(counter.hits);
    return 0;
}
"#;
    write_files(&dir, &[("main.pep", source)]);
    let out = dir.join("out");
    assert_eq!(emit(&dir.join("main.pep"), &[], &out), Ok(0));
    let emitted = std::fs::read_to_string(out.join("main.pep")).unwrap();
    for expected in [
        "if (shape is Shape.Rect) {",
        "sum += match (shape) { Shape.Rect(_, _pep_value) => _pep_value, else => __default<int>() } * (2);",
        "if (color == Color.Green) {",
        "sum += first();",
        "counter.hits = sum;",
    ] {
        assert!(emitted.contains(expected), "missing {:?} in\n{}", expected, emitted);
    }
    assert_eq!(build_and_run(&dir.join("main.pep"), &dir, "original"), build_and_run(&out.join("main.pep"), &dir, "emitted"));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn files_without_blocks_are_copied_and_originals_are_kept() {
    let dir = scratch("files");
    let helper = "# Unchanged.\nexport twice(n: int): int {\n    return n * 2;\n}\n";
    let main = "import \"helpers/math\" as math;\n\nmain(): int {\n    var n = 0;\n    static (n) {\n        n = 21;\n    }\n    print(math.twice(n));\n    return 0;\n}\n";
    write_files(&dir, &[("main.pep", main), ("helpers/math.pep", helper)]);
    // The default folder would be beside the program; name one.
    let out = dir.join("expanded");
    assert_eq!(emit(&dir.join("main.pep"), &[], &out), Ok(0));
    assert_eq!(std::fs::read_to_string(out.join("helpers/math.pep")).unwrap(), helper);
    assert_eq!(std::fs::read_to_string(dir.join("main.pep")).unwrap(), main);
    assert!(std::fs::read_to_string(out.join("main.pep")).unwrap().contains("    {\n        n = 21;\n    }\n    # end static\n"));
    assert_eq!(build_and_run(&out.join("main.pep"), &dir, "emitted"), "42\n\nexit: Some(0)");
    // Never over the originals.
    let error = emit(&dir.join("main.pep"), &[], &dir).unwrap_err();
    assert!(error.contains("would overwrite"), "{}", error);
    let _ = std::fs::remove_dir_all(&dir);
}

/// An error in a block stops `--emit-static` as it stops a build. An error
/// in what a block emits is found when the copy is built, at the line of
/// the copy that has it.
#[test]
fn errors_are_reported_in_the_block_or_in_the_copy() {
    let dir = scratch("errors");
    write_files(&dir, &[("bad.pep", "main(): int {\n    static {\n        reflect.error(\"not ready\");\n    }\n    return 0;\n}\n")]);
    let error = emit(&dir.join("bad.pep"), &[], &dir.join("bad")).unwrap_err();
    assert!(error.contains("bad.pep:3:17: error: not ready"), "{}", error);
    assert!(!dir.join("bad").exists());

    write_files(&dir, &[("main.pep", "main(): int {\n    var n = 0;\n    static (n) {\n        n = nope;\n    }\n    return n;\n}\n")]);
    let out = dir.join("out");
    assert_eq!(emit(&dir.join("main.pep"), &[], &out), Ok(0));
    use clap::Parser;
    let copy = out.join("main.pep");
    let exe = dir.join("main");
    let argv = ["pep-build", &copy.to_string_lossy(), "-o", &exe.to_string_lossy()];
    let error = pepper_driver::run(pepper_driver::Options::parse_from(argv)).unwrap_err();
    assert!(error.contains("main.pep:5:13: error: use of undeclared identifier 'nope'\n    5 |         n = nope;"), "{}", error);
    let _ = std::fs::remove_dir_all(&dir);
}

/// Every `docs/examples/reflection-*` program builds from its expanded copy
/// into one that prints the same.
#[test]
fn reflection_examples_round_trip() {
    let examples = repo_root().join("docs/examples");
    let mut programs: Vec<PathBuf> = std::fs::read_dir(&examples)
        .unwrap()
        .filter_map(|entry| entry.ok().map(|e| e.path()))
        .filter(|path| path.file_name().is_some_and(|name| name.to_string_lossy().starts_with("reflection-")))
        .map(|path| if path.is_dir() { path.join("main.pep") } else { path })
        .collect();
    programs.sort();
    assert!(programs.len() >= 8, "{:?}", programs);
    let failures: Vec<String> = parallel_map(&programs, |main| {
        let name = main.strip_prefix(&examples).unwrap().to_string_lossy().replace(['/', '\\', '.'], "_");
        let dir = scratch(&name);
        let out = dir.join("out");
        if let Err(error) = emit(main, &[], &out) {
            return Some(format!("{}: {}", name, error));
        }
        let emitted = out.join(main.file_name().unwrap());
        let text = std::fs::read_to_string(&emitted).unwrap();
        if text.contains("static (") && !text.contains("expanded from") {
            return Some(format!("{}: nothing expanded:\n{}", name, text));
        }
        let (original, copy) = (build_and_run(main, &dir, "original"), build_and_run(&emitted, &dir, "emitted"));
        let _ = std::fs::remove_dir_all(&dir);
        (original != copy).then(|| format!("{}: the expanded copy prints\n{}\ninstead of\n{}", name, copy, original))
    })
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "{}", failures.join("\n\n"));
}

/// Formatted by `pep-fmt`, as the compiler does when it finds it, the
/// copies still build and are what `pep-fmt --check` wants.
#[test]
fn formatted_copies_still_build() {
    let pep_fmt = support::pepper_tool("pep-fmt");
    let dir = scratch("formatted");
    let main = repo_root().join("docs/examples/reflection-cases.pep");
    let out = dir.join("out");
    assert_eq!(emit(&main, &[], &out), Ok(0));
    let emitted = out.join("reflection-cases.pep");
    let status = Command::new(pep_fmt).arg("-w").arg(&emitted).status().unwrap();
    assert!(status.success());
    let check = Command::new(pep_fmt).arg("--check").arg(&emitted).output().unwrap();
    assert!(check.status.success() && check.stdout.is_empty(), "{}", output_text(&check));
    assert_eq!(build_and_run(&main, &dir, "original"), build_and_run(&emitted, &dir, "emitted"));
    let _ = std::fs::remove_dir_all(&dir);
}
