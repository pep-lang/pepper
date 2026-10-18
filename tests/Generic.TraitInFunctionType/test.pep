# A trait type naming a generic function's parameter inside a function type
# (`(T) => Iterator<U>`) is substituted when the function is specialized,
# and the unspecialized function compiles (#992).

# Never called: its signature alone used to fail.
unused<T, U>(make: (T) => Iterator<U>): int {
    return 0;
}

first_of<T, U>(item: T, make: (T) => Iterator<U>, fallback: U): U {
    Iterator<U> inner = make(item);
    if (inner.next()) {
        return inner.current();
    }
    return fallback;
}

main(): int {
    if (first_of<int, String>(2, (n) => { Iterator<String> it = ["x", "y"].iterate(); return it; }, "") != "x") {
        return 1;
    }
    if (first_of<int, int>(7, (n) => { Iterator<int> it = [n].iterate(); return it; }, 0) != 7) {
        return 2;
    }
    return 0;
}
