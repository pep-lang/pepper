## Random numbers: bytes from the operating system's secure source, and
## `Generator`, a fast seedable generator for everything else.
##
## `random` is a module: bring it in with `import random` (and write
## `random.next_int(1..>6)`) or import names directly with
## `import [Generator, shuffle] from random`.
##
## - [Entropy](random-entropy.md): `bytes`, `fill` and `secure_ulong`, from the
##   operating system, for keys, tokens and identifiers
## - [Generators](random-generator.md): `Generator`, seeded from entropy or
##   from a fixed seed, and `next_int`, `next_double`, `next_bool`,
##   `choose` and `shuffle` on this thread's own generator
##
## @example
##     import random;
##
##     main(): int {
##         var die = random.next_int(1..>6);            # 1 to 6
##         var names = ["ada", "grace", "edsger"];
##         random.shuffle(names);
##         var key = random.bytes(32);                   # 32 secure bytes
##         var replay = random.Generator(42);            # the same numbers every run
##         print(replay.next_double());
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "entropy";
import "generator";

export fill;
export bytes;
export secure_ulong;
export Generator;
export next_ulong;
export next_int;
export next_double;
export next_bool;
export choose;
export shuffle;
