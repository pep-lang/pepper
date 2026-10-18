<!-- Generated from runtime/math/module.pep by `pep-doc reference`. Do not edit. -->

# The math module

Numbers beyond the operators: the math library as it grows.

Bring it in with `import math`. The floating-point functions (`sine`,
`logarithm`, `cube_root`, `is_nan`, ...) are methods of `float` and
`double`, which every program has without an import; this module holds
the constants and the integer functions.

- [Constants](math-constants.md): `PI`, `TAU`, `E`, `INFINITY`, `NAN`, and
  the epsilon and limits of `float` and `double`
- [Integers](math-integers.md): `gcd` and `lcm`
- [Parsing](math-parse.md): `parse_int`, deprecated: every number type
  has a static `parse` (`long.parse(text, base)`) without an import

**Example**
```pepper
import math;
var radius = 2.0;
var area = math.PI * radius ** 2;
assert((math.PI / 2).sine() == 1.0, "a quarter turn");
```

Source: `runtime/math/module.pep`
