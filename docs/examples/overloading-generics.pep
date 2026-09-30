# Generic and non-generic overloads, and overloads called from generic code.

# A non-generic overload wins a tie with a generic one.
describe<T>(value: T): String { return "something"; }
describe(value: int): String { return "an int"; }

# Generic overloads can differ in their number of parameters.
last<T>(a: T): T { return a; }
last<T>(a: T, b: T): T { return b; }

kind(n: int): String { return "number"; }
kind(s: String): String { return "text"; }

# Each specialization resolves `kind` for its own `T`.
label<T>(value: T): String { return kind(value); }

main(): int {
    assert(describe(7) == "an int", "non-generic wins the tie");
    assert(describe(1.5) == "something", "only the generic fits");
    assert(describe<int>(7) == "something", "type arguments pick generic overloads");

    assert(last(1) == 1, "one argument");
    assert(last(1, 2) == 2, "two arguments");

    assert(label(3) == "number", "label<int> calls kind(int)");
    assert(label("x") == "text", "label<String> calls kind(String)");
    return 0;
}
