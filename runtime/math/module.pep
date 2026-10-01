## Numbers beyond the operators: parsing them from text for now, and the
## rest of the math library as it grows.
##
## Bring it in with `import math`.
##
## - [Parsing](math-parse.md): `parse_int`
##
## @example
##     import math;
##
##     main(): int {
##         var port = math.parse_int("8080");
##         assert(port.is_some() && port.value() == 8080, "parsed");
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "parse";

export parse_int;
