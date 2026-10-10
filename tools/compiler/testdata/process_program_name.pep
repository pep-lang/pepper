# Exits with 0 when argument zero names this program (programs_test.pep).

import process;

main(): int {
    return process.arguments()[0].contains("process_program_name") ? 0 : 1;
}
