## A syntax tree as source-like text, for `pep-build --emit-ast` (and
## `--emit-ast=text`). Every binary is in parentheses, a block's statements
## are indented one level from its braces, and a module's declarations come
## after its imports and exports, one per line.

import "ast";

## Returns `module` as source-like text, each import, export and
## declaration on its own line.
##
## @param module the syntax tree
## @returns the text
export module_text(module: Module): String {
    var out = StringBuilder();
    for (var imported in module.imports) {
        out.append(_import(imported) + ";\n");
    }
    for (var alias in module.exports) {
        out.append(_attributes(alias.attributes) + "export " + alias.symbol);
        if (alias.alias.is_value()) {
            out.append(" as " + alias.alias.value());
        }
        out.append(";\n");
    }
    for (var declaration in module.declarations) {
        out.append(_declaration(declaration) + "\n");
    }
    return out.to_string();
}

# `import [a as b] from x as y`, or `export * from "file"`.
_import(imported: Import): String {
    var out = StringBuilder();
    out.append(_attributes(imported.attributes));
    out.append(imported.reexport ? "export " : "import ");
    if (imported.symbols.is_value()) {
        var symbols = Array<String>();
        for (var symbol in imported.symbols.value()) {
            symbols.append(symbol.alias.is_value() ? $"{symbol.name} as {symbol.alias.value()}" : symbol.name);
        }
        out.append($"[{", ".join(symbols)}] from ");
    } else if (imported.reexport) {
        out.append("* from ");
    }
    out.append(imported.is_local ? $"\"{imported.name}\"" : imported.name);
    if (imported.alias.is_value()) {
        out.append(" as " + imported.alias.value());
    }
    return out.to_string();
}

# A declaration as a module or a statement writes it, with the `;` a
# variable or type alias ends with.
_declaration(declaration: Declaration): String {
    match (declaration) {
        Variable(decl) => {
            return _variable(decl) + ";";
        }
        Function(decl) => {
            return _function(decl);
        }
        Struct(decl) => {
            return _struct(decl);
        }
        Trait(decl) => {
            return _trait(decl);
        }
        Extend(decl) => {
            return _extend(decl);
        }
        TypeAlias(decl) => {
            return _type_alias(decl) + ";";
        }
        Static(block) => {
            return _static(block);
        }
    }
    return "";
}

# The attributes before a declaration, each followed by a space.
_attributes(attributes: Attribute[]): String {
    var out = StringBuilder();
    for (var attribute in attributes) {
        out.append(_attribute(attribute) + " ");
    }
    return out.to_string();
}

# `[Name(args)]`: a binary at the top, or as a call's one argument, bare,
# as written.
_attribute(attribute: Attribute): String {
    var body = attribute.body;
    match (body) {
        Binary(lhs, op, rhs, _) => {
            return $"[{expression_text(lhs)} {op} {expression_text(rhs)}]";
        }
        FunctionCall(function, arguments, _) => {
            if (arguments.count == 1 and function is SymbolRef(_, _)) {
                var argument = arguments[0];
                if (argument is Binary(lhs, op, rhs, _)) {
                    return $"[{expression_text(function)}({expression_text(lhs)} {op} {expression_text(rhs)})]";
                }
                return $"[{expression_text(function)}({expression_text(argument)})]";
            }
        }
        else => {}
    }
    return $"[{expression_text(body)}]";
}

# `{`, each statement on its own line indented by four spaces, `}`.
_block_body(block: Block): String {
    var out = StringBuilder();
    out.append("{");
    for (var statement in block.statements) {
        out.append("\n    " + statement_text(statement));
    }
    if (!block.statements.is_empty) {
        out.append("\n");
    }
    out.append("}");
    return out.to_string();
}

# A block with its attributes.
_block(block: Block): String {
    return _attributes(block.attributes) + _block_body(block);
}

# The modifiers `export` and `private`, as written before a declaration.
_visibility(exported: bool, hidden: bool): String {
    return (exported ? "export " : "") + (hidden ? "private " : "");
}

# `var name: Type = value`, without its `;`.
_variable(decl: VariableDecl): String {
    var out = _attributes(decl.attributes) + _visibility(decl.is_exported, decl.is_private);
    out = out + (decl.is_const ? "const " : "var ") + $"{decl.name}: {decl.type_name.to_string()}";
    if (decl.default_value.is_value()) {
        out = out + " = " + expression_text(decl.default_value.value());
    }
    return out;
}

# The parameters of a function, separated by commas.
_parameters(parameters: VariableDecl[]): String {
    var out = Array<String>();
    for (var parameter in parameters) {
        out.append(_variable(parameter));
    }
    return ", ".join(out);
}

# `T: A & B=Default`.
_generic_param(param: GenericParam): String {
    var out = param.name;
    if (!param.bounds.is_empty) {
        out = out + ": " + _types(param.bounds, " & ");
    }
    if (param.default.is_value()) {
        out = out + "=" + param.default.value().to_string();
    }
    return out;
}

# `<T, U: Bound>`, or nothing.
_generic_params(params: GenericParam[]): String {
    if (params.is_empty) {
        return "";
    }
    var out = Array<String>();
    for (var param in params) {
        out.append(_generic_param(param));
    }
    return $"<{", ".join(out)}>";
}

# Types joined by `separator`.
_types(types: TypeName[], separator: String): String {
    var out = Array<String>();
    for (var t in types) {
        out.append(t.to_string());
    }
    return separator.join(out);
}

_function(decl: FunctionDecl): String {
    var out = StringBuilder();
    out.append(_attributes(decl.attributes) + _visibility(decl.is_exported, decl.is_private));
    if (decl.external) {
        out.append($"extern {decl.return_type.to_string()} {decl.name}({_parameters(decl.parameters)}");
        if (decl.is_variadic) {
            out.append(", ...");
        }
        out.append(")");
        return out.to_string();
    }
    if (decl.is_static) {
        out.append("static ");
    }
    if (decl.is_indexer) {
        out.append($"{decl.return_type.to_string()} []");
    } else {
        out.append(decl.name + _generic_params(decl.generic_params));
    }
    out.append($"({_parameters(decl.parameters)})");
    if (!decl.is_indexer and decl.return_type.name != AUTO_TYPE) {
        out.append(": " + decl.return_type.to_string());
    }
    if (decl.body.is_value()) {
        out.append(" " + _block(decl.body.value()));
    } else if (!decl.is_indexer) {
        out.append(";");
    }
    return out.to_string();
}

_struct(decl: StructDecl): String {
    var out = StringBuilder();
    out.append(_attributes(decl.attributes) + _visibility(decl.is_exported, decl.is_private));
    out.append((decl.enumeration.is_value() ? "enum " : "struct ") + decl.name + _generic_params(decl.generic_params));
    if (decl.enumeration.is_value() and decl.enumeration.value().representation.is_value()) {
        out.append(": " + decl.enumeration.value().representation.value().to_string());
    }
    out.append(" {");
    bool members = false;
    if (decl.enumeration.is_value()) {
        for (var enum_case in decl.enumeration.value().cases) {
            members = true;
            out.append("\n    " + _attributes(enum_case.attributes) + enum_case.name);
            if (enum_case.payload.is_value()) {
                out.append($"({_parameters(enum_case.payload.value())})");
            }
            if (enum_case.value.is_value()) {
                out.append(" = " + expression_text(enum_case.value.value()));
            }
            out.append(",");
        }
    }
    for (var field in decl.fields) {
        members = true;
        out.append("\n    " + _variable(field));
    }
    for (var property in decl.properties) {
        members = true;
        out.append("\n    " + _property(property));
    }
    for (var constructor in decl.constructors) {
        members = true;
        out.append(
            "\n    " + _attributes(constructor.attributes) + $"construct({_parameters(constructor.parameters)})"
        );
        if (constructor.body.is_value()) {
            out.append(" " + _block(constructor.body.value()));
        }
    }
    if (decl.destructor.is_value()) {
        members = true;
        out.append(
            "\n    "
                + _attributes(decl.destructor.value().attributes)
                + "destruct "
                + _block_body(decl.destructor.value())
        );
    }
    for (var method in decl.methods) {
        members = true;
        out.append("\n    " + _function(method));
    }
    if (members) {
        out.append("\n");
    }
    out.append("}");
    return out.to_string();
}

_trait(decl: TraitDecl): String {
    var out = StringBuilder();
    out.append(_attributes(decl.attributes) + _visibility(decl.is_exported, decl.is_private));
    out.append("trait " + decl.name + _generic_params(decl.generic_params) + " {");
    out.append(_members(decl.properties, decl.methods));
    out.append("}");
    return out.to_string();
}

# Properties and methods, each on its own line, and a line break after
# them when there are any.
_members(properties: PropertyDecl[], methods: FunctionDecl[]): String {
    var out = StringBuilder();
    for (var property in properties) {
        out.append("\n    " + _property(property));
    }
    for (var method in methods) {
        out.append("\n    " + _function(method));
    }
    if (!methods.is_empty or !properties.is_empty) {
        out.append("\n");
    }
    return out.to_string();
}

# `var name: Type { get { ... } set; } = value;`.
_property(decl: PropertyDecl): String {
    var out = StringBuilder();
    out.append(
        _attributes(decl.attributes)
            + (decl.is_static ? "static " : "")
            + $"var {decl.name}: {decl.type_name.to_string()} {{"
    );
    if (decl.getter.is_value()) {
        out.append(_accessor("get", decl.getter.value()));
    }
    if (decl.setter.is_value()) {
        out.append(_accessor("set", decl.setter.value()));
    }
    out.append(" }");
    if (decl.default_value.is_value()) {
        out.append($" = {expression_text(decl.default_value.value())};");
    }
    return out.to_string();
}

# ` get { ... }`, or ` get;`.
_accessor(keyword: String, accessor: Accessor): String {
    var body = accessor.function.body;
    return body.is_value() ? $" {keyword} {_block(body.value())}" : $" {keyword};";
}

_extend(decl: ExtendDecl): String {
    var out = StringBuilder();
    out.append(_attributes(decl.attributes) + _visibility(decl.is_exported, decl.is_private));
    bool bounded = false;
    for (var bounds in decl.target_bounds) {
        bounded = bounded or !bounds.is_empty;
    }
    if (!bounded) {
        out.append("extend " + decl.target.to_string());
    } else {
        var arguments = Array<String>();
        var count = decl.target.generic_types.count;
        for (var i in 0..count) {
            var argument = decl.target.generic_types[i].to_string();
            if (i < decl.target_bounds.count and !decl.target_bounds[i].is_empty) {
                argument = argument + ": " + _types(decl.target_bounds[i], " & ");
            }
            arguments.append(argument);
        }
        out.append($"extend {decl.target.name}<{", ".join(arguments)}>");
    }
    if (!decl.traits.is_empty) {
        out.append(" with " + _types(decl.traits, ", "));
        if (decl.methods.is_empty and decl.properties.is_empty) {
            out.append(";");
            return out.to_string();
        }
    }
    out.append(" {" + _members(decl.properties, decl.methods) + "}");
    return out.to_string();
}

# `type Name<T> = Target`, without its `;`.
_type_alias(decl: TypeAliasDecl): String {
    return _attributes(decl.attributes)
        + _visibility(decl.is_exported, decl.is_private)
        + $"type {decl.name}{_generic_params(decl.generic_params)} = {decl.target.to_string()}";
}

# `static (a, b) { ... }`.
_static(block: StaticBlock): String {
    if (block.captures.is_empty) {
        return "static " + _block(block.block);
    }
    var names = Array<String>();
    for (var capture in block.captures) {
        names.append(capture.name);
    }
    return $"static ({", ".join(names)}) {_block(block.block)}";
}

# `name: Type`, or `(a, b)` for a nested destructure.
_binding(binding: DestructureBinding): String {
    if (!binding.nested.is_empty) {
        return $"({_bindings(binding.nested)})";
    }
    return binding.type_name.name == AUTO_TYPE ? binding.name : $"{binding.name}: {binding.type_name.to_string()}";
}

_bindings(bindings: DestructureBinding[]): String {
    var out = Array<String>();
    for (var binding in bindings) {
        out.append(_binding(binding));
    }
    return ", ".join(out);
}

# ` if guard`, with the space before it, or nothing.
_guard(guard: Expression?): String {
    return guard.is_value() ? " if " + expression_text(guard.value()) : "";
}

_patterns(patterns: Pattern[]): String {
    var out = Array<String>();
    for (var pattern in patterns) {
        out.append(pattern.to_string());
    }
    return ", ".join(out);
}

## Returns `statement` as source-like text, as `--emit-ast=text` prints it.
##
## @param statement the statement
## @returns the text
export statement_text(statement: Statement): String {
    match (statement) {
        Expression(expression) => {
            return expression_text(expression) + ";";
        }
        Block(block) => {
            return _block(block);
        }
        Declaration(declaration) => {
            return _declaration(declaration);
        }
        Branch(condition, if_block, else_block, _) => {
            var out = $"if {expression_text(condition)} {_block(if_block)}";
            if (else_block.is_value()) {
                out = out + " else " + _block(else_block.value());
            }
            return out;
        }
        While(condition, block, _) => {
            return $"while {expression_text(condition)} {_block(block)}";
        }
        For(binding, pattern, iterable, block, _) => {
            if (!pattern.is_empty) {
                return $"for (var ({_bindings(pattern)}) in {expression_text(iterable)}) {_block(block)}";
            }
            return $"for ({_variable(binding)} in {expression_text(iterable)}) {_block(block)}";
        }
        With(binding, scope, block, else_block, _) => {
            var out = binding.is_value() ?
                $"with ({_variable(binding.value())} = {expression_text(scope)}) {_block(block)}" :
                $"with ({expression_text(scope)}) {_block(block)}";
            if (else_block.is_value()) {
                out = out + " else " + _block(else_block.value());
            }
            return out;
        }
        Return(value, _) => {
            return value.is_value() ? $"return {expression_text(value.value())};" : "return;";
        }
        LoopBreak(is_continue, label, _, _) => {
            var word = is_continue ? "continue" : "break";
            return label.is_empty ? word + ";" : $"{word} {label};";
        }
        Labeled(label, _, loop, _) => {
            return $"{label}: {statement_text(loop)}";
        }
        Destructure(bindings, value, is_const, _) => {
            return $"{is_const ? "const" : "var"} ({_bindings(bindings)}) = {expression_text(value)};";
        }
        Match(written) => {
            var out = StringBuilder();
            out.append($"match ({expression_text(written.value)}) {{");
            for (var arm in written.arms) {
                out.append($" {_patterns(arm.patterns)}{_guard(arm.guard)} => {_block(arm.body)}");
            }
            if (written.else_block.is_value()) {
                out.append(" else => " + _block(written.else_block.value()));
            }
            out.append(" }");
            return out.to_string();
        }
        Static(block) => {
            return _static(block);
        }
    }
    return "";
}

## Returns `expression` as source-like text, every binary in parentheses,
## closures and `match` expressions in full (`Expression.to_string` prints
## those in short, for diagnostics).
##
## @param expression the expression
## @returns the text
export expression_text(expression: Expression): String {
    match (expression) {
        Unary(op, prefix, operand, _) => {
            return prefix ? op + expression_text(operand) : expression_text(operand) + op;
        }
        Binary(lhs, op, rhs, _) => {
            return $"({expression_text(lhs)} {op} {expression_text(rhs)})";
        }
        Cast(value, type_name, _, _, optional) => {
            return $"({expression_text(value)} as{optional ? "?" : ""} {type_name.to_string()})";
        }
        Ternary(condition, true_expr, false_expr, _) => {
            return $"({expression_text(condition)} ? {expression_text(true_expr)} : {expression_text(false_expr)})";
        }
        Index(lhs, rhs, _) => {
            return $"{expression_text(lhs)}[{expression_text(rhs)}]";
        }
        MemberAccess(lhs, name, _, _) => {
            return $"{expression_text(lhs)}.{name}";
        }
        FunctionCall(function, arguments, _) => {
            return $"{expression_text(function)}({_expressions(arguments)})";
        }
        NamedArgument(name, _, value, _) => {
            return $"{name} = {expression_text(value)}";
        }
        Closure(closure) => {
            var params = Array<String>();
            for (var p in closure.parameters) {
                params.append(p.type_name.name == AUTO_TYPE ? p.name : $"{p.name}: {p.type_name.to_string()}");
            }
            var out = $"({", ".join(params)})";
            if (closure.return_type.name != AUTO_TYPE) {
                out = out + ": " + closure.return_type.to_string();
            }
            if (closure.expression_body and closure.body.statements.count == 1) {
                var only = closure.body.statements[0];
                if (only is Return(value, _)) {
                    if (value.is_value()) {
                        return out + " => " + expression_text(value.value());
                    }
                }
            }
            return out + " => " + _block_body(closure.body);
        }
        Tuple(elements, labels, _) => {
            if (labels.count == 0) {
                return $"({_expressions(elements)})";
            }
            var parts = Array<String>();
            ulong i = 0;
            while (i < elements.count and i < labels.count) {
                parts.append($"{labels[i].name}: {expression_text(elements[i])}");
                i += 1;
            }
            return $"({", ".join(parts)})";
        }
        ArrayLiteral(elements, _) => {
            return $"[{_expressions(elements)}]";
        }
        MapLiteral(entries, _) => {
            if (entries.count == 0) {
                return "[:]";
            }
            var parts = Array<String>();
            for (var entry in entries) {
                parts.append($"{expression_text(entry.key)}: {expression_text(entry.value)}");
            }
            return $"[{", ".join(parts)}]";
        }
        Match(match_expression) => {
            var out = StringBuilder();
            out.append($"match ({expression_text(match_expression.value)}) {{");
            for (var arm in match_expression.arms) {
                out.append($" {_patterns(arm.patterns)}{_guard(arm.guard)} => {expression_text(arm.value)},");
            }
            if (match_expression.else_value.is_value()) {
                out.append($" else => {expression_text(match_expression.else_value.value())},");
            }
            out.append(" }");
            return out.to_string();
        }
        Is(value, pattern, _, _) => {
            return $"({expression_text(value)} is {pattern.to_string()})";
        }
        Parenthesized(value, _) => {
            return $"({expression_text(value)})";
        }
        else => {
            return expression.to_string();
        }
    }
    return "";
}

_expressions(expressions: Expression[]): String {
    var out = Array<String>();
    for (var e in expressions) {
        out.append(expression_text(e));
    }
    return ", ".join(out);
}
