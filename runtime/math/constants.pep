## Constants for floating-point math: π, *e*, the infinities and NaN, and
## the limits of `float` and `double`.
##
## Each is a `double` unless its name starts with `FLOAT_`; write
## `math.PI as float` for a `float`.

## π, the ratio of a circle's circumference to its diameter.
export const PI: double = 3.141592653589793;

## τ = 2π, the angle of a full turn in radians.
export const TAU: double = 6.283185307179586;

## *e*, the base of the natural logarithm.
export const E: double = 2.718281828459045;

## Positive infinity; `-math.INFINITY` is negative infinity.
export const INFINITY: double = 1.0 / 0.0;

## A NaN (not a number). It is not equal to anything, itself included, so
## test for it with `is_nan()`, never `==`.
export const NAN: double = 0.0 / 0.0;

## The gap between 1 and the next larger `double`, 2^-52.
export const DOUBLE_EPSILON: double = 2.220446049250313e-16;

## The largest finite `double`.
export const DOUBLE_MAX: double = 1.7976931348623157e308;

## The smallest positive normal `double`, 2^-1022.
export const DOUBLE_MIN_POSITIVE: double = 2.2250738585072014e-308;

## The gap between 1 and the next larger `float`, 2^-23.
export const FLOAT_EPSILON: float = 1.1920928955078125e-7;

## The largest finite `float`.
export const FLOAT_MAX: float = 3.4028234663852886e38;

## The smallest positive normal `float`, 2^-126.
export const FLOAT_MIN_POSITIVE: float = 1.1754943508222875e-38;
