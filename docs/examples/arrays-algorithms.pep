total(values: ArrayView<int>): int {
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

    # Reshaping.
    var digits = [1, 2, 3, 4, 5];
    digits.rotate(2);
    assert(digits == [3, 4, 5, 1, 2], "rotated");
    var drained = digits.drain(1, 3);
    assert(digits == [3, 1, 2] && drained == [4, 5], "drained");
    digits.remove_if((x) => x > 2);
    digits.extend_from(drained.slice(0, 1));
    assert(digits == [1, 2, 4], "filtered and extended");

    # Ordering without a full stable sort.
    var scores = [40, 95, 12, 77, 63, 8];
    scores.select_nth(2);
    assert(scores[2] == 40, "the third smallest");
    scores.partial_sort(2);
    assert(scores[0] == 8 && scores[1] == 12, "the two smallest, in order");
    scores.sort_unstable((x, y) => y - x);
    assert(scores == [95, 77, 63, 40, 12, 8], "descending");
    assert([1, 2, 3].compare([1, 3]) < 0, "lexicographic");
    assert([1, 2, 3] < [1, 3], "arrays of Comparable elements are Comparable");
    var rows = [[2, 1], [1, 5], [1]];
    rows.sort();
    assert(rows == [[1], [1, 5], [2, 1]], "an array of arrays sorts");

    # A slice views part of an array without copying it.
    var numbers = [1, 2, 3, 4, 5];
    var middle = numbers.slice(1, 4);
    assert(middle.count == 3 && middle[0] == 2, "views [2, 3, 4]");
    assert(total(middle) == 9, "passed to a function");
    assert(middle.to_array() == [2, 3, 4], "copied out");
    var (head, rest) = middle.split_at(1);
    assert(head.count == 1 && rest[0] == 3, "split in two");
    var pairs = 0;
    for (var pair in numbers.chunks(2)) {
        pairs = pairs + pair.count;   # [1, 2], [3, 4], [5]
    }
    assert(pairs == 5, "every element in some chunk");
    var rises = 0;
    for (var pair in numbers.windows(2)) {
        rises = rises + (pair[1] > pair[0] ? 1 : 0);
    }
    assert(rises == 4, "each neighbor is larger");
    assert(numbers.slice(0, 2) == [9, 1, 2].slice(1, 3), "equal elements");
    return 0;
}
