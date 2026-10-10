# Prints the system's name and the architecture (programs_test.pep).

import os;

main(): int {
    print(os.system_name());
    print(os.system_os().name());
    print(os.architecture());
    return 0;
}
