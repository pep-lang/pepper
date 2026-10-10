# Does not build: `add_options` cannot declare a map field
# (programs_test.pep).

import cli;

struct Options {
    var table: Map<String, int>;
}

main(): int {
    cli.Parser("x").add_options(Options());
    return 0;
}
