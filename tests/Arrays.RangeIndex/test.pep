# A range written as an index is a slice (#370): `a[i..j]` is
# `a.slice(i, j)` and `a[i..>j]` includes `j`, on an Array and on a slice.

main(): int {
    var a = [1, 2, 3, 4, 5];
    var middle = a[1..4];
    assert(middle.count == 3 && middle[0] == 2 && middle[2] == 4, "half-open");
    var tail = a[3..>4];
    assert(tail.to_array() == [4, 5], "closed");
    ulong two = 2;
    assert(a[0..two].count == 2, "ulong bounds");
    assert(middle[1..>2].to_array() == [3, 4], "a slice of a slice");
    assert(a[2..2].count == 0, "empty");
    var start = 1;
    assert(a[start..start + 2][1] == 3, "computed bounds");
    return 0;
}
