# A small library, documented the way the standard library is.
# This line and the one above are ordinary comments: they start with a
# single '#'. Doc comments start with '##'.

## A last-in, first-out collection.
##
## Elements come out in the reverse of the order they went in.
##
## @typeParam T the type of the elements
## @example
##     var s = Stack<int>();
##     s.push(1);
##     s.push(2);
##     var top = s.pop();   # top == 2
struct Stack<T> {
    ## The elements, bottom first.
    var items: Array<T> = Array<T>();

    ## Adds `value` on top of the stack.
    ##
    ## @param value the element to add
    push(value: T) {
        items.append(value);
    }

    ## Removes and returns the element on top of the stack.
    ##
    ## @returns the element that was pushed last
    ## @panics if the stack is empty
    ## @see Stack.push
    pop(): T {
        assert(items.count > 0, "pop() on an empty Stack");
        return items.remove_at(items.count - 1);
    }

    ## Returns the number of elements.
    ##
    ## @returns how many elements the stack holds
    count(): ulong {
        return items.count;
    }
}

## Returns the larger of `a` and `b`.
##
## @param a the first value
## @param b the second value
## @returns `a` when it is at least `b`, otherwise `b`
## @note ties return `a`
larger(a: int, b: int): int {
    # An implementation note for maintainers, not part of the docs.
    return a >= b ? a : b;
}

main(): int {
    var s = Stack<int>();
    s.push(1);
    s.push(2);
    assert(s.pop() == 2, "the last element comes out first");
    assert(s.count() == 1, "one element is left");
    assert(larger(3, 7) == 7, "larger returns the larger value");
    return 0;
}
