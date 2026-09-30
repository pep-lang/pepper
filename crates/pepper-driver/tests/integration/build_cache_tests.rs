//! The build cache: a program is emitted as one object per compilation
//! unit, and a unit whose bitcode is unchanged comes from the cache (see
//! INTERNALS.md §4.3).

use clap::Parser;
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

/// Emit the example `example` with the cache at `cache` into `build`.
fn build(example: &str, cache: &Path, build: &Path) -> Vec<UnitObject> {
    // chdir so namespaces (paths from the project) resolve like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    let entry = format!("docs/examples/{}.pep", example);
    let options = pepper_driver::Options::parse_from([
        "pepper".to_string(),
        entry,
        "--cache".to_string(),
        cache.to_string_lossy().into_owned(),
        "--build".to_string(),
        build.to_string_lossy().into_owned(),
    ]);
    let (module, program) = pepper_driver::compiler::compile_program(&options).unwrap();
    pepper_driver::objects(&options, &module, &program, build, "main").unwrap()
}

fn hits(objects: &[UnitObject]) -> Vec<(String, Option<bool>)> {
    objects.iter().map(|o| (o.unit.clone(), o.hit)).collect()
}

fn hit(objects: &[UnitObject], unit: &str) -> Option<bool> {
    objects.iter().find(|o| o.unit == unit).unwrap_or_else(|| panic!("no unit '{}' in {:?}", unit, hits(objects))).hit
}

#[test]
fn unchanged_units_come_from_the_cache() {
    let dir = scratch("reuse");
    let cache = dir.join("cache");
    let first = build("threads-basics", &cache, &dir.join("a"));
    assert!(first.len() > 3, "expected several units: {:?}", hits(&first));
    for object in &first {
        let expected = if object.unit == "__program" { None } else { Some(false) };
        assert_eq!(object.hit, expected, "{:?}", hits(&first));
        assert!(object.path.is_file(), "{} was not written", object.path.display());
    }
    let second = build("threads-basics", &cache, &dir.join("b"));
    for object in second.iter().filter(|o| o.unit != "__program") {
        assert_eq!(object.hit, Some(true), "{:?}", hits(&second));
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
    assert_eq!(hit(&build("threads-basics", &cache, &dir.join("a")), "prelude"), Some(false));
    // Another program compiles the runtime to the same object.
    let other = build("tutorial-hello", &cache, &dir.join("b"));
    assert_eq!(hit(&other, "prelude"), Some(true), "{:?}", hits(&other));
    assert_eq!(hit(&other, "docs/examples/tutorial_hello"), Some(false));
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
    std::fs::write(&record, "{\"key\": \"stale\"}\n").unwrap();
    let again = build("tutorial-hello", &cache, &dir.join("b"));
    assert_eq!(hit(&again, "docs/examples/tutorial_hello"), Some(false));
    assert_eq!(hit(&again, "prelude"), Some(true));
    assert_eq!(hit(&build("tutorial-hello", &cache, &dir.join("c")), "docs/examples/tutorial_hello"), Some(true));
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
