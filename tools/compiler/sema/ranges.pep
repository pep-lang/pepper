## Range bounds must be integers: `pepper_sema::passes::ranges` in Pepper.
## The builder lowers `a..b` to `_range(a, b, inclusive)`, whose `T` is
## inferred from the bounds; once each call is specialized
## (`_range<String>`), a bound that is not an integer is reported at the
## range operator rather than inside the runtime's `Range<T>`.

import [error_at] from "common";
import [Expression, Module] from "model";
import [PassState] from "state";
import [Rewriter, rewrite_block] from "walk";

## The name the builder gives a range's call.
const _RANGE_FUNCTION = "_range";

## Reports the first range whose bounds are not integers, as
## `ranges::check_ranges` does.
##
## @param module the model
## @param state the passes' state, which takes the first error
export check_ranges(module: Module, state: PassState) {
    var checker = _RangeChecker(state);
    for (var st in module.structs) {
        if (st.ty.is_generic() and st.name == st.ty.name) {
            continue;
        }
        for (var c in st.constructors) {
            if (c.body.is_value()) {
                rewrite_block(c.body.value(), checker);
            }
        }
        for (var m in st.method_members) {
            if (m.body.is_value()) {
                rewrite_block(m.body.value(), checker);
            }
        }
    }
    for (var f in module.functions) {
        if (!f.is_generic_func and f.body.is_value()) {
            rewrite_block(f.body.value(), checker);
        }
    }
}

struct _RangeChecker {
    var state: PassState;

    construct(state: PassState) {
        this.state = state;
    }

    rewrite(e: Expression): Expression {
        if (e is FunctionCall(node)) {
            var prefix = _RANGE_FUNCTION + "<";
            if (node.function.starts_with(prefix) and node.function.ends_with(">")) {
                var bound = node.function.substr_bytes(prefix.size, node.function.size - prefix.size - 1);
                if (!_is_range_integer(bound)) {
                    state.report(error_at($"range bounds must be integers, not '{bound}'", node.loc));
                }
            }
        }
        return e;
    }
}

extend _RangeChecker with Rewriter;

## Whether `ty` is an integer type a range can step through (not `bool`, a
## float, or an enum).
_is_range_integer(ty: String): bool {
    for (var name in [
        "i8",
        "char",
        "u8",
        "byte",
        "i16",
        "short",
        "u16",
        "ushort",
        "i32",
        "int",
        "u32",
        "uint",
        "i64",
        "long",
        "u64",
        "ulong"
    ]) {
        if (ty == name) {
            return true;
        }
    }
    return false;
}
