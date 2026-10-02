# `T` is a type parameter: each use such as `Stack<int>` or
# `Stack<String>` makes a separate, fully typed version of the struct.
struct Stack<T> {
    var items: Array<T>;

    construct() {
        items = Array<T>();
    }

    push(item: T) {
        items.append(item);
    }

    pop(): T {
        return items.pop();
    }

    peek(): T {
        # `top` is inferred as `T`: an `int` in `Stack<int>`, a `String`
        # in `Stack<String>`.
        var top = items.last();
        return top;
    }

    is_empty(): bool {
        return items.is_empty;
    }
}

# Several parameters are separated by commas.
struct Entry<K, V> {
    var key: K;
    var value: V;
    construct(K key, V value) {
        this.key = key;
        this.value = value;
    }
}

main(): int {
    var numbers = Stack<int>();
    numbers.push(1);
    numbers.push(2);
    assert(numbers.peek() == 2, "peek looks at the top");
    assert(numbers.pop() == 2, "last in, first out");
    assert(numbers.pop() == 1, "then the first");
    assert(numbers.is_empty(), "empty again");

    var words = Stack<String>();
    words.push("hello");
    assert(words.pop() == "hello", "the same code works for Strings");

    var e = Entry<String, int>("answer", 42);
    assert(e.key == "answer" && e.value == 42, "two type parameters");
    return 0;
}
