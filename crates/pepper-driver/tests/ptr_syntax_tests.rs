//! `__ptr<T>` is the only pointer spelling outside `extern` declarations
//! (`T*` is rejected by the parser there). These exercise every pointer
//! operation the runtime and tests relied on with `T*`, spelled `__ptr<T>`,
//! end-to-end through the JIT.

use pepper_codegen::CodeGenerator;

fn compile_jit_with_runtime(source: &str) -> i32 {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

#[test]
fn ptr_param_arithmetic_index_and_extern_arg() {
    // `__ptr<void>` param: `p + n` strides bytes, `p[i]` reads a byte, and it
    // passes straight to an extern declared with `void*`.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
extern void memset(void* p, int c, ulong n);
fill(p: __ptr<void>, n: ulong) {
    memset(p + 1, 9, n);
}
test(): int {
    var p = _pep_malloc(8);
    fill(p, 3);
    var r = (p[0] as int) * 100 + (p[1] as int) * 10 + (p[3] as int);
    _pep_free(p);
    return r;
}
"#
        ),
        99
    );
}

#[test]
fn ptr_null_compare_and_ulong_cast() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
is_null(p: __ptr<char>): bool {
    return p == __null;
}
addr(p: __ptr<void>): ulong {
    return p as ulong;
}
test(): int {
    var p = _pep_malloc(8);
    var r = 0;
    if (is_null(__null)) { r = r + 1; }
    if (!is_null(p)) { r = r + 10; }
    if (addr(p) != 0) { r = r + 100; }
    if (p != __null) { r = r + 1000; }
    _pep_free(p);
    return r;
}
"#
        ),
        1111
    );
}

#[test]
fn ptr_local_return_and_cast() {
    // Typed locals, a `__ptr<char>` return, and `as __ptr<T>` casts.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
make(): __ptr<char> {
    var buf: __ptr<char> = _pep_malloc(4) as __ptr<char>;
    buf[0] = 65;
    buf[1] = 0;
    return buf;
}
test(): int {
    var s = make();
    __ptr<char> t = s + 0;
    var r = t[0] as int;
    _pep_free(s as __ptr<void>);
    return r;
}
"#
        ),
        65
    );
}

#[test]
fn ptr_nested_pointer() {
    // `__ptr<__ptr<char>>` lowers to `char**`: indexing yields a `__ptr<char>`.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var buf: __ptr<char> = _pep_malloc(4) as __ptr<char>;
    buf[2] = 42;
    var pp: __ptr<__ptr<char>> = _pep_malloc(16) as __ptr<__ptr<char>>;
    pp[1] = buf;
    var inner: __ptr<char> = pp[1];
    var r = inner[2] as int;
    _pep_free(pp as __ptr<void>);
    _pep_free(buf as __ptr<void>);
    return r;
}
"#
        ),
        42
    );
}

#[test]
fn ptr_struct_field_and_global() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Holder {
    __ptr<char> data = __null;
}
var g: __ptr<void> = __null;
test(): int {
    var h = Holder();
    h.data = _pep_malloc(4) as __ptr<char>;
    h.data[0] = 5;
    var r = h.data[0] as int;
    if (g == __null) { r = r + 10; }
    _pep_free(h.data as __ptr<void>);
    return r;
}
"#
        ),
        15
    );
}

#[test]
fn ptr_type_alias() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
type Bytes = __ptr<char>;
second(p: Bytes): int {
    return p[1] as int;
}
test(): int {
    var b: Bytes = _pep_malloc(4) as Bytes;
    b[1] = 7;
    var r = second(b);
    _pep_free(b as __ptr<void>);
    return r;
}
"#
        ),
        7
    );
}

#[test]
fn ptr_local_in_constructor() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Buf {
    int first = 0;
    new() {
        var b: __ptr<char> = _pep_malloc(4) as __ptr<char>;
        b[0] = 3;
        first = b[0] as int;
        _pep_free(b as __ptr<void>);
    }
}
test(): int {
    var b = Buf();
    return b.first;
}
"#
        ),
        3
    );
}

#[test]
fn ptr_generic_argument() {
    // `__ptr<T>` as a generic argument: `Array<__ptr<char>>` lowers to `Array<char*>`.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var buf: __ptr<char> = _pep_malloc(4) as __ptr<char>;
    buf[0] = 8;
    var a = Array<__ptr<char>>();
    a.append(buf);
    var p: __ptr<char> = a[0];
    var r = p[0] as int;
    _pep_free(buf as __ptr<void>);
    return r;
}
"#
        ),
        8
    );
}

#[test]
fn ptr_compares_with_pointer_and_integer_operands() {
    // `==`/`!=` with a pointer on either side and a pointer or an integer on
    // the other compare addresses. A pointer on the left of an integer used
    // to be taken as pointer arithmetic and failed with "unsupported op
    // Equal on pointer" (a Windows HANDLE compared with an int local).
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var p = _pep_malloc(8);
    var q = p;
    var s = p + 1;
    long bits = p as long;
    long minus_one = -1;
    int small = 7;
    var r = 0;
    if (p == q) { r = r + 1; }
    if (p != s) { r = r + 10; }
    if (p == bits) { r = r + 100; }
    if (bits == p) { r = r + 1000; }
    if (p != minus_one) { r = r + 10000; }
    if (p != small) { r = r + 100000; }
    _pep_free(p);
    return r;
}
"#
        ),
        111111
    );
}
