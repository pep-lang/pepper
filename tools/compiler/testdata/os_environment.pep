# Prints the variables the parent sets (programs_test.pep), and exits with
# how many of them it lists.

import os;

main(): int {
    var set = os.environment("OS_TEST_SET");
    print($"set=[{set.value_or("<none>")}]");
    print($"empty=[{os.environment("OS_TEST_EMPTY").value_or("<none>")}]");
    print($"missing={os.environment("OS_TEST_MISSING").is_empty()}");
    print($"blank={os.environment("").is_empty()}");
    var count = 0;
    for (var (name, value) in os.environment_variables()) {
        if (name == "OS_TEST_SET" || name == "OS_TEST_EMPTY" || name == "OS_TEST_EQUALS") {
            print($"listed {name}=[{value}]");
            count = count + 1;
        }
    }
    var variables = os.environment_variables();
    if (!variables.contains("OS_TEST_SET") || variables.get("OS_TEST_EQUALS") != "a=b=c") {
        return 100;
    }
    return count;
}
