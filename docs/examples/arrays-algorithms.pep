total(values: ArraySlice<int>): int {
    var sum = 0;
    for (var x in values) {
        sum = sum + x;
    }
    return sum;
}

main(): int {
    # Searching a sorted array.
    var sorted = [1, 3, 3, 5, 8];
    assert(sorted.is_sorted(), "sorted");
    assert(sorted.binary_search(5).value() == 3, "found at 3");
    assert(sorted.binary_search(4).is_empty(), "no 4");
    assert(sorted.upper_bound(3) - sorted.lower_bound(3) == 2, "two 3s");

    # Changing elements in place.
    var a = [4, 4, 1, 2, 2, 7];
    a.dedup();
    assert(a == [4, 1, 2, 7], "adjacent repeats removed");
    a.retain((x) => x % 2 == 0);
    assert(a == [4, 2], "odd elements removed");
    a.resize(4, 0);
    assert(a == [4, 2, 0, 0], "padded with 0");
    var tail = a.split_off(2);
    assert(a == [4, 2] && tail == [0, 0], "split in two");
    tail.fill(9);
    assert(tail == [9, 9], "filled");

    # A slice views part of an array without copying it.
    var numbers = [1, 2, 3, 4, 5];
    var middle = numbers.slice(1, 4);
    assert(middle.count == 3 && middle[0] == 2, "views [2, 3, 4]");
    assert(total(middle) == 9, "passed to a function");
    assert(middle.to_array() == [2, 3, 4], "copied out");
    return 0;
}
