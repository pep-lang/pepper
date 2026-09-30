//! The build cache: a program is emitted as one object per compilation
//! unit, and a unit whose sources are unchanged comes from the cache without
//! generating its code (see INTERNALS.md §4.3). Every build here verifies
//! its hits (`--verify-cache`): a hit unit's code is generated anyway and
//! must match the cached object's.

use clap::Parser;
use pepper_driver::cache::Outcome;
use pepper_driver::UnitObject;
use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

/// A fresh directory for one test.
fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pepper_cache_{}_{}", name, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// Build `entry` with the cache at `cache` into `build`, verifying hits.
fn build_entry(entry: &Path, cache: &Path, build: &Path) -> Vec<UnitObject> {
    // chdir so namespaces (paths from the project) resolve like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    let options = pepper_driver::Options::parse_from([
        "pepper".to_string(),
        entry.to_string_lossy().into_owned(),
        "--cache".to_string(),
        cache.to_string_lossy().into_owned(),
        "--build".to_string(),
        build.to_string_lossy().into_owned(),
        "--verify-cache".to_string(),
    ]);
    let (module, program) = pepper_driver::compiler::compile_program(&options).unwrap();
    pepper_driver::objects(&options, &module, &program, build, "main").unwrap()
}

/// Build the documentation example `example`.
fn build(example: &str, cache: &Path, build: &Path) -> Vec<UnitObject> {
    build_entry(&PathBuf::from(format!("docs/examples/{}.pep", example)), cache, build)
}

fn outcomes(objects: &[UnitObject]) -> Vec<(String, Option<Outcome>)> {
    objects.iter().map(|o| (o.unit.clone(), o.outcome)).collect()
}

/// The outcome of the unit `unit`.
fn outcome(objects: &[UnitObject], unit: &str) -> Option<Outcome> {
    objects
        .iter()
        .find(|o| o.unit == unit)
        .unwrap_or_else(|| panic!("no unit '{}' in {:?}", unit, outcomes(objects)))
        .outcome
}

/// Write `files` (name, text) into `dir`.
fn write(dir: &Path, files: &[(&str, &str)]) {
    for (name, text) in files {
        std::fs::write(dir.join(name), text).unwrap();
    }
}

#[test]
fn unchanged_units_come_from_the_cache() {
    let dir = scratch("reuse");
    let cache = dir.join("cache");
    let first = build("threads-basics", &cache, &dir.join("a"));
    assert!(first.len() > 3, "expected several units: {:?}", outcomes(&first));
    for object in &first {
        let expected = if object.unit == "__program" { None } else { Some(Outcome::Miss) };
        assert_eq!(object.outcome, expected, "{:?}", outcomes(&first));
        assert!(object.path.is_file(), "{} was not written", object.path.display());
    }
    let second = build("threads-basics", &cache, &dir.join("b"));
    for object in second.iter().filter(|o| o.unit != "__program") {
        assert_eq!(object.outcome, Some(Outcome::Hit), "{:?}", outcomes(&second));
    }
    // Byte-identical to the first build's objects.
    for (a, b) in first.iter().zip(&second) {
        assert_eq!(std::fs::read(&a.path).unwrap(), std::fs::read(&b.path).unwrap(), "{} differs", a.unit);
    }
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn the_runtime_unit_is_shared_between_programs() {
    let dir = scratch("shared");
    let cache = dir.join("cache");
    assert_eq!(outcome(&build("threads-basics", &cache, &dir.join("a")), "prelude"), Some(Outcome::Miss));
    // Another program has the same runtime sources, so the same key.
    let other = build("tutorial-hello", &cache, &dir.join("b"));
    assert_eq!(outcome(&other, "prelude"), Some(Outcome::Hit), "{:?}", outcomes(&other));
    assert_eq!(outcome(&other, "docs/examples/tutorial_hello"), Some(Outcome::Miss));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_record_that_does_not_match_is_a_miss() {
    let dir = scratch("stale");
    let cache = dir.join("cache");
    build("tutorial-hello", &cache, &dir.join("a"));
    let record = std::fs::read_dir(cache.join("v1"))
        .unwrap()
        .flatten()
        .map(|e| e.path().join("docs/examples/tutorial_hello.json"))
        .find(|p| p.is_file())
        .expect("the unit's record");
    std::fs::write(&record, "{\"key\": \"stale\", \"bitcode\": \"stale\"}\n").unwrap();
    let again = build("tutorial-hello", &cache, &dir.join("b"));
    assert_eq!(outcome(&again, "docs/examples/tutorial_hello"), Some(Outcome::Miss));
    assert_eq!(outcome(&again, "prelude"), Some(Outcome::Hit));
    assert_eq!(outcome(&build("tutorial-hello", &cache, &dir.join("c")), "docs/examples/tutorial_hello"), Some(Outcome::Hit));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn an_edit_rebuilds_only_its_unit_and_the_units_that_import_it() {
    let dir = scratch("edit");
    let (cache, project) = (dir.join("cache"), dir.join("project"));
    std::fs::create_dir_all(&project).unwrap();
    write(
        &project,
        &[
            ("lib.pep", "export twice(x: int): int { return x * 2; }\n"),
            ("other.pep", "export three(): int { return 3; }\n"),
            ("main.pep", "import \"lib\";\nimport \"other\";\nmain(): int { return twice(three()) - 6; }\n"),
        ],
    );
    let entry = project.join("main.pep");
    build_entry(&entry, &cache, &dir.join("a"));
    // The entry file changes: only its unit misses.
    write(&project, &[("main.pep", "import \"lib\";\nimport \"other\";\nmain(): int { return twice(three()) - 7 + 1; }\n")]);
    let edited = build_entry(&entry, &cache, &dir.join("b"));
    assert_eq!(outcome(&edited, "main"), Some(Outcome::Miss), "{:?}", outcomes(&edited));
    assert_eq!(outcome(&edited, "lib"), Some(Outcome::Hit));
    assert_eq!(outcome(&edited, "other"), Some(Outcome::Hit));
    assert_eq!(outcome(&edited, "prelude"), Some(Outcome::Hit));
    // A body in lib changes: lib misses, main (which imports lib) is
    // generated again but its code, which only calls `twice`, is the same.
    write(&project, &[("lib.pep", "export twice(x: int): int { return x + x; }\n")]);
    let body = build_entry(&entry, &cache, &dir.join("c"));
    assert_eq!(outcome(&body, "lib"), Some(Outcome::Miss), "{:?}", outcomes(&body));
    assert_eq!(outcome(&body, "main"), Some(Outcome::SameCode));
    assert_eq!(outcome(&body, "other"), Some(Outcome::Hit));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_comment_edit_reuses_the_object() {
    let dir = scratch("comment");
    let (cache, project) = (dir.join("cache"), dir.join("project"));
    std::fs::create_dir_all(&project).unwrap();
    let entry = project.join("main.pep");
    write(&project, &[("main.pep", "main(): int { return 0; }\n")]);
    build_entry(&entry, &cache, &dir.join("a"));
    write(&project, &[("main.pep", "# The entry point.\nmain(): int { return 0; }\n")]);
    let edited = build_entry(&entry, &cache, &dir.join("b"));
    assert_eq!(outcome(&edited, "main"), Some(Outcome::SameCode), "{:?}", outcomes(&edited));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn an_override_in_a_file_a_unit_does_not_import_is_part_of_its_key() {
    // user.pep instantiates `twice<Point>`, whose `describe<Point>` call
    // reaches the override in extra.pep (which can see the generic it
    // overrides), though user.pep never imports extra.pep.
    let dir = scratch("override");
    let (cache, project) = (dir.join("cache"), dir.join("project"));
    std::fs::create_dir_all(&project).unwrap();
    write(
        &project,
        &[
            ("lib.pep", "export describe<T>(v: T): int { return 1; }\nexport twice<T>(v: T): int { return describe<T>(v) * 2; }\n"),
            ("geo.pep", "export struct Point { var x: int; }\n"),
            ("user.pep", "import \"lib\";\nimport \"geo\";\nexport measure(): int { return twice<Point>(Point()); }\n"),
            ("extra.pep", "import \"lib\";\nimport \"geo\";\nexport extra(): int { return 0; }\n"),
            ("main.pep", "import \"user\";\nimport \"extra\";\nmain(): int { return measure() + extra(); }\n"),
        ],
    );
    let entry = project.join("main.pep");
    build_entry(&entry, &cache, &dir.join("a"));
    write(&project, &[("extra.pep", "import \"lib\";\nimport \"geo\";\ndescribe<Point>(p: Point): int { return 20; }\nexport extra(): int { return 0; }\n")]);
    // Verifying: had user.pep's key left extra.pep out, its hit would fail.
    let overridden = build_entry(&entry, &cache, &dir.join("b"));
    assert_eq!(outcome(&overridden, "user"), Some(Outcome::Miss), "{:?}", outcomes(&overridden));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn concurrent_builds_share_one_cache() {
    let dir = scratch("concurrent");
    let cache = dir.join("cache");
    // Every build writes or reads the same units at once; the unit locks
    // keep each object whole.
    let builds: Vec<Vec<UnitObject>> = std::thread::scope(|scope| {
        let handles: Vec<_> = (0..4)
            .map(|i| {
                let (cache, out) = (cache.clone(), dir.join(format!("b{}", i)));
                std::thread::Builder::new()
                    .stack_size(8 << 20)
                    .spawn_scoped(scope, move || build("threads-basics", &cache, &out))
                    .unwrap()
            })
            .collect();
        handles.into_iter().map(|h| h.join().unwrap()).collect()
    });
    for objects in &builds[1..] {
        for (a, b) in builds[0].iter().zip(objects) {
            assert_eq!(std::fs::read(&a.path).unwrap(), std::fs::read(&b.path).unwrap(), "{} differs", a.unit);
        }
    }
    let _ = std::fs::remove_dir_all(&dir);
}
