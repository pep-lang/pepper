# A generic method's type parameter may default to a type parameter of the
# struct or trait that declares it (`widen<U=T>`): each specialization of
# the struct, and each type a trait's default method is copied into, gets
# the default with its own type argument.

trait Holds<T> {
    held(): T;

    pair<U=T>(): (U, U) {
        U value = held();
        return (value, value);
    }
}

struct Box<T> {
    var value: T;

    construct(value: T) {
        this.value = value;
    }

    held(): T {
        return value;
    }

    widen<U=T>(): U {
        U result = value;
        return result;
    }
}

extend Box<T> with Holds<T>;

main(): int {
    var small = Box<int>(3);
    if (small.widen() != 3) {
        return 1;
    }
    long wide = small.widen<long>();
    if (wide != 3) {
        return 2;
    }
    var (a, b) = Box<String>("x").pair();
    if (a + b != "xx") {
        return 3;
    }
    return 0;
}
