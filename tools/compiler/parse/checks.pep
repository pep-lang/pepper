# The rules the Rust parser enforces on the finished tree rather than in
# its grammar: `T*` belongs only in `extern` declarations, and imports come
# before every declaration and re-export.

import compiler.ast;
import [
    Attribute,
    Block,
    Declaration,
    DestructureBinding,
    Expression,
    FunctionDecl,
    GenericParam,
    Module,
    Span,
    Statement,
    TypeName,
    VariableDecl
] from compiler.ast;

# What a check found wrong, and where.
export struct CheckError {
    var message: String = "";
    var offset: ulong;

    construct(message: String, offset: ulong) {
        this.message = message;
        this.offset = offset;
    }
}

# The first rule `module` breaks: a C pointer type outside `extern`, then a
# late import.
export check_module(module: Module): CheckError? {
    var checker = _PointerCheck();
    for (var d in module.declarations) {
        checker.declaration(d);
        if (checker.error.is_value()) {
            return checker.error;
        }
    }
    return check_import_order(module);
}

# Imports must come before every declaration and re-export: qualified
# generic constructions (`m.Box<int>()`) are recognized from the imports
# parsed so far.
export check_import_order(module: Module): CheckError? {
    bool any = false;
    ulong first = 0;
    for (var d in module.declarations) {
        var start = d.span().start;
        if (!any or start < first) {
            first = start;
            any = true;
        }
    }
    for (var e in module.exports) {
        if (!any or e.span.start < first) {
            first = e.span.start;
            any = true;
        }
    }
    if (!any) {
        return Optional<CheckError>.Empty;
    }
    for (var imp in module.imports) {
        if (imp.span.start > first) {
            return Optional<CheckError>.Value(CheckError("imports must come before all declarations", imp.span.start));
        }
    }
    return Optional<CheckError>.Empty;
}

# Rejects `T*` in every type position outside `extern` function
# declarations, which mirror C prototypes.
struct _PointerCheck {
    var error: CheckError?;

    construct() {}

    type_name(t: TypeName) {
        if (error.is_value()) {
            return;
        }
        ulong stars = 0;
        while (stars < t.name.size and t.name.byte_at(t.name.size - 1 - stars) == '*') {
            stars += 1;
        }
        if (stars > 0) {
            var base = TypeName(t.name.substr_bytes(0, t.name.size - stars), t.span);
            base.generic_types = t.generic_types;
            base.labels = t.labels;
            var text = base.to_string();
            var written = text + "*".repeat(stars);
            var suggested = "__ptr<".repeat(stars) + text + ">".repeat(stars);
            error = Optional<CheckError>.Value(
                CheckError(
                    $"C pointer syntax `{written}` is only allowed in extern declarations; use `{suggested}`",
                    t.span.start
                )
            );
            return;
        }
        for (var argument in t.generic_types) {
            type_name(argument);
        }
    }

    attributes(list: Attribute[]) {
        for (var a in list) {
            expression(a.body);
        }
    }

    generic_params(params: GenericParam[]) {
        for (var p in params) {
            for (var bound in p.bounds) {
                type_name(bound);
            }
            if (p.default.is_value()) {
                type_name(p.default.value());
            }
        }
    }

    variable(v: VariableDecl) {
        attributes(v.attributes);
        type_name(v.type_name);
        if (v.default_value.is_value()) {
            expression(v.default_value.value());
        }
    }

    function(f: FunctionDecl) {
        attributes(f.attributes);
        if (f.external) {
            return;
        }
        generic_params(f.generic_params);
        type_name(f.return_type);
        for (var p in f.parameters) {
            variable(p);
        }
        if (f.body.is_value()) {
            block(f.body.value());
        }
    }

    declaration(d: Declaration) {
        if (error.is_value()) {
            return;
        }
        match (d) {
            Variable(v) => {
                variable(v);
            }
            Function(f) => {
                function(f);
            }
            Struct(s) => {
                attributes(s.attributes);
                generic_params(s.generic_params);
                for (var field in s.fields) {
                    variable(field);
                }
                for (var m in s.methods) {
                    function(m);
                }
                for (var c in s.constructors) {
                    function(c);
                }
                if (s.enumeration.is_value()) {
                    for (var c in s.enumeration.value().cases) {
                        attributes(c.attributes);
                        if (c.payload.is_value()) {
                            for (var p in c.payload.value()) {
                                variable(p);
                            }
                        }
                    }
                }
                if (s.destructor.is_value()) {
                    block(s.destructor.value());
                }
            }
            Trait(t) => {
                attributes(t.attributes);
                generic_params(t.generic_params);
                for (var m in t.methods) {
                    function(m);
                }
            }
            Extend(e) => {
                attributes(e.attributes);
                type_name(e.target);
                for (var bounds in e.target_bounds) {
                    for (var bound in bounds) {
                        type_name(bound);
                    }
                }
                for (var t in e.traits) {
                    type_name(t);
                }
                for (var m in e.methods) {
                    function(m);
                }
            }
            TypeAlias(a) => {
                attributes(a.attributes);
                generic_params(a.generic_params);
                type_name(a.target);
            }
            Static(s) => {
                attributes(s.attributes);
                block(s.block);
            }
        }
    }

    block(b: Block) {
        attributes(b.attributes);
        for (var s in b.statements) {
            statement(s);
        }
    }

    _leaves(bindings: DestructureBinding[]) {
        for (var b in bindings) {
            if (b.nested.count > 0) {
                _leaves(b.nested);
            } else {
                type_name(b.type_name);
            }
        }
    }

    statement(s: Statement) {
        if (error.is_value()) {
            return;
        }
        match (s) {
            Expression(e) => {
                expression(e);
            }
            Block(b) => {
                block(b);
            }
            Declaration(d) => {
                declaration(d);
            }
            Branch(condition, if_block, else_block, _) => {
                expression(condition);
                block(if_block);
                if (else_block.is_value()) {
                    block(else_block.value());
                }
            }
            While(condition, body, _) => {
                expression(condition);
                block(body);
            }
            For(binding, _, iterable, body, _) => {
                type_name(binding.type_name);
                expression(iterable);
                block(body);
            }
            With(binding, scope, body, else_block, _) => {
                if (binding.is_value()) {
                    type_name(binding.value().type_name);
                }
                expression(scope);
                block(body);
                if (else_block.is_value()) {
                    block(else_block.value());
                }
            }
            Return(value, _) => {
                if (value.is_value()) {
                    expression(value.value());
                }
            }
            LoopBreak(_, _) => {}
            Destructure(bindings, value, _, _) => {
                _leaves(bindings);
                expression(value);
            }
            Match(m) => {
                expression(m.value);
                for (var arm in m.arms) {
                    if (arm.guard.is_value()) {
                        expression(arm.guard.value());
                    }
                }
                for (var arm in m.arms) {
                    block(arm.body);
                }
                if (m.else_block.is_value()) {
                    block(m.else_block.value());
                }
            }
            Static(s) => {
                block(s.block);
            }
        }
    }

    expression(e: Expression) {
        if (error.is_value()) {
            return;
        }
        match (e) {
            Literal(_, _) => {}
            SymbolRef(_, _) => {}
            TypeLiteral(t) => {
                type_name(t);
            }
            SizeOf(t) => {
                type_name(t);
            }
            Unary(_, _, operand, _) => {
                expression(operand);
            }
            Cast(value, t, _, _, _) => {
                expression(value);
                type_name(t);
            }
            Binary(lhs, _, rhs, _) => {
                expression(lhs);
                expression(rhs);
            }
            Index(lhs, rhs, _) => {
                expression(lhs);
                expression(rhs);
            }
            Ternary(condition, yes, no, _) => {
                expression(condition);
                expression(yes);
                expression(no);
            }
            MemberAccess(lhs, _, _, _) => {
                expression(lhs);
            }
            NamedArgument(_, _, value, _) => {
                expression(value);
            }
            FunctionCall(function, arguments, _) => {
                expression(function);
                for (var a in arguments) {
                    expression(a);
                }
            }
            Closure(c) => {
                for (var p in c.parameters) {
                    type_name(p.type_name);
                }
                type_name(c.return_type);
                block(c.body);
            }
            Tuple(elements, _, _) => {
                for (var element in elements) {
                    expression(element);
                }
            }
            ArrayLiteral(elements, _) => {
                for (var element in elements) {
                    expression(element);
                }
            }
            MapLiteral(entries, _) => {
                for (var entry in entries) {
                    expression(entry.key);
                    expression(entry.value);
                }
            }
            Match(m) => {
                expression(m.value);
                for (var arm in m.arms) {
                    if (arm.guard.is_value()) {
                        expression(arm.guard.value());
                    }
                }
                for (var arm in m.arms) {
                    expression(arm.value);
                }
                if (m.else_value.is_value()) {
                    expression(m.else_value.value());
                }
            }
            Is(value, _, _, _) => {
                expression(value);
            }
            Interpolated(parts, _) => {
                for (var part in parts) {
                    if (part is Hole(value, _, _)) {
                        expression(value);
                    }
                }
            }
            # Its arguments are the call's.
            FormatString(_, _, _, _) => {}
        }
    }
}
