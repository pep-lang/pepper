# An extern bound to an LLVM intrinsic: a call is the instruction itself.
[Link(name = "llvm.umin")]
extern ulong smaller(ulong a, ulong b);

# `llvm.ctlz` takes a second argument that must be a constant.
[Link(name = "llvm.ctlz")]
extern ushort leading_zeros(ushort value, bool is_zero_poison);

main(): int {
    assert(smaller(7, 3) == 3, "llvm.umin.i64");
    assert(leading_zeros(1, false) == 15, "llvm.ctlz.i16");
    return 0;
}
