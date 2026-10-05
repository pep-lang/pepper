## Runtime checks (#265), as `crates/pepper-codegen/src/checks.rs` makes
## them: integer arithmetic that overflows, a division by zero (or
## `MIN / -1`), and a shift by at least the type's width panic with a
## located message. Each checked operation branches to its own cold block
## that calls `_pep_panic`; two constant operands that overflow are a
## compile error at the operator.

import compiler.ast;
import llvm;
import compiler.sema;
import [BinaryOp, Loc] from compiler.sema;
import "address";
import "calls";
import "expressions";
import "functions";
import [Generator] from "generator";
import "generator";
import "globals";
import "lazy";
import "operators";
import "ops";
import "refs";
import "simd";
import "traits";
import "types";

## The first byte of a location that a call in an `[Unsafe("bounds")]`
## function passes as `__caller_location()`.
const UNCHECKED_BOUNDS_MARK = "\x01";

## The attribute that turns runtime checks off in one function's body.
const UNSAFE_ATTRIBUTE = "Unsafe";

## The `LLVMAttributeFunctionIndex` a call attribute on the call itself
## takes.
const FUNCTION_ATTRIBUTE_INDEX: uint = 0xffffffff;

## Which runtime checks the generated code performs.
export struct RuntimeChecks {
    ## `+`, `-`, `*`, `**`, unary `-`, `++`, `--` and compound assignment
    ## overflowing their type.
    var overflow: bool = true;
    ## Division or remainder by zero, and `MIN / -1` of a signed type.
    var divide: bool = true;
    ## A shift count of at least the type's width.
    var shift: bool = true;
    ## Array and string indexing out of range.
    var bounds: bool = true;
    ## Calling through, or matching on, a null reference.
    var null: bool = true;

    ## Creates the checks with every check on.
    construct() {}

    ## Every check on.
    ##
    ## @returns the checks
    static all(): RuntimeChecks {
        return RuntimeChecks();
    }

    ## Every check on except those named in `list`, a comma-separated list
    ## of check names or `all`.
    ##
    ## @param list the names
    ## @returns the checks, or none for an unknown name
    static without(list: String): RuntimeChecks? {
        var checks = RuntimeChecks();
        for (var part in list.split(",")) {
            match (part.trim()) {
                "overflow" => {
                    checks.overflow = false;
                }
                "divide" => {
                    checks.divide = false;
                }
                "shift" => {
                    checks.shift = false;
                }
                "bounds" => {
                    checks.bounds = false;
                }
                "null" => {
                    checks.null = false;
                }
                "all" => {
                    checks.overflow = false;
                    checks.divide = false;
                    checks.shift = false;
                    checks.bounds = false;
                    checks.null = false;
                }
                else => {
                    return Optional<RuntimeChecks>.Empty;
                }
            }
        }
        return Optional<RuntimeChecks>.Value(checks);
    }

    ## The checks both `this` and `other` keep.
    ##
    ## @param other the other checks
    ## @returns the checks
    both(other: RuntimeChecks): RuntimeChecks {
        var out = RuntimeChecks();
        out.overflow = overflow and other.overflow;
        out.divide = divide and other.divide;
        out.shift = shift and other.shift;
        out.bounds = bounds and other.bounds;
        out.null = null and other.null;
        return out;
    }
}

## The checks a function whose attributes are `attributes` keeps, as its
## `[Unsafe("...")]` says. An invalid list keeps every check.
##
## @param attributes the function's attributes
## @returns the checks
export function_checks(attributes: ast.Attribute[]): RuntimeChecks {
    var checks = RuntimeChecks.all();
    for (var attribute in attributes) {
        var name = sema.attribute_name(attribute);
        if (!name.is_value() or name.value() != UNSAFE_ATTRIBUTE) {
            continue;
        }
        var arguments = sema.attribute_arguments(attribute);
        if (arguments.count != 1) {
            continue;
        }
        var argument = arguments[0];
        if (argument.name.is_value()) {
            var (key, _) = argument.name.value();
            if (key != "checks") {
                continue;
            }
        }
        if (argument.value is Literal(literal, _)) {
            if (literal is String(text)) {
                var listed = RuntimeChecks.without(text);
                if (listed.is_value()) {
                    checks = checks.both(listed.value());
                }
            }
        }
    }
    return checks;
}

## The Pepper name of the integer type `width` bits wide.
_int_type_name(width: uint, unsigned: bool): String {
    match (width) {
        8 => {
            return unsigned ? "byte" : "char";
        }
        16 => {
            return unsigned ? "ushort" : "short";
        }
        64 => {
            return unsigned ? "ulong" : "long";
        }
        else => {
            return unsigned ? "uint" : "int";
        }
    }
}

## What a message calls the operation `op`.
_operation_name(op: BinaryOp): String {
    match (op) {
        Add, AddOverflows => {
            return "addition";
        }
        Sub, SubOverflows => {
            return "subtraction";
        }
        Mul, MulOverflows => {
            return "multiplication";
        }
        Div => {
            return "division";
        }
        Mod => {
            return "remainder";
        }
        Pow => {
            return "exponentiation";
        }
        else => {
            return "operation";
        }
    }
}

## The message for an overflow of `op` in a `width`-bit integer.
_overflow_message(width: uint, unsigned: bool, operation: String): String {
    return $"integer overflow in '{_int_type_name(width, unsigned)}' {operation}";
}

## Whether `value` fits a signed integer `width` bits wide (under 64).
_fits_signed(value: long, width: uint): bool {
    if (width >= 64) {
        return true;
    }
    long bound = 1;
    bound = bound << ((width - 1) as long);
    return value >= -bound and value < bound;
}

## Whether `value` fits an unsigned integer `width` bits wide.
_fits_unsigned(value: ulong, width: uint): bool {
    if (width >= 64) {
        return true;
    }
    ulong bound = 1;
    bound = bound << (width as ulong);
    return value < bound;
}

## `l op r` exactly for two signed `width`-bit constants, or none when it
## overflows the width. `op` is `+`, `-` or `*`.
_signed_exact(op: BinaryOp, l: long, r: long, width: uint): long? {
    if (width >= 64) {
        if (op == BinaryOp.Add) {
            return _add_overflows_signed(l, r) ? Optional<long>.Empty : Optional<long>.Value(l + r);
        }
        if (op == BinaryOp.Sub) {
            return _sub_overflows_signed(l, r) ? Optional<long>.Empty : Optional<long>.Value(l - r);
        }
        return _mul_overflows_signed(l, r) ? Optional<long>.Empty : Optional<long>.Value(l * r);
    }
    # Both fit 32 bits, so the exact result fits a long.
    long exact = op == BinaryOp.Add ? l + r : (op == BinaryOp.Sub ? l - r : l * r);
    return _fits_signed(exact, width) ? Optional<long>.Value(exact) : Optional<long>.Empty;
}

## `l op r` exactly for two unsigned `width`-bit constants, or none when it
## overflows the width.
_unsigned_exact(op: BinaryOp, l: ulong, r: ulong, width: uint): ulong? {
    if (op == BinaryOp.Sub) {
        return l < r ? Optional<ulong>.Empty : Optional<ulong>.Value(l - r);
    }
    if (width >= 64) {
        if (op == BinaryOp.Add) {
            return _add_overflows_unsigned(l, r) ? Optional<ulong>.Empty : Optional<ulong>.Value(l + r);
        }
        return _mul_overflows_unsigned(l, r) ? Optional<ulong>.Empty : Optional<ulong>.Value(l * r);
    }
    ulong exact = op == BinaryOp.Add ? l + r : l * r;
    return _fits_unsigned(exact, width) ? Optional<ulong>.Value(exact) : Optional<ulong>.Empty;
}

## Whether `l op r` of two constant integers overflows their width.
_constant_overflows(op: BinaryOp, l: llvm.Value, r: llvm.Value, width: uint, unsigned: bool): bool {
    if (unsigned) {
        return !_unsigned_exact(op, l.zero_extended(), r.zero_extended(), width).is_value();
    }
    return !_signed_exact(op, l.sign_extended(), r.sign_extended(), width).is_value();
}

## Whether constant `base ** exp` overflows its width.
_constant_pow_overflows(base: llvm.Value, exp: llvm.Value, width: uint, unsigned: bool): bool {
    if (unsigned) {
        ulong b = base.zero_extended();
        ulong e = exp.zero_extended();
        ulong acc = 1;
        ulong steps = e < 200 ? e : 200;
        for (var _ in 0..steps) {
            var next = _unsigned_exact(BinaryOp.Mul, acc, b, width);
            if (!next.is_value()) {
                return true;
            }
            acc = next.value();
            if (b == 0 or b == 1) {
                break;
            }
        }
        return false;
    }
    long b = base.sign_extended();
    long e = exp.sign_extended();
    if (e < 0) {
        return false;
    }
    long acc = 1;
    long steps = e < 200 ? e : 200;
    for (var _ in 0..steps) {
        var next = _signed_exact(BinaryOp.Mul, acc, b, width);
        if (!next.is_value()) {
            return true;
        }
        acc = next.value();
        if (b == 0 or b == 1) {
            break;
        }
    }
    return false;
}

## The smallest signed `width`-bit value, as a long.
_signed_min(width: uint): long {
    if (width >= 64) {
        return -9223372036854775807 - 1;
    }
    long bound = 1;
    return -(bound << ((width - 1) as long));
}

## FNV-1a of `text`'s bytes.
[Unsafe("overflow")]
_fnv1a(text: String): ulong {
    ulong hash = 0xcbf29ce484222325;
    for (var b in text.bytes()) {
        hash = (hash ^ (b as ulong)) * 0x100000001b3;
    }
    return hash;
}

extend Generator {
    ## Records each source's name and line starts, for `location_text`.
    index_check_files() {
        check_files = Array<(String, ulong[])>();
        for (var source in state.sources) {
            var lines = Array<ulong>();
            lines.append(0);
            var bytes = source.text.bytes();
            for (var index in 0..bytes.count) {
                if (bytes[index] == 10) {
                    lines.append(index + 1);
                }
            }
            check_files.append((source.name, lines));
        }
    }

    ## `file:line:col` for `loc`; none when the location is unknown.
    location_string(loc: Loc): String? {
        if (loc.is_none() or loc.file as ulong >= check_files.count) {
            return Optional<String>.Empty;
        }
        var (name, lines) = check_files[loc.file as ulong];
        var position = loc.span.start;
        # The number of line starts at or before the position.
        ulong low = 0;
        ulong high = lines.count;
        while (low < high) {
            var middle = (low + high) / 2;
            if (lines[middle] <= position) {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        var line = low > 1 ? low : 1;
        var column = position - lines[line - 1];
        return Optional<String>.Value($"{name}:{line}:{column + 1}");
    }

    ## `loc` as the constant C string `file:line:col` that `_pep_panic`
    ## prints before a message, or a null pointer when the location is
    ## unknown: the value of `__caller_location()`.
    location_text(loc: Loc): llvm.Value {
        var text = location_string(loc);
        if (text.is_value()) {
            return check_message(text.value());
        }
        return context.pointer_type().zero();
    }

    ## `location_text` marked with `UNCHECKED_BOUNDS_MARK`: the caller
    ## location a call in an `[Unsafe("bounds")]` function passes.
    unchecked_location_text(loc: Loc): llvm.Value {
        var text = location_string(loc);
        return check_message(UNCHECKED_BOUNDS_MARK + (text.is_value() ? text.value() : ""));
    }

    ## The null check `_pep_assert(condition, message, location)`, located
    ## at `loc`.
    located_assert(condition: llvm.Value, message: String, loc: Loc): Result<void> {
        var text = check_message(message);
        var location = location_text(loc);
        call_function("_pep_assert", [condition, text, location])?;
        return Result<void>.ok();
    }

    ## Panics with `message` (located at `loc`) when `failed` is true, and
    ## carries on after it otherwise. Without the runtime the failure traps.
    panic_if(failed: llvm.Value, message: String, loc: Loc): Result<void> {
        var function = builder.insert_block().parent();
        var fail_block = context.append_block(function, "check.fail");
        var ok = context.append_block(function, "check.ok");
        builder.conditional_branch(failed, fail_block, ok);
        builder.position_at_end(fail_block);
        var panic = ir.function("_pep_panic");
        if (!panic.is_value()) {
            panic = functions.try_get("_pep_panic");
        }
        if (panic.is_value()) {
            var text = check_message(message);
            var location = location_text(loc);
            var call = builder.call(panic.value().global_type(), panic.value(), [text, location]);
            # Argument memory read (1), inaccessible memory read and written
            # (3 << 2): a count stepped around a check still folds away.
            call.add_call_attribute(FUNCTION_ATTRIBUTE_INDEX, context.attribute("memory", 1 | (3 << 2)));
        } else {
            var trap = ir.intrinsic("llvm.trap");
            if (!trap.is_value()) {
                return fail<void>("no llvm.trap");
            }
            builder.call(trap.value().global_type(), trap.value(), Array<llvm.Value>());
        }
        builder.unreachable();
        builder.position_at_end(ok);
        return Result<void>.ok();
    }

    ## The constant C string `text`, one per distinct text, named by its
    ## hash.
    check_message(text: String): llvm.Value {
        var name = $"__pep_check_message.{_fnv1a(text):016x}";
        var existing = ir.global(name);
        if (existing.is_value()) {
            return existing.value();
        }
        var bytes = context.const_string(text, true);
        var global = ir.add_global(bytes.value_type(), name);
        global.set_initializer(bytes);
        global.set_global_constant(true);
        global.set_linkage(llvm.Linkage.Private);
        # `unnamed_addr`.
        global.set_unnamed_address(2);
        return global;
    }

    ## `op`'s result and whether it overflowed, through
    ## `llvm.{s,u}{add,sub,mul}.with.overflow`.
    with_overflow(op: BinaryOp, lhs: llvm.Value, rhs: llvm.Value, unsigned: bool): Result<(llvm.Value, llvm.Value)> {
        String base;
        match (op) {
            Add, AddOverflows, WrappingAdd => {
                base = "add";
            }
            Sub, SubOverflows, WrappingSub => {
                base = "sub";
            }
            else => {
                base = "mul";
            }
        }
        var name = $"llvm.{unsigned ? "u" : "s"}{base}.with.overflow";
        var declaration = ir.intrinsic(name, [lhs.value_type()]);
        if (!declaration.is_value()) {
            return fail<(llvm.Value, llvm.Value)>($"no {name}");
        }
        var pair = builder.call(declaration.value().global_type(), declaration.value(), [lhs, rhs], base);
        var value = builder.extract_value(pair, 0, base);
        var overflowed = builder.extract_value(pair, 1, "overflowed");
        return Result<(llvm.Value, llvm.Value)>.ok((value, overflowed));
    }

    ## `lhs op rhs` for `+`, `-` or `*`, panicking on overflow when the
    ## check is on. `operation` names it in the message when it is not
    ## `op`'s own name (`negation`, `increment`).
    checked_arithmetic(
        op: BinaryOp, lhs: llvm.Value, rhs: llvm.Value, unsigned: bool, loc: Loc, operation: String = ""
    ): Result<llvm.Value> {
        var width = lhs.value_type().int_width();
        var message = _overflow_message(width, unsigned, operation.is_empty ? _operation_name(op) : operation);
        bool constants = lhs.is_constant() and rhs.is_constant();
        if (lhs.is_constant_int() and rhs.is_constant_int() and _constant_overflows(op, lhs, rhs, width, unsigned)) {
            return fail<llvm.Value>(message);
        }
        if (!runtime_checks.overflow or constants) {
            if (op == BinaryOp.Add) {
                return Result<llvm.Value>.ok(builder.add(lhs, rhs, "add"));
            }
            if (op == BinaryOp.Sub) {
                return Result<llvm.Value>.ok(builder.sub(lhs, rhs, "sub"));
            }
            return Result<llvm.Value>.ok(builder.mul(lhs, rhs, "mul"));
        }
        var (value, overflowed) = with_overflow(op, lhs, rhs, unsigned)?;
        panic_if(overflowed, message, loc)?;
        return Result<llvm.Value>.ok(value);
    }

    ## `lhs / rhs` or `lhs % rhs`, panicking on a zero divisor and on
    ## `MIN / -1` when the check is on. A constant zero divisor is a compile
    ## error.
    checked_division(op: BinaryOp, lhs: llvm.Value, rhs: llvm.Value, unsigned: bool, loc: Loc): Result<llvm.Value> {
        var ty = lhs.value_type();
        var width = ty.int_width();
        bool divisor_known = rhs.is_constant_int();
        if (divisor_known and rhs.zero_extended() == 0) {
            return fail<llvm.Value>("division by zero");
        }
        bool divisor_minus_one = divisor_known and !unsigned and rhs.sign_extended() == -1;
        bool can_overflow = !unsigned and (!divisor_known or divisor_minus_one);
        bool lhs_min = lhs.is_constant_int() and lhs.sign_extended() == _signed_min(width);
        if (lhs.is_constant_int() and divisor_minus_one and lhs_min) {
            return fail<llvm.Value>(_overflow_message(width, unsigned, _operation_name(op)));
        }
        if (runtime_checks.divide) {
            if (!divisor_known) {
                var zero = builder.compare(llvm.IntPredicate.Equal, rhs, ty.zero(), "divisor_zero");
                panic_if(zero, "division by zero", loc)?;
            }
            bool lhs_safe = lhs.is_constant() and lhs.is_constant_int() and !lhs_min;
            if (can_overflow and !lhs_safe) {
                long min = _signed_min(width);
                var min_value = ty.const_int(min);
                var is_min = builder.compare(llvm.IntPredicate.Equal, lhs, min_value, "is_min");
                var is_minus_one = builder.compare(llvm.IntPredicate.Equal, rhs, ty.all_ones(), "is_minus_one");
                var overflowed = builder.bit_and(is_min, is_minus_one, "overflowed");
                panic_if(overflowed, _overflow_message(width, unsigned, _operation_name(op)), loc)?;
            }
        }
        if (op == BinaryOp.Div) {
            if (unsigned) {
                return Result<llvm.Value>.ok(builder.unsigned_divide(lhs, rhs, "udiv"));
            }
            return Result<llvm.Value>.ok(builder.signed_divide(lhs, rhs, "sdiv"));
        }
        if (unsigned) {
            return Result<llvm.Value>.ok(builder.unsigned_remainder(lhs, rhs, "urem"));
        }
        return Result<llvm.Value>.ok(builder.signed_remainder(lhs, rhs, "srem"));
    }

    ## `lhs << rhs` or `lhs >> rhs`, panicking when the count is at least
    ## the type's width and the check is on; without the check the count is
    ## masked to the width.
    checked_shift(op: BinaryOp, lhs: llvm.Value, rhs: llvm.Value, unsigned: bool, loc: Loc): Result<llvm.Value> {
        var ty = lhs.value_type();
        var width = ty.int_width();
        bool in_range = rhs.is_constant_int() and rhs.zero_extended() < width as ulong;
        var count = rhs;
        if (!in_range) {
            if (runtime_checks.shift) {
                var too_far = builder.compare(
                    llvm.IntPredicate.UnsignedGreaterOrEqual, rhs, ty.const_uint(width as ulong), "shift_too_far"
                );
                var type_name = _int_type_name(width, unsigned);
                panic_if(too_far, $"shift count out of range for '{type_name}': must be from 0 to {width - 1}", loc)?;
            } else {
                count = builder.bit_and(rhs, ty.const_uint(width as ulong - 1), "shift_count");
            }
        }
        if (op == BinaryOp.LShift) {
            return Result<llvm.Value>.ok(builder.shift_left(lhs, count, "shl"));
        }
        if (unsigned) {
            return Result<llvm.Value>.ok(builder.logical_shift_right(lhs, count, "shr"));
        }
        return Result<llvm.Value>.ok(builder.arithmetic_shift_right(lhs, count, "shr"));
    }

    ## `base ** exp` with every multiplication checked: a multiply whose
    ## result is used and overflows panics.
    checked_pow(base: llvm.Value, exp: llvm.Value, unsigned: bool, loc: Loc): Result<llvm.Value> {
        var ty = base.value_type();
        var width = ty.int_width();
        var message = _overflow_message(width, unsigned, _operation_name(BinaryOp.Pow));
        if (base.is_constant_int() and exp.is_constant_int() and _constant_pow_overflows(base, exp, width, unsigned)) {
            return fail<llvm.Value>(message);
        }
        if (!runtime_checks.overflow or (base.is_constant() and exp.is_constant())) {
            var unchecked = int_binary(BinaryOp.Pow, base, exp, unsigned ? "u64" : "i64");
            if (!unchecked.is_value()) {
                return fail<llvm.Value>("unsupported op Pow");
            }
            return Result<llvm.Value>.ok(unchecked.value());
        }
        # A small constant exponent unrolls to checked multiplies.
        if (exp.is_constant_int()) {
            bool small = unsigned ? exp.zero_extended() <= 31 : exp.sign_extended() >= 0 and exp.sign_extended() <= 31;
            if (small) {
                var acc = ty.const_uint(1);
                for (var _ in 0..exp.zero_extended()) {
                    var (product, overflowed) = with_overflow(BinaryOp.Mul, acc, base, unsigned)?;
                    panic_if(overflowed, message, loc)?;
                    acc = product;
                }
                return Result<llvm.Value>.ok(acc);
            }
        }
        var power = exp;
        if (!exp.value_type().same(ty)) {
            if (exp.value_type().int_width() < width) {
                power = builder.sign_extend(exp, ty, "powexp");
            } else {
                power = builder.truncate(exp, ty, "powexp");
            }
        }
        var one = ty.const_uint(1);
        var zero = ty.zero();
        var entry = builder.insert_block();
        var function = entry.parent();
        var header = context.append_block(function, "pow.loop");
        var body = context.append_block(function, "pow.body");
        var done = context.append_block(function, "pow.done");
        builder.branch(header);

        builder.position_at_end(header);
        var acc = builder.phi(ty, "pow.acc");
        var factor = builder.phi(ty, "pow.factor");
        var remaining = builder.phi(ty, "pow.exp");
        var more = builder.compare(
            unsigned ? llvm.IntPredicate.NotEqual : llvm.IntPredicate.SignedGreater, remaining, zero, "pow.more"
        );
        builder.conditional_branch(more, body, done);

        builder.position_at_end(body);
        var low_bit = builder.bit_and(remaining, one, "pow.bit");
        var odd = builder.compare(llvm.IntPredicate.NotEqual, low_bit, zero, "pow.odd");
        var (multiplied, multiply_overflowed) = with_overflow(BinaryOp.Mul, acc, factor, unsigned)?;
        var halved = builder.logical_shift_right(remaining, one, "pow.half");
        var (squared, square_overflowed) = with_overflow(BinaryOp.Mul, factor, factor, unsigned)?;
        # The product counts when this bit is set; the square only when a
        # later bit will use it.
        var used_product = builder.bit_and(odd, multiply_overflowed, "pow.product_overflowed");
        var more_bits = builder.compare(llvm.IntPredicate.NotEqual, halved, zero, "pow.more_bits");
        var used_square = builder.bit_and(more_bits, square_overflowed, "pow.square_overflowed");
        var overflowed = builder.bit_or(used_product, used_square, "pow.overflowed");
        panic_if(overflowed, message, loc)?;
        var next_acc = builder.select(odd, multiplied, acc, "pow.next");
        var body_end = builder.insert_block();
        builder.branch(header);

        acc.add_incoming([one, next_acc], [entry, body_end]);
        factor.add_incoming([base, squared], [entry, body_end]);
        remaining.add_incoming([power, halved], [entry, body_end]);

        builder.position_at_end(done);
        if (unsigned) {
            return Result<llvm.Value>.ok(acc);
        }
        var negative = builder.compare(llvm.IntPredicate.SignedLess, power, zero, "pow.neg");
        var exp_bit = builder.bit_and(power, one, "pow.expbit");
        var exp_odd = builder.compare(llvm.IntPredicate.NotEqual, exp_bit, zero, "pow.expodd");
        var minus_one = ty.all_ones();
        var base_is_one = builder.compare(llvm.IntPredicate.Equal, base, one, "pow.one");
        var base_is_minus_one = builder.compare(llvm.IntPredicate.Equal, base, minus_one, "pow.minusone");
        var sign = builder.select(exp_odd, minus_one, one, "pow.sign");
        var fraction = builder.select(base_is_minus_one, sign, zero, "pow.frac");
        fraction = builder.select(base_is_one, one, fraction, "pow.frac");
        return Result<llvm.Value>.ok(builder.select(negative, fraction, acc, "pow"));
    }

    ## `lhs op rhs` on two integers of one width, with the runtime checks
    ## `op` has, or none for an operator that has none. `ty` is the
    ## operands' sema type, which carries their signedness.
    checked_int_binary(op: BinaryOp, lhs: llvm.Value, rhs: llvm.Value, ty: String, loc: Loc): Result<llvm.Value?> {
        if (lhs.value_type().int_width() < 8 or !lhs.value_type().same(rhs.value_type())) {
            return Result<llvm.Value?>.ok(Optional<llvm.Value>.Empty);
        }
        var unsigned = sema.is_unsigned_int_type(state, ty);
        llvm.Value value;
        match (op) {
            Add, Sub, Mul => {
                value = checked_arithmetic(op, lhs, rhs, unsigned, loc)?;
            }
            Div, Mod => {
                value = checked_division(op, lhs, rhs, unsigned, loc)?;
            }
            LShift, RShift => {
                value = checked_shift(op, lhs, rhs, unsigned, loc)?;
            }
            Pow => {
                value = checked_pow(lhs, rhs, unsigned, loc)?;
            }
            WrappingAdd => {
                value = builder.add(lhs, rhs, "wrapping_add");
            }
            WrappingSub => {
                value = builder.sub(lhs, rhs, "wrapping_sub");
            }
            WrappingMul => {
                value = builder.mul(lhs, rhs, "wrapping_mul");
            }
            AddOverflows, SubOverflows, MulOverflows => {
                var (_, overflowed) = with_overflow(op, lhs, rhs, unsigned)?;
                value = overflowed;
            }
            else => {
                return Result<llvm.Value?>.ok(Optional<llvm.Value>.Empty);
            }
        }
        return Result<llvm.Value?>.ok(Optional<llvm.Value>.Value(value));
    }
}

## Whether `l + r` overflows a long.
[Unsafe("overflow")]
_add_overflows_signed(l: long, r: long): bool {
    long sum = l + r;
    return (l >= 0) == (r >= 0) and (sum >= 0) != (l >= 0);
}

## Whether `l - r` overflows a long.
[Unsafe("overflow")]
_sub_overflows_signed(l: long, r: long): bool {
    long difference = l - r;
    return (l >= 0) != (r >= 0) and (difference >= 0) != (l >= 0);
}

## Whether `l * r` overflows a long.
[Unsafe("overflow")]
_mul_overflows_signed(l: long, r: long): bool {
    if (l == 0 or r == 0) {
        return false;
    }
    long min = -9223372036854775807 - 1;
    if ((l == -1 and r == min) or (r == -1 and l == min)) {
        return true;
    }
    long product = l * r;
    return product / r != l;
}

## Whether `l + r` overflows a ulong.
[Unsafe("overflow")]
_add_overflows_unsigned(l: ulong, r: ulong): bool {
    ulong sum = l + r;
    return sum < l;
}

## Whether `l * r` overflows a ulong.
[Unsafe("overflow")]
_mul_overflows_unsigned(l: ulong, r: ulong): bool {
    if (l == 0) {
        return false;
    }
    ulong product = l * r;
    return product / l != r;
}
