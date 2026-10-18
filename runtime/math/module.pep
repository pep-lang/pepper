## Numbers beyond the operators: the math library as it grows.
##
## Bring it in with `import math`. The floating-point functions (`sine`,
## `logarithm`, `cube_root`, `is_nan`, ...) are methods of `float` and
## `double`, which every program has without an import; this module holds
## the constants and the integer functions.
##
## - [Constants](math-constants.md): `PI`, `TAU`, `E`, `INFINITY`, `NAN`, and
##   the epsilon and limits of `float` and `double`
## - [Integers](math-integers.md): `gcd` and `lcm`
## - [Parsing](math-parse.md): `parse_int`, deprecated: every number type
##   has a static `parse` (`long.parse(text, base)`) without an import
##
## @example
##     import math;
##     var radius = 2.0;
##     var area = math.PI * radius ** 2;
##     assert((math.PI / 2).sine() == 1.0, "a quarter turn");

# This file only gathers the module's public API from its other files.

import "constants";
import "integers";
import "parse";

export PI;
export TAU;
export E;
export INFINITY;
export NAN;
export DOUBLE_EPSILON;
export DOUBLE_MAX;
export DOUBLE_MIN_POSITIVE;
export FLOAT_EPSILON;
export FLOAT_MAX;
export FLOAT_MIN_POSITIVE;
export gcd;
export lcm;
export parse_int;
