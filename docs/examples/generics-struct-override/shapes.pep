# A generic function, and code that calls it for any type.
export describe<T>(v: T): int {
    return 0;
}

export describe_twice<T>(v: T): int {
    return describe<T>(v) * 2;
}
