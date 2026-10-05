# What the syntax tree of a document says at an offset: the declaration
# whose name is there, the names in scope there (locals, parameters, the
# members of the struct around it, top-level declarations), and the
# innermost expression or type name there. Hover and go-to-definition
# (`navigate.pep`) start from these; what a name means across files comes
# from linking (`imports.pep`) and sema.

import compiler.ast;
import [
    Block,
    ClosureLiteral,
    Declaration,
    DestructureBinding,
    Expression,
    FunctionDecl,
    GenericParam,
    Module,
    Pattern,
    Span,
    Statement,
    StructDecl,
    TypeName,
    VariableDecl
] from compiler.ast;
import [built_in_name] from compiler.doc;
import "symbols";

## A declared name: what hover shows for it and where it is declared.
export struct Symbol {
    ## The name.
    var name: String;
    ## Where the name is written in its declaration.
    var name_span: Span;
    ## Its type or signature as written (`int`, `area(r: float): float`);
    ## empty or `unknown` when the declaration does not say.
    var type_text: String;

    ## Creates a symbol.
    ##
    ## @param name the name
    ## @param name_span where it is declared
    ## @param type_text its type as written
    construct(name: String, name_span: Span, type_text: String) {
        this.name = name;
        this.name_span = name_span;
        this.type_text = type_text;
    }
}

## A declaration whose name is at an offset, and the struct, trait or
## extended type it is a member of.
export struct Declared {
    ## The declaration.
    var symbol: Symbol;
    ## The type it is a member of; empty for a top-level declaration, a
    ## local or a parameter.
    var owner: String?;

    ## Creates one.
    ##
    ## @param symbol the declaration
    ## @param owner the type it is a member of
    construct(symbol: Symbol, owner: String? = Optional<String>.Empty) {
        this.symbol = symbol;
        this.owner = owner;
    }
}

## The code around an offset: a function's body or a destructor, with the
## struct it belongs to.
export struct Enclosing {
    ## The function, method, constructor or accessor; empty in a
    ## destructor.
    var function: FunctionDecl?;
    ## Its body.
    var body: Block;
    ## The struct it is a member of; empty for a free function or an
    ## extension's method.
    var owner: StructDecl?;

    ## Creates one.
    ##
    ## @param function the function, if any
    ## @param body its body
    ## @param owner the struct, if any
    construct(function: FunctionDecl?, body: Block, owner: StructDecl?) {
        this.function = function;
        this.body = body;
        this.owner = owner;
    }
}

## Whether `span` holds `offset`, its end left out.
##
## @param span the span
## @param offset the byte offset
## @returns true when inside
export contains(span: Span, offset: ulong): bool {
    return span.start <= offset and offset < span.end;
}

## Whether the cursor at `offset` is on the name at `span`: inside it or
## just after its last byte.
##
## @param span the name
## @param offset the byte offset
## @returns true when on it
export on_name(span: Span, offset: ulong): bool {
    return span.start <= offset and offset <= span.end;
}

## The top-level declarations of `module`, each with its type or
## signature. A `[__BuiltIn]` declaration goes by the built-in it declares
## (`reflect.name`), so a use of the built-in finds it and a declaration of
## the same plain name elsewhere does not.
##
## @param module the syntax tree
## @returns the declarations, in source order
export collect_globals(module: Module): Symbol[] {
    var out = Array<Symbol>();
    for (var declaration in module.declarations) {
        var spelled = built_in_name(declaration.attributes(), declaration.declared_name());
        var name = spelled.is_value() ? spelled.value() : declaration.declared_name();
        match (declaration) {
            Variable(v) => {
                out.append(Symbol(name, v.name_span, variable_type(v)));
            }
            Function(f) => {
                var signature = function_signature(f);
                out.append(
                    Symbol(name, f.name_span, name + signature.substr_bytes(f.name.size, signature.size - f.name.size))
                );
            }
            Struct(s) => {
                var kind = s.enumeration.is_value() ? "enum" : "struct";
                out.append(Symbol(name, s.name_span, $"{kind} {name}{generics_string(s.generic_params)}"));
            }
            Trait(t) => {
                out.append(Symbol(name, t.name_span, $"trait {name}{generics_string(t.generic_params)}"));
            }
            TypeAlias(t) => {
                var target = t.target.to_string();
                out.append(Symbol(name, t.name_span, $"type {name}{generics_string(t.generic_params)} = {target}"));
            }
            # Its constants are declared beside it, as variables.
            else => {}
        }
    }
    return out;
}

## The members of `s`: its enum cases, fields, properties, constructors and
## methods.
##
## @param s the struct
## @returns the members, each with its type or signature
export collect_struct_members(s: StructDecl): Symbol[] {
    var out = Array<Symbol>();
    if (s.enumeration is Value(body)) {
        for (var case in body.cases) {
            out.append(Symbol(case.name, case.name_span, $"{s.name}.{case.name}"));
        }
    }
    for (var field in s.fields) {
        out.append(Symbol(field.name, field.name_span, field.type_name.to_string()));
    }
    for (var property in s.properties) {
        out.append(Symbol(property.name, property.name_span, property.type_name.to_string()));
    }
    for (var c in s.constructors) {
        var parameters = Array<String>();
        for (var p in c.parameters) {
            parameters.append($"{p.name}: {p.type_name.to_string()}");
        }
        var listed = ", ".join(parameters);
        out.append(Symbol("construct", c.name_span, $"construct({listed})"));
    }
    for (var m in s.methods) {
        out.append(Symbol(m.name, m.name_span, function_signature(m)));
    }
    return out;
}

## A variable declaration as a symbol.
##
## @param v the declaration
## @returns its symbol
export variable_symbol(v: VariableDecl): Symbol {
    return Symbol(v.name, v.name_span, variable_type(v));
}

## The function, method, constructor or accessor whose body holds
## `offset`, or the destructor, with the struct it belongs to.
##
## @param module the syntax tree
## @param offset the byte offset
## @returns the code around it; empty at module scope
export body_at(module: Module, offset: ulong): Enclosing? {
    for (var declaration in module.declarations) {
        match (declaration) {
            Function(f) => {
                if (_inside(f, offset)) {
                    return Optional<Enclosing>.Value(
                        Enclosing(Optional<FunctionDecl>.Value(f), f.body.value(), Optional<StructDecl>.Empty)
                    );
                }
            }
            Struct(s) => {
                if (!contains(s.span, offset)) {
                    continue;
                }
                var owner = Optional<StructDecl>.Value(s);
                for (var f in _struct_functions(s)) {
                    if (_inside(f, offset)) {
                        return Optional<Enclosing>.Value(
                            Enclosing(Optional<FunctionDecl>.Value(f), f.body.value(), owner)
                        );
                    }
                }
                if (s.destructor is Value(destructor)) {
                    if (contains(destructor.span, offset)) {
                        return Optional<Enclosing>.Value(Enclosing(Optional<FunctionDecl>.Empty, destructor, owner));
                    }
                }
            }
            Extend(e) => {
                var functions = Array<FunctionDecl>();
                functions.append_all(e.methods);
                _append_accessors(e.properties, functions);
                for (var f in functions) {
                    if (_inside(f, offset)) {
                        return Optional<Enclosing>.Value(
                            Enclosing(Optional<FunctionDecl>.Value(f), f.body.value(), Optional<StructDecl>.Empty)
                        );
                    }
                }
            }
            # A trait's method with a default body.
            Trait(t) => {
                for (var f in t.methods) {
                    if (_inside(f, offset)) {
                        return Optional<Enclosing>.Value(
                            Enclosing(Optional<FunctionDecl>.Value(f), f.body.value(), Optional<StructDecl>.Empty)
                        );
                    }
                }
            }
            else => {}
        }
    }
    return Optional<Enclosing>.Empty;
}

# Whether `f` has a body and its span holds `offset`.
_inside(f: FunctionDecl, offset: ulong): bool {
    return f.body.is_value() and contains(f.span, offset);
}

# A struct's methods, constructors and property accessors.
_struct_functions(s: StructDecl): FunctionDecl[] {
    var out = Array<FunctionDecl>();
    out.append_all(s.methods);
    out.append_all(s.constructors);
    _append_accessors(s.properties, out);
    return out;
}

_append_accessors(properties: ast.PropertyDecl[], out: FunctionDecl[]) {
    for (var property in properties) {
        if (property.getter is Value(getter)) {
            out.append(getter.function);
        }
        if (property.setter is Value(setter)) {
            out.append(setter.function);
        }
    }
}

## The name of the type the extension around `offset` extends.
##
## @param module the syntax tree
## @param offset the byte offset
## @returns the extended type's name; empty outside an extension
export extended_at(module: Module, offset: ulong): String? {
    for (var declaration in module.declarations) {
        if (declaration is Extend(e)) {
            if (contains(e.span, offset)) {
                return Optional<String>.Value(e.target.name);
            }
        }
    }
    return Optional<String>.Empty;
}

## The declaration whose name is at `offset`: a top-level declaration, a
## member (field, method, enum case, a case's value), a local, a parameter
## or a generic parameter.
##
## @param module the syntax tree
## @param offset the byte offset
## @returns the declaration; empty when no name is declared there
export declared_at(module: Module, offset: ulong): Declared? {
    for (var symbol in collect_globals(module)) {
        if (on_name(symbol.name_span, offset)) {
            return Optional<Declared>.Value(Declared(symbol));
        }
    }
    for (var declaration in module.declarations) {
        var found = _member_declared_at(declaration, offset);
        if (found.is_value()) {
            return found;
        }
    }
    for (var symbol in scope_locals(module, offset)) {
        if (on_name(symbol.name_span, offset)) {
            return Optional<Declared>.Value(Declared(symbol));
        }
    }
    var parameter = parameter_at(module, offset);
    if (parameter.is_value()) {
        return Optional<Declared>.Value(Declared(parameter.value()));
    }
    var generic = generic_param_at(module, offset, (p: GenericParam) => on_name(p.name_span, offset));
    if (generic.is_value()) {
        return Optional<Declared>.Value(Declared(generic.value()));
    }
    return Optional<Declared>.Empty;
}

# The member of `declaration` whose name is at `offset`.
_member_declared_at(declaration: Declaration, offset: ulong): Declared? {
    var none = Optional<Declared>.Empty;
    match (declaration) {
        Struct(s) => {
            var owner = Optional<String>.Value(s.name);
            for (var member in collect_struct_members(s)) {
                if (on_name(member.name_span, offset)) {
                    return Optional<Declared>.Value(Declared(member, owner));
                }
            }
            # A value an enum case carries (`Circle(radius: int)`).
            if (s.enumeration is Value(body)) {
                for (var case in body.cases) {
                    if (case.payload is Value(payload)) {
                        for (var v in payload) {
                            if (on_name(v.name_span, offset)) {
                                return Optional<Declared>.Value(Declared(variable_symbol(v), owner));
                            }
                        }
                    }
                }
            }
        }
        Trait(t) => {
            return _method_declared_at(t.name, t.methods, offset);
        }
        Extend(e) => {
            return _method_declared_at(e.target.name, e.methods, offset);
        }
        else => {}
    }
    return none;
}

_method_declared_at(owner: String, methods: FunctionDecl[], offset: ulong): Declared? {
    for (var m in methods) {
        if (on_name(m.name_span, offset)) {
            return Optional<Declared>.Value(
                Declared(Symbol(m.name, m.name_span, function_signature(m)), Optional<String>.Value(owner))
            );
        }
    }
    return Optional<Declared>.Empty;
}

## The parameter whose name is at `offset`, of any function, method,
## constructor or accessor.
##
## @param module the syntax tree
## @param offset the byte offset
## @returns the parameter; empty when none is named there
export parameter_at(module: Module, offset: ulong): Symbol? {
    for (var f in _all_functions(module)) {
        for (var p in f.parameters) {
            if (on_name(p.name_span, offset)) {
                return Optional<Symbol>.Value(variable_symbol(p));
            }
        }
    }
    return Optional<Symbol>.Empty;
}

# Every function of `module` that has parameters: free functions,
# methods, constructors, accessors, and trait and extension methods.
_all_functions(module: Module): FunctionDecl[] {
    var out = Array<FunctionDecl>();
    for (var declaration in module.declarations) {
        match (declaration) {
            Function(f) => {
                out.append(f);
            }
            Struct(s) => {
                out.append_all(_struct_functions(s));
            }
            Trait(t) => {
                out.append_all(t.methods);
            }
            Extend(e) => {
                out.append_all(e.methods);
                _append_accessors(e.properties, out);
            }
            else => {}
        }
    }
    return out;
}

## The generic parameter of the declaration around `offset` that
## `matches`, innermost first, as a symbol whose type reads `type
## parameter`.
##
## @param module the syntax tree
## @param offset the byte offset
## @param matches which parameter to find
## @returns the parameter; empty when none matches
export generic_param_at(module: Module, offset: ulong, matches: (GenericParam) => bool): Symbol? {
    var scopes = Array<GenericParam[]>();
    for (var declaration in module.declarations) {
        match (declaration) {
            Function(f) => {
                if (contains(f.span, offset)) {
                    scopes.append(f.generic_params);
                }
            }
            Struct(s) => {
                if (contains(s.span, offset)) {
                    scopes.append(s.generic_params);
                    _append_method_generics(s.methods, offset, scopes);
                }
            }
            Trait(t) => {
                if (contains(t.span, offset)) {
                    scopes.append(t.generic_params);
                    _append_method_generics(t.methods, offset, scopes);
                }
            }
            Extend(e) => {
                if (contains(e.span, offset)) {
                    _append_method_generics(e.methods, offset, scopes);
                }
            }
            TypeAlias(t) => {
                if (contains(t.span, offset)) {
                    scopes.append(t.generic_params);
                }
            }
            else => {}
        }
    }
    long i = scopes.count as long - 1;
    while (i >= 0) {
        for (var p in scopes[i as ulong]) {
            if (!matches(p)) {
                continue;
            }
            var type_text = "type parameter";
            if (p.bounds.count > 0) {
                var bounds = Array<String>();
                for (var bound in p.bounds) {
                    bounds.append(bound.to_string());
                }
                type_text += ": " + " & ".join(bounds);
            }
            return Optional<Symbol>.Value(Symbol(p.name, p.name_span, type_text));
        }
        i -= 1;
    }
    return Optional<Symbol>.Empty;
}

_append_method_generics(methods: FunctionDecl[], offset: ulong, scopes: Array<GenericParam[]>) {
    for (var m in methods) {
        if (contains(m.span, offset)) {
            scopes.append(m.generic_params);
        }
    }
}

## The names in scope at `offset` inside a body: the function's
## parameters, the locals declared before `offset` in the blocks around
## it, the names a pattern binds there, and a closure's parameters and
## locals. A name declared at `offset` itself counts too.
##
## @param module the syntax tree
## @param offset the byte offset
## @returns the names, outermost first, so the last of a name is the one
##   in effect
export scope_locals(module: Module, offset: ulong): Symbol[] {
    var out = Array<Symbol>();
    var enclosing = body_at(module, offset);
    if (enclosing.is_empty()) {
        # A closure in a module-scope variable's initializer.
        for (var declaration in module.declarations) {
            if (declaration is Variable(v)) {
                if (v.default_value is Value(initializer)) {
                    var closure = closure_in_expression(initializer, offset);
                    if (closure.is_value()) {
                        _push_closure_locals(closure.value(), offset, out);
                    }
                }
            }
        }
        return out;
    }
    var found = enclosing.value();
    if (found.function is Value(f)) {
        for (var p in f.parameters) {
            if (p.name != "this") {
                out.append(variable_symbol(p));
            }
        }
    }
    _collect_locals(found.body, offset, out);
    var closure = closure_in_block(found.body, offset);
    if (closure.is_value()) {
        _push_closure_locals(closure.value(), offset, out);
    }
    return out;
}

# The locals inside closure `c` at `offset`: its parameters, what its body
# declares, and so on for each closure nested there.
_push_closure_locals(c: ClosureLiteral, offset: ulong, out: Symbol[]) {
    var closure = Optional<ClosureLiteral>.Value(c);
    while (closure is Value(current)) {
        for (var p in current.parameters) {
            out.append(variable_symbol(p));
        }
        _collect_locals(current.body, offset, out);
        closure = closure_in_block(current.body, offset);
    }
}

# The named bindings of a destructuring pattern, nested ones included.
_push_pattern(bindings: DestructureBinding[], out: Symbol[]) {
    for (var b in bindings) {
        if (b.nested.count > 0) {
            _push_pattern(b.nested, out);
            continue;
        }
        if (b.name == "_") {
            continue;
        }
        var type_text = b.type_name.name == "__auto" ? "" : b.type_name.to_string();
        out.append(Symbol(b.name, b.name_span, type_text));
    }
}

# The names a pattern binds, which the code it guards sees.
_push_bound_names(patterns: Pattern[], out: Symbol[]) {
    for (var pattern in patterns) {
        for (var label in pattern.bound_names()) {
            # Not the hidden names `String.format`'s lowering binds.
            if (!label.name.starts_with("_pep_")) {
                out.append(Symbol(label.name, label.span, ""));
            }
        }
    }
}

# The names `if (x is P(a))` or `while (x is P(a))` binds in its block.
_push_is_bindings(condition: Expression, out: Symbol[]) {
    if (condition is Is(_, pattern, _, _)) {
        _push_bound_names([pattern], out);
    }
}

# Adds the locals `block` declares before `offset`, and those of the
# statement holding `offset`, nested blocks included.
_collect_locals(block: Block, offset: ulong, out: Symbol[]) {
    for (var statement in block.statements) {
        var span = statement.span();
        if (span.end <= offset) {
            if (statement is Declaration(declaration)) {
                if (declaration is Variable(v)) {
                    out.append(variable_symbol(v));
                }
            } else if (statement is Destructure(bindings, _, _, _)) {
                _push_pattern(bindings, out);
            }
            continue;
        }
        if (!contains(span, offset)) {
            continue;
        }
        _collect_in_statement(statement, offset, out);
    }
}

# Adds the locals the statement holding `offset` binds there.
_collect_in_statement(statement: Statement, offset: ulong, out: Symbol[]) {
    match (statement) {
        # The name being declared, under the cursor.
        Declaration(declaration) => {
            if (declaration is Variable(v)) {
                if (on_name(v.name_span, offset)) {
                    out.append(variable_symbol(v));
                }
            }
        }
        Destructure(bindings, _, _, _) => {
            var names = Array<Symbol>();
            _push_pattern(bindings, names);
            for (var name in names) {
                if (on_name(name.name_span, offset)) {
                    out.append(name);
                }
            }
        }
        Block(inner) => {
            _collect_locals(inner, offset, out);
        }
        Branch(condition, if_block, else_block, _) => {
            if (contains(if_block.span, offset)) {
                _push_is_bindings(condition, out);
                _collect_locals(if_block, offset, out);
            } else if (else_block is Value(otherwise)) {
                if (contains(otherwise.span, offset)) {
                    _collect_locals(otherwise, offset, out);
                }
            }
        }
        While(condition, body, _) => {
            if (contains(body.span, offset)) {
                _push_is_bindings(condition, out);
                _collect_locals(body, offset, out);
            }
        }
        For(binding, pattern, _, body, _) => {
            if (on_name(binding.name_span, offset)) {
                out.append(variable_symbol(binding));
            } else if (contains(body.span, offset)) {
                if (pattern.count == 0) {
                    out.append(variable_symbol(binding));
                } else {
                    _push_pattern(pattern, out);
                }
                _collect_locals(body, offset, out);
            }
        }
        With(binding, _, body, else_block, _) => {
            if (contains(body.span, offset)) {
                if (binding is Value(b)) {
                    out.append(variable_symbol(b));
                }
                _collect_locals(body, offset, out);
            } else if (else_block is Value(otherwise)) {
                if (contains(otherwise.span, offset)) {
                    _collect_locals(otherwise, offset, out);
                }
            }
        }
        Static(block) => {
            if (contains(block.block.span, offset)) {
                _collect_locals(block.block, offset, out);
            }
        }
        Match(m) => {
            for (var arm in m.arms) {
                # The names the arm's patterns bind, in its guard and its
                # block.
                if (arm.span.start <= offset and offset < arm.body.span.end) {
                    _push_bound_names(arm.patterns, out);
                }
                if (contains(arm.body.span, offset)) {
                    _collect_locals(arm.body, offset, out);
                }
            }
            if (m.else_block is Value(otherwise)) {
                if (contains(otherwise.span, offset)) {
                    _collect_locals(otherwise, offset, out);
                }
            }
        }
        Expression(e) => {
            _push_match_bindings(e, offset, out);
        }
        Return(value, _) => {
            if (value is Value(e)) {
                _push_match_bindings(e, offset, out);
            }
        }
        else => {}
    }
}

# The names a `match` expression's arm binds (`Circle(r) => 3 * r * r`),
# for the arm in `e` whose guard or value holds `offset`.
_push_match_bindings(e: Expression, offset: ulong, out: Symbol[]) {
    if (!contains(e.extent(), offset)) {
        return;
    }
    if (e is Match(m)) {
        for (var arm in m.arms) {
            if (arm.span.start <= offset and offset < arm.value.extent().end) {
                _push_bound_names(arm.patterns, out);
            }
        }
    }
    for (var child in children(e)) {
        _push_match_bindings(child, offset, out);
    }
}

## The direct sub-expressions of `e`. A closure's body is a block, not a
## sub-expression.
##
## @param e the expression
## @returns its children, in source order
export children(e: Expression): Expression[] {
    var out = Array<Expression>();
    match (e) {
        Unary(_, _, operand, _) => {
            out.append(operand);
        }
        Cast(value, _, _, _, _) => {
            out.append(value);
        }
        Binary(lhs, _, rhs, _) => {
            out.append(lhs);
            out.append(rhs);
        }
        Ternary(condition, true_expr, false_expr, _) => {
            out.append(condition);
            out.append(true_expr);
            out.append(false_expr);
        }
        Index(lhs, rhs, _) => {
            out.append(lhs);
            out.append(rhs);
        }
        MemberAccess(lhs, _, _, _) => {
            out.append(lhs);
        }
        FunctionCall(function, arguments, _) => {
            out.append(function);
            out.append_all(arguments);
        }
        NamedArgument(_, _, value, _) => {
            out.append(value);
        }
        Tuple(elements, _, _) => {
            out.append_all(elements);
        }
        ArrayLiteral(elements, _) => {
            out.append_all(elements);
        }
        MapLiteral(entries, _) => {
            for (var entry in entries) {
                out.append(entry.key);
                out.append(entry.value);
            }
        }
        Match(m) => {
            out.append(m.value);
            for (var arm in m.arms) {
                if (arm.guard is Value(guard)) {
                    out.append(guard);
                }
                out.append(arm.value);
            }
            if (m.else_value is Value(otherwise)) {
                out.append(otherwise);
            }
        }
        Is(value, _, _, _) => {
            out.append(value);
        }
        else => {}
    }
    return out;
}

## The outermost closure in `block` whose span holds `offset`.
##
## @param block the block
## @param offset the byte offset
## @returns the closure; empty when none holds it
export closure_in_block(block: Block, offset: ulong): ClosureLiteral? {
    for (var statement in block.statements) {
        if (!contains(statement.span(), offset)) {
            continue;
        }
        for (var e in _statement_expressions(statement)) {
            var found = closure_in_expression(e, offset);
            if (found.is_value()) {
                return found;
            }
        }
        for (var inner in statement_blocks(statement)) {
            if (contains(inner.span, offset)) {
                return closure_in_block(inner, offset);
            }
        }
    }
    return Optional<ClosureLiteral>.Empty;
}

## The outermost closure in `e` whose span holds `offset`.
##
## @param e the expression
## @param offset the byte offset
## @returns the closure; empty when none holds it
export closure_in_expression(e: Expression, offset: ulong): ClosureLiteral? {
    if (!contains(e.extent(), offset)) {
        return Optional<ClosureLiteral>.Empty;
    }
    if (e is Closure(c)) {
        return Optional<ClosureLiteral>.Value(c);
    }
    for (var child in children(e)) {
        var found = closure_in_expression(child, offset);
        if (found.is_value()) {
            return found;
        }
    }
    return Optional<ClosureLiteral>.Empty;
}

# The expressions a statement holds directly, not those of its blocks.
_statement_expressions(statement: Statement): Expression[] {
    var out = Array<Expression>();
    match (statement) {
        Expression(e) => {
            out.append(e);
        }
        Return(value, _) => {
            if (value is Value(e)) {
                out.append(e);
            }
        }
        Declaration(declaration) => {
            if (declaration is Variable(v)) {
                if (v.default_value is Value(e)) {
                    out.append(e);
                }
            }
        }
        Destructure(_, value, _, _) => {
            out.append(value);
        }
        Branch(condition, _, _, _) => {
            out.append(condition);
        }
        While(condition, _, _) => {
            out.append(condition);
        }
        For(_, _, iterable, _, _) => {
            out.append(iterable);
        }
        With(_, scope, _, _, _) => {
            out.append(scope);
        }
        Match(m) => {
            out.append(m.value);
            for (var arm in m.arms) {
                if (arm.guard is Value(guard)) {
                    out.append(guard);
                }
            }
        }
        else => {}
    }
    return out;
}

## The blocks a statement holds directly: a branch's, a loop's, a match
## arm's.
##
## @param statement the statement
## @returns its blocks, in source order
export statement_blocks(statement: Statement): Block[] {
    var out = Array<Block>();
    match (statement) {
        Block(inner) => {
            out.append(inner);
        }
        Branch(_, if_block, else_block, _) => {
            out.append(if_block);
            if (else_block is Value(otherwise)) {
                out.append(otherwise);
            }
        }
        While(_, body, _) => {
            out.append(body);
        }
        For(_, _, _, body, _) => {
            out.append(body);
        }
        With(_, _, body, else_block, _) => {
            out.append(body);
            if (else_block is Value(otherwise)) {
                out.append(otherwise);
            }
        }
        Static(block) => {
            out.append(block.block);
        }
        Match(m) => {
            for (var arm in m.arms) {
                out.append(arm.body);
            }
            if (m.else_block is Value(otherwise)) {
                out.append(otherwise);
            }
        }
        else => {}
    }
    return out;
}

## The innermost expression holding `offset` anywhere in `module`: in a
## body, a parameter's default value, or a module-scope variable's
## initializer. The member name of `x.name` stands for the whole access.
##
## @param module the syntax tree
## @param offset the byte offset
## @returns the expression; empty when none holds it
export find_expression(module: Module, offset: ulong): Expression? {
    var enclosing = body_at(module, offset);
    if (enclosing is Value(found)) {
        var in_body = _in_block(found.body, offset);
        if (in_body.is_value() or found.function.is_empty()) {
            return in_body;
        }
        # A parameter's default value (`construct(this.op = square)`).
        for (var p in found.function.value().parameters) {
            if (p.default_value is Value(e)) {
                var in_default = expression_at(e, offset);
                if (in_default.is_value()) {
                    return in_default;
                }
            }
        }
        return Optional<Expression>.Empty;
    }
    for (var declaration in module.declarations) {
        if (declaration is Variable(v)) {
            if (v.default_value is Value(e)) {
                var found = expression_at(e, offset);
                if (found.is_value()) {
                    return found;
                }
            }
        }
    }
    return Optional<Expression>.Empty;
}

# The innermost expression in `block` holding `offset`.
_in_block(block: Block, offset: ulong): Expression? {
    for (var statement in block.statements) {
        for (var e in _statement_expressions(statement)) {
            var found = expression_at(e, offset);
            if (found.is_value()) {
                return found;
            }
        }
        for (var inner in statement_blocks(statement)) {
            if (contains(inner.span, offset)) {
                return _in_block(inner, offset);
            }
        }
    }
    return Optional<Expression>.Empty;
}

## The innermost expression in `e` holding `offset`. The member name of
## `x.name` stands for the whole access; a closure's body is searched as
## a block.
##
## @param e the expression
## @param offset the byte offset
## @returns the expression; empty when `e` does not hold it
export expression_at(e: Expression, offset: ulong): Expression? {
    if (!contains(e.extent(), offset)) {
        return Optional<Expression>.Empty;
    }
    match (e) {
        MemberAccess(lhs, _, name_span, _) => {
            if (contains(name_span, offset)) {
                return Optional<Expression>.Value(e);
            }
            return expression_at(lhs, offset);
        }
        Closure(c) => {
            var in_body = _in_block(c.body, offset);
            return in_body.is_value() ? in_body : Optional<Expression>.Value(e);
        }
        else => {}
    }
    for (var child in children(e)) {
        var found = expression_at(child, offset);
        if (found.is_value()) {
            return found;
        }
    }
    # Operators and calls hold their operands: only the operands name
    # anything.
    match (e) {
        Binary(_, _, _, _) => {
            return Optional<Expression>.Empty;
        }
        Unary(_, _, _, _) => {
            return Optional<Expression>.Empty;
        }
        Index(_, _, _) => {
            return Optional<Expression>.Empty;
        }
        Ternary(_, _, _, _) => {
            return Optional<Expression>.Empty;
        }
        NamedArgument(_, _, _, _) => {
            return Optional<Expression>.Empty;
        }
        else => {}
    }
    return Optional<Expression>.Value(e);
}

## The innermost type name written at `offset` anywhere in `module`: in a
## declaration, a signature, a local's type, a cast, a generic call's type
## arguments.
##
## @param module the syntax tree
## @param offset the byte offset
## @returns the type name; empty when none is written there
export type_at(module: Module, offset: ulong): TypeName? {
    var finder = _TypeFinder(offset);
    for (var declaration in module.declarations) {
        finder.declaration(declaration);
        if (finder.found.is_value()) {
            return finder.found;
        }
    }
    return Optional<TypeName>.Empty;
}

# Finds the innermost type name at an offset; the first found wins.
struct _TypeFinder {
    var offset: ulong;
    var found: TypeName?;

    construct(offset: ulong) {
        this.offset = offset;
        this.found = Optional<TypeName>.Empty;
    }

    type_name(t: TypeName) {
        if (found.is_value() or !contains(t.span, offset) or t.name == "__auto") {
            return;
        }
        for (var argument in t.generic_types) {
            type_name(argument);
        }
        if (found.is_empty()) {
            found = Optional<TypeName>.Value(t);
        }
    }

    generics(parameters: GenericParam[]) {
        for (var p in parameters) {
            for (var bound in p.bounds) {
                type_name(bound);
            }
            if (p.default is Value(fallback)) {
                type_name(fallback);
            }
        }
    }

    variable(v: VariableDecl) {
        type_name(v.type_name);
        if (v.default_value is Value(e)) {
            expression(e);
        }
    }

    function(f: FunctionDecl) {
        if (!contains(f.span, offset) and !contains(f.name_span, offset)) {
            return;
        }
        generics(f.generic_params);
        type_name(f.return_type);
        for (var p in f.parameters) {
            variable(p);
        }
        if (f.body is Value(body)) {
            block(body);
        }
    }

    declaration(d: Declaration) {
        match (d) {
            Variable(v) => {
                variable(v);
            }
            Function(f) => {
                function(f);
            }
            Struct(s) => {
                generics(s.generic_params);
                for (var field in s.fields) {
                    variable(field);
                }
                for (var property in s.properties) {
                    type_name(property.type_name);
                }
                if (s.enumeration is Value(body)) {
                    if (body.representation is Value(representation)) {
                        type_name(representation);
                    }
                    for (var case in body.cases) {
                        if (case.payload is Value(payload)) {
                            for (var v in payload) {
                                variable(v);
                            }
                        }
                    }
                }
                for (var f in _struct_functions(s)) {
                    function(f);
                }
                if (s.destructor is Value(destructor)) {
                    block(destructor);
                }
            }
            Trait(t) => {
                generics(t.generic_params);
                for (var m in t.methods) {
                    function(m);
                }
            }
            Extend(e) => {
                type_name(e.target);
                for (var t in e.traits) {
                    type_name(t);
                }
                for (var m in e.methods) {
                    function(m);
                }
            }
            TypeAlias(t) => {
                generics(t.generic_params);
                type_name(t.target);
            }
            Static(s) => {
                block(s.block);
            }
        }
    }

    block(b: Block) {
        if (!contains(b.span, offset)) {
            return;
        }
        for (var statement in b.statements) {
            statement_types(statement);
        }
    }

    statement_types(s: Statement) {
        match (s) {
            Declaration(d) => {
                declaration(d);
            }
            For(binding, pattern, _, _, _) => {
                variable(binding);
                _bindings(pattern);
            }
            With(binding, _, _, _, _) => {
                if (binding is Value(b)) {
                    variable(b);
                }
            }
            Destructure(bindings, _, _, _) => {
                _bindings(bindings);
            }
            Match(m) => {
                for (var arm in m.arms) {
                    _patterns(arm.patterns);
                }
            }
            else => {}
        }
        for (var e in _statement_expressions(s)) {
            expression(e);
        }
        for (var inner in statement_blocks(s)) {
            block(inner);
        }
    }

    _bindings(bindings: DestructureBinding[]) {
        for (var b in bindings) {
            type_name(b.type_name);
            _bindings(b.nested);
        }
    }

    _patterns(patterns: Pattern[]) {
        for (var p in patterns) {
            if (p.qualifier is Value(qualifier)) {
                type_name(qualifier);
            }
        }
    }

    expression(e: Expression) {
        if (found.is_value() or !contains(e.extent(), offset)) {
            return;
        }
        match (e) {
            TypeLiteral(t) => {
                type_name(t);
            }
            SizeOf(t) => {
                type_name(t);
            }
            Cast(_, t, _, _, _) => {
                type_name(t);
            }
            Closure(c) => {
                for (var p in c.parameters) {
                    variable(p);
                }
                type_name(c.return_type);
                block(c.body);
            }
            Match(m) => {
                for (var arm in m.arms) {
                    _patterns(arm.patterns);
                }
            }
            Is(_, pattern, _, _) => {
                _patterns([pattern]);
            }
            else => {}
        }
        for (var child in children(e)) {
            expression(child);
        }
    }
}
