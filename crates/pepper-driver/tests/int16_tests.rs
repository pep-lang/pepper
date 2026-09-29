//! 16-bit integer primitives: `i16`/`short` and `u16`/`ushort`. Covers
//! storage width, wraparound, sign- vs zero-extension, truncation, C integer
//! promotion against the other widths, containers, raw pointers, sizeof,
//! struct fields, generics, extern (C `short`) calls, and `print`.
//! The exhaustive operator matrix lives in `arithmetic_c_semantics_tests.rs`.

use pepper_codegen::CodeGenerator;
use clap::Parser;
use std::path::PathBuf;
use std::process::Command;

fn compile_jit_with_runtime(source: &str) -> i32 {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

/// Run a `test(): int` program whose checks `return <case index>` on failure.
fn assert_cases(source: &str) {
    assert_eq!(compile_jit_with_runtime(source), 0, "first failing case index");
}

#[test]
fn aliases_and_storage_width() {
    assert_cases(
        r#"test(): int {
    i16 a = 1; short b = 2; u16 c = 3; ushort d = 4;
    if (a + b + c + d != 10) { return 1; }
    if (sizeof<i16>() != 2) { return 2; }
    if (sizeof<short>() != 2) { return 3; }
    if (sizeof<u16>() != 2) { return 4; }
    if (sizeof<ushort>() != 2) { return 5; }
    # Aliases are the same type: assignment between them is lossless.
    short s = -5; i16 t = s; ushort u = 65000; u16 v = u;
    if (t != -5 || v != 65000) { return 6; }
    return 0;
}"#,
    );
}

#[test]
fn wraparound_on_store() {
    assert_cases(
        r#"test(): int {
    u16 a = 65535; a = a + 1;
    if (a != 0) { return 1; }
    i16 b = 32767; b = b + 1;
    if (b != -32768) { return 2; }
    u16 c = 0; c = c - 1;
    if (c != 65535) { return 3; }
    i16 d = -32768; d = d - 1;
    if (d != 32767) { return 4; }
    u16 e = 65535; e += 1;
    if (e != 0) { return 5; }
    i16 f = 32767; f += 1;
    if (f != -32768) { return 6; }
    u16 g = 300; g *= 300;
    if (g != 24464) { return 7; }
    # The binary itself promotes to int: no 16-bit wrap before the store.
    u16 h = 65535;
    if (h + 1 != 65536) { return 8; }
    i16 k = 32767;
    if (k + 1 != 32768) { return 9; }
    return 0;
}"#,
    );
}

#[test]
fn widening_casts_extend_by_signedness() {
    assert_cases(
        r#"test(): int {
    i16 a = -1;
    if ((a as long) != -1) { return 1; }
    if ((a as int) != -1) { return 2; }
    if ((a as ulong) + 1 != 0) { return 3; }
    if ((a as uint) != 4294967295) { return 4; }
    u16 b = 65535;
    if ((b as long) != 65535) { return 5; }
    if ((b as int) != 65535) { return 6; }
    if ((b as ulong) != 65535) { return 7; }
    if ((b as uint) != 65535) { return 8; }
    # Implicit widening on initialization follows the same rule.
    long c = a; long d = b;
    if (c != -1 || d != 65535) { return 9; }
    # 8-bit sources widen into 16 bits by their own signedness.
    char e = -1; u8 f = 255;
    i16 g = e; u16 h = f; i16 k = f; u16 m = e;
    if (g != -1 || h != 255 || k != 255 || m != 65535) { return 10; }
    if ((e as i16) != -1 || (f as i16) != 255 || (e as u16) != 65535) { return 11; }
    return 0;
}"#,
    );
}

#[test]
fn narrowing_casts_truncate() {
    assert_cases(
        r#"test(): int {
    if ((70000 as u16) != 4464) { return 1; }
    if ((70000 as i16) != 4464) { return 2; }
    if ((40000 as i16) != -25536) { return 3; }
    if (((0 - 1) as u16) != 65535) { return 4; }
    long big = 4294967297;
    if ((big as u16) != 1) { return 5; }
    u16 a = 65535;
    if ((a as i16) != -1) { return 6; }
    i16 b = -32768;
    if ((b as u16) != 32768) { return 7; }
    u16 c = 511;
    if ((c as u8) != 255) { return 8; }
    if ((c as char) != -1) { return 9; }
    u16 d = 70000;
    if (d != 4464) { return 10; }
    return 0;
}"#,
    );
}

#[test]
fn float_conversions() {
    assert_cases(
        r#"test(): int {
    u16 a = 65535;
    if ((a as double) != 65535.0) { return 1; }
    if ((a as float) != 65535.0) { return 2; }
    i16 b = -32768;
    if ((b as double) != -32768.0) { return 3; }
    if ((65535.0 as u16) != 65535) { return 4; }
    if ((-12345.9 as i16) != -12345) { return 5; }
    if ((40000.5 as u16) != 40000) { return 6; }
    double c = a;
    if (c != 65535.0) { return 7; }
    return 0;
}"#,
    );
}

#[test]
fn promotion_with_other_widths() {
    assert_cases(
        r#"test(): int {
    # u16 promotes to signed int: 0 - 1 is -1, and compares below 0.
    u16 a = 0; u16 one = 1;
    if (a - one != -1) { return 1; }
    if (!(a - one < 0)) { return 2; }
    # u16 vs u32: unsigned 32-bit arithmetic.
    uint u = 0;
    if (a + u - one != 4294967295) { return 3; }
    # i16 vs u8 / char.
    i16 s = -300; u8 b = 200; char c = -100;
    if (s + b != -100) { return 4; }
    if (s * c != 30000) { return 5; }
    # i16 vs int, long, ulong.
    int i = 100000;
    if (s + i != 99700) { return 6; }
    long l = 10000000000;
    if (s + l != 9999999700) { return 7; }
    ulong ul = 1;
    if ((s + ul) + 299 != 0) { return 8; }
    u16 m = 65535;
    if ((m + ul) != 65536) { return 9; }
    # i16 vs u16: both promote to int, no unsigned wrap.
    i16 neg = -1; u16 max = 65535;
    if (neg < max == false) { return 10; }
    if (neg + max != 65534) { return 11; }
    # Mixed-width comparison: signed short against unsigned int converts to uint.
    uint uz = 0;
    if (neg < uz) { return 12; }
    return 0;
}"#,
    );
}

#[test]
fn division_modulo_shift_signedness() {
    assert_cases(
        r#"test(): int {
    i16 a = -7; i16 b = 2;
    if (a / b != -3) { return 1; }
    if (a % b != -1) { return 2; }
    if (a >> 1 != -4) { return 3; }
    u16 c = 65535; u16 d = 2;
    if (c / d != 32767) { return 4; }
    if (c % d != 1) { return 5; }
    if (c >> 1 != 32767) { return 6; }
    if (c >> 15 != 1) { return 7; }
    # Left shift promotes to int first: bits above 16 survive.
    if (c << 1 != 131070) { return 8; }
    u16 e = 1;
    if (e << 20 != 1048576) { return 9; }
    i16 f = -32768; u16 g = 32768;
    if (f >> 15 != -1) { return 10; }
    if (g >> 15 != 1) { return 11; }
    # Unsigned 16-bit against a negative int: promotion is to signed int.
    int n = -2;
    if (c / n != -32767) { return 12; }
    # Unary ops promote to int.
    u16 h = 1;
    if (-h != -1) { return 13; }
    if (~h != -2) { return 14; }
    i16 k = 0;
    if (~k != -1) { return 15; }
    return 0;
}"#,
    );
}

#[test]
fn ptr_indexing_and_arithmetic() {
    assert_cases(
        r#"test(): int {
    __ptr<u16> p = _pep_malloc(4 * sizeof<u16>());
    p[0] = 1; p[1] = 65535; p[2] = 70000; p[3] = 40000;
    if (p[0] != 1) { return 1; }
    if (p[1] != 65535) { return 2; }
    if (p[2] != 4464) { return 3; }
    # Elements are 2 bytes apart: p[1] occupies bytes 2..3.
    __ptr<u8> bytes = p;
    if (bytes[2] != 255 || bytes[3] != 255 || bytes[0] != 1 || bytes[1] != 0) { return 4; }
    __ptr<u16> q = p + 1;
    if (q[0] != 65535 || q[1] != 4464) { return 5; }
    long total = 0;
    var i = 0;
    while (i < 4) { total += p[i]; i = i + 1; }
    if (total != 1 + 65535 + 4464 + 40000) { return 6; }
    __ptr<i16> s = p;
    if (s[1] != -1 || s[3] != -25536) { return 7; }
    _pep_free(p);
    return 0;
}"#,
    );
}

#[test]
fn array_elements() {
    assert_cases(
        r#"test(): int {
    var a = Array<u16>();
    a.append(65535);
    a.append(7);
    a.append(70000);
    if (a.count() != 3) { return 1; }
    if (a[0] != 65535) { return 2; }
    if (a[2] != 4464) { return 3; }
    long sum = a[0] + a[1];
    if (sum != 65542) { return 4; }
    var b = Array<short>();
    b.append(-1);
    b.append(-32768);
    if (b[0] != -1 || b[1] != -32768) { return 5; }
    if ((b[1] as long) != -32768) { return 6; }
    if (!a.contains(7)) { return 7; }
    a[1] = 65534;
    if (a[1] != 65534) { return 8; }
    return 0;
}"#,
    );
}

#[test]
fn struct_fields() {
    assert_cases(
        r#"struct Pixel {
    u8 tag;
    u16 x;
    i16 y;
    ushort w;
    short h;

    construct(this.tag = 0, this.x = 0, this.y = 0, this.w = 0, this.h = 0) {}
};

test(): int {
    var p = Pixel(1, 65535, -32768, 40000, -2);
    if (p.x != 65535) { return 1; }
    if (p.y != -32768) { return 2; }
    if (p.w != 40000 || p.h != -2) { return 3; }
    p.x += 1;
    if (p.x != 0) { return 4; }
    p.y -= 1;
    if (p.y != 32767) { return 5; }
    if ((p.h as long) != -2 || (p.w as long) != 40000) { return 6; }
    return 0;
}"#,
    );
}

#[test]
fn generics_and_functions() {
    assert_cases(
        r#"identity<T>(T v): T { return v; }

add16(i16 a, i16 b): i16 { return a + b; }
widen(u16 v): long { return v; }

test(): int {
    u16 a = 65535;
    if (identity<u16>(a) != 65535) { return 1; }
    i16 b = -2;
    if (identity<i16>(b) != -2) { return 2; }
    if (add16(32767, 1) != -32768) { return 3; }
    if (widen(65535) != 65535) { return 4; }
    if (hash<u16>(a) == hash<u16>(1)) { return 5; }
    return 0;
}"#,
    );
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf()
}

/// Compile `source` to a native binary via the driver and return its path.
fn build_binary(name: &str, source: &str) -> PathBuf {
    std::env::set_current_dir(repo_root()).unwrap();
    let dir = std::env::temp_dir().join(format!("pepper_{name}_test"));
    std::fs::create_dir_all(&dir).unwrap();
    let src_path = dir.join(format!("{name}.pep"));
    let out_path = dir.join(if cfg!(windows) { format!("{name}.exe") } else { name.to_string() });
    std::fs::write(&src_path, source).unwrap();
    let options = pepper_driver::Options::parse_from(vec![
        "pepper".to_string(),
        src_path.to_string_lossy().into_owned(),
        "-o".to_string(),
        out_path.to_string_lossy().into_owned(),
    ]);
    assert_eq!(pepper_driver::run(options).expect("compile + link"), 0);
    out_path
}

#[test]
fn print_uses_signedness() {
    let out_path = build_binary(
        "int16_print",
        r#"
main(): int {
    u16 a = 65535;
    i16 b = -32768;
    u8 c = 200;
    print(a);
    print(b);
    print(c);
    return 0;
}"#,
    );
    let out = Command::new(&out_path).output().expect("spawn binary");
    assert!(out.status.success(), "binary exited with {}", out.status);
    let stdout = String::from_utf8_lossy(&out.stdout);
    let lines: Vec<&str> = stdout.lines().map(str::trim).collect();
    assert_eq!(lines, ["65535", "-32768", "200"]);
}

#[test]
#[cfg(unix)]
fn extern_unsigned_short_round_trip() {
    // htons/ntohs take and return `uint16_t` (C `unsigned short`). The
    // byte swap is only observable on a little-endian host; big-endian
    // hosts see the identity, which the program also accepts.
    let out_path = build_binary(
        "int16_extern",
        r#"
extern ushort htons(ushort v);
extern ushort ntohs(ushort v);

main(): int {
    u16 v = 0x1234;
    u16 n = htons(v);
    if (n != 0x3412 && n != 0x1234) { return 1; }
    if (ntohs(n) != 0x1234) { return 2; }
    u16 hi = 0xFF80;
    if (ntohs(htons(hi)) != 65408) { return 3; }
    if ((htons(hi) as long) < 0) { return 4; }
    return 0;
}"#,
    );
    let status = Command::new(&out_path).status().expect("spawn binary");
    assert!(status.success(), "binary exited with {}", status);
}
