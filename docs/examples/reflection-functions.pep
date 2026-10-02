[Attribute]
struct Check {
    const weight: int = 1;
}

[Check]
check_addition(): bool {
    return 1 + 1 == 2;
}

[Check(weight = 3)]
check_strings(): bool {
    return "ab" + "c" == "abc";
}

# `reflect.functions_with<A>()` lists every function in the program that
# carries `A`; `check.call()` calls it directly.
run_checks(): int {
    var score = 0;
    static (score) {
        for (var check in reflect.functions_with<Check>()) {
            if (check.call()) {
                score += check.attribute<Check>().weight;
            }
        }
    }
    return score;
}

main(): int {
    assert(run_checks() == 4, "each [Check] function runs once, weighted");
    return 0;
}
