//! Projects (`pep.toml`, #217): `pep-build` with no source file builds the
//! project its `[build]` table describes, and an import of a dependency
//! finds it in the project's `.pep/deps` (or, for a `path` dependency, its
//! folder), resolved against the `pep.toml` of the package the importing
//! file belongs to.

use std::path::{Path, PathBuf};
use std::process::Command;

use crate::support::{repo_root, run_program, stdout_of};
use clap::Parser;

/// A fresh project folder for `test`, holding `files` (path, text).
fn project(test: &str, files: &[(&str, &str)]) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pepper_project_{}_{}", test, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    for (name, text) in files {
        let path = dir.join(name);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }
    dir
}

/// Runs `pep-build` with `args` in the folder `cwd`, as the command line
/// would: the project applies first.
fn build_in(cwd: &Path, args: &[&str]) -> Result<i32, String> {
    // Runtime discovery resolves like the CLI's in a checkout.
    std::env::set_current_dir(repo_root()).unwrap();
    let argv = std::iter::once("pep-build").chain(args.iter().copied());
    let mut options = pepper_driver::Options::parse_from(argv);
    options.apply_project_in(cwd)?;
    pepper_driver::run(options)
}

fn executable(dir: &Path, name: &str) -> PathBuf {
    dir.join(if cfg!(windows) { format!("{name}.exe") } else { name.to_string() })
}

const GEOMETRY: &str = "export area(w: int, h: int): int {\n    return w * h;\n}\n";

#[test]
fn builds_the_project_with_no_source_file() {
    let main = r#"
import geo;
import geo.shapes;
import util;
import local;

main(): int {
    print("{0} {1} {2} {3}", geo.area(3, 4), shapes.sides(), util.twice(5), local.one());
    return 0;
}
"#;
    let dir = project(
        "build",
        &[
            (
                "app/pep.toml",
                "[package]\nname = \"demo\"\nversion = \"0.1.0\"\n\n[build]\nentry = \"src/main.pep\"\ninclude = [\"vendor\"]\n\n\
                 [dependencies]\ngeo = { github = \"someone/geometry\", version = \"1.0\" }\nlocal = { path = \"../local\" }\n",
            ),
            ("app/src/main.pep", main),
            ("app/vendor/util/module.pep", "export twice(x: int): int {\n    return x * 2;\n}\n"),
            ("app/.pep/deps/github.com/someone/geometry/module.pep", GEOMETRY),
            ("app/.pep/deps/github.com/someone/geometry/shapes/module.pep", "export sides(): int {\n    return 4;\n}\n"),
            ("local/module.pep", "export one(): int {\n    return 1;\n}\n"),
        ],
    );
    let app = dir.join("app");
    // From a folder inside the project, as from its root.
    assert_eq!(build_in(&app.join("src"), &[]), Ok(0));
    let built = executable(&app, "demo");
    assert!(app.join(".pep").join("build").is_dir(), "the build goes in the project's .pep");
    let output = run_program(&mut Command::new(&built), main).unwrap();
    assert_eq!(stdout_of(&output), "12 4 10 1\n");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_dependency_imports_its_own_dependencies() {
    // `app` names `someone/geometry` `geo`; geometry names `other/numbers`
    // `numbers`, and app names it `nums`: one copy serves both names.
    let main = r#"
import geo;
import nums;

main(): int {
    print("{0} {1}", geo.double_area(2, 3), nums.TEN);
    return 0;
}
"#;
    let dir = project(
        "transitive",
        &[
            (
                "pep.toml",
                "[package]\nname = \"app\"\n\n[dependencies]\ngeo = { github = \"someone/geometry\" }\nnums = { codeberg = \"other/numbers\" }\n",
            ),
            ("main.pep", main),
            (".pep/deps/github.com/someone/geometry/pep.toml", "[package]\nname = \"geometry\"\n\n[dependencies]\nnumbers = { codeberg = \"other/numbers\" }\n"),
            (
                ".pep/deps/github.com/someone/geometry/module.pep",
                "import numbers;\n\nexport double_area(w: int, h: int): int {\n    return numbers.twice(w * h);\n}\n",
            ),
            (".pep/deps/codeberg.org/other/numbers/pep.toml", "[package]\nname = \"numbers\"\n"),
            (
                ".pep/deps/codeberg.org/other/numbers/module.pep",
                "export const TEN = 10;\n\nexport twice(x: int): int {\n    return x * 2;\n}\n",
            ),
        ],
    );
    assert_eq!(build_in(&dir, &[]), Ok(0));
    let output = run_program(&mut Command::new(executable(&dir, "app")), main).unwrap();
    assert_eq!(stdout_of(&output), "12 10\n");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_source_file_in_a_project_uses_its_dependencies() {
    let main = "import geo;\n\nmain(): int {\n    return geo.area(2, 3) - 6;\n}\n";
    let dir = project(
        "file",
        &[
            ("pep.toml", "[package]\nname = \"app\"\n\n[dependencies]\ngeo = { gitlab = \"group/sub/geometry\" }\n"),
            ("tools/main.pep", main),
            (".pep/deps/gitlab.com/group/sub/geometry/module.pep", GEOMETRY),
        ],
    );
    let out = executable(&dir, "tool");
    let entry = dir.join("tools").join("main.pep");
    assert_eq!(build_in(&dir, &[entry.to_str().unwrap(), "-o", out.to_str().unwrap()]), Ok(0));
    assert!(run_program(&mut Command::new(&out), main).unwrap().status.success());
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn without_a_source_file_or_a_project_it_says_so() {
    let dir = project("none", &[("readme.txt", "")]);
    let error = build_in(&dir, &[]).unwrap_err();
    assert!(error.starts_with("no source files provided, and no pep.toml in "), "{}", error);
    let dir2 = project("no_entry", &[("pep.toml", "[package]\nname = \"app\"\n")]);
    let error = build_in(&dir2, &[]).unwrap_err();
    assert!(error.starts_with("cannot find the project's entry file "), "{}", error);
    assert!(error.ends_with(&format!("set 'entry' in '[build]' of {}", dir2.join("pep.toml").display())), "{}", error);
    let _ = std::fs::remove_dir_all(&dir);
    let _ = std::fs::remove_dir_all(&dir2);
}
