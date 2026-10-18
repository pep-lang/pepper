# A range literal passes where `Range<int>` is spelled: the literal's
# `Range<i32>` and the parameter's `Range<int>` are one value struct.

span(range: Range<int>): int {
    return range.end - range.start;
}

main(): int {
    var r = 1..>6;
    if (span(r) != 5 or span(2..9) != 7) {
        return 1;
    }
    return 0;
}
