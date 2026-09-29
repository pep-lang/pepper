//! HashMap / HashSet API coverage: each snippet is compiled together with
//! the runtime prelude and JIT-executed through the entry function `test`.

use pepper_codegen::CodeGenerator;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;

/// `_pep_live_allocs()` is a process-wide counter, so leak-census tests must
/// not run concurrently with each other; serialize on this lock.
static CENSUS_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn compile_jit_with_runtime(source: &str) -> i32 {
    let _census = CENSUS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut module = SemaModule::default();
    let (runtime_sources, _libs, _dirs) = pepper_driver::runtime::discover();
    assert!(!runtime_sources.is_empty(), "runtime prelude not discovered");
    for path in runtime_sources {
        let content = std::fs::read_to_string(&path).expect("read runtime source");
        let ast = pepper_parser::parser::parse_source(&path.to_string_lossy(), &content)
            .expect("parse runtime source");
        module.merge(build(&ast).expect("build"));
    }
    let ast = pepper_parser::parser::parse_source("test.pep", source).expect("parse error");
    pepper_driver::compiler::check_with_runtime("test.pep", source).expect("visibility");
    module.merge(build(&ast).expect("build"));
    pepper_sema::apply_platform_filters(&mut module).expect("platform");
    struct_body::apply(&mut module).expect("sema");
    transform_pass(&mut module).expect("sema");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

#[test]
fn hash_is_deterministic() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = hash<int>(5);
    var b = hash<int>(5);
    if (a != b) { return -1; }
    if (hash<String>("hello") != hash<String>("hello")) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn hash_string_override() {
    // The concrete `hash<String>` override must be used for String call
    // sites (not the generic base): equal strings at different addresses
    // hash identically, and a different String hashes differently.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = "hello";
    var b = "hello";
    if (hash<String>(a) != hash<String>(b)) { return -1; }
    var c = "world";
    if (hash<String>(a) == hash<String>(c)) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn empty_map() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, int>();
    if (!m.empty()) { return -1; }
    if (m.count() != 0) { return -2; }
    if (m.contains(1)) { return -3; }
    if (m[42] != 0) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn insert_get_contains() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, int>();
    if (!m.insert(1, 10)) { return -1; }
    if (m.insert(2, 20) != true) { return -2; }
    if (m.count() != 2) { return -3; }
    if (!m.contains(1) || !m.contains(2)) { return -4; }
    if (m[1] != 10 || m[2] != 20) { return -5; }
    if (m.get(2) != 20) { return -6; }
    if (m.get(99) != 0) { return -7; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn duplicate_key_overwrites() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, int>();
    if (!m.insert(5, 1)) { return -1; }
    if (m.insert(5, 2) != false) { return -2; }
    if (m.count() != 1) { return -3; }
    if (m[5] != 2) { return -4; }
    m[5] = 3;
    if (m[5] != 3) { return -5; }
    if (m.count() != 1) { return -6; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn same_bucket_collision() {
    // int keys 1 and 9 hash to the same initial bucket (h & 7 == 4 for both)
    // but have distinct full hashes, so they must be separated by probing.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, int>();
    if ((hash<int>(1) & 7) != (hash<int>(9) & 7)) { return -1; }
    if (!m.insert(1, 100)) { return -2; }
    if (!m.insert(9, 200)) { return -3; }
    if (m.count() != 2) { return -4; }
    if (m[1] != 100 || m[9] != 200) { return -5; }
    if (!m.remove(1)) { return -6; }
    if (m[9] != 200) { return -7; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn growth_preserves_entries() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, int>();
    var i = 0;
    while (i < 25) {
        if (!m.insert(i, i * 10)) { return -1; }
        i = i + 1;
    }
    if (m.count() != 25) { return -2; }
    if (m.cap() < 64) { return -3; }
    var j = 0;
    while (j < 25) {
        if (m[j] != j * 10) { return -4; }
        j = j + 1;
    }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn remove_and_reinsert() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, int>();
    if (!m.insert(3, 30)) { return -1; }
    if (!m.insert(11, 110)) { return -2; }
    if (m.remove(99) != false) { return -3; }
    if (!m.remove(3)) { return -4; }
    if (m.count() != 1) { return -5; }
    if (m.contains(3)) { return -6; }
    if (m[3] != 0) { return -7; }
    if (!m.insert(3, 31)) { return -8; }
    if (m.count() != 2) { return -9; }
    if (m[3] != 31 || m[11] != 110) { return -10; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn clear_empties_map() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, int>();
    m.insert(1, 1);
    m.insert(2, 2);
    m.clear();
    if (!m.empty()) { return -1; }
    if (m.count() != 0) { return -2; }
    if (!m.insert(3, 3)) { return -3; }
    if (m[3] != 3) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn struct_keys_by_identity() {
    // Struct keys hash by object address: two equal-valued Points are
    // DISTINCT keys, and a lookup finds only the exact stored object.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    int y;
    new(this.x = 0, this.y = 0) {}
}
build(): int {
    var m = HashMap<Point, int>();
    var p = Point();
    p.x = 1;
    p.y = 2;
    if (!m.insert(p, 42)) { return -1; }
    var q = Point();
    q.x = 1;
    q.y = 2;
    if (m.contains(q)) { return -2; }
    if (!m.insert(q, 7)) { return -3; }
    if (m.count() != 2) { return -4; }
    if (m.get(p) != 42 || m.get(q) != 7) { return -5; }
    if (!m.remove(q)) { return -6; }
    if (m.count() != 1 || !m.contains(p)) { return -7; }
    if (m.get(p) != 42) { return -8; }
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # Every allocation must be freed when build's scope exits.
    if (_pep_live_allocs() != before) { return -9; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn string_keys_by_content() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<String, int>();
    if (!m.insert("hello", 1)) { return -1; }
    var s = "hello";
    if (!m.contains(s)) { return -2; }
    if (m.get(s) != 1) { return -3; }
    m[s] = 5;
    if (m["hello"] != 5) { return -4; }
    if (m.count() != 1) { return -5; }
    if (!m.insert("world", 2)) { return -6; }
    if (m.count() != 2) { return -7; }
    if (m["hello"] != 5 || m["world"] != 2) { return -8; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn empty_set() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = HashSet<int>();
    if (!s.empty()) { return -1; }
    if (s.count() != 0) { return -2; }
    if (s.contains(1)) { return -3; }
    if (s[7] != 0) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn set_insert_contains_remove() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = HashSet<int>();
    if (!s.insert(1)) { return -1; }
    if (s.insert(1) != false) { return -2; }
    if (s.count() != 1) { return -3; }
    if (!s.contains(1)) { return -4; }
    if (s[1] != 1) { return -5; }
    if (s[9] != 0) { return -6; }
    s[2] = 2;
    if (s.count() != 2) { return -7; }
    if (!s.remove(1)) { return -8; }
    if (s.remove(1) != false) { return -9; }
    if (s.count() != 1 || !s.contains(2)) { return -10; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn set_growth_and_clear() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = HashSet<int>();
    var i = 0;
    while (i < 20) {
        if (!s.insert(i)) { return -1; }
        i = i + 1;
    }
    if (s.count() != 20) { return -2; }
    var j = 0;
    while (j < 20) {
        if (!s.contains(j)) { return -3; }
        j = j + 1;
    }
    s.clear();
    if (!s.empty()) { return -4; }
    if (!s.insert(5)) { return -5; }
    if (s.count() != 1) { return -6; }
    return 0;
}
"#
        ),
        0
    );
}

#[test]
fn set_struct_keys_identity() {
    // Struct elements hash by address: equal-valued Points are distinct
    // members, and remove finds only the exact stored object.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    int y;
    new(this.x = 0, this.y = 0) {}
}
build(): int {
    var s = HashSet<Point>();
    var p = Point();
    p.x = 3;
    p.y = 4;
    if (!s.insert(p)) { return -1; }
    var q = Point();
    q.x = 3;
    q.y = 4;
    if (!s.insert(q)) { return -2; }
    if (s.count() != 2) { return -3; }
    var r = Point();
    r.x = 4;
    r.y = 3;
    if (!s.insert(r)) { return -4; }
    if (s.count() != 3) { return -5; }
    if (!s.remove(q)) { return -6; }
    if (s.count() != 2 || !s.contains(p) || !s.contains(r)) { return -7; }
    if (s.contains(q)) { return -8; }
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # Every allocation must be freed when build's scope exits.
    if (_pep_live_allocs() != before) { return -9; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn map_string_values_refcounted() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, String>();
    if (!m.insert(1, "alpha")) { return -1; }
    if (m[1] != "alpha") { return -2; }
    m[1] = "beta";
    if (m[1] != "beta") { return -3; }
    if (m.count() != 1) { return -4; }
    if (!m.remove(1)) { return -5; }
    if (!m.empty()) { return -6; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn map_release_frees_contents() {
    // The map and its contents are allocated inside `build`; when build's
    // scope exits, the automatic releases must free every allocation made
    // for the map (Point keys, String values, arrays).
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    int y;
    new(this.x = 0, this.y = 0) {}
}
build(): int {
    var m = HashMap<Point, String>();
    var p1 = Point();
    p1.x = 1;
    p1.y = 2;
    var p2 = Point();
    p2.x = 2;
    p2.y = 4;
    var p3 = Point();
    p3.x = 3;
    p3.y = 6;
    var s1 = "one";
    var s2 = "two";
    var s3 = "three";
    if (!m.insert(p1, s1)) { return -1; }
    if (!m.insert(p2, s2)) { return -2; }
    if (!m.insert(p3, s3)) { return -3; }
    # The map's slots hold one ref each (acquired on insert); build's
    # scope exit drops the creators' refs.
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # Every allocation made for the map and its contents must be freed.
    if (_pep_live_allocs() != before) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn many_struct_keys_same_bucket() {
    // Regression: every `_pep_malloc` result is 8-byte aligned, so a raw
    // address hash lands ALL struct keys in bucket 0 of a small table. The
    // address bits must be folded through FNV and the probe sequence must
    // cover every slot, or the 4th insert finds no empty slot at capacity 8
    // and is silently dropped. Struct keys are identity-hashed, so lookups
    // re-use the stored objects themselves.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    int y;
    new(this.x = 0, this.y = 0) {}
}
build(): int {
    var m = HashMap<Point, int>(8);
    var kept = Array<Point>();
    var i = 0;
    while (i < 4) {
        var p = Point();
        p.x = i + 1;
        p.y = (i + 1) * 2;
        if (!m.insert(p, (i + 1) * 10)) { return -1 - i; }
        kept.append(p);
        i = i + 1;
    }
    if (m.count() != 4) { return -5; }
    if (m.get(kept[2]) != 30) { return -6; }
    var fresh = Point();
    fresh.x = 3;
    fresh.y = 6;
    if (m.contains(fresh)) { return -7; }
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # Every allocation must be freed when build's scope exits.
    if (_pep_live_allocs() != before) { return -8; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn many_struct_set_members_same_bucket() {
    // Same regression as `many_struct_keys_same_bucket`, for HashSet: four
    // distinct Point members must all be stored and found at capacity 8.
    // Identity-hashed, so lookups re-use the stored objects themselves.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    int y;
    new(this.x = 0, this.y = 0) {}
}
build(): int {
    var s = HashSet<Point>(8);
    var kept = Array<Point>();
    var i = 0;
    while (i < 4) {
        var p = Point();
        p.x = i + 1;
        p.y = (i + 1) * 2;
        if (!s.insert(p)) { return -1 - i; }
        kept.append(p);
        i = i + 1;
    }
    if (s.count() != 4) { return -5; }
    if (!s.contains(kept[1])) { return -6; }
    var fresh = Point();
    fresh.x = 9;
    fresh.y = 9;
    if (s.contains(fresh)) { return -7; }
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # Every allocation must be freed when build's scope exits.
    if (_pep_live_allocs() != before) { return -8; }
    return 0;
}"#
        ),
        0
    );
}
