## The scope walk that linking shares with the checks that follow it: one
## traversal of a file's syntax tree that tracks the names bound locally at
## each point (parameters, locals, generic parameters, and the members of
## the struct being defined or extended), which hide top-level names.
##
## A pass implements the hooks of `ScopeWalk`: what a reference or a type
## name means to it, and which struct members and `extend` parameters are
## in scope. An enum's payload cannot change, so the walk returns each
## expression and statement it visits, rebuilt where a hook changed it.
##
## What platform selection drops is never compiled, so the walk skips it: a
## function or block whose `[Target(...)]` is false. Constructors and
## destructors are always walked, since platform selection never drops
## them.

import compiler.ast;
import [
    Attribute,
    Block,
    Declaration,
    DestructureBinding,
    Expression,
    FunctionDecl,
    GenericParam,
    MapEntry,
    Pattern,
    PropertyDecl,
    Span,
    Statement,
    TypeName,
    VariableDecl
] from compiler.ast;

## The built-in constraint `Shared`, which names no declaration.
export const SHARED_CONSTRAINT = "Shared";

## The name a property's accessors call its storage.
export const PROPERTY_FIELD = "field";

## The name a property's setter calls the value it is given.
export const PROPERTY_VALUE = "value";

## What one level of local names is.
export enum ScopeKind {
    ## Parameters and locals: they hide top-level names used as values.
    Values,
    ## Generic parameters: they hide top-level names as values and as
    ## types.
    Generics,
    ## The members of a struct visible in this file, looked up through the
    ## walker's `is_member` rather than copied.
    Members,
    ## A trait whose default method bodies are being walked. It binds no
    ## names.
    Trait,
    ## A `static` block: binds `reflect`, the compile-time API, like a
    ## local.
    Static,
}

## One level of names bound inside a declaration.
export struct Scope {
    ## What the level is.
    var kind: ScopeKind;
    ## The names bound in it.
    var names: HashSet<String> = HashSet<String>();
    ## The struct or trait, for `Members` and `Trait`.
    var owner: String = "";
    ## The values bound in it that the walker marked (see
    ## `ScopeWalk.visit_binding`).
    var marked: HashSet<String> = HashSet<String>();

    ## Creates a level.
    ##
    ## @param kind what it is
    ## @param owner the struct or trait, for `Members` and `Trait`
    construct(kind: ScopeKind, owner: String = "") {
        this.kind = kind;
        this.owner = owner;
    }
}

## The locally bound names at one point of the walk, innermost last.
export struct Scopes {
    ## The levels, outermost first.
    var levels: Scope[] = Array<Scope>();

    ## Creates an empty stack.
    construct() {}

    ## Returns whether `name` is bound locally where a type is expected (a
    ## type position, or a generic call such as `f<int>()`): only generic
    ## parameters.
    ##
    ## @param name the name
    ## @returns true when a generic parameter binds it
    is_type_local(name: String): bool {
        for (var level in levels) {
            if (level.kind == ScopeKind.Generics and level.names.contains(name)) {
                return true;
            }
        }
        return false;
    }

    ## Returns whether `name` is bound here as a parameter or local.
    ##
    ## @param name the name
    ## @returns true when bound
    is_value_bound(name: String): bool {
        for (var level in levels) {
            if ((level.kind == ScopeKind.Values or level.kind == ScopeKind.Static) and level.names.contains(name)) {
                return true;
            }
        }
        return false;
    }

    ## Returns whether the value `name` refers to here (its innermost
    ## binding) was marked when it was bound.
    ##
    ## @param name the name
    ## @returns true when marked
    is_marked_value(name: String): bool {
        long i = levels.count as long - 1;
        while (i >= 0) {
            var level = levels[i as ulong];
            if (level.kind == ScopeKind.Values and level.names.contains(name)) {
                return level.marked.contains(name);
            }
            i -= 1;
        }
        return false;
    }

    ## Returns whether the walk is inside a `static` block, where a
    ## compile-time value qualifies a type (`field.Type`) as a module does.
    ##
    ## @returns true inside a `static` block
    in_static_block(): bool {
        for (var level in levels) {
            if (level.kind == ScopeKind.Static) {
                return true;
            }
        }
        return false;
    }

    ## Returns the struct whose body or extension is being walked.
    ##
    ## @returns the struct's name, or none
    current_struct(): String? {
        return _innermost(ScopeKind.Members);
    }

    ## Returns the trait whose default method bodies are being walked.
    ##
    ## @returns the trait's name, or none
    current_trait(): String? {
        return _innermost(ScopeKind.Trait);
    }

    _innermost(kind: ScopeKind): String? {
        long i = levels.count as long - 1;
        while (i >= 0) {
            if (levels[i as ulong].kind == kind) {
                return Optional<String>.Value(levels[i as ulong].owner);
            }
            i -= 1;
        }
        return Optional<String>.Empty;
    }

    ## Enters a level.
    ##
    ## @param scope the level
    push(scope: Scope) {
        levels.append(scope);
    }

    ## Enters a level of `kind` binding `names`.
    ##
    ## @param kind what it is
    ## @param names the names it binds
    push_names(kind: ScopeKind, names: HashSet<String>) {
        var scope = Scope(kind);
        scope.names = names;
        levels.append(scope);
    }

    ## Leaves the innermost level.
    pop() {
        levels.pop();
    }

    ## Binds `name` in the innermost level, when it binds values or generic
    ## parameters.
    ##
    ## @param name the name
    bind(name: String) {
        if (levels.count == 0) {
            return;
        }
        var last = levels[levels.count - 1];
        if (last.kind == ScopeKind.Values or last.kind == ScopeKind.Generics) {
            last.names.insert(name);
        }
    }

    ## Binds the value `name` in the innermost level, marked or not.
    ##
    ## @param name the name
    ## @param marked whether the walker marked it
    bind_value(name: String, marked: bool) {
        bind(name);
        if (levels.count == 0) {
            return;
        }
        var last = levels[levels.count - 1];
        if (marked) {
            last.marked.insert(name);
        } else {
            last.marked.remove(name);
        }
    }
}

## A walk over one file's syntax tree that tracks its local names.
export trait ScopeWalk {
    ## Returns the names bound at this point of the walk.
    ##
    ## @returns the scopes
    scopes(): Scopes;

    ## Returns whether `name` is a member of `struct_name` visible to this
    ## file.
    ##
    ## @param struct_name the struct
    ## @param name the member
    ## @returns true when visible
    is_member(struct_name: String, name: String): bool;

    ## Returns the names `extend target` introduces as generic parameters:
    ## in `extend Box<T>`, a `T` that names no type.
    ##
    ## @param target_type the extension's target
    ## @returns the names
    extend_params(target_type: TypeName): HashSet<String>;

    ## Returns whether platform selection keeps what `attributes` mark.
    ##
    ## @param attributes the attributes
    ## @returns true when kept
    keeps(attributes: Attribute[]): bool;

    ## Visits a bare name used as a value.
    ##
    ## @param id the name
    ## @param span where it is written
    ## @returns the name it is to be spelled with
    visit_symbol(id: String, span: Span): String;

    ## Visits a type name, generic arguments included. The default walks
    ## only the arguments.
    ##
    ## @param type_name the type
    visit_type_name(type_name: TypeName) {
        walk_type_name(type_name);
    }

    ## Visits a function before its generic parameters are bound.
    ##
    ## @param function the function
    ## @returns true when they are types, not parameters (a concrete
    ##   override): then they bind no names
    visit_function_generics(function: FunctionDecl): bool {
        return false;
    }

    ## Visits a value as it is bound (a variable, parameter or loop
    ## variable) with its declared type and the expression it is
    ## initialized from, if any.
    ##
    ## @param type_name its declared type
    ## @param initializer what it is initialized from
    ## @returns true to mark it (see `Scopes.is_marked_value`)
    visit_binding(type_name: TypeName, initializer: Expression?): bool {
        return false;
    }

    ## Visits the callee of a call, before it is walked.
    ##
    ## @param function the callee
    visit_callee(function: Expression) {}

    ## Visits the name of a member access (`m` in `x.m`), after its
    ## receiver is walked.
    ##
    ## @param name the member's name
    ## @param name_span where the name is written
    visit_member(name: String, name_span: Span) {}

    ## Enters a declaration, a member, a property or an enum case, before it
    ## is walked. Each is paired with an `exit_declaration`.
    ##
    ## @param attributes its attributes
    enter_declaration(attributes: Attribute[]) {}

    ## Leaves the declaration the matching `enter_declaration` entered.
    exit_declaration() {}

    ## Visits an expression. The default walks it.
    ##
    ## @param e the expression
    ## @returns the expression to put in its place
    visit_expression(e: Expression): Expression {
        return walk_expression(e);
    }

    ## Visits a bare name in a pattern (`MAX`, or `limits.MAX`) that is not
    ## bound locally, which may name a module-scope constant.
    ##
    ## @param pattern the pattern
    visit_pattern_name(pattern: Pattern) {}

    ## Visits a case pattern's name read as a type, for a match on a trait
    ## value.
    ##
    ## @param pattern the pattern
    visit_case_type(pattern: Pattern) {}

    ## Returns whether `name` is bound locally where a value is expected: a
    ## parameter, local, generic parameter, or a member `is_member`
    ## accepts.
    ##
    ## @param name the name
    ## @returns true when bound
    is_local(name: String): bool {
        for (var level in scopes().levels) {
            match (level.kind) {
                Members => {
                    if (is_member(level.owner, name)) {
                        return true;
                    }
                }
                Trait => {}
                else => {
                    if (level.names.contains(name)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    ## Walks a type's generic arguments.
    ##
    ## @param type_name the type
    walk_type_name(type_name: TypeName) {
        for (var argument in type_name.generic_types) {
            visit_type_name(argument);
        }
    }

    ## Walks a declaration, binding a variable's name in the innermost
    ## scope.
    ##
    ## @param declaration the declaration
    walk_declaration(declaration: Declaration) {
        enter_declaration(declaration.attributes());
        match (declaration) {
            Variable(decl) => {
                visit_type_name(decl.type_name);
                if (decl.default_value.is_value()) {
                    decl.default_value = Optional<Expression>.Value(visit_expression(decl.default_value.value()));
                }
                scopes().bind_value(decl.name, visit_binding(decl.type_name, decl.default_value));
            }
            Function(decl) => {
                walk_function(decl);
            }
            Struct(decl) => {
                push_generics(decl.generic_params);
                scopes().push(Scope(ScopeKind.Members, decl.name));
                if (decl.enumeration.is_value()) {
                    var body = decl.enumeration.value();
                    if (body.representation.is_value()) {
                        visit_type_name(body.representation.value());
                    }
                    for (var c in body.cases) {
                        enter_declaration(c.attributes);
                        if (c.payload.is_value()) {
                            for (var p in c.payload.value()) {
                                visit_type_name(p.type_name);
                            }
                        }
                        if (c.value.is_value()) {
                            c.value = Optional<Expression>.Value(visit_expression(c.value.value()));
                        }
                        exit_declaration();
                    }
                }
                for (var field in decl.fields) {
                    enter_declaration(field.attributes);
                    visit_type_name(field.type_name);
                    if (field.default_value.is_value()) {
                        field.default_value = Optional<Expression>.Value(visit_expression(field.default_value.value()));
                    }
                    exit_declaration();
                }
                for (var property in decl.properties) {
                    walk_property(property);
                }
                # Platform selection never drops a constructor or
                # destructor, whatever its attributes.
                for (var c in decl.constructors) {
                    walk_function_body(c);
                }
                if (decl.destructor.is_value()) {
                    walk_block_body(decl.destructor.value());
                }
                for (var method in decl.methods) {
                    walk_function(method);
                }
                scopes().pop();
                scopes().pop();
            }
            Trait(decl) => {
                push_generics(decl.generic_params);
                scopes().push(Scope(ScopeKind.Trait, decl.name));
                # In a default method, the trait's methods are members of
                # `this`: a bare call binds to them.
                var methods = HashSet<String>();
                for (var method in decl.methods) {
                    if (keeps(method.attributes)) {
                        methods.insert(method.name);
                    }
                }
                scopes().push_names(ScopeKind.Values, methods);
                for (var property in decl.properties) {
                    walk_property(property);
                }
                for (var method in decl.methods) {
                    walk_function(method);
                }
                scopes().pop();
                scopes().pop();
                scopes().pop();
            }
            Extend(decl) => {
                # `extend Box<T>` introduces T; bind it before the target
                # and traits that mention it.
                scopes().push_names(ScopeKind.Generics, extend_params(decl.target));
                visit_type_name(decl.target);
                for (var bounds in decl.target_bounds) {
                    for (var bound in bounds) {
                        if (!(bound.name == SHARED_CONSTRAINT and bound.generic_types.count == 0)) {
                            visit_type_name(bound);
                        }
                    }
                }
                for (var t in decl.traits) {
                    visit_type_name(t);
                }
                scopes().push(Scope(ScopeKind.Members, decl.target.name));
                for (var property in decl.properties) {
                    walk_property(property);
                }
                for (var method in decl.methods) {
                    walk_function(method);
                }
                scopes().pop();
                scopes().pop();
            }
            TypeAlias(decl) => {
                push_generics(decl.generic_params);
                visit_type_name(decl.target);
                scopes().pop();
            }
            Static(block) => {
                walk_static_block(block.block);
            }
        }
        exit_declaration();
    }

    ## Walks a `static` block's body, where `reflect` is bound.
    ##
    ## @param block the body
    walk_static_block(block: Block) {
        var names = HashSet<String>();
        names.insert("reflect");
        scopes().push_names(ScopeKind.Static, names);
        walk_block(block);
        scopes().pop();
    }

    ## Walks a function, unless platform selection drops it.
    ##
    ## @param function the function
    walk_function(function: FunctionDecl) {
        if (keeps(function.attributes)) {
            walk_function_body(function);
        }
    }

    ## Walks a property: its type, its initializer and its accessors'
    ## bodies, where `field` and `value` are bound.
    ##
    ## @param property the property
    walk_property(property: PropertyDecl) {
        enter_declaration(property.attributes);
        visit_type_name(property.type_name);
        if (property.default_value.is_value()) {
            property.default_value = Optional<Expression>.Value(visit_expression(property.default_value.value()));
        }
        scopes().push(Scope(ScopeKind.Values));
        scopes().bind(PROPERTY_FIELD);
        scopes().bind(PROPERTY_VALUE);
        if (property.getter.is_value() and property.getter.value().function.body.is_value()) {
            walk_block(property.getter.value().function.body.value());
        }
        if (property.setter.is_value() and property.setter.value().function.body.is_value()) {
            walk_block(property.setter.value().function.body.value());
        }
        scopes().pop();
        exit_declaration();
    }

    ## Walks a function whatever its attributes: its generic parameters,
    ## signature and body.
    ##
    ## @param function the function
    walk_function_body(function: FunctionDecl) {
        enter_declaration(function.attributes);
        if (visit_function_generics(function)) {
            scopes().push(Scope(ScopeKind.Generics));
        } else {
            push_generics(function.generic_params);
        }
        visit_type_name(function.return_type);
        scopes().push(Scope(ScopeKind.Values));
        for (var parameter in function.parameters) {
            visit_type_name(parameter.type_name);
            if (parameter.default_value.is_value()) {
                parameter.default_value = Optional<Expression>.Value(visit_expression(parameter.default_value.value()));
            }
            scopes().bind_value(parameter.name, visit_binding(parameter.type_name, Optional<Expression>.Empty));
        }
        if (function.body.is_value()) {
            walk_block(function.body.value());
        }
        scopes().pop();
        scopes().pop();
        exit_declaration();
    }

    ## Binds a destructuring pattern's names, nested ones included, in the
    ## current scope (`_` binds nothing).
    ##
    ## @param bindings the pattern's bindings
    bind_pattern(bindings: DestructureBinding[]) {
        for (var binding in bindings) {
            if (binding.nested.count > 0) {
                bind_pattern(binding.nested);
                continue;
            }
            visit_type_name(binding.type_name);
            var marked = visit_binding(binding.type_name, Optional<Expression>.Empty);
            if (binding.name != "_") {
                scopes().bind_value(binding.name, marked);
            }
        }
    }

    ## Walks a block, unless platform selection drops it.
    ##
    ## @param block the block
    walk_block(block: Block) {
        if (keeps(block.attributes)) {
            walk_block_body(block);
        }
    }

    ## Walks a block's statements in a scope of their own.
    ##
    ## @param block the block
    walk_block_body(block: Block) {
        scopes().push(Scope(ScopeKind.Values));
        ulong i = 0;
        while (i < block.statements.count) {
            block.statements[i] = walk_statement(block.statements[i]);
            i += 1;
        }
        scopes().pop();
    }

    ## Walks a statement.
    ##
    ## @param statement the statement
    ## @returns the statement to put in its place
    walk_statement(statement: Statement): Statement {
        match (statement) {
            Expression(e) => {
                return Statement.Expression(visit_expression(e));
            }
            Block(block) => {
                walk_block(block);
            }
            Declaration(declaration) => {
                walk_declaration(declaration);
            }
            Branch(condition, if_block, else_block, span) => {
                var tested = visit_expression(condition);
                # `if (x is P(a))` binds `a` in its block only.
                scopes().push(Scope(ScopeKind.Values));
                bind_is_test(tested);
                walk_block(if_block);
                scopes().pop();
                if (else_block.is_value()) {
                    walk_block(else_block.value());
                }
                return Statement.Branch(tested, if_block, else_block, span);
            }
            While(condition, block, span) => {
                var tested = visit_expression(condition);
                scopes().push(Scope(ScopeKind.Values));
                bind_is_test(tested);
                walk_block(block);
                scopes().pop();
                return Statement.While(tested, block, span);
            }
            For(binding, pattern, iterable, block, span) => {
                # The iterable is evaluated outside the loop variable's
                # scope.
                var walked = visit_expression(iterable);
                scopes().push(Scope(ScopeKind.Values));
                if (pattern.count == 0) {
                    visit_type_name(binding.type_name);
                    scopes().bind_value(
                        binding.name, visit_binding(binding.type_name, Optional<Expression>.Value(walked))
                    );
                } else {
                    bind_pattern(pattern);
                }
                walk_block(block);
                scopes().pop();
                return Statement.For(binding, pattern, walked, block, span);
            }
            With(binding, scope, block, else_block, span) => {
                # The binding is visible in the body only, not in `else`.
                var walked = visit_expression(scope);
                scopes().push(Scope(ScopeKind.Values));
                if (binding.is_value()) {
                    visit_type_name(binding.value().type_name);
                    var marked = visit_binding(binding.value().type_name, Optional<Expression>.Value(walked));
                    scopes().bind_value(binding.value().name, marked);
                }
                walk_block(block);
                scopes().pop();
                if (else_block.is_value()) {
                    walk_block(else_block.value());
                }
                return Statement.With(binding, walked, block, else_block, span);
            }
            Return(value, span) => {
                if (value.is_value()) {
                    return Statement.Return(Optional<Expression>.Value(visit_expression(value.value())), span);
                }
            }
            LoopBreak(_, _) => {}
            Destructure(bindings, value, is_const, span) => {
                # The value is evaluated before the bindings exist; they
                # belong to the enclosing block.
                var walked = visit_expression(value);
                bind_pattern(bindings);
                return Statement.Destructure(bindings, walked, is_const, span);
            }
            Static(block) => {
                walk_static_block(block.block);
            }
            Match(m) => {
                m.value = visit_expression(m.value);
                for (var arm in m.arms) {
                    # A pattern's bindings are visible in its arm only.
                    scopes().push(Scope(ScopeKind.Values));
                    for (var p in arm.patterns) {
                        visit_pattern(p);
                    }
                    if (arm.guard.is_value()) {
                        arm.guard = Optional<Expression>.Value(visit_expression(arm.guard.value()));
                    }
                    walk_block(arm.body);
                    scopes().pop();
                }
                if (m.else_block.is_value()) {
                    walk_block(m.else_block.value());
                }
            }
        }
        return statement;
    }

    ## Walks an expression's parts.
    ##
    ## @param e the expression
    ## @returns the expression rebuilt from what its parts' visits returned
    walk_expression(e: Expression): Expression {
        match (e) {
            Literal(_, _) => {}
            SymbolRef(id, span) => {
                var renamed = visit_symbol(id, span);
                if (renamed != id) {
                    return Expression.SymbolRef(renamed, span);
                }
            }
            TypeLiteral(type_name) => {
                visit_type_name(type_name);
            }
            SizeOf(type_name) => {
                visit_type_name(type_name);
            }
            Unary(op, prefix, operand, span) => {
                return Expression.Unary(op, prefix, visit_expression(operand), span);
            }
            Cast(expr, type_name, span, keyword_span, optional) => {
                var walked = visit_expression(expr);
                visit_type_name(type_name);
                return Expression.Cast(walked, type_name, span, keyword_span, optional);
            }
            Binary(lhs, op, rhs, span) => {
                var left = visit_expression(lhs);
                return Expression.Binary(left, op, visit_expression(rhs), span);
            }
            Index(lhs, rhs, span) => {
                var left = visit_expression(lhs);
                return Expression.Index(left, visit_expression(rhs), span);
            }
            Ternary(condition, true_expr, false_expr, span) => {
                var tested = visit_expression(condition);
                var yes = visit_expression(true_expr);
                return Expression.Ternary(tested, yes, visit_expression(false_expr), span);
            }
            MemberAccess(lhs, name, name_span, span) => {
                var walked = visit_expression(lhs);
                visit_member(name, name_span);
                return Expression.MemberAccess(walked, name, name_span, span);
            }
            FunctionCall(function, arguments, span) => {
                visit_callee(function);
                var callee = visit_expression(function);
                return Expression.FunctionCall(callee, _visit_all(arguments), span);
            }
            Closure(closure) => {
                # A closure's parameters hide outer names in its body.
                scopes().push(Scope(ScopeKind.Values));
                for (var parameter in closure.parameters) {
                    visit_type_name(parameter.type_name);
                    scopes().bind_value(parameter.name, visit_binding(parameter.type_name, Optional<Expression>.Empty));
                }
                visit_type_name(closure.return_type);
                walk_block(closure.body);
                scopes().pop();
            }
            Tuple(elements, labels, span) => {
                return Expression.Tuple(_visit_all(elements), labels, span);
            }
            ArrayLiteral(elements, span) => {
                return Expression.ArrayLiteral(_visit_all(elements), span);
            }
            MapLiteral(entries, span) => {
                for (var entry in entries) {
                    entry.key = visit_expression(entry.key);
                    entry.value = visit_expression(entry.value);
                }
            }
            Match(m) => {
                m.value = visit_expression(m.value);
                for (var arm in m.arms) {
                    scopes().push(Scope(ScopeKind.Values));
                    for (var p in arm.patterns) {
                        visit_pattern(p);
                    }
                    if (arm.guard.is_value()) {
                        arm.guard = Optional<Expression>.Value(visit_expression(arm.guard.value()));
                    }
                    arm.value = visit_expression(arm.value);
                    scopes().pop();
                }
                if (m.else_value.is_value()) {
                    m.else_value = Optional<Expression>.Value(visit_expression(m.else_value.value()));
                }
            }
            NamedArgument(name, name_span, value, span) => {
                return Expression.NamedArgument(name, name_span, visit_expression(value), span);
            }
            Is(value, pattern, keyword_span, span) => {
                var walked = visit_expression(value);
                # Its bindings are bound by the `if` or `while` it is the
                # condition of (`bind_is_test`).
                visit_pattern_types(pattern);
                return Expression.Is(walked, pattern, keyword_span, span);
            }
        }
        return e;
    }

    _visit_all(expressions: Expression[]): Expression[] {
        var out = Array<Expression>();
        for (var e in expressions) {
            out.append(visit_expression(e));
        }
        return out;
    }

    ## Visits a pattern: its values and types, then binds its names in the
    ## innermost scope.
    ##
    ## @param pattern the pattern
    visit_pattern(pattern: Pattern) {
        visit_pattern_values(pattern);
        visit_pattern_types(pattern);
        for (var label in pattern.bound_names()) {
            scopes().bind(label.name);
        }
    }

    ## Visits the values in a pattern and its nested patterns: a range's
    ## bounds, and the names that may be constants.
    ##
    ## @param pattern the pattern
    visit_pattern_values(pattern: Pattern) {
        if (pattern.elements.is_value()) {
            for (var element in pattern.elements.value()) {
                visit_pattern_values(element);
            }
            return;
        }
        if (pattern.bindings.is_value()) {
            for (var sub in pattern.bindings.value()) {
                visit_pattern_values(sub);
            }
            return;
        }
        if (pattern.range_end.is_value()) {
            if (pattern.literal.is_value()) {
                pattern.literal = Optional<Expression>.Value(visit_expression(pattern.literal.value()));
            }
            pattern.range_end = Optional<Expression>.Value(visit_expression(pattern.range_end.value()));
            return;
        }
        bool single_qualifier = !pattern.qualifier.is_value() or !pattern.qualifier.value().name.contains(".");
        if (pattern.literal.is_empty()
            and single_qualifier
            and (pattern.qualifier.is_value() or !is_local(pattern.case_name))) {
            visit_pattern_name(pattern);
        }
    }

    ## Visits the enums named before cases in a pattern and its nested
    ## patterns.
    ##
    ## @param pattern the pattern
    visit_pattern_types(pattern: Pattern) {
        if (pattern.constant.is_value()) {
            return;
        }
        if (pattern.qualifier.is_value()) {
            visit_type_name(pattern.qualifier.value());
        }
        if (pattern.type_name.is_value()) {
            visit_case_type(pattern);
        }
        if (pattern.elements.is_value()) {
            for (var element in pattern.elements.value()) {
                visit_pattern_types(element);
            }
        }
        if (pattern.bindings.is_value()) {
            for (var sub in pattern.bindings.value()) {
                visit_pattern_types(sub);
            }
        }
    }

    ## Binds the names of `condition` when it is an `is` test.
    ##
    ## @param condition the condition
    bind_is_test(condition: Expression) {
        match (condition) {
            Is(_, pattern, _, _) => {
                for (var label in pattern.bound_names()) {
                    scopes().bind(label.name);
                }
            }
            else => {}
        }
    }

    ## Binds generic parameters, then walks their constraints and defaults,
    ## which may mention them (`R<T, E=T>`, `<T, I: Iterator<T>>`).
    ##
    ## @param params the parameters
    push_generics(params: GenericParam[]) {
        var names = HashSet<String>();
        for (var param in params) {
            names.insert(param.name);
        }
        scopes().push_names(ScopeKind.Generics, names);
        for (var param in params) {
            for (var bound in param.bounds) {
                if (!(bound.name == SHARED_CONSTRAINT and bound.generic_types.count == 0)) {
                    visit_type_name(bound);
                }
            }
            if (param.default.is_value()) {
                visit_type_name(param.default.value());
            }
        }
    }
}
