# Imports the Pepper shared library `tally`: the program, the library and
# the runtime library they both link share one heap, so the program extends
# and frees what the library made.

import tally;

main(): int {
    var names = tally.starting("ada");
    names.add("grace");
    print($"{", ".join(names.names)}: {tally.total.load()}");
    return 0;
}

# Output:
# ada, grace: 2
