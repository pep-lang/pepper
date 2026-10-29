# Structs named like the type parameters of Array, HashMap and a generic
# of the program's own are their type arguments (#317): the program
# exits with 1 + 3 + 1.

struct T {
    var n: int = 1;
}

struct K {
    var n: int = 2;
}

struct V {
    var n: int = 3;
}

struct Box<T> {
    var item: T;

    construct(item: T) {
        this.item = item;
    }
}

main(): int {
    var a = Array<T>();
    a.append(T());
    var m = HashMap<K, V>();
    var key = K();
    m[key] = V();
    var b = Box<T>(T());
    return a[0].n + m[key].n + b.item.n;
}
