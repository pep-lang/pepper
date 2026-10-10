## Reading an attribute as written: its name and its arguments. Apart from
## `static_blocks`, which checks attributes against their `[Attribute]`
## structs, so that the passes reading an attribute need not import it.

import compiler.ast;

## An argument of an attribute call: its label and the label's span, if it
## has one, and its value.
export struct AttributeArgument {
    var name: (String, ast.Span)?;
    var value: ast.Expression;

    construct(name: (String, ast.Span)?, value: ast.Expression) {
        this.name = name;
        this.value = value;
    }
}

## Returns the attribute's arguments in the order written; none for a bare
## `[Name]`.
##
## @param attribute the attribute
## @returns the arguments
export attribute_arguments(attribute: ast.Attribute): AttributeArgument[] {
    var out = Array<AttributeArgument>();
    if (attribute.body is FunctionCall(_, arguments, _)) {
        for (var argument in arguments) {
            if (argument is NamedArgument(name, name_span, value, _)) {
                out.append(AttributeArgument(Optional<(String, ast.Span)>.Value((name, name_span)), value));
            } else {
                out.append(AttributeArgument(Optional<(String, ast.Span)>.Empty, argument));
            }
        }
    }
    return out;
}

_spelled(e: ast.Expression): String? {
    match (e) {
        SymbolRef(id, _) => {
            return Optional<String>.Value(id);
        }
        MemberAccess(lhs, name, _, _) => {
            var head = _spelled(lhs);
            if (!head.is_value()) {
                return head;
            }
            return Optional<String>.Value($"{head.value()}.{name}");
        }
        TypeLiteral(ty) => {
            return Optional<String>.Value(ty.name);
        }
        else => {
            return Optional<String>.Empty;
        }
    }
}

## Returns the name an attribute is written with: `Option` in
## `[Option("o")]`, and `json.Name` in `[json.Name("id")]`.
##
## @param attribute the attribute
## @returns the name, if it has one
export attribute_name(attribute: ast.Attribute): String? {
    if (attribute.body is FunctionCall(function, _, _)) {
        return _spelled(function);
    }
    return _spelled(attribute.body);
}
