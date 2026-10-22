# An imported `const` string (a `StringConstant`) next to the result of a
# method of a runtime specialization (`Optional<String>.value`), built whole
# and in compilation units: `T` is `String` either way (#175).
import k;

const LOCAL = "local";

same<T>(a: T, b: T): bool {
    return a == b;
}

show(text: String): String {
    return "String " + text;
}

show(text: StringConstant): String {
    return "StringConstant " + text;
}

main(): int {
    var kind = Optional<String>.Value("quickfix");
    print(same(kind.value(), k.QUICK_FIX));
    print(same(kind.value(), LOCAL));
    var copy = k.QUICK_FIX;
    print(show(copy));
    print(show(k.QUICK_FIX));
    print($"{k.QUICK_FIX}/{LOCAL}");
    return 0;
}
