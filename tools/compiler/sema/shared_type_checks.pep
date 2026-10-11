## What threads may share: `check_shared_types`. A `[Shared]` struct's
## fields must be `const` and thread-safe, a module-scope variable must be
## `const` and thread-safe, and a `[ThreadLocal]` one must be thread-safe
## and start from a constant.

import compiler.ast;
import [Diagnostic, Location] from compiler.diagnostic;
import [demangle_name] from compiler.link;
import [SHARED_ATTRIBUTE, THREAD_LOCAL_ATTRIBUTE] from "builder";
import "common";
import "constraints";
import [is_enum] from "enums";
import [Loc] from "loc";
import [Block, Expression, FunctionDef, Kind, Module, StructDef, TypeName, UnaryOp, VariableDef] from "model";
import [ThreadSafeStructs, unsafe_part_in] from "shared_types";
import [PassState] from "state";
import "type_name";
import [Rewriter, rewrite_expression] from "walk";

## Reports the first `[Shared]` struct field, module-scope variable or
## thread-local that breaks the rules above.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_shared_types(module: Module, state: PassState) {
    # Built once: it walks every value struct to a fixed point.
    var safe = ThreadSafeStructs(module, state);
    if (!_check_shared_structs(module, safe, state)) {
        return;
    }
    _check_globals(module, safe, state);
}

## The value of a thread-local's initializer, which every thread starts
## from.
export enum ThreadLocalConstant {
    Int(value: long),
    Float(value: double),
    Null,
}

## The constant `e` stands for, if it is one a thread-local may start
## from: a number, `bool` or `char` literal (negated, or cast to another
## number or an enum, as an enum case is), or null.
##
## @param e the initializer
## @param state the passes' state, which knows the enums
## @returns the constant, or none
export thread_local_constant(e: Expression, state: PassState): ThreadLocalConstant? {
    var none = Optional<ThreadLocalConstant>.Empty;
    match (e) {
        IntLiteral(v) => {
            return Optional<ThreadLocalConstant>.Value(ThreadLocalConstant.Int(v));
        }
        BoolLiteral(v) => {
            return Optional<ThreadLocalConstant>.Value(ThreadLocalConstant.Int(v ? 1 : 0));
        }
        FloatLiteral(v) => {
            return Optional<ThreadLocalConstant>.Value(ThreadLocalConstant.Float(v));
        }
        PointerLiteral => {
            return Optional<ThreadLocalConstant>.Value(ThreadLocalConstant.Null);
        }
        Unary(node) => {
            if (node.op == UnaryOp.Pos) {
                return thread_local_constant(node.operand, state);
            }
            if (node.op != UnaryOp.Neg) {
                return none;
            }
            var inner = thread_local_constant(node.operand, state);
            if (!inner.is_value()) {
                return none;
            }
            match (inner.value()) {
                Int(v) => {
                    return Optional<ThreadLocalConstant>.Value(ThreadLocalConstant.Int(0 - v));
                }
                Float(v) => {
                    return Optional<ThreadLocalConstant>.Value(ThreadLocalConstant.Float(-v));
                }
                Null => {
                    return none;
                }
            }
        }
        Cast(node) => {
            var integral = node.ty.is_integral() or (node.ty.is_scalar() and is_enum(state, node.ty.name));
            if (!integral or node.ty.is_pointer()) {
                return none;
            }
            var inner = thread_local_constant(node.expr, state);
            if (!inner.is_value()) {
                return none;
            }
            var floating = _is_floating(node.ty);
            match (inner.value()) {
                Int(v) => {
                    if (floating) {
                        return Optional<ThreadLocalConstant>.Value(ThreadLocalConstant.Float(v as double));
                    }
                }
                Float(v) => {
                    if (!floating) {
                        return Optional<ThreadLocalConstant>.Value(ThreadLocalConstant.Int(v as long));
                    }
                }
                Null => {
                    return none;
                }
            }
            return inner;
        }
        else => {}
    }
    return none;
}

_is_floating(ty: TypeName): bool {
    return ty.name == "float" or ty.name == "double" or ty.name == "f32" or ty.name == "f64";
}

## The first of `locs` that is a location.
_first_loc(a: Loc, b: Loc): Loc {
    if (!a.is_none()) {
        return a;
    }
    return b.is_none() ? Loc.none() : b;
}

## Module-scope variables must be `const` and thread-safe; a
## `[ThreadLocal]` one need not be `const`, but starts from a constant.
_check_globals(module: Module, safe: ThreadSafeStructs, state: PassState) {
    for (var global in module.globals) {
        # A checked runtime's were checked with it.
        if (module.checked.globals.contains(global.name)) {
            continue;
        }
        if (ast.has_attribute(global.attributes, THREAD_LOCAL_ATTRIBUTE)) {
            if (!_check_thread_local(module, global, safe, state)) {
                return;
            }
            continue;
        }
        if (!global.is_const) {
            state.report(
                error_at(
                    $"module-scope variable '{global.name}' must be 'const'",
                    global.loc
                ).with_note(
                    "every thread can reach a module-scope variable; change its state through a thread-safe type such as 'async.Atomic<T>' (after 'import async'), or declare it '[ThreadLocal]' to give each thread its own copy",
                    Optional<Location>.Empty
                )
            );
            return;
        }
        var offender = unsafe_part_in(global.ty, safe);
        if (!offender.is_value()) {
            continue;
        }
        var diagnostic = error_at(
            $"module-scope variable '{global.name}' has type '{global.ty.display()}', which is not thread-safe",
            _first_loc(global.type_loc, global.loc)
        );
        state.report(_not_shared_note(diagnostic, offender.value(), module));
        return;
    }
}

## A `[ThreadLocal]` variable must be thread-safe and start from a
## constant. Returns whether it does.
_check_thread_local(module: Module, global: VariableDef, safe: ThreadSafeStructs, state: PassState): bool {
    var name = demangle_name(global.name);
    var offender = unsafe_part_in(global.ty, safe);
    if (offender.is_value()) {
        var diagnostic = error_at(
            $"thread-local variable '{name}' has type '{global.ty.display()}', which is not thread-safe",
            _first_loc(global.type_loc, global.loc)
        ).with_note(
            "a per-thread value of any type is an 'async.ThreadLocal<T>' (after 'import async')",
            Optional<Location>.Empty
        );
        state.report(_not_shared_note(diagnostic, offender.value(), module));
        return false;
    }
    if (global.default.is_value() and !thread_local_constant(global.default.value(), state).is_value()) {
        state.report(
            error_at(
                $"thread-local variable '{name}' must start from a constant",
                _first_loc(_expression_loc(global.default.value()), global.loc)
            ).with_note(
                "every thread starts from this value; leave it out and assign the value on the thread's first use instead",
                Optional<Location>.Empty
            )
        );
        return false;
    }
    return true;
}

## Every `[Shared]` struct's fields must be `const` and thread-safe.
## Returns whether they all are.
_check_shared_structs(module: Module, safe: ThreadSafeStructs, state: PassState): bool {
    for (var st in module.structs) {
        # A checked runtime's were checked with it; the specializations the
        # program adds are not checked yet.
        if (!ast.has_attribute(st.attributes, SHARED_ATTRIBUTE) or module.checked.structs.contains(st.name)) {
            continue;
        }
        var is_generic_base = st.name == st.ty.name and st.ty.is_generic();
        var is_specialization = st.name.contains("<");
        for (var field in st.field_members) {
            if (field.kind != Kind.Field or field.name.starts_with("__")) {
                continue;
            }
            # Declared once per source struct: check it there, not again in
            # every specialization.
            if (!is_specialization and !field.is_const) {
                state.report(
                    error_at(
                        $"field '{field.name}' of shared struct '{st.name}' must be 'const'",
                        field.loc
                    ).with_note(
                        "threads change a shared struct's state through a thread-safe member such as 'async.Atomic<T>' (after 'import async')",
                        Optional<Location>.Empty
                    )
                );
                return false;
            }
            if (is_generic_base) {
                continue;
            }
            var offender = unsafe_part_in(field.ty, safe);
            if (!offender.is_value()) {
                continue;
            }
            var field_loc = _first_loc(field.type_loc, field.loc);
            # A reference enum's field holds a value of one of its cases.
            var what = $"field '{field.name}'";
            var owner = "struct";
            var dot = field.name.find(".");
            if (dot >= 0 and st.enum_cases.is_value()) {
                var case_name = field.name.substr_bytes(0, dot as ulong);
                var value = field.name.substr_bytes((dot as ulong) + 1, field.name.size - (dot as ulong) - 1);
                what = $"value '{value}' of case '{case_name}'";
                owner = "enum";
            }
            Diagnostic? made = Optional<Diagnostic>.Empty;
            if (is_specialization) {
                var site = field_loc;
                var through = Array<(String, Loc)>();
                var found = _user_use_site(module, st.name);
                if (found.is_value()) {
                    var (at, passed) = found.value();
                    site = at;
                    through = passed;
                }
                # Name what the user wrote: the outermost specialization.
                var asked = through.count > 0 ?
                    $"'{_pair_name(through[through.count - 1])}'" :
                    $"shared struct '{st.ty.display()}'";
                var diagnostic = error_at(
                    $"{asked} requires thread-safe type arguments; '{offender.value().display()}' is not thread-safe",
                    site
                );
                var required = st.ty.display();
                for (var (function, loc) in through) {
                    diagnostic = diagnostic.with_note(
                        $"'{required}' is required here, in '{function}'", Optional<Location>.Value(location_of(loc))
                    );
                    required = function;
                }
                made = Optional<Diagnostic>.Value(
                    diagnostic.with_note(
                        $"required by {what} declared here", Optional<Location>.Value(location_of(field_loc))
                    )
                );
            } else {
                made = Optional<Diagnostic>.Value(
                    error_at(
                        $"{what} of shared {owner} '{st.name}' has type '{field.ty.display()}', which is not thread-safe",
                        field_loc
                    )
                );
            }
            state.report(_not_shared_note(made.value(), offender.value(), module));
            return false;
        }
    }
    return true;
}

_pair_name(pair: (String, Loc)): String {
    var (name, at) = pair;
    return name;
}

## Where the program names type `spec` (a variable, field or parameter
## type, or a constructor call), with the name of the free function it is
## in, if any.
_find_use_site(module: Module, spec: String): _UseSite? {
    for (var g in module.globals) {
        var at = _var_site(g, spec);
        if (!at.is_value() and g.default.is_value()) {
            at = _expression_site(g.default.value(), spec);
        }
        if (at.is_value()) {
            return Optional<_UseSite>.Value(_UseSite(at.value(), Optional<String>.Empty));
        }
    }
    for (var f in module.functions) {
        var at = _function_site(f, spec);
        if (at.is_value()) {
            return Optional<_UseSite>.Value(_UseSite(at.value(), Optional<String>.Value(f.name)));
        }
    }
    for (var st in module.structs) {
        for (var field in st.field_members) {
            var at = _var_site(field, spec);
            if (at.is_value()) {
                return Optional<_UseSite>.Value(_UseSite(at.value(), Optional<String>.Empty));
            }
        }
        var functions = Array<FunctionDef>();
        for (var m in st.method_members) {
            functions.append(m);
        }
        for (var c in st.constructors) {
            functions.append(c);
        }
        functions.append(st.destructor);
        for (var m in functions) {
            var at = _function_site(m, spec);
            if (at.is_value()) {
                return Optional<_UseSite>.Value(_UseSite(at.value(), Optional<String>.Empty));
            }
        }
    }
    return Optional<_UseSite>.Empty;
}

## Returns where the program names type `spec` (a variable, field or
## parameter type, or a constructor call), for errors about a
## specialization.
##
## @param module the model
## @param spec the type's spelling
## @returns the location, if it is named
export use_site(module: Module, spec: String): Loc? {
    var found = _find_use_site(module, spec);
    return found.is_value() ? Optional<Loc>.Value(found.value().loc) : Optional<Loc>.Empty;
}

## Where a type is named, and the free function that names it, if any.
struct _UseSite {
    var loc: Loc;
    var function: String?;

    construct(loc: Loc, function: String?) {
        this.loc = loc;
        this.function = function;
    }
}

## `_find_use_site`, followed out of generic function specializations to
## the code the user wrote, with each specialization passed through
## (innermost first) and where it names the next inner thing.
_user_use_site(module: Module, spec: String): (Loc, Array<(String, Loc)>)? {
    var first = _find_use_site(module, spec);
    if (!first.is_value()) {
        return Optional<(Loc, Array<(String, Loc)>)>.Empty;
    }
    var loc = first.value().loc;
    var function = first.value().function;
    var through = Array<(String, Loc)>();
    while (function.is_value()) {
        var name = function.value();
        if (!name.contains("<")) {
            break;
        }
        bool seen = false;
        for (var (passed, at) in through) {
            if (passed == name) {
                seen = true;
                break;
            }
        }
        if (seen) {
            break;
        }
        var outer = _find_use_site(module, name);
        if (!outer.is_value()) {
            break;
        }
        through.append((name, loc));
        loc = outer.value().loc;
        function = outer.value().function;
    }
    return Optional<(Loc, Array<(String, Loc)>)>.Value((loc, through));
}

_mentions_spec(ty: TypeName, spec: String): bool {
    if (ty.to_string() == spec) {
        return true;
    }
    for (var t in ty.sub_types) {
        if (_mentions_spec(t, spec)) {
            return true;
        }
    }
    return false;
}

## An inferred type (`var a = Atomic<String>();`) has no type location:
## the constructor call in the initializer names it.
_var_site(variable: VariableDef, spec: String): Loc? {
    if (!_mentions_spec(variable.ty, spec) or variable.type_loc.is_none()) {
        return Optional<Loc>.Empty;
    }
    return Optional<Loc>.Value(variable.type_loc);
}

_function_site(f: FunctionDef, spec: String): Loc? {
    for (var p in f.parameters) {
        var at = _var_site(p, spec);
        if (at.is_value()) {
            return at;
        }
    }
    if (f.body.is_value()) {
        return _block_site(f.body.value(), spec);
    }
    return Optional<Loc>.Empty;
}

_block_site(body: Block, spec: String): Loc? {
    for (var statement in body.items) {
        Loc? found = Optional<Loc>.Empty;
        match (statement) {
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    found = _var_site(variable, spec);
                    if (!found.is_value() and variable.default.is_value()) {
                        found = _expression_site(variable.default.value(), spec);
                    }
                }
            }
            Block(inner) => {
                found = _block_site(inner, spec);
            }
            Branch(branch) => {
                found = _expression_site(branch.condition, spec);
                if (!found.is_value()) {
                    found = _block_site(branch.if_block, spec);
                }
                if (!found.is_value() and branch.else_block.is_value()) {
                    found = _block_site(branch.else_block.value(), spec);
                }
            }
            While(loop) => {
                found = _expression_site(loop.condition, spec);
                if (!found.is_value()) {
                    found = _block_site(loop.block, spec);
                }
            }
            Expression(e) => {
                found = _expression_site(e, spec);
            }
            Return(ret) => {
                if (ret.expr.is_value()) {
                    found = _expression_site(ret.expr.value(), spec);
                }
            }
            else => {}
        }
        if (found.is_value()) {
            return found;
        }
    }
    return Optional<Loc>.Empty;
}

_expression_site(e: Expression, spec: String): Loc? {
    var finder = _SpecCall(spec);
    rewrite_expression(e, finder);
    return finder.found;
}

## Finds the first located call of a constructor or function named `spec`.
struct _SpecCall {
    var spec: String;
    var found: Loc? = Optional<Loc>.Empty;

    construct(spec: String) {
        this.spec = spec;
    }

    rewrite(e: Expression): Expression {
        if (!found.is_value()) {
            if (e is FunctionCall(node)) {
                if (node.function == spec and !node.loc.is_none()) {
                    found = Optional<Loc>.Value(node.loc);
                }
            }
        }
        return e;
    }
}

extend _SpecCall with Rewriter;
