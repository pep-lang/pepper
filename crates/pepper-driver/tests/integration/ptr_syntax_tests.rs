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
const g: __ptr<void> = __null;
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
    construct() {
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
fn ptr_arithmetic_strides_by_pointer_and_float_elements() {
    // `p + n` advances `n` elements: a pointer element is 8 bytes and a
    // double 8, a float 4. Pointer and float elements used to stride by one
    // byte and four bytes, so `slot + 1` on a `__ptr<__ptr<void>>` (an out
    // parameter pair for CreatePipe) wrote across the first slot.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    __ptr<__ptr<void>> slots = _pep_malloc(16);
    __ptr<double> d = _pep_malloc(16);
    __ptr<float> f = _pep_malloc(16);
    var r = ((slots + 1) as long - slots as long) as int;
    r = r * 100 + ((d + 1) as long - d as long) as int;
    r = r * 100 + ((f + 1) as long - f as long) as int;
    _pep_free(slots);
    _pep_free(d);
    _pep_free(f);
    return r;
}
"#
        ),
        80804
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

#[test]
fn var_from_ptr_index_infers_the_pointee_type() {
    // `var v = p[i]` takes the pointee's type, so a `ulong` above 2^32
    // survives the read. It used to infer `int` (truncating) whenever `p`
    // was a parameter or field: in a free function, a static method, a
    // method reading a field, a generic struct's method, and through a
    // pointer to a pointer.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
free_read(p: __ptr<ulong>, i: ulong): ulong {
    var v = p[i];
    return v;
}
free_equal(p: __ptr<ulong>): bool {
    var v = p[1];
    return v == 5000000001;
}
struct Slots {
    __ptr<ulong> data;
    construct() { data = _pep_malloc(16); }
    static read(p: __ptr<ulong>): ulong {
        var v = p[0];
        return v;
    }
    read_field(): ulong {
        var v = data[1];
        return v;
    }
}
struct Reader<T> {
    static read(p: __ptr<T>): T {
        var v = p[0];
        return v;
    }
}
nested(pp: __ptr<__ptr<ulong>>): ulong {
    var p = pp[0];
    var v = p[1];
    return v;
}
test(): int {
    __ptr<ulong> p = _pep_malloc(16);
    p[0] = 5000000000;
    p[1] = 5000000001;
    __ptr<__ptr<ulong>> pp = _pep_malloc(8);
    pp[0] = p;
    var s = Slots();
    s.data[1] = 5000000002;
    var r = 0;
    if (free_read(p, 1) == 5000000001) { r = r + 1; }
    if (free_equal(p)) { r = r + 10; }
    if (Slots.read(p) == 5000000000) { r = r + 100; }
    if (s.read_field() == 5000000002) { r = r + 1000; }
    if (Reader<ulong>.read(p) == 5000000000) { r = r + 10000; }
    if (nested(pp) == 5000000001) { r = r + 100000; }
    _pep_free(pp);
    _pep_free(p);
    return r;
}
"#
        ),
        111111
    );
}
