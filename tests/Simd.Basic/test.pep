# simd.Vector and simd.Mask: every operation, at each lane type.
# The corpus runs it natively and, under wasmtime, on WebAssembly without
# simd128 (the scalar fallback); simd_tests.rs runs it at -O2 and with
# -msimd128.
import simd;

# A vector of 0, 1, 2, ... in its lanes.
counting<T: simd.Lane, N>(): simd.Vector<T, N> {
    var v = simd.Vector<T, N>();
    ulong i = 0;
    while (i < v.count as ulong) {
        v[i] = i as T;
        i = i + 1;
    }
    return v;
}

integers() {
    var a = counting<int, 4>();
    var b = simd.Vector<int, 4>(10);
    assert(a.count == 4 && a[3] == 3, "lanes");
    assert((a + b)[2] == 12 && (b - a)[3] == 7 && (a * b)[3] == 30, "arithmetic");
    assert((a + 1)[0] == 1 && (a - 1)[0] == -1 && (a * 3)[2] == 6, "with a scalar");
    assert((b / 3)[0] == 3 && (b % 3)[0] == 1 && (-b / 3)[0] == -3 && (-b % 3)[0] == -1, "division");
    assert((a & 1)[3] == 1 && (a | 8)[1] == 9 && (a ^ b)[2] == 8 && (~a)[0] == -1, "bitwise");
    assert((a << 4)[3] == 48 && (-b >> 1)[0] == -5 && (-a)[2] == -2, "shifts");
    assert((-b).abs() == b && a.min(simd.Vector<int, 4>(2))[3] == 2 && a.max(simd.Vector<int, 4>(2))[0] == 2, "min, max, abs");
    assert(a.sum() == 6 && a.minimum() == 0 && a.maximum() == 3, "reductions");
    assert(simd.Vector<int, 4>(1).rotate_left(31)[0] == -2147483648 && simd.Vector<int, 4>(1).rotate_right(1)[1] == -2147483648, "rotates");
    # Wrapping, where scalar arithmetic panics.
    var top = simd.Vector<int, 4>(2147483647);
    assert((top + 1)[0] == -2147483648 && (top * 2)[0] == -2, "wraps");
    var lowest = simd.Vector<int, 4>(-2147483647 - 1);
    assert(lowest.abs() == lowest && -lowest == lowest, "lowest stays itself");
}

unsigned() {
    var a = simd.Vector<byte, 16>(200 as byte);
    assert((a + (100 as byte))[5] == 44, "byte wraps");
    assert((a / (255 as byte))[0] == 0 && (a >> 4)[0] == 12, "unsigned division and shift");
    assert(a.greater(100 as byte).all() && a.max(simd.Vector<byte, 16>(250 as byte))[0] == 250, "unsigned order");
    var c = simd.Vector<char, 16>(-56 as char);
    assert(c.less(0 as char).all() && (c >> 4)[0] == -4, "signed bytes");
    var u = simd.Vector<uint, 4>(0x80000000 as uint);
    assert(u.greater(1 as uint).all() && (u >> 31)[0] == 1 && u.minimum() == 0x80000000, "uint");
    var s = counting<short, 8>() * (1000 as short);
    assert(s[7] == 7000 && s.sum() == 28000 && (s * (10 as short))[7] == 4464, "short");
    var w = counting<ushort, 8>() - (1 as ushort);
    assert(w[0] == 65535 && w.maximum() == 65535 && w.minimum() == 0, "ushort");
    var l = counting<long, 2>() + 0x100000000;
    assert(l[1] == 0x100000001 && l.sum() == 0x200000001, "long");
    var q = simd.Vector<ulong, 2>(0xFFFFFFFFFFFFFFFF as ulong);
    assert((q + (2 as ulong))[0] == 1 && q.greater(0 as ulong).all(), "ulong");
}

floats() {
    var a = counting<float, 4>() + 0.5;
    assert(a[1] == 1.5 && (a * a)[2] == 6.25 && a.sum() == 8.0, "float arithmetic");
    assert((a / 0.5)[3] == 7.0 && (a % 1.0)[3] == 0.5 && (-a)[0] == -0.5, "float division");
    assert(a.floor()[3] == 3.0 && a.ceiling()[0] == 1.0 && (a * a).square_root() == a, "rounding");
    assert((-a).abs() == a && a.minimum() == 0.5 && a.maximum() == 3.5, "float reductions");
    var d = simd.Vector<double, 2>(1.0) / 0.0;
    assert(d[0] > 1e308 && d.equal(d).all(), "infinity");
    var nan = (simd.Vector<double, 2>() / 0.0);
    assert(!nan.equal(nan).any() && nan.not_equal(nan).all() && nan != nan, "NaN equals nothing");
    assert(nan.min(simd.Vector<double, 2>(2.0))[0] == 2.0, "min skips NaN");
}

masks() {
    var a = counting<int, 8>();
    var low = a.less(3);
    assert(low.count == 8 && low[2] && !low[3], "mask lanes");
    assert(low.to_bits() == 7 && low.any() && !low.all(), "to_bits, any, all");
    var odd = (a & 1).equal(1);
    assert(odd.to_bits() == 0xAA && (low & odd).to_bits() == 2 && (low | odd).to_bits() == 0xAF, "mask and, or");
    assert((low ^ odd).to_bits() == 0xAD && (~low).to_bits() == 0xF8, "mask xor, not");
    assert(a.less_equal(3).to_bits() == 0xF && a.greater(5).to_bits() == 0xC0 && a.greater_equal(7).to_bits() == 0x80, "comparisons");
    assert(a.not_equal(0).to_bits() == 0xFE && a.equal(a).all(), "equality");
    var picked = low.select(a, simd.Vector<int, 8>(-1));
    assert(picked[1] == 1 && picked[5] == -1, "select");
    assert(simd.Mask<16>(true).to_bits() == 0xFFFF && !simd.Mask<4>().any(), "splat masks");
    assert(simd.Mask<64>(true).to_bits() == 0xFFFFFFFFFFFFFFFF, "64 lanes");
    var bytes = simd.Vector<byte, 32>(32 as byte);
    bytes[17] = 0xE9 as byte;
    assert(bytes.greater_equal(0x80 as byte).to_bits().trailing_zeros() == 17, "first high byte");
}

shuffles() {
    var a = counting<int, 4>();
    var reversed = a.reverse();
    assert(reversed[0] == 3 && reversed[3] == 0, "reverse");
    var indices = simd.Vector<int, 4>(2);
    indices[3] = 5;  # taken modulo 4
    var picked = a.shuffle(indices);
    assert(picked[0] == 2 && picked[3] == 1, "shuffle");
    var b = a + 10;
    var low = a.interleave_low(b);
    var high = a.interleave_high(b);
    assert(low[0] == 0 && low[1] == 10 && low[2] == 1 && low[3] == 11, "interleave low");
    assert(high[0] == 2 && high[1] == 12 && high[3] == 13, "interleave high");
}

conversions() {
    var a = counting<int, 4>() - 1;
    var f = a.convert<float>();
    assert(f[0] == -1.0 && f[3] == 2.0, "int to float");
    var back = (f * 2.5).convert<int>();
    assert(back[0] == -2 && back[3] == 5, "float to int truncates");
    var big = simd.Vector<double, 2>(1e20);
    big[1] = -1.0 / 0.0;
    var clamped = big.convert<int>();
    assert(clamped[0] == 2147483647 && clamped[1] == -2147483648, "saturates");
    var nan = (simd.Vector<double, 2>() / 0.0).convert<long>();
    assert(nan[0] == 0, "NaN converts to 0");
    var narrowed = (a + 256).convert<byte>();
    assert(narrowed[0] == 255 && narrowed[2] == 1, "truncates");
    var widened = simd.Vector<char, 4>(-1 as char).convert<int>();
    var zero_extended = simd.Vector<byte, 4>(255 as byte).convert<int>();
    assert(widened[0] == -1 && zero_extended[0] == 255, "sign and zero extension");
    var bits = simd.Vector<float, 4>(1.0).reinterpret<uint, 4>();
    assert(bits[0] == 0x3F800000, "reinterpret");
    var bytes = simd.Vector<uint, 4>(0x04030201 as uint).reinterpret<byte, 16>();
    assert(bytes[0] == 1 && bytes[3] == 4 && bytes[4] == 1, "reinterpret to bytes");
}

memory() {
    var values = [1, 2, 3, 4, 5, 6, 7, 8, 9];
    var v = simd.Vector<int, 4>.load(values, 1);
    assert(v[0] == 2 && v[3] == 5, "load from an array");
    (v * 10).store(values, 5);
    assert(values[4] == 5 && values[5] == 20 && values[8] == 50, "store to an array");
    var raw = simd.Vector<int, 4>.load(values._data + 2);
    assert(raw[0] == 3, "load from a pointer");
    simd.Vector<int, 4>(0).store(values._data);
    assert(values[3] == 0 && values[4] == 5, "store to a pointer");
    var text = "abcdefghijklmnopqrstuvwxyz";
    var letters = simd.Vector<byte, 16>.load(unsafe_cast<__ptr<byte>>(text.c_str()));
    assert(letters[0] == 97 && letters.greater(0x6A as byte).to_bits() == 0xFC00, "load from a string's bytes");
}

# A value: copies are independent, and it can live in a struct and an array.
struct Holder {
    var lanes: simd.Vector<int, 4>;
    construct() {}
}

# Thread-safe: a module constant and a field of a [Shared] struct.
const ONES = simd.Vector<int, 4>(1);

[Shared]
struct Table {
    const scale: simd.Vector<float, 4>;
    construct() {
        scale = simd.Vector<float, 4>(2.0);
    }
}

values() {
    var a = simd.Vector<int, 4>(1);
    var b = a;
    b[0] = 5;
    assert(a[0] == 1 && b[0] == 5, "copied by value");
    var holder = Holder();
    holder.lanes = holder.lanes + 3;
    assert(holder.lanes.sum() == 12, "a field");
    var list = Array<simd.Vector<int, 4>>();
    list.append(a);
    list.append(b);
    assert(list[1][0] == 5 && list[0] != list[1], "in an array");
    var copied = copy(b);
    copied[1] = 7;
    assert(b[1] == 1 && copied[1] == 7, "copy");
    assert(ONES.sum() == 4 && Table().scale.sum() == 8.0, "shared");
}

main(): int {
    integers();
    unsigned();
    floats();
    masks();
    shuffles();
    conversions();
    memory();
    values();
    print("simd ok");
    return 0;
}
