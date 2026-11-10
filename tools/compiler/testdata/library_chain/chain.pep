# A Pepper library whose structs a program's chains run through
# (`pepper_library_test.pep`, #220): a `Box` holds any `Item`, and a
# `Pair`, an `Item`, holds a `Box`, so `Box -> Pair -> Box` is a cycle of
# the library's own that the program's `Wrap` extends.

export trait Item {
    links(): int;
}

# The end of a chain.
export struct End {}

extend End with Item {
    links(): int {
        return 0;
    }
}

export struct Box {
    var item: Item;

    construct(item: Item) {
        this.item = item;
    }
}

export struct Pair {
    var box: Box;

    construct(box: Box) {
        this.box = box;
    }
}

extend Pair with Item {
    links(): int {
        return 1;
    }
}
