## Injected types: the constructs whose type the compiler supplies rather
## than the program spelling it. The builder and the desugaring lower each
## to a call: a string literal stays a `StringLiteral`, `$"a{x}"` becomes
## `"a" + _pep_interpolate(x)`, a tuple literal `__tuple(a, b)`, an array or
## map literal an `_array_literal` / `_map_literal` chain, a range
## `_range(a, b, inclusive)`, and `e?` a hidden `__try_N` local. Optional
## types are `Optional<T>` from the parser on.
##
## `resolve_injected` gives every such construct whose type needs no
## inference its real form, in every place code lives (`places.pep`), right
## after overload sets are named: a string literal becomes the `String`
## constructor call, and a `+` whose left side is such a `String` (literal
## concatenation, and every interpolated string) becomes the `String` `+`
## method call `resolve_operators` would make. From then on every pass sees
## an ordinary call that yields a `String`. The rest take their type from
## their operands' (`resolve_implicit_types` spells `__tuple<int, String>`,
## `_range<int>`, `_pep_interpolate<int>`), and specialization makes the
## calls. `verify_injected` checks, at the end of the passes, that no
## concrete code still holds one in its placeholder form.

import [error_at] from "common";
import [is_text_conversion] from "interpolation";
import [convert_string_literal] from "literals";
import [Loc] from "loc";
import [BinaryOp, Expression, MethodCallExpression, Module, Statement, TypeName] from "model";
import [for_each_place, Place, PlaceVisitor, rewrite_places] from "places";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [tuple_constructor_labels] from "tuple_literals";
import "type_name";
import [Rewriter] from "walk";

## Gives each string literal and each `String` concatenation in `module`
## its real form: `"abc"` becomes `String(raw, size, length)` (the raw
## literal stays a `char*` global), and `lhs + rhs` whose `lhs` is such a
## `String` becomes the method call `lhs.+(rhs)`. Every place is covered:
## bodies, parameter defaults, field and module-scope initializers,
## extension methods, generic methods and trait default methods.
##
## @param module the model, changed in place
export resolve_injected(module: Module) {
    rewrite_places(module, _Injected(), templates = true);
}

## Converts what `resolve_injected` converts, at each expression.
struct _Injected {
    rewrite(e: Expression): Expression {
        if (e is Binary(node)) {
            if (node.op == BinaryOp.Add and _is_string(node.lhs)) {
                return Expression.MethodCall(MethodCallExpression(node.lhs, "+", [node.rhs], node.loc));
            }
            return e;
        }
        return convert_string_literal(e);
    }
}

extend _Injected with Rewriter;

## Whether `e` yields a `String` that `resolve_injected` can tell without
## types: a string literal (before or after conversion), a text conversion
## of an interpolated string, or a concatenation starting with either.
_is_string(e: Expression): bool {
    match (e) {
        StringLiteral(literal) => {
            return !literal.is_raw;
        }
        FunctionCall(call) => {
            return call.function == "String" or is_text_conversion(call.function);
        }
        MethodCall(call) => {
            return call.method == "+" and _is_string(call.this_value);
        }
        Binary(node) => {
            return node.op == BinaryOp.Add and _is_string(node.lhs);
        }
        else => {
            return false;
        }
    }
}

## Reports the first injected construct concrete code still holds in its
## placeholder form, as an internal error at it: a string literal that is
## not a `String`, a `+` on one, a tuple literal without its type
## (`__tuple`), a call to a runtime function an injected construct calls
## without its type arguments (`_pep_interpolate`, `_pep_format*`,
## `_array_literal`, `_map_literal`, `_range`), or a `?`'s hidden local
## without a type, the last two only when their operands have types (an
## operand without one is the program's error, which code generation
## reports). Fields' own initializers are left out: each constructor runs
## its copy. The passes run it after every other with
## `PEPC_VERIFY_INJECTED` set (`scripts/pepper-tests.sh` sets it), so a
## regression is caught where the placeholder is left, not as a code
## generation error.
##
## @param module the model
## @param state the passes' state, which takes the error
export verify_injected(module: Module, state: PassState) {
    var table = StructTable(module, memo = state.trait_types_memo());
    for_each_place(module, _Verifier(table, state), extensions = false, fields = false);
}

## Walks each place of concrete code for placeholders.
struct _Verifier {
    var table: StructTable;
    var state: PassState;

    construct(table: StructTable, state: PassState) {
        this.table = table;
        this.state = state;
    }

    visit(place: Place) {
        if (place.is_generic() or state.error.is_value()) {
            return;
        }
        var finder = _Placeholders(table, place.this_type, state);
        place.rewrite(finder);
        if (place.function.is_value() and place.function.value().body.is_value()) {
            _untyped_locals(place.function.value().body.value().items, finder);
        }
        if (finder.found.is_value()) {
            var (what, at) = finder.found.value();
            state.report(error_at($"internal error: {what} left unresolved", at));
        }
    }
}

extend _Verifier with PlaceVisitor;

## The first placeholder a walk meets.
struct _Placeholders {
    var found: (String, Loc)? = Optional<(String, Loc)>.Empty;
    var table: StructTable;
    var current: TypeName?;
    var state: PassState;

    construct(table: StructTable, current: TypeName?, state: PassState) {
        this.table = table;
        this.current = current;
        this.state = state;
    }

    ## Whether every argument has a type, so nothing but a pass can have
    ## left the call without the types they give it. An argument without
    ## one is the program's error, which code generation reports.
    typed(args: Expression[]): bool {
        for (var arg in args) {
            if (!static_type_of(arg, table, current, state).is_value()) {
                return false;
            }
        }
        return true;
    }

    rewrite(e: Expression): Expression {
        if (found.is_value()) {
            return e;
        }
        match (e) {
            StringLiteral(literal) => {
                if (!literal.is_raw) {
                    note("string literal", literal.loc);
                }
            }
            Binary(node) => {
                if (node.op == BinaryOp.Add and _is_string(node.lhs)) {
                    note("'String' '+'", node.loc);
                }
            }
            FunctionCall(call) => {
                if (_is_placeholder_call(call.function) and typed(call.args)) {
                    note($"call to '{call.function}'", call.loc);
                }
            }
            else => {}
        }
        return e;
    }

    note(what: String, at: Loc) {
        found = Optional<(String, Loc)>.Value((what, at));
    }
}

extend _Placeholders with Rewriter;

## Whether `function` is an injected construct's call that still lacks the
## types its operands give it.
_is_placeholder_call(function: String): bool {
    if (tuple_constructor_labels(function).is_value()) {
        return true;
    }
    match (function) {
        "_pep_interpolate", "_pep_format", "_pep_format_integer", "_pep_format_float", "_array_literal", "_map_literal", "_range" => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## Notes a `?`'s hidden local (`__try_N`) still without a type, in nested
## blocks too.
_untyped_locals(items: Statement[], finder: _Placeholders) {
    for (var statement in items) {
        if (finder.found.is_value()) {
            return;
        }
        match (statement) {
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    if (variable.name.starts_with("__try_")
                        and variable.ty.is_auto()
                        and variable.default.is_value()
                        and finder.typed([variable.default.value()])) {
                        finder.note($"'?' operand '{variable.name}'", variable.loc);
                    }
                }
            }
            Block(inner) => {
                _untyped_locals(inner.items, finder);
            }
            Branch(branch) => {
                _untyped_locals(branch.if_block.items, finder);
                if (branch.else_block.is_value()) {
                    _untyped_locals(branch.else_block.value().items, finder);
                }
            }
            While(loop) => {
                _untyped_locals(loop.block.items, finder);
            }
            else => {}
        }
    }
}
