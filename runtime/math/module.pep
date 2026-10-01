## Numbers beyond the operators: the math library as it grows.
##
## Bring it in with `import math`.
##
## - [Parsing](math-parse.md): `parse_int`, deprecated: every number type
##   has a static `parse` (`long.parse(text, base)`) without an import

# This file only gathers the module's public API from its other files.

import "parse";

export parse_int;
