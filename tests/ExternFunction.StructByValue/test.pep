# C functions that take and return structs by value (#384): the C library's
# `div` and `lldiv`, which return a quotient and remainder together.

[Value]
struct Division {
    var quot: int;
    var rem: int;
}

[Value]
struct LongDivision {
    var quot: i64;
    var rem: i64;
}

extern Division div(int numerator, int denominator);
extern LongDivision lldiv(i64 numerator, i64 denominator);

main(): int {
    var small = div(17, 5);
    assert(small.quot == 3 && small.rem == 2, "17 / 5 is 3, remainder 2");
    var large = lldiv(10000000007, 10);
    assert(large.quot == 1000000000 && large.rem == 7, "C's long long division");
    return 0;
}
