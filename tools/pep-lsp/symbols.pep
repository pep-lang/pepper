# The document's outline (`textDocument/documentSymbol`) and how
# declarations are spelled in it.

import compiler.ast;
import [FunctionDecl, GenericParam, VariableDecl] from compiler.ast;
import lsp;

## The outline of `module`, the syntax tree of `document`: each top-level
## declaration, with a struct's or enum's cases, fields and methods inside
## it.
##
## @param document the document
## @param module its syntax tree
## @returns the symbols, in source order
export document_symbols(document: lsp.TextDocument, module: ast.Module): Array<lsp.DocumentSymbol> {
    var out = Array<lsp.DocumentSymbol>();
    for (var declaration in module.declarations) {
        match (declaration) {
            Function(f) => {
                out.append(_symbol(document, f.name, function_signature(f), lsp.SYMBOL_FUNCTION, f.span, f.name_span));
            }
            Struct(s) => {
                var symbol = _symbol(document, s.name, "struct", lsp.SYMBOL_STRUCT, s.span, s.name_span);
                if (s.enumeration is Value(body)) {
                    symbol.kind = lsp.SYMBOL_ENUM;
                    symbol.detail = Optional<String>.Value("enum");
                    for (var case in body.cases) {
                        symbol.children.append(
                            _symbol(
                                document,
                                case.name,
                                $"{s.name}.{case.name}",
                                lsp.SYMBOL_ENUM_MEMBER,
                                case.span,
                                case.name_span
                            )
                        );
                    }
                }
                for (var field in s.fields) {
                    symbol.children.append(
                        _symbol(
                            document,
                            field.name,
                            field.type_name.to_string(),
                            lsp.SYMBOL_FIELD,
                            field.span,
                            field.name_span
                        )
                    );
                }
                for (var method in s.methods) {
                    symbol.children.append(
                        _symbol(
                            document,
                            method.name,
                            function_signature(method),
                            lsp.SYMBOL_METHOD,
                            method.span,
                            method.name_span
                        )
                    );
                }
                out.append(symbol);
            }
            Variable(v) => {
                out.append(_symbol(document, v.name, variable_type(v), lsp.SYMBOL_VARIABLE, v.span, v.name_span));
            }
            Trait(t) => {
                out.append(_symbol(document, t.name, "trait", lsp.SYMBOL_INTERFACE, t.span, t.name_span));
            }
            Extend(e) => {
                out.append(
                    _symbol(document, e.target.to_string(), "extend", lsp.SYMBOL_NAMESPACE, e.span, e.target.span)
                );
            }
            TypeAlias(t) => {
                out.append(_symbol(document, t.name, "type", lsp.SYMBOL_STRUCT, t.span, t.name_span));
            }
            # Its constants are listed beside it, as variables.
            Static(_) => {}
        }
    }
    return out;
}

_symbol(
    document: lsp.TextDocument, name: String, detail: String, kind: int, span: ast.Span, name_span: ast.Span
): lsp.DocumentSymbol {
    var out = lsp.DocumentSymbol(
        name, kind, document.range_of(span.start, span.end), document.range_of(name_span.start, name_span.end)
    );
    out.detail = Optional<String>.Value(detail);
    return out;
}

## A function as declared: `name<T: Shape>(a: int, b: T): String`.
##
## @param f the function
## @returns its signature
export function_signature(f: FunctionDecl): String {
    var parameters = Array<String>();
    for (var p in f.parameters) {
        parameters.append($"{p.name}: {p.type_name.to_string()}");
    }
    var listed = ", ".join(parameters);
    return $"{f.name}{generics_string(f.generic_params)}({listed}): {f.return_type.to_string()}";
}

## Generic parameters as written, constraints and defaults included:
## `<T: Shape & Named = Square>`, or nothing without any.
##
## @param parameters the parameters
## @returns their spelling
export generics_string(parameters: GenericParam[]): String {
    if (parameters.count == 0) {
        return "";
    }
    var spelled = Array<String>();
    for (var p in parameters) {
        var out = p.name;
        if (p.bounds.count > 0) {
            var bounds = Array<String>();
            for (var bound in p.bounds) {
                bounds.append(bound.to_string());
            }
            out += ": " + " & ".join(bounds);
        }
        if (p.default is Value(fallback)) {
            out += (p.bounds.count == 0 ? "=" : " = ") + fallback.to_string();
        }
        spelled.append(out);
    }
    var listed = ", ".join(spelled);
    return $"<{listed}>";
}

## The type of a variable declaration as written; an inferred one
## (`var x = 1;`) is named from a literal initializer, or `unknown`.
##
## @param v the declaration
## @returns the type's spelling
export variable_type(v: VariableDecl): String {
    if (v.type_name.name != "__auto") {
        return v.type_name.to_string();
    }
    if (v.default_value.is_empty()) {
        return "unknown";
    }
    var value = v.default_value.value();
    if (value is Literal(literal, _)) {
        return _literal_type(literal);
    }
    return "unknown";
}

# The type a literal has where nothing else decides it.
_literal_type(literal: ast.Literal): String {
    match (literal) {
        String(_) => {
            return "String";
        }
        Integer(_) => {
            return "int";
        }
        Float(_) => {
            return "float";
        }
        Bool(_) => {
            return "bool";
        }
        Char(_) => {
            return "byte";
        }
        Null => {
            return "__null";
        }
    }
    return "unknown";
}
