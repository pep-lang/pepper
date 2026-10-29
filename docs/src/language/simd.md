# SIMD vectors

A SIMD vector holds several numbers of one type, its **lanes**, and computes
on all of them with one instruction. The `simd` module has two types:

- `Vector<T, N>`: `N` lanes of the number type `T`.
- `Mask<N>`: `N` booleans, what a lane-wise comparison gives.

```pepper
{{#include ../../examples/simd-basics.pep}}
```

Bring them in with `import simd;` and write `simd.Vector<byte, 16>`, or
`import [Vector, Mask] from simd;` and write `Vector<byte, 16>`.

## Lane types and counts

- `T` is an integer or floating-point type: `byte`, `char`, `short`,
  `ushort`, `int`, `uint`, `long`, `ulong`, `float` or `double`. These
  conform to the module's `Lane` trait; any other type is an error at the
  type argument:

  ```text
  main.pep:3:25: error: 'String' does not conform to trait 'Lane', required by 'T' in 'Vector'
  ```

  `Lane` is sealed: only the runtime declares its conformances, so
  `extend Money with simd.Lane` is an error too:

  ```text
  main.pep:7:19: error: 'Lane' is sealed: only the runtime declares which types conform to it
  ```

- `N` is written as a number, a power of two from 1 to 64:

  ```text
  main.pep:3:30: error: lane count of 'Vector<int, 3>' must be a power of two from 1 to 64, not '3'
  ```

  A number is a type argument only here, for a lane count (and for a
  struct of yours that passes its parameter on as one, such as a field of
  type `Vector<T, N>`). Anywhere else it is an error at the number:

  ```text
  main.pep:5:20: error: '4' is not a type; a number is a type argument only as a SIMD type's lane count, as in 'simd.Vector<float, 4>'
  ```

  It is not a general constant parameter, so code cannot compute with `N`
  (use the `count` property for the lane count as a value).

- Sixteen bytes (`Vector<byte, 16>`, `Vector<short, 8>`, `Vector<int, 4>`,
  `Vector<float, 4>`, `Vector<double, 2>`) fits a vector register on every
  target Pepper supports and is the width to reach for first. A wider vector
  works everywhere: where the target's registers are narrower, each
  operation takes several instructions.

A vector is a [value struct](value-structs.md): it is stored inline, copied
like a number, and safe to share between threads (a `[Shared]` struct's
field, a module constant).

## Operations

| | |
|---|---|
| Make | `Vector<T, N>()` (every lane 0), `Vector<T, N>(x)` (every lane `x`) |
| Lanes | `v[i]`, `v[i] = x` (panics when `i >= N`), `v.count` |
| Arithmetic | `+ - *`, unary `-`, with a vector or a scalar: `v * 2` |
| Division | `/ %`: integer lanes panic on a zero divisor lane, and on the lowest value divided by -1; float lanes follow IEEE |
| Bitwise (integers) | `& \| ^ ~`, `<< >>` by an `int` count (panics outside `0..` the lane width; `>>` is arithmetic for signed `T`), `rotate_left`, `rotate_right` |
| Floats | `square_root`, `floor`, `ceiling` |
| Both | `min`, `max`, `abs` |
| Horizontal | `sum`, `minimum`, `maximum` |
| Comparisons | `equal`, `not_equal`, `less`, `less_equal`, `greater`, `greater_equal`, with a vector or a scalar, giving a `Mask<N>` |
| Whole vector | `==` (every lane equal), `!=` (some lane differs) |
| Rearranging | `shuffle(indices)`, `reverse`, `interleave_low`, `interleave_high` |
| Types | `convert<U>()` (lane by lane, like `as`), `reinterpret<U, M>()` (the same bits) |
| Memory | `Vector<T, N>.load(array, index)`, `v.store(array, index)` (panic unless `index + N <= array.count`); `load`, `store`, `load_aligned`, `store_aligned` on a `__ptr<T>` |

A mask has `any()`, `all()`, `& | ^ ~`, `m[i]`, `select(a, b)` (each lane
from `a` where the mask is true, else from `b`) and `to_bits()`, which packs
lane `i` into bit `i` of a `ulong`. With `trailing_zeros()` (see
[integer bit methods](types-and-variables.md)) that finds the first true
lane, which is how a scan for a byte, or for a byte that is not ASCII, finds
its match sixteen bytes at a time.

Some differences from scalar arithmetic are deliberate:

- Integer lanes **wrap around** on overflow in `+`, `-`, `*`, unary `-` and
  `abs`, as vector instructions do; scalar arithmetic panics instead.
- Comparisons that give a lane per lane are methods, because a comparison
  operator must return `bool` (see [operators](structs.md#operators)). `==`
  and `!=` compare whole vectors.
- `shuffle` takes each index modulo `N`, so every index picks a lane. With
  constant indices an optimized build makes it one shuffle instruction.
- `convert` from float to integer saturates: a lane outside the target
  type's range becomes its nearest value, and NaN becomes 0.
- The bitwise operators, shifts and rotates exist only for integer lanes,
  and `square_root`, `floor` and `ceiling` only for float lanes:

  ```text
  main.pep:4:15: error: no member named 'square_root' in 'Vector<int, 4>'
  ```

## Targets and optimization

The operations compile to LLVM vector instructions, which the target turns
into its own: SSE2 on x86-64 (wider with `-march=x86-64-v3` for AVX2, see
[pep-build](../tools/pep-build.md)), NEON on arm64, and WebAssembly's
`simd128` with `-msimd128`. A target without vector instructions, such as
`wasm32-wasip1` without `-msimd128`, computes the same results one lane at a
time. Nothing picks instructions at run time: the `-m` options decide.

Each operation is a small method that the compiler always inlines, so an
optimized build (`-O2`) of a loop over vectors has no calls in it, only the
vector instructions. At `-O0` it still runs, more slowly, like the rest of
an unoptimized program.
