## The usual arithmetic conversions: `pepper_sema::arithmetic` in Pepper.
## The type a `var` infers from `a + b`: integers promote to at least 32
## bits, keeping unsignedness only at the promoted width; floats to the
## wider float; an enum computes as the integer type it is stored as.

import [BinaryOp, TypeName] from "model";
import [PassState] from "state";

## Returns `name`, or the integer type it is stored as when it names an
## enum.
##
## @param state the passes' state, which knows the enums
## @param name the type's name
## @returns the type it computes as
export stored_as(state: PassState, name: String): String {
    var found = state.enum_representations.try_get(name);
    if (found.is_value()) {
        var (representation, _) = found.value();
        return representation;
    }
    return name;
}

## Returns the bit width a numeric primitive is stored in (`bool` is 1).
##
## @param name the type's name
## @returns the width, or none for any other type
export bit_width(name: String): uint? {
    match (name) {
        "bool", "i1" => {
            return Optional<uint>.Value(1);
        }
        "i8", "char", "u8", "byte" => {
            return Optional<uint>.Value(8);
        }
        "i16", "short", "u16", "ushort" => {
            return Optional<uint>.Value(16);
        }
        "i32", "int", "u32", "uint", "f32", "float" => {
            return Optional<uint>.Value(32);
        }
        "f64", "double", "i64", "long", "u64", "ulong" => {
            return Optional<uint>.Value(64);
        }
        else => {
            return Optional<uint>.Empty;
        }
    }
}

## Whether `name` is a numeric primitive (bool, integer or float, aliases
## included), not an enum.
export is_primitive_numeric(name: String): bool {
    return bit_width(name).is_value();
}

## Returns whether `name` is a numeric primitive or an enum.
##
## @param state the passes' state, which knows the enums
## @param name the type's name
## @returns true for a number
export is_numeric_type(state: PassState, name: String): bool {
    return is_primitive_numeric(name) or state.enum_representations.contains(name);
}

## Returns whether `name` is an unsigned integer type, or an enum stored as
## one.
##
## @param state the passes' state, which knows the enums
## @param name the type's name
## @returns true for an unsigned integer
export is_unsigned_int_type(state: PassState, name: String): bool {
    match (stored_as(state, name)) {
        "u8", "byte", "u16", "ushort", "u32", "uint", "u64", "ulong" => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## Returns whether `name` is a float type.
##
## @param name the type's name
## @returns true for `f32` and `f64`, by any spelling
export is_float_type(name: String): bool {
    return name == "f32" or name == "float" or name == "f64" or name == "double";
}

_width(name: String): uint {
    var w = bit_width(name);
    return w.is_value() ? w.value() : 32;
}

## Returns the result type of a mixed-type arithmetic operation, as
## `arithmetic::result_type` does.
##
## @param state the passes' state, which knows the enums
## @param left the left operand's type
## @param right the right operand's type
## @returns the promoted type's name
export result_type(state: PassState, left: String, right: String): String {
    var lhs = stored_as(state, left);
    var rhs = stored_as(state, right);
    if (!is_numeric_type(state, lhs) or !is_numeric_type(state, rhs)) {
        return lhs;
    }
    var w = _width(lhs) > _width(rhs) ? _width(lhs) : _width(rhs);
    if (is_float_type(lhs) or is_float_type(rhs)) {
        return w > 32 ? "f64" : "f32";
    }
    uint promoted = w > 32 ? 64 : 32;
    bool unsigned = (is_unsigned_int_type(state, lhs) and _width(lhs) == promoted)
        or (is_unsigned_int_type(state, rhs) and _width(rhs) == promoted);
    if (w > 32) {
        return unsigned ? "u64" : "i64";
    }
    return unsigned ? "u32" : "i32";
}

## Returns the type of the arithmetic or bitwise `lhs op rhs` on numeric
## operands (a shift keeps its promoted left operand's type).
##
## @param state the passes' state
## @param op the operator
## @param lhs the left operand's type
## @param rhs the right operand's type
## @returns the type, or none when an operand is not numeric
export binary_result(state: PassState, op: BinaryOp, lhs: String, rhs: String): String? {
    if (!is_numeric_type(state, lhs) or !is_numeric_type(state, rhs)) {
        return Optional<String>.Empty;
    }
    if (op == BinaryOp.LShift or op == BinaryOp.RShift) {
        return Optional<String>.Value(result_type(state, lhs, lhs));
    }
    return Optional<String>.Value(result_type(state, lhs, rhs));
}

## Returns the type of `c ? a : b` whose arms have types `a` and `b`: the
## arms' type when they agree, else for two numbers their usual arithmetic
## conversion; anything else keeps `a`.
##
## @param state the passes' state
## @param a the first arm's type
## @param b the second arm's type
## @returns the type's name
export conditional_result(state: PassState, a: String, b: String): String {
    if (a == b or _canonical(TypeName.named(a)) == _canonical(TypeName.named(b))) {
        return a;
    }
    if (!is_primitive_numeric(a) or !is_primitive_numeric(b)) {
        return a;
    }
    return result_type(state, a, b);
}

## Returns the type of an integer literal, as in C: `i32` when it fits,
## else `i64`.
##
## @param value the literal
## @returns the type's name
export int_literal_type(value: long): String {
    return value >= -2147483648 and value <= 2147483647 ? "i32" : "i64";
}
