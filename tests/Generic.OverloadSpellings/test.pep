# Two spellings of one type argument (`int`, `i32`) make two
# specializations; an overloaded method of theirs is still one candidate.
struct Box<T> {
    var item: T;

    construct(item: T) {
        this.item = item;
    }

    value(): T {
        return item;
    }

    value(fallback: T): T {
        return item;
    }
}

main(): int {
    var a = Box<int>(1);
    var b = Box<i32>(2);
    if (a.value() + b.value() != 3) {
        return 1;
    }
    if (a.value(0) + b.value(0) != 3) {
        return 2;
    }
    return 0;
}
