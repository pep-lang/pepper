//! The build cache: a program is emitted as one object per compilation
//! unit, and a unit whose sources are unchanged comes from the cache without
//! generating its code or checking its bodies (see INTERNALS.md §4.3). Most
//! builds here verify the cache (`--verify-cache`): a hit unit's code is
//! generated anyway and must match the cached object's, and every other
//! unit must come out the same when sema skips the hit units' bodies.

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

/// Build `entry` with the cache at `cache` into `build`, verifying the cache.
fn build_entry(entry: &Path, cache: &Path, build: &Path) -> Vec<UnitObject> {
    compile_entry(entry, cache, build, true).1
}

/// Build `entry` with the cache at `cache` into `build`, verifying the
/// cache when `verify`: the module sema produced and the objects.
fn compile_entry(entry: &Path, cache: &Path, build: &Path, verify: bool) -> (pepper_sema::model::Module, Vec<UnitObject>) {
    // chdir so namespaces (paths from the project) resolve like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    let mut args = vec![
        "pepper".to_string(),
        entry.to_string_lossy().into_owned(),
        "--cache".to_string(),
        cache.to_string_lossy().into_owned(),
        "--build".to_string(),
        build.to_string_lossy().into_owned(),
    ];
    // Not verifying overrides PEPPER_CACHE_VERIFY, which CI sets.
    args.push(if verify { "--verify-cache" } else { "--no-verify-cache" }.to_string());
    let options = pepper_driver::Options::parse_from(args);
    let compiled = pepper_driver::compiler::compile_for_objects(&options, &pepper_driver::units_dir(build, "main")).unwrap();
    let objects = pepper_driver::objects(&options, &compiled.module, compiled.trial.as_ref(), &compiled.interfaces, &compiled.program, build, "main")
        .unwrap();
    (compiled.module, objects)
}

/// Whether sema kept the body of the function `name`.
fn has_body(module: &pepper_sema::model::Module, name: &str) -> bool {
    module.functions.iter().find(|f| f.name == name).unwrap_or_else(|| panic!("no function '{}'", name)).body.is_some()
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
fn an_edit_rebuilds_only_its_unit_and_the_units_whose_inputs_changed() {
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
    // A body in lib changes: lib misses, but lib's interface is the same,
    // so main (which imports lib) is a hit (early cutoff).
    write(&project, &[("lib.pep", "export twice(x: int): int { return x + x; }\n")]);
    let body = build_entry(&entry, &cache, &dir.join("c"));
    assert_eq!(outcome(&body, "lib"), Some(Outcome::Miss), "{:?}", outcomes(&body));
    assert_eq!(outcome(&body, "main"), Some(Outcome::Hit), "{:?}", outcomes(&body));
    assert_eq!(outcome(&body, "other"), Some(Outcome::Hit));
    // A comment moves every declaration of lib: positions are not part of
    // its interface.
    write(&project, &[("lib.pep", "# Doubling.\n\nexport twice(x: int): int { return x + x; }\n")]);
    let moved = build_entry(&entry, &cache, &dir.join("d"));
    assert_eq!(outcome(&moved, "main"), Some(Outcome::Hit), "{:?}", outcomes(&moved));
    // Its signature changes: main is generated again.
    write(&project, &[("lib.pep", "export twice(x: long): int { return (x + x) as int; }\n")]);
    let signature = build_entry(&entry, &cache, &dir.join("e"));
    assert_eq!(outcome(&signature, "lib"), Some(Outcome::Miss), "{:?}", outcomes(&signature));
    assert_ne!(outcome(&signature, "main"), Some(Outcome::Hit), "{:?}", outcomes(&signature));
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
                    .stack_size(pepper_driver::STACK_SIZE)
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

#[test]
fn sema_skips_the_bodies_of_cached_units() {
    let dir = scratch("skip");
    let (cache, project) = (dir.join("cache"), dir.join("project"));
    std::fs::create_dir_all(&project).unwrap();
    write(
        &project,
        &[
            ("lib.pep", "export twice(x: int): int { return x * 2; }\nexport inferred(x: int) { return x; }\n"),
            ("main.pep", "import \"lib\";\nmain(): int { return twice(3) - 6 + inferred(0); }\n"),
        ],
    );
    let entry = project.join("main.pep");
    let (first, _) = compile_entry(&entry, &cache, &dir.join("a"), false);
    assert!(has_body(&first, "twice") && has_body(&first, "main"), "nothing is cached yet");
    // Every unit is a hit: no body is checked, except one whose return
    // type comes from it.
    let (again, objects) = compile_entry(&entry, &cache, &dir.join("b"), false);
    assert!(!has_body(&again, "twice") && !has_body(&again, "main"));
    assert!(has_body(&again, "inferred"), "a return type inferred from the body needs the body");
    assert!(objects.iter().all(|o| o.unit == "__program" || o.outcome == Some(Outcome::Hit)), "{:?}", outcomes(&objects));
    // An edit to main: its body is checked again; lib's still is not.
    write(&project, &[("main.pep", "import \"lib\";\nmain(): int { return twice(4) - 8; }\n")]);
    let (edited, objects) = compile_entry(&entry, &cache, &dir.join("c"), false);
    assert!(has_body(&edited, "main") && !has_body(&edited, "twice"));
    assert_eq!(outcome(&objects, "main"), Some(Outcome::Miss));
    // Verifying generates every unit, so no body is skipped.
    let (verified, _) = compile_entry(&entry, &cache, &dir.join("d"), true);
    assert!(has_body(&verified, "twice") && has_body(&verified, "main"));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_unit_that_warned_keeps_its_bodies_so_it_warns_again() {
    let dir = scratch("warned");
    let (cache, project) = (dir.join("cache"), dir.join("project"));
    std::fs::create_dir_all(&project).unwrap();
    write(
        &project,
        &[
            (
                "lib.pep",
                "## Deprecated: use `new_way` instead.\n[Deprecated(\"use 'new_way' instead\", \"new_way\")]\nexport old_way(): int { return 0; }\nexport new_way(): int { return 0; }\n",
            ),
            ("main.pep", "import \"lib\";\nmain(): int { return old_way(); }\n"),
        ],
    );
    let entry = project.join("main.pep");
    let (first, _) = compile_entry(&entry, &cache, &dir.join("a"), false);
    assert!(first.warnings.iter().any(|w| w.message.contains("old_way")), "expected a deprecation warning: {:?}", first.warnings);
    let (again, objects) = compile_entry(&entry, &cache, &dir.join("b"), false);
    assert_eq!(outcome(&objects, "main"), Some(Outcome::Hit));
    assert!(has_body(&again, "main"), "main warned, so its body is checked again");
    assert!(again.warnings.iter().any(|w| w.message.contains("old_way")), "the warning is reported again: {:?}", again.warnings);
    assert!(!has_body(&again, "old_way"), "lib did not warn");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn skipping_the_cached_units_bodies_changes_no_other_unit() {
    // After the first program, the runtime units are hits, so each later
    // program's own units are also generated from a module without the
    // runtime's bodies, and verifying requires the same code (generics
    // instantiated from the runtime included).
    let dir = scratch("trial");
    let cache = dir.join("cache");
    for (i, example) in ["threads-basics", "tuples-collections", "tutorial-word-count/main", "threads-copy"].iter().enumerate() {
        let objects = build(example, &cache, &dir.join(format!("b{}", i)));
        if i > 0 {
            assert_eq!(outcome(&objects, "prelude"), Some(Outcome::Hit), "{:?}", outcomes(&objects));
        }
    }
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_skipped_body_keeps_its_recorded_link_summary() {
    // `make` returns a new Tracker, so its result may go to the `[Sending]`
    // parameter of `ThreadLocal.set`. With lib's bodies skipped, sema knows
    // that only from the link summary the cache recorded for `make`.
    let dir = scratch("summaries");
    let (cache, project) = (dir.join("cache"), dir.join("project"));
    std::fs::create_dir_all(&project).unwrap();
    let main = |n: i32| {
        format!(
            "import async;\nimport \"lib\";\nconst slot = async.ThreadLocal<Tracker>();\nmain(): int {{\n    slot.set(make());\n    return {} - {};\n}}\n",
            n, n
        )
    };
    write(
        &project,
        &[
            ("lib.pep", "export struct Tracker {\n    var value: int;\n}\nexport make(): Tracker {\n    return Tracker();\n}\n"),
            ("main.pep", &main(1)),
        ],
    );
    let entry = project.join("main.pep");
    compile_entry(&entry, &cache, &dir.join("a"), false);
    write(&project, &[("main.pep", &main(2))]);
    let (edited, objects) = compile_entry(&entry, &cache, &dir.join("b"), false);
    assert_ne!(outcome(&objects, "main"), Some(Outcome::Hit), "{:?}", outcomes(&objects));
    assert!(!has_body(&edited, "make"), "lib's bodies are skipped");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn syntax_trees_are_kept_and_a_damaged_one_is_parsed_again() {
    let dir = scratch("parsed");
    let cache = dir.join("cache");
    build("tutorial-hello", &cache, &dir.join("a"));
    let parsed: Vec<PathBuf> = std::fs::read_dir(cache.join("v1"))
        .unwrap()
        .flatten()
        .flat_map(|target| std::fs::read_dir(target.path().join("parsed")).unwrap().flatten().map(|e| e.path()))
        .collect();
    assert!(parsed.len() > 10, "one tree per file: {:?}", parsed);
    for tree in &parsed {
        std::fs::write(tree, b"not a tree").unwrap();
    }
    // Damaged trees are parsed again (and replaced); the build is unchanged.
    let again = build("tutorial-hello", &cache, &dir.join("b"));
    assert_eq!(outcome(&again, "docs/examples/tutorial_hello"), Some(Outcome::Hit), "{:?}", outcomes(&again));
    assert!(parsed.iter().all(|tree| std::fs::metadata(tree).unwrap().len() > 32));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_function_whose_body_is_skipped_is_still_a_value() {
    // lib's bodies are skipped once it is a hit, but `twice` is still
    // defined (in lib's cached object), so main can pass it as a value,
    // from its own body and from a closure's.
    let dir = scratch("function_value");
    let (cache, project) = (dir.join("cache"), dir.join("project"));
    std::fs::create_dir_all(&project).unwrap();
    let main = |n: i32| {
        format!(
            "import \"lib\";\napply(f: (int) => int, x: int): int {{\n    return f(x);\n}}\nmain(): int {{\n    var g = () => apply(twice, {});\n    return apply(twice, {}) - g();\n}}\n",
            n, n
        )
    };
    write(&project, &[("lib.pep", "export twice(x: int): int {\n    return x * 2;\n}\n"), ("main.pep", &main(1))]);
    let entry = project.join("main.pep");
    compile_entry(&entry, &cache, &dir.join("a"), false);
    write(&project, &[("main.pep", &main(2))]);
    let (edited, objects) = compile_entry(&entry, &cache, &dir.join("b"), false);
    assert_ne!(outcome(&objects, "main"), Some(Outcome::Hit), "{:?}", outcomes(&objects));
    assert!(!has_body(&edited, "twice"), "lib's bodies are skipped");
    let _ = std::fs::remove_dir_all(&dir);
}
