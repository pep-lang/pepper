//! SIMD vectors (#517): `simd.Vector<T, N>` and `simd.Mask<N>`. The corpus
//! fixture `tests/Simd.Basic` runs every operation natively at `-O0` and,
//! under wasmtime, as WebAssembly without `simd128` (the scalar fallback);
//! these tests run it optimized and with `simd128`, check the code an
//! optimized loop becomes, and check the panics.

use crate::support::{build_executable, output_text, repo_root, run_linked_with, run_under_wasmtime, stdout_of, wasi_tools};
use std::path::PathBuf;
use std::process::Command;

fn fixture() -> PathBuf {
    repo_root().join("tests").join("Simd.Basic").join("test.pep")
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pepper_simd_{}_{}", name, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

#[test]
fn every_operation_runs_optimized() {
    std::env::set_current_dir(repo_root()).unwrap();
    let source = std::fs::read_to_string(fixture()).unwrap();
    let output = run_linked_with("simd_optimized", &source, &["-O2"], |_| {});
    assert!(output.status.success(), "{}", output_text(&output));
    assert_eq!(stdout_of(&output), "simd ok\n");
}

/// WebAssembly's `simd128`; the corpus covers the scalar fallback.
#[test]
fn every_operation_runs_on_webassembly_simd128() {
    let Some(wasi) = wasi_tools() else {
        eprintln!("skipped: set WASI_SDK_PATH and put wasmtime on the PATH (or set WASMTIME) to run it");
        return;
    };
    std::env::set_current_dir(repo_root()).unwrap();
    for options in [&["-msimd128", "--no-cache"][..], &["-msimd128", "-O2", "--no-cache"]] {
        let build = scratch("wasm");
        let output = run_under_wasmtime(&wasi, &fixture(), options, &build).unwrap_or_else(|e| panic!("{:?}: {}", options, e));
        let _ = std::fs::remove_dir_all(&build);
        assert_eq!(String::from_utf8_lossy(&output.stdout), "simd ok\n", "{:?}", options);
    }
}

/// An optimized scan for a byte with its high bit set is one vector compare
/// and a mask packed into bits (`pmovmskb` on x86-64), with no calls.
#[test]
fn an_optimized_scan_is_a_vector_compare_and_a_bit_mask() {
    use clap::Parser;
    std::env::set_current_dir(repo_root()).unwrap();
    let dir = scratch("scan");
    std::fs::write(
        dir.join("main.pep"),
        "import simd;
export first_high(data: __ptr<byte>, size: ulong): ulong {
    ulong i = 0;
    while (i + 16 <= size) {
        var high = simd.Vector<byte, 16>.load(data + i).greater_equal(0x80 as byte).to_bits();
        if (high != 0) {
            return i + high.trailing_zeros();
        }
        i = i + 16;
    }
    return size;
}
main(): int {
    var text = \"plain ascii text, then \u{e9}\";
    return first_high(unsafe_cast<__ptr<byte>>(text.c_str()), text.size) as int;
}
",
    )
    .unwrap();
    let main = dir.join("main.pep");
    let build = dir.join("build");
    let argv = ["pep-build", main.to_str().unwrap(), "-O2", "--emit-llvm", "--build", build.to_str().unwrap()];
    assert_eq!(pepper_driver::run(pepper_driver::Options::parse_from(argv)).expect("compile"), 0);
    let ir = std::fs::read_to_string(build.join("main.ll")).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    let start = ir.find("@first_high(").expect("first_high defined");
    let body = &ir[start..start + ir[start..].find("\n}").unwrap()];
    assert!(body.contains("load <16 x i8>"), "{}", body);
    assert!(body.contains("icmp slt <16 x i8>"), "{}", body);
    assert!(body.contains("bitcast <16 x i1>"), "{}", body);
    assert!(!body.contains("Vector"), "{}", body);
}

/// Each check panics at the caller's line and column.
#[test]
fn vector_checks_panic_at_the_caller() {
    std::env::set_current_dir(repo_root()).unwrap();
    let dir = scratch("panics");
    let source = r#"import simd;
main(args: String[]): int {
    var v = simd.Vector<int, 4>(1);
    var values = [1, 2, 3];
    var which = args[1];
    if (which == "divide") { var r = v / simd.Vector<int, 4>(); }
    if (which == "overflow") { var r = simd.Vector<char, 16>(-128 as char) / (-1 as char); }
    if (which == "shift") { var r = v << 32; }
    if (which == "lane") { var r = v[4]; }
    if (which == "set") { v[7] = 0; }
    if (which == "array") { var r = simd.Vector<int, 4>.load(values, 0); }
    if (which == "store") { v.store(values, 2); }
    if (which == "aligned") { var r = simd.Vector<int, 4>.load_aligned(values._data + 1); }
    if (which == "mask") { var r = v.equal(1)[9]; }
    return 0;
}
"#;
    std::fs::write(dir.join("main.pep"), source).unwrap();
    let exe = dir.join(if cfg!(windows) { "main.exe" } else { "main" });
    build_executable(&dir.join("main.pep"), &[], &exe, &dir.join("build"));
    let cases = [
        ("divide", "main.pep:6:40: panic: division by zero in a vector lane"),
        ("overflow", "main.pep:7:76: panic: integer overflow in a vector lane division"),
        ("shift", "main.pep:8:39: panic: shift count 32 is out of range for 32-bit vector lanes"),
        ("lane", "main.pep:9:36: panic: lane index 4 is out of range for a vector of 4 lanes"),
        ("set", "main.pep:10:32: panic: lane index 7 is out of range for a vector of 4 lanes"),
        ("array", "main.pep:11:57: panic: vector access of 4 elements at index 0 is out of bounds for an array of 3"),
        ("store", "main.pep:12:31: panic: vector access of 4 elements at index 2 is out of bounds for an array of 3"),
        ("aligned", "main.pep:13:59: panic: vector access is not aligned to the vector's size"),
        ("mask", "main.pep:14:36: panic: lane index 9 is out of range for a mask of 4 lanes"),
    ];
    let failures: Vec<String> = cases
        .iter()
        .filter_map(|(which, expected)| {
            let output = Command::new(&exe).arg(which).env("PEPPER_BACKTRACE", "0").output().expect("run");
            let stderr = String::from_utf8_lossy(&output.stderr).replace('\r', "");
            (output.status.success() || !stderr.contains(expected)).then(|| format!("{}: {}", which, stderr))
        })
        .collect();
    let _ = std::fs::remove_dir_all(&dir);
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
