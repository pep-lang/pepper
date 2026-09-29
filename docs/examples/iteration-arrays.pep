struct Item {
    int Value;
    construct(this.Value = 0) {}
}

make_items(): Array<Item> {
    var items = Array<Item>();
    items.append(Item(20));
    items.append(Item(22));
    return items;
}

main(): int {
    var nums = Array<int>();
    nums.append(1);
    nums.append(2);
    nums.append(39);

    # The basic loop: x takes each element in order.
    var total = 0;
    for (var x in nums) {
        total = total + x;
    }
    assert(total == 42, "sum of the elements");

    # The loop variable may be typed, and the parentheses are optional.
    long wide = 0;
    for (long x in nums) {
        wide = wide + x;
    }
    for var x: int in nums {
        wide = wide - x;
    }
    assert(wide == 0, "typed loop variables");

    # break and continue work as in a while loop.
    var odd = 0;
    for (var x in nums) {
        if (x % 2 == 0) {
            continue;
        }
        if (x > 10) {
            break;
        }
        odd = odd + x;
    }
    assert(odd == 1, "only 1 is odd and below 10");

    # A struct element is shared: changing a field changes the element,
    # but rebinding the loop variable does not touch the array.
    var items = make_items();
    for (var item in items) {
        item.Value = item.Value * 10;
        item = Item(99);
    }
    assert(items[0].Value == 200, "first element was updated");
    assert(items[1].Value == 220, "second element was updated");

    # Iterating a temporary keeps it alive for the whole loop.
    var sum = 0;
    for (var item in make_items()) {
        sum = sum + item.Value;
    }
    assert(sum == 42, "temporary array stays alive");

    # The loop is shorthand for driving the iterator yourself.
    var it = nums.iterate();
    var manual = 0;
    while (it.next()) {
        manual = manual + it.current();
    }
    assert(manual == 42, "the same elements, by hand");

    # Modifying the array after the loop is fine.
    nums.append(100);
    assert(nums.count() == 4, "appended after the loop");
    return 0;
}
