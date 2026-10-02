//! Uri: parsing absolute URIs with any scheme and relative references,
//! the errors parse reports, percent-decoding, and putting a URI back
//! together. Each test returns 0 on success or a distinct negative code per
//! check.

use pepper_codegen::CodeGenerator;

/// Compile and JIT `test()`; assert it left no allocation behind and return
/// its result.
fn run(source: &str) -> i32 {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    let ee = generator.jit_engine(&mut module).expect("jit");
    let live_allocs =
        unsafe { ee.get_function::<unsafe extern "C" fn() -> i64>("_pep_live_allocs").expect("_pep_live_allocs") };
    let before = unsafe { live_allocs.call() };
    let result = CodeGenerator::jit_call_i32(&ee, "test").expect("entry");
    let after = unsafe { live_allocs.call() };
    assert_eq!(after - before, 0, "allocations leaked or double-released");
    result
}

#[test]
fn parses_components() {
    assert_eq!(
        run(r##"
test(): int {
    var a = Uri.parse("HTTPS://user:pw@Example.com:8443/a%20b/c?x=1&y#top");
    if (a.is_err()) { return -1; }
    var u = a.value();
    if (u.scheme != "https" || !u.is_absolute()) { return -2; }
    if (u.user_info.value_or("") != "user:pw") { return -3; }
    if (u.host.value_or("") != "Example.com") { return -4; }
    if (u.port.value_or(0) != 8443) { return -5; }
    if (u.path != "/a%20b/c") { return -6; }
    if (u.query.value_or("") != "x=1&y") { return -7; }
    if (u.fragment.value_or("") != "top") { return -8; }
    if (u.authority().value_or("") != "user:pw@Example.com:8443") { return -9; }
    if (u.path_and_query() != "/a%20b/c?x=1&y") { return -10; }
    if (u.to_string() != "https://user:pw@Example.com:8443/a%20b/c?x=1&y#top") { return -11; }
    if ($"{u}" != u.to_string()) { return -12; }

    var mail = Uri.parse("mailto:someone@example.com").value();
    if (mail.scheme != "mailto" || mail.host.is_value()) { return -20; }
    if (mail.path != "someone@example.com" || mail.query.is_value()) { return -21; }

    var file = Uri.parse("file:///tmp/x").value();
    if (file.host.value_or("?") != "" || file.path != "/tmp/x") { return -30; }
    if (file.to_string() != "file:///tmp/x") { return -31; }

    var v6 = Uri.parse("http://[::1]:8080").value();
    if (v6.host.value_or("") != "::1" || v6.port.value_or(0) != 8080) { return -40; }
    if (v6.authority().value_or("") != "[::1]:8080" || v6.path_and_query() != "/") { return -41; }

    var empty = Uri.parse("git+ssh://h/?#").value();
    if (empty.scheme != "git+ssh" || empty.port.is_value()) { return -50; }
    if (empty.query.value_or("x") != "" || empty.fragment.value_or("x") != "") { return -51; }
    var no_port = Uri.parse("http://h:/").value();
    if (no_port.port.is_value() || no_port.host.value_or("") != "h") { return -52; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn parses_relative_references() {
    assert_eq!(
        run(r##"
test(): int {
    var target = Uri.parse("/items?page=2").value();
    if (target.is_absolute() || target.host.is_value()) { return -1; }
    if (target.path != "/items" || target.query.value_or("") != "page=2") { return -2; }
    var net = Uri.parse("//cdn.example.com/lib.js").value();
    if (net.scheme != "" || net.host.value_or("") != "cdn.example.com") { return -3; }
    var bare = Uri.parse("a/b:c").value();
    if (bare.path != "a/b:c" || bare.is_absolute()) { return -4; }
    var nothing = Uri.parse("").value();
    if (nothing.to_string() != "" || nothing.path_and_query() != "/") { return -5; }
    var fragment = Uri.parse("#part").value();
    if (fragment.path != "" || fragment.fragment.value_or("") != "part") { return -6; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn reports_invalid_uris() {
    assert_eq!(
        run(r##"
test(): int {
    if (!Uri.parse("a b").is_err()) { return -1; }
    if (!Uri.parse("1http://x").is_err()) { return -2; }
    if (!Uri.parse(":x").is_err()) { return -3; }
    if (!Uri.parse("http://[::1/").is_err()) { return -4; }
    if (!Uri.parse("http://[::1]x/").is_err()) { return -5; }
    if (!Uri.parse("http://h:99999/").is_err()) { return -6; }
    if (!Uri.parse("http://h:8a/").is_err()) { return -7; }
    if (!Uri.parse("/a%2").is_err()) { return -8; }
    if (!Uri.parse("/a%zz").is_err()) { return -9; }
    if (!Uri.parse("/caf\u{E9}").is_err()) { return -10; }
    var message = Uri.parse("http://h:99999/").error().message;
    if (message != "invalid URI 'http://h:99999/': invalid port '99999'") { return -11; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn decodes_percent_escapes() {
    assert_eq!(
        run(r##"
test(): int {
    if (Uri.decode("caf%C3%A9%21").value() != "caf\u{E9}!") { return -1; }
    if (Uri.decode("a+b%2Bc").value() != "a+b+c") { return -2; }
    if (Uri.decode("%ff").value() != "\u{FFFD}") { return -3; }
    if (!Uri.decode("100%").is_err()) { return -4; }
    if (!Uri.decode("%g0").is_err()) { return -5; }
    if (Uri.decode("").value() != "") { return -6; }
    return 0;
}
"##),
        0
    );
}
