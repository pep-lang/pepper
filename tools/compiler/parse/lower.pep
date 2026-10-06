## Builds the compiler's syntax tree (`compiler.ast`) from the lossless tree
## that `syntax.parse` reads, the way the Rust parser
## (`crates/pepper-parser`) builds its own: the same nodes, the same spans,
## and the same lowering of properties. Interpolated strings, `print` and
## `String.format` formats, module-scope `static` blocks and parentheses
## stay as the source writes them (`parse_written`), which also keeps
## every token and its comments; `parse` rewrites them as the Rust parser
## does with `compiler.desugar`, and keeps no tokens.

import compiler.ast;
import [
    Accessor,
    Attribute,
    Block,
    Declaration,
    DestructureBinding,
    EnumBody,
    EnumCase,
    ExportAlias,
    Expression,
    ExtendDecl,
    FormatSpec,
    FunctionDecl,
    GenericParam,
    Import,
    ImportedSymbol,
    Label,
    Literal,
    MapEntry,
    Match,
    MatchArm,
    MatchExpression,
    MatchValueArm,
    Pattern,
    PropertyDecl,
    Span,
    Statement,
    StaticBlock,
    StringPart,
    StructDecl,
    SyntaxWarning,
    TraitDecl,
    TypeAliasDecl,
    TypeName,
    VariableDecl
] from compiler.ast;
import compiler.desugar;
import syntax;
import [Node, NodeKind, Token, TokenKind] from syntax;
import [Utf8] from text;
import "checks" as checks;

## An error the parser reports: what is wrong and where.
export struct ParseError {
    ## The message, worded like clang's.
    var message: String;
    ## The byte range it is about.
    var span: Span;

    ## Creates an error.
    ##
    ## @param message what is wrong
    ## @param span where
    construct(message: String = "", span: Span = Span()) {
        this.message = message;
        this.span = span;
    }
}

## Parses Pepper source into the compiler's syntax tree, in the shape the
## Rust parser builds: interpolated strings and `print` and `String.format`
## formats lowered to calls, and each module-scope `static` block followed
## by the constants it declares (see `compiler.desugar`).
##
## @param source the text of one source file
## @returns the module, or the first syntax error
export parse(source: String): Result<ast.Module, ParseError> {
    return _parse(source, true);
}

## Parses Pepper source into the compiler's syntax tree as the source
## writes it: interpolated strings stay `Expression.Interpolated`, a
## `print` or `String.format` format stays the call's first argument as an
## `Expression.FormatString`, a module-scope `static` block declares
## nothing beside it, and parentheses stay `Expression.Parenthesized`. A
## format whose braces and arguments do not match is an error only when
## `compiler.desugar` rewrites it. The module keeps every token, with its
## comments and line breaks (`Module.tokens`), for tools that print the
## source back.
##
## @param source the text of one source file
## @returns the module, or the first syntax error
export parse_written(source: String): Result<ast.Module, ParseError> {
    return _parse(source, false);
}

# Parses `source`, desugared or as written.
_parse(source: String, desugared: bool): Result<ast.Module, ParseError> {
    var tree = syntax.parse(source);
    if (tree.is_err()) {
        var error = tree.error();
        return Result<ast.Module, ParseError>.err(ParseError(error.message, Span(error.offset, error.offset)));
    }
    var lowerer = Lowerer(source);
    # `parse` applies `compiler.desugar`'s rewrite to each interpolated
    # string, format and module-scope `static` block as it reads it, so
    # each error is found where it was before and no second walk is needed.
    lowerer.desugared = desugared;
    var module = lowerer.module(tree.value());
    if (lowerer.error.is_value()) {
        return Result<ast.Module, ParseError>.err(lowerer.error.value());
    }
    var broken = checks.check_module(module);
    if (broken.is_value()) {
        var offset = broken.value().offset;
        return Result<ast.Module, ParseError>.err(ParseError(broken.value().message, Span(offset, offset)));
    }
    return Result<ast.Module, ParseError>.ok(module);
}

# Lowers one source file's lossless tree into a `compiler.ast` module,
# recording the first error.
struct Lowerer {
    var source: String;
    # The text the tokens being lowered point into: `source`, or inside an
    # interpolated string's braces the expression's own text.
    var token_source: String;
    # Added to every token offset: the offset in the file of the text being
    # lowered, which is not 0 inside an interpolated string's braces.
    var base: ulong;
    # Every token's offset, in order: the token after a token is where a
    # declaration that the Rust parser ends after the whitespace following
    # it ends.
    var token_offsets: ulong[] = Array<ulong>();
    # Every token, as written (`parse_written`) only.
    var source_tokens: ast.SourceTokens?;
    var error: ParseError?;
    var build_option_tests: Attribute[] = Array<Attribute>();
    var warnings: SyntaxWarning[] = Array<SyntaxWarning>();
    var build_option_spans: HashSet<ulong> = HashSet<ulong>();
    # The names that qualify a type in an interpolated string's braces
    # (`geo.Box<int>()`): import qualifiers, and inside a `static` block the
    # names its `for`s and `var`s bind.
    var qualifiers: HashSet<String> = HashSet<String>();
    var static_depth: long;
    # Whether a struct's, enum's or extension's members are being lowered,
    # whose `Type name()` return types end at the type's name.
    var in_members: bool;
    # Whether interpolated strings, formats and module-scope `static`
    # blocks are desugared as they are read (`parse`), else kept as written
    # (`parse_written`).
    var desugared: bool;

    construct(source: String) {
        this.source = source;
        this.token_source = source;
    }

    # ── Errors and positions ────────────────────────────────────────────

    fail(message: String, span: Span) {
        if (!error.is_value()) {
            error = Optional<ParseError>.Value(ParseError(message, span));
        }
    }

    # The text of `token`, from the source its offset points into.
    token_text(token: Token): String {
        return token.text(token_source);
    }

    # Whether `token` is spelled `text`, compared in place.
    token_spells(token: Token, text: String): bool {
        return token.spells(token_source, text);
    }

    span_of(token: Token): Span {
        return Span(base + token.offset, base + token.offset + token.size);
    }

    start(node: Node): ulong {
        return base + node.first_token().offset;
    }

    end(node: Node): ulong {
        var last = node.last_token();
        return base + last.offset + last.size;
    }

    whole(node: Node): Span {
        return Span(start(node), end(node));
    }

    # The offset of the first token after `node`: the end of a span that
    # the Rust parser takes after skipping the whitespace that follows.
    after(node: Node): ulong {
        var last = node.last_token();
        var offset = base + last.offset;
        # A binary search for the token at `offset`.
        ulong low = 0;
        ulong high = token_offsets.count;
        while (low < high) {
            var middle = low + (high - low) / 2;
            if (token_offsets[middle] < offset) {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        if (low + 1 < token_offsets.count and token_offsets[low] == offset) {
            return token_offsets[low + 1];
        }
        return end(node);
    }

    # Records every token's offset; as written (`parse_written`), keeps the
    # tokens themselves too, for `Module.tokens`.
    record_tokens(root: Node) {
        token_offsets = Array<ulong>();
        if (desugared) {
            collect_token_offsets(root, token_offsets);
            return;
        }
        var tokens = Array<Token>();
        collect_tokens(root, token_offsets, tokens);
        source_tokens = Optional<ast.SourceTokens>.Value(ast.SourceTokens(source, tokens));
    }

    # ── Module ──────────────────────────────────────────────────────────

    module(root: Node): ast.Module {
        record_tokens(root);
        var out = ast.Module();
        for (var child in root.children) {
            if (error.is_value()) {
                break;
            }
            match (child.kind) {
                Import => {
                    var imported = import_declaration(child);
                    if (imported.symbols.is_empty() and !imported.reexport) {
                        if (imported.alias.is_value()) {
                            qualifiers.insert(imported.alias.value());
                        } else if (!imported.is_local) {
                            var segments = imported.name.split(".");
                            qualifiers.insert(segments[segments.count - 1]);
                        }
                    }
                    out.imports.append(imported);
                }
                ExportAlias => {
                    out.exports.append(export_alias(child));
                }
                Empty => {}
                Token => {}
                else => {
                    var declaration = declaration(child);
                    if (declaration.is_value()) {
                        out.declarations.append(declaration.value());
                        if (desugared) {
                            if (declaration.value() is Static(module_block)) {
                                desugar.static_constants(module_block, out.declarations);
                            }
                        }
                    }
                }
            }
        }
        out.build_option_tests = build_option_tests;
        out.warnings = warnings;
        out.tokens = source_tokens;
        return out;
    }

    # Splits a declaration's leading attributes and `export` from the rest.
    prefix(node: Node, attributes: Attribute[]): ulong {
        ulong index = 0;
        while (index < node.count and node.child(index).kind == NodeKind.Attribute) {
            attributes.append(attribute(node.child(index)));
            index += 1;
        }
        return index;
    }

    is_exported(node: Node, index: ulong): bool {
        return index < node.count and node.child(index).is_token(token_source, "export");
    }

    is_private(node: Node, index: ulong): bool {
        return index < node.count and node.child(index).is_token(token_source, "private");
    }

    declaration(node: Node): Declaration? {
        var attributes = Array<Attribute>();
        ulong index = prefix(node, attributes);
        bool exported = is_exported(node, index);
        bool file_private = is_private(node, index);
        ulong decl_start = start(node);
        in_members = false;
        if (exported or file_private) {
            index += 1;
        }
        Declaration? result;
        match (node.kind) {
            Function => {
                var function = function_declaration(node, index, attributes);
                function.is_exported = exported;
                function.is_private = file_private;
                result = Optional<Declaration>.Value(Declaration.Function(function));
            }
            ExternFunction => {
                var function = extern_function(node, index, attributes);
                function.is_exported = exported;
                function.is_private = file_private;
                result = Optional<Declaration>.Value(Declaration.Function(function));
            }
            Variable => {
                var variable = variable_declaration(node, index, attributes);
                variable.is_exported = exported;
                variable.is_private = file_private;
                result = Optional<Declaration>.Value(Declaration.Variable(variable));
            }
            Struct => {
                var declaration = struct_declaration(node, index, attributes);
                declaration.is_exported = exported;
                declaration.is_private = file_private;
                result = Optional<Declaration>.Value(Declaration.Struct(declaration));
            }
            Enum => {
                var declaration = enum_declaration(node, index, attributes);
                declaration.is_exported = exported;
                declaration.is_private = file_private;
                result = Optional<Declaration>.Value(Declaration.Struct(declaration));
            }
            Trait => {
                var declaration = trait_declaration(node, index, attributes);
                declaration.is_exported = exported;
                declaration.is_private = file_private;
                result = Optional<Declaration>.Value(Declaration.Trait(declaration));
            }
            Extend => {
                var declaration = extend_declaration(node, index, attributes);
                declaration.is_exported = exported;
                declaration.is_private = file_private;
                result = Optional<Declaration>.Value(Declaration.Extend(declaration));
            }
            TypeAlias => {
                var declaration = type_alias(node, index, attributes);
                declaration.is_exported = exported;
                declaration.is_private = file_private;
                result = Optional<Declaration>.Value(Declaration.TypeAlias(declaration));
            }
            Static => {
                var block = static_block(node, index);
                block.attributes = attributes;
                if (attributes.count > 0) {
                    block.span = Span(attributes[0].span.start, block.span.end);
                }
                block.is_exported = exported;
                block.is_private = file_private;
                result = Optional<Declaration>.Value(Declaration.Static(block));
            }
            else => {
                fail("expected declaration", whole(node));
                return Optional<Declaration>.Empty;
            }
        }
        if (exported or file_private) {
            widen_start(result.value(), decl_start);
        }
        return result;
    }

    # An exported or private declaration's span starts at its attributes or
    # its modifier.
    widen_start(declaration: Declaration, at: ulong) {
        match (declaration) {
            Variable(decl) => {
                decl.span = Span(decl.span.start.min(at), decl.span.end);
            }
            Function(decl) => {
                decl.span = Span(decl.span.start.min(at), decl.span.end);
            }
            Struct(decl) => {
                decl.span = Span(decl.span.start.min(at), decl.span.end);
            }
            Trait(decl) => {
                decl.span = Span(decl.span.start.min(at), decl.span.end);
            }
            Extend(decl) => {
                decl.span = Span(decl.span.start.min(at), decl.span.end);
            }
            TypeAlias(decl) => {
                decl.span = Span(decl.span.start.min(at), decl.span.end);
            }
            Static(block) => {
                block.span = Span(block.span.start.min(at), block.span.end);
            }
        }
    }

    # ── Imports and exports ─────────────────────────────────────────────

    import_declaration(node: Node): Import {
        var out = Import();
        var attributes = Array<Attribute>();
        ulong index = prefix(node, attributes);
        out.attributes = attributes;
        var keyword = node.child(index);
        out.reexport = keyword.is_token(token_source, "export");
        index += 1;
        out.span = Span(attributes.count > 0 ? attributes[0].span.start : start(keyword), 0);
        if (node.child(index).is_token(token_source, "*")) {
            index += 2;
        }
        if (node.child(index).kind == NodeKind.ImportList) {
            var symbols = Array<ImportedSymbol>();
            for (var item in node.child(index).children) {
                if (item.kind != NodeKind.ImportSymbol) {
                    continue;
                }
                var symbol = ImportedSymbol();
                var name = item.child(0).leaf;
                symbol.name = token_text(name);
                symbol.name_span = span_of(name);
                if (item.count > 2) {
                    var alias = item.child(2).leaf;
                    symbol.alias = Optional<String>.Value(token_text(alias));
                    symbol.span = Span(symbol.name_span.start, span_of(alias).end);
                } else {
                    symbol.span = Span(symbol.name_span.start, after(item));
                }
                symbols.append(symbol);
            }
            out.symbols = Optional<ImportedSymbol[]>.Value(symbols);
            index += 2;
        }
        var first = node.child(index).leaf;
        ulong name_start = span_of(first).start;
        ulong name_end = span_of(first).end;
        if (first.kind == TokenKind.String) {
            out.name = string_text(first);
            out.is_local = true;
            index += 1;
        } else {
            var name = StringBuilder();
            name.append(token_text(first));
            index += 1;
            while (index + 1 < node.count and node.child(index).is_token(token_source, ".")) {
                var segment = node.child(index + 1).leaf;
                name.append(".").append(token_text(segment));
                name_end = span_of(segment).end;
                index += 2;
            }
            out.name = name.to_string();
        }
        out.name_span = Span(name_start, name_end);
        ulong end = name_end;
        if (index + 1 < node.count and node.child(index).is_token(token_source, "as")) {
            var alias = node.child(index + 1).leaf;
            out.alias = Optional<String>.Value(token_text(alias));
            end = span_of(alias).end;
        }
        out.span = Span(out.span.start, end);
        return out;
    }

    export_alias(node: Node): ExportAlias {
        var out = ExportAlias();
        var attributes = Array<Attribute>();
        ulong index = prefix(node, attributes);
        out.attributes = attributes;
        var keyword = node.child(index);
        index += 1;
        var first = node.child(index).leaf;
        var symbol = StringBuilder();
        symbol.append(token_text(first));
        ulong symbol_end = span_of(first).end;
        index += 1;
        while (index + 1 < node.count and node.child(index).is_token(token_source, ".")) {
            var segment = node.child(index + 1).leaf;
            symbol.append(".").append(token_text(segment));
            symbol_end = span_of(segment).end;
            index += 2;
        }
        out.symbol = symbol.to_string();
        out.symbol_span = Span(span_of(first).start, symbol_end);
        ulong end = symbol_end;
        if (index + 1 < node.count and node.child(index).is_token(token_source, "as")) {
            var alias = node.child(index + 1).leaf;
            out.alias = Optional<String>.Value(token_text(alias));
            end = span_of(alias).end;
        }
        out.span = Span(attributes.count > 0 ? attributes[0].span.start : start(keyword), end);
        return out;
    }

    # ── Attributes ──────────────────────────────────────────────────────

    attribute(node: Node): Attribute {
        var body = expression(node.child(1));
        var out = Attribute(body, whole(node));
        if (contains_platform_predicate(body) and mentions_build_option(body)) {
            if (!build_option_spans.contains(out.span.start)) {
                build_option_spans.insert(out.span.start);
                build_option_tests.append(out);
            }
        }
        return out;
    }

    # ── Types ───────────────────────────────────────────────────────────

    type_name(node: Node): TypeName {
        var first = node.child(0);
        if (first.kind == NodeKind.Token and first.leaf.kind == TokenKind.Number) {
            return TypeName(token_text(first.leaf), span_of(first.leaf));
        }
        if (first.is_token(token_source, "(")
            or ((first.is_token(token_source, "shared") or first.is_token(token_source, "extern"))
                and node.count > 1
                and node.child(1).is_token(token_source, "("))) {
            return parenthesized_type(node);
        }
        # A name, qualified by `.name`s, then type arguments.
        var name = StringBuilder();
        name.append(token_text(first.leaf));
        ulong type_start = span_of(first.leaf).start;
        ulong end = span_of(first.leaf).end;
        ulong index = 1;
        while (index + 1 < node.count and node.child(index).is_token(token_source, ".")) {
            name.append(".").append(token_text(node.child(index + 1).leaf));
            end = span_of(node.child(index + 1).leaf).end;
            index += 2;
        }
        var out = TypeName(name.to_string(), Span(type_start, end));
        if (index < node.count and node.child(index).kind == NodeKind.TypeArguments) {
            var arguments = node.child(index);
            type_arguments(arguments, out.generic_types);
            end = end(arguments);
            out.span = Span(type_start, end);
            index += 1;
        }
        # `[]` suffixes extend the name; `?` wraps the type in Optional;
        # `*` suffixes extend the name of the outermost type.
        var array_suffix = StringBuilder();
        while (index + 1 < node.count
            and node.child(index).is_token(token_source, "[")
            and node.child(index + 1).is_token(token_source, "]")) {
            array_suffix.append("[]");
            end = end(node.child(index + 1));
            index += 2;
        }
        if (!array_suffix.is_empty) {
            out.name = out.name + array_suffix.to_string();
        }
        while (index < node.count and node.child(index).is_token(token_source, "?")) {
            ulong question_end = end(node.child(index));
            var wrapped = TypeName(ast.OPTIONAL_TYPE, Span(out.span.start, question_end));
            wrapped.generic_types.append(out);
            out = wrapped;
            end = end.max(question_end);
            index += 1;
        }
        while (index < node.count
            and (node.child(index).is_token(token_source, "*") or node.child(index).is_token(token_source, "**"))) {
            var stars = token_text(node.child(index).leaf);
            out.name = out.name + stars;
            end = end(node.child(index));
            index += 1;
        }
        out.span = Span(out.span.start, end);
        return out;
    }

    # A function type `[shared|extern] (P, ...) => R`, or a tuple type
    # `(A, B, ...)` with its `?` suffixes.
    parenthesized_type(node: Node): TypeName {
        ulong index = 0;
        var name = ast.FUNCTION_TYPE;
        if (node.child(0).is_token(token_source, "shared")) {
            name = ast.SHARED_FUNCTION_TYPE;
            index = 1;
        } else if (node.child(0).is_token(token_source, "extern")) {
            name = ast.EXTERN_FUNCTION_TYPE;
            index = 1;
        }
        ulong type_start = start(node);
        var elements = Array<TypeName>();
        var labels = Array<String>();
        bool any_label = false;
        index += 1;
        String label = "";
        while (index < node.count) {
            var child = node.child(index);
            if (child.is_token(token_source, ")")) {
                index += 1;
                break;
            }
            if (child.kind == NodeKind.Token
                and child.leaf.kind == TokenKind.Identifier
                and index + 1 < node.count
                and node.child(index + 1).is_token(token_source, ":")) {
                label = token_text(child.leaf);
                any_label = true;
                index += 2;
                continue;
            }
            if (child.kind == NodeKind.Type) {
                elements.append(type_name(child));
                labels.append(label);
                label = "";
            }
            index += 1;
        }
        if (index < node.count and node.child(index).is_token(token_source, "=>")) {
            var result = type_name(node.child(index + 1));
            var out = TypeName(name, Span(type_start, result.span.end));
            out.generic_types.append(result);
            for (var element in elements) {
                out.generic_types.append(element);
            }
            return out;
        }
        var out = TypeName(ast.TUPLE_TYPE, Span(type_start, 0));
        out.generic_types = elements;
        if (any_label) {
            out.labels = labels;
        }
        # The `)` closes the tuple; `?`s after it wrap it.
        ulong close_end = 0;
        ulong i = 0;
        while (i < node.count) {
            if (node.child(i).is_token(token_source, ")")) {
                close_end = end(node.child(i));
            }
            i += 1;
        }
        out.span = Span(type_start, close_end);
        while (index < node.count and node.child(index).is_token(token_source, "?")) {
            var wrapped = TypeName(ast.OPTIONAL_TYPE, Span(type_start, end(node.child(index))));
            wrapped.generic_types.append(out);
            out = wrapped;
            index += 1;
        }
        return out;
    }

    # The types in a `<...>`, without the constraints an `extend` target
    # restates after `:`.
    type_arguments(arguments: Node, out: TypeName[]) {
        bool in_bounds = false;
        for (var argument in arguments.children) {
            if (argument.is_token(token_source, ":")) {
                in_bounds = true;
            } else if (argument.is_token(token_source, ",")) {
                in_bounds = false;
            } else if (argument.kind == NodeKind.Type and !in_bounds) {
                out.append(type_name(argument));
            }
        }
    }

    # ── Expressions ─────────────────────────────────────────────────────

    expression(node: Node): Expression {
        match (node.kind) {
            Token => {
                return token_expression(node.leaf);
            }
            Parenthesized => {
                var value = expression(node.child(1));
                if (desugared) {
                    return value;
                }
                return Expression.Parenthesized(value, whole(node));
            }
            Binary => {
                return binary(node);
            }
            Ternary => {
                var condition = expression(node.child(0));
                var true_expr = expression(node.child(2));
                var false_expr = expression(node.child(4));
                return Expression.Ternary(
                    condition, true_expr, false_expr, Span(desugar.desugared_span(condition).start, end(node))
                );
            }
            Prefix => {
                return prefix_expression(node, false);
            }
            Postfix => {
                var operand = expression(node.child(0));
                var op = token_text(node.child(1).leaf);
                return Expression.Unary(op, false, operand, Span(desugar.desugared_span(operand).start, end(node)));
            }
            Cast => {
                var value = expression(node.child(0));
                var keyword = span_of(node.child(1).leaf);
                bool optional = node.count > 3 and node.child(2).is_token(token_source, "?");
                var type_node = node.child(node.count - 1);
                if (optional) {
                    keyword = Span(keyword.start, keyword.end + 1);
                }
                var cast_type = type_name(type_node);
                return Expression.Cast(
                    value, cast_type, Span(desugar.desugared_span(value).start, end(type_node)), keyword, optional
                );
            }
            Member => {
                return member(node);
            }
            Index => {
                var lhs = expression(node.child(0));
                var rhs = expression(node.child(2));
                return Expression.Index(lhs, rhs, Span(desugar.desugared_span(lhs).start, end(node)));
            }
            Call => {
                return call(node);
            }
            Sizeof => {
                return Expression.SizeOf(type_name(node.child(2)));
            }
            TypeLiteral => {
                return Expression.TypeLiteral(type_name(node.child(0)));
            }
            Closure => {
                return closure(node);
            }
            Tuple => {
                return tuple(node);
            }
            Array => {
                var elements = Array<Expression>();
                for (var child in node.children) {
                    if (child.kind != NodeKind.Token
                        or !(child.is_token(token_source, "[")
                            or child.is_token(token_source, "]")
                            or child.is_token(token_source, ","))) {
                        elements.append(expression(child));
                    }
                }
                return Expression.ArrayLiteral(elements, whole(node));
            }
            Map => {
                var entries = Array<MapEntry>();
                for (var child in node.children) {
                    if (child.kind == NodeKind.MapEntry) {
                        entries.append(MapEntry(expression(child.child(0)), expression(child.child(2))));
                    }
                }
                return Expression.MapLiteral(entries, whole(node));
            }
            Match => {
                return match_expression(node);
            }
            else => {}
        }
        fail("expected expression", whole(node));
        return Expression.Literal(Literal.Null, whole(node));
    }

    token_expression(token: Token): Expression {
        var span = span_of(token);
        match (token.kind) {
            Number => {
                return Expression.Literal(number(token_text(token), span, false), span);
            }
            String => {
                if (token_text(token).starts_with("$")) {
                    return interpolated_string(token);
                }
                return Expression.Literal(Literal.String(string_text(token)), span);
            }
            Character => {
                return Expression.Literal(character(token), span);
            }
            Identifier => {
                if (token_spells(token, "true")) {
                    return Expression.Literal(Literal.Bool(true), span);
                }
                if (token_spells(token, "false")) {
                    return Expression.Literal(Literal.Bool(false), span);
                }
                if (token_spells(token, "__null")) {
                    return Expression.Literal(Literal.Null, span);
                }
                return Expression.SymbolRef(token_text(token), span);
            }
            else => {}
        }
        fail($"unexpected '{token_text(token)}'", span);
        return Expression.Literal(Literal.Null, span);
    }

    # `-1` written as one literal: in a pattern, and after `**`.
    is_negative_literal(node: Node): bool {
        return node.kind == NodeKind.Prefix
            and node.count == 2
            and node.child(0).is_token(token_source, "-")
            and node.child(1).kind == NodeKind.Token
            and node.child(1).leaf.kind == TokenKind.Number
            and !node.child(1).leaf.space_before;
    }

    negative_literal(node: Node): Expression {
        var span = whole(node);
        return Expression.Literal(number("-" + token_text(node.child(1).leaf), span, true), span);
    }

    prefix_expression(node: Node, literal_allowed: bool): Expression {
        if (literal_allowed and is_negative_literal(node)) {
            return negative_literal(node);
        }
        var op = token_text(node.child(0).leaf);
        var operand = expression(node.child(1));
        return Expression.Unary(op, true, operand, Span(start(node), end(node)));
    }

    # An operand of `**`, where `-1` is one literal.
    power_operand(node: Node): Expression {
        if (is_negative_literal(node)) {
            return negative_literal(node);
        }
        if (node.kind == NodeKind.Binary and node.child(1).is_token(token_source, "**")) {
            return binary(node);
        }
        return expression(node);
    }

    binary(node: Node): Expression {
        var op_token = node.child(1).leaf;
        var op = token_text(op_token);
        if (op == "is") {
            var value = expression(node.child(0));
            var tested = pattern(node.child(2));
            return Expression.Is(
                value, tested, span_of(op_token), Span(desugar.desugared_span(value).start, tested.span.end)
            );
        }
        Expression lhs;
        Expression rhs;
        if (op == "**") {
            lhs = power_operand(node.child(0));
            rhs = power_operand(node.child(2));
        } else {
            lhs = expression(node.child(0));
            rhs = expression(node.child(2));
        }
        return Expression.Binary(lhs, op, rhs, Span(span_of(op_token).start, end(node)));
    }

    member(node: Node): Expression {
        var lhs = expression(node.child(0));
        var name_token = node.child(2).leaf;
        var name_span = span_of(name_token);
        var name = token_text(name_token);
        ulong member_end = name_span.end;
        if (node.count > 3 and node.child(3).kind == NodeKind.TypeArguments) {
            var arguments = node.child(3);
            var generic = TypeName(name, name_span);
            type_arguments(arguments, generic.generic_types);
            name = generic.to_string();
            member_end = end(arguments);
        }
        return Expression.MemberAccess(lhs, name, name_span, Span(desugar.desugared_span(lhs).start, member_end));
    }

    call(node: Node): Expression {
        var callee = node.child(0);
        var arguments = node.child(1);
        var function = expression(callee);
        var format = format_call(node);
        if (format.is_value()) {
            var span = Span(desugar.desugared_span(function).start, end(node));
            if (!desugared) {
                return Expression.FunctionCall(function, format.value(), span);
            }
            var lowered = desugar.desugar_format_call(function, format.value(), span);
            if (lowered.is_err()) {
                fail(lowered.error().message, lowered.error().span);
                return Expression.Literal(Literal.Null, span);
            }
            return lowered.value();
        }
        var values = Array<Expression>();
        for (var argument in arguments.children) {
            if (argument.kind == NodeKind.Token
                and (argument.is_token(token_source, "(")
                    or argument.is_token(token_source, ")")
                    or argument.is_token(token_source, ","))) {
                continue;
            }
            values.append(argument_expression(argument));
        }
        return Expression.FunctionCall(function, values, Span(desugar.desugared_span(function).start, end(node)));
    }

    # An argument, `name = value` being a named one.
    argument_expression(node: Node): Expression {
        if (node.kind == NodeKind.Binary and node.child(1).is_token(token_source, "=")) {
            var name = node.child(0);
            if (name.kind == NodeKind.Token and name.leaf.kind == TokenKind.Identifier) {
                var value = expression(node.child(2));
                var name_span = span_of(name.leaf);
                return Expression.NamedArgument(
                    token_text(name.leaf), name_span, value, Span(name_span.start, desugar.desugared_span(value).end)
                );
            }
        }
        return expression(node);
    }

    tuple(node: Node): Expression {
        var elements = Array<Expression>();
        var labels = Array<Label>();
        for (var child in node.children) {
            if (child.kind == NodeKind.TupleElement) {
                var label = child.child(0).leaf;
                labels.append(Label(token_text(label), span_of(label)));
                elements.append(expression(child.child(2)));
            } else if (child.kind != NodeKind.Token
                or !(child.is_token(token_source, "(")
                    or child.is_token(token_source, ")")
                    or child.is_token(token_source, ","))) {
                elements.append(expression(child));
            }
        }
        return Expression.Tuple(elements, labels, whole(node));
    }

    closure(node: Node): Expression {
        var out = ast.ClosureLiteral();
        var parameters = node.child(0);
        for (var parameter in parameters.children) {
            if (parameter.kind != NodeKind.ClosureParameter) {
                continue;
            }
            var name = parameter.child(0).leaf;
            var decl = VariableDecl(token_text(name));
            decl.name_span = span_of(name);
            if (parameter.count > 2) {
                decl.type_name = type_name(parameter.child(2));
            }
            decl.span = Span(decl.name_span.start, after(parameter));
            out.parameters.append(decl);
        }
        ulong index = 1;
        if (node.child(index).is_token(token_source, ":")) {
            out.return_type = type_name(node.child(index + 1));
            index += 2;
        }
        var body = node.child(index + 1);
        if (body.kind == NodeKind.Block) {
            out.body = block(body);
        } else {
            var value = expression(body);
            var span = desugar.desugared_span(value);
            var wrapper = Block(span);
            wrapper.statements.append(Statement.Return(Optional<Expression>.Value(value), span));
            out.body = wrapper;
            out.expression_body = true;
        }
        out.span = Span(start(node), end(node));
        return Expression.Closure(out);
    }

    match_expression(node: Node): Expression {
        var out = MatchExpression(expression(node.child(1)));
        out.keyword_span = span_of(node.child(0).leaf);
        out.span = Span(out.keyword_span.start, end(node));
        for (var arm in node.child(2).children) {
            if (arm.kind != NodeKind.MatchArm) {
                continue;
            }
            if (arm.child(0).is_token(token_source, "else")) {
                out.else_span = span_of(arm.child(0).leaf);
                out.else_value = Optional<Expression>.Value(expression(arm.child(2)));
                continue;
            }
            var value_arm = MatchValueArm();
            ulong index = 0;
            while (index < arm.count) {
                var child = arm.child(index);
                if (child.kind == NodeKind.Pattern) {
                    value_arm.patterns.append(pattern(child));
                } else if (child.is_token(token_source, "if")) {
                    value_arm.guard = Optional<Expression>.Value(expression(arm.child(index + 1)));
                    index += 1;
                } else if (child.is_token(token_source, "=>")) {
                    value_arm.value = expression(arm.child(index + 1));
                    break;
                }
                index += 1;
            }
            value_arm.span = Span(start(arm), desugar.desugared_span(value_arm.value).end);
            out.arms.append(value_arm);
        }
        return Expression.Match(out);
    }

    # ── Patterns ────────────────────────────────────────────────────────

    pattern(node: Node): Pattern {
        var out = Pattern();
        var first = node.child(0);
        if (first.is_token(token_source, "(")) {
            var elements = Array<Pattern>();
            for (var child in node.children) {
                if (child.kind == NodeKind.Pattern) {
                    elements.append(pattern(child));
                }
            }
            out.elements = Optional<Pattern[]>.Value(elements);
            out.span = whole(node);
            out.case_span = out.span;
            return out;
        }
        if (first.kind != NodeKind.Token
            or first.leaf.kind != TokenKind.Identifier
            or first.is_token(token_source, "true")
            or first.is_token(token_source, "false")) {
            # A literal, perhaps the start of a range.
            Expression literal;
            if (is_negative_literal(first)) {
                literal = negative_literal(first);
            } else {
                literal = expression(first);
            }
            out.literal = Optional<Expression>.Value(literal);
            var span = desugar.desugared_span(literal);
            if (node.count > 2) {
                var range_end = expression(node.child(2));
                out.range_end = Optional<Expression>.Value(range_end);
                out.range_inclusive = node.child(1).is_token(token_source, "..>");
                span = Span(span.start, desugar.desugared_span(range_end).end);
            }
            out.span = span;
            out.case_span = span;
            return out;
        }
        # A name, qualified by `.name`s.
        var segments = Array<Token>();
        segments.append(first.leaf);
        ulong index = 1;
        while (index + 1 < node.count and node.child(index).is_token(token_source, ".")) {
            segments.append(node.child(index + 1).leaf);
            index += 2;
        }
        ulong pattern_start = span_of(first.leaf).start;
        if (index < node.count
            and (node.child(index).is_token(token_source, "..") or node.child(index).is_token(token_source, "..>"))) {
            # A range from a named constant: `MIN..MAX`.
            Expression low = Expression.SymbolRef(token_text(first.leaf), span_of(first.leaf));
            ulong i = 1;
            while (i < segments.count) {
                var segment = segments[i];
                low = Expression.MemberAccess(
                    low, token_text(segment), span_of(segment), Span(pattern_start, span_of(segment).end)
                );
                i += 1;
            }
            out.literal = Optional<Expression>.Value(low);
            var range_end = expression(node.child(index + 1));
            out.range_end = Optional<Expression>.Value(range_end);
            out.range_inclusive = node.child(index).is_token(token_source, "..>");
            out.span = Span(pattern_start, end(node));
            out.case_span = out.span;
            return out;
        }
        var names = StringBuilder();
        ulong i = 0;
        while (i < segments.count) {
            if (i > 0) {
                names.append(".");
            }
            names.append(token_text(segments[i]));
            i += 1;
        }
        var names_end = span_of(segments.last()).end;
        var case_type = TypeName(names.to_string(), Span(pattern_start, names_end));
        if (index < node.count and node.child(index).kind == NodeKind.TypeArguments) {
            var arguments = node.child(index);
            type_arguments(arguments, case_type.generic_types);
            case_type.span = Span(pattern_start, end(arguments));
            index += 1;
        }
        var case_token = segments.last();
        out.case_name = token_text(case_token);
        out.case_span = span_of(case_token);
        if (segments.count > 1) {
            var qualifier = StringBuilder();
            ulong q = 0;
            while (q + 1 < segments.count) {
                if (q > 0) {
                    qualifier.append(".");
                }
                qualifier.append(token_text(segments[q]));
                q += 1;
            }
            out.qualifier = Optional<TypeName>.Value(
                TypeName(qualifier.to_string(), Span(pattern_start, span_of(segments[segments.count - 2]).end))
            );
        }
        if (index < node.count and node.child(index).is_token(token_source, "(")) {
            var bindings = Array<Pattern>();
            while (index < node.count) {
                var child = node.child(index);
                if (child.kind == NodeKind.Pattern) {
                    bindings.append(pattern(child));
                }
                index += 1;
            }
            out.bindings = Optional<Pattern[]>.Value(bindings);
        }
        out.type_name = Optional<TypeName>.Value(case_type);
        out.span = Span(pattern_start, end(node));
        return out;
    }

    # ── Statements ──────────────────────────────────────────────────────

    block(node: Node): Block {
        var attributes = Array<Attribute>();
        ulong index = prefix(node, attributes);
        var out = Block(whole(node));
        out.attributes = attributes;
        index += 1;
        while (index < node.count) {
            var child = node.child(index);
            index += 1;
            if (child.kind == NodeKind.Token or child.kind == NodeKind.Empty) {
                continue;
            }
            var statement = statement(child);
            if (statement.is_value()) {
                out.statements.append(statement.value());
            }
            if (error.is_value()) {
                break;
            }
        }
        return out;
    }

    statement(node: Node): Statement? {
        match (node.kind) {
            Block => {
                return Optional<Statement>.Value(Statement.Block(block(node)));
            }
            If => {
                return Optional<Statement>.Value(branch(node));
            }
            While => {
                var condition = expression(node.child(1));
                var body = block(node.child(2));
                return Optional<Statement>.Value(Statement.While(condition, body, Span(start(node), body.span.end)));
            }
            For => {
                return Optional<Statement>.Value(for_statement(node));
            }
            With => {
                return Optional<Statement>.Value(with_statement(node));
            }
            Static => {
                return Optional<Statement>.Value(Statement.Static(static_block(node, 0)));
            }
            Match => {
                return Optional<Statement>.Value(match_statement(node));
            }
            Return => {
                var keyword = span_of(node.child(0).leaf);
                if (node.count > 1 and node.child(1).kind != NodeKind.Token
                    or (node.count > 1 and !node.child(1).is_token(token_source, ";"))) {
                    var value = expression(node.child(1));
                    return Optional<Statement>.Value(
                        Statement.Return(
                            Optional<Expression>.Value(value), Span(keyword.start, desugar.desugared_span(value).end)
                        )
                    );
                }
                return Optional<Statement>.Value(Statement.Return(Optional<Expression>.Empty, keyword));
            }
            Jump => {
                var keyword = node.child(0).leaf;
                return Optional<Statement>.Value(
                    Statement.LoopBreak(token_spells(keyword, "continue"), span_of(keyword))
                );
            }
            Destructure => {
                bool is_const = node.child(0).is_token(token_source, "const");
                var bindings = destructure_bindings(node.child(1));
                var value = expression(node.child(3));
                return Optional<Statement>.Value(
                    Statement.Destructure(bindings, value, is_const, Span(start(node), end(node.child(3))))
                );
            }
            Variable => {
                var attributes = Array<Attribute>();
                ulong index = prefix(node, attributes);
                var variable = variable_declaration(node, index, attributes);
                if (static_depth > 0) {
                    qualifiers.insert(variable.name);
                }
                return Optional<Statement>.Value(Statement.Declaration(Declaration.Variable(variable)));
            }
            ExpressionStatement => {
                return Optional<Statement>.Value(Statement.Expression(expression(node.child(0))));
            }
            else => {}
        }
        fail("expected statement", whole(node));
        return Optional<Statement>.Empty;
    }

    branch(node: Node): Statement {
        var attributes = Array<Attribute>();
        ulong index = prefix(node, attributes);
        ulong keyword_start = start(node.child(index));
        var condition = expression(node.child(index + 1));
        var if_block = block(node.child(index + 2));
        Block? else_block;
        ulong end = if_block.span.end;
        if (index + 4 < node.count) {
            var other = node.child(index + 4);
            if (other.kind == NodeKind.If) {
                var inner = branch(other);
                if (inner is Branch(_, _, _, inner_span)) {
                    var wrapper = Block(inner_span);
                    wrapper.statements.append(inner);
                    else_block = Optional<Block>.Value(wrapper);
                    end = inner_span.end;
                }
            } else {
                var b = block(other);
                else_block = Optional<Block>.Value(b);
                end = b.span.end;
            }
        }
        ulong branch_start = keyword_start;
        if (attributes.count > 0) {
            branch_start = attributes[0].span.start;
            if_block.attributes = attributes;
        }
        return Statement.Branch(condition, if_block, else_block, Span(branch_start, end));
    }

    for_statement(node: Node): Statement {
        ulong index = 1;
        if (node.child(index).is_token(token_source, "(")) {
            index += 1;
        }
        var header = node.child(index);
        VariableDecl binding;
        var pattern = Array<DestructureBinding>();
        if (header.kind == NodeKind.Destructure) {
            pattern = destructure_bindings(header.child(1));
            binding = VariableDecl("");
            var span = whole(header);
            binding.name_span = span;
            binding.span = span;
        } else {
            binding = variable_declaration(header, 0, Array<Attribute>());
            if (static_depth > 0) {
                qualifiers.insert(binding.name);
            }
        }
        var iterable = expression(node.child(index + 2));
        var body = block(node.child(node.count - 1));
        return Statement.For(binding, pattern, iterable, body, Span(start(node), body.span.end));
    }

    with_statement(node: Node): Statement {
        ulong index = 1;
        if (node.child(index).is_token(token_source, "(")) {
            index += 1;
        }
        var header = node.child(index);
        VariableDecl? binding;
        Expression scope;
        if (header.kind == NodeKind.Variable) {
            var variable = variable_declaration(header, 0, Array<Attribute>());
            scope = variable.default_value.value();
            variable.default_value = Optional<Expression>.Empty;
            binding = Optional<VariableDecl>.Value(variable);
        } else {
            scope = expression(header);
        }
        Block? body;
        Block? else_block;
        ulong end = 0;
        index += 1;
        while (index < node.count) {
            var child = node.child(index);
            if (child.kind == NodeKind.Block) {
                var b = block(child);
                end = b.span.end;
                if (body.is_value()) {
                    else_block = Optional<Block>.Value(b);
                } else {
                    body = Optional<Block>.Value(b);
                }
            }
            index += 1;
        }
        return Statement.With(binding, scope, body.value(), else_block, Span(start(node), end));
    }

    match_statement(node: Node): Statement {
        var out = Match(expression(node.child(1)));
        out.keyword_span = span_of(node.child(0).leaf);
        out.span = Span(out.keyword_span.start, end(node));
        for (var arm in node.child(2).children) {
            if (arm.kind != NodeKind.MatchArm) {
                continue;
            }
            var attributes = Array<Attribute>();
            ulong index = prefix(arm, attributes);
            if (arm.child(index).is_token(token_source, "else")) {
                out.else_span = span_of(arm.child(index).leaf);
                var body = block(arm.child(arm.count - 1));
                body.attributes = attributes;
                out.else_block = Optional<Block>.Value(body);
                continue;
            }
            var match_arm = MatchArm();
            while (index < arm.count) {
                var child = arm.child(index);
                if (child.kind == NodeKind.Pattern) {
                    match_arm.patterns.append(pattern(child));
                } else if (child.is_token(token_source, "if")) {
                    match_arm.guard = Optional<Expression>.Value(expression(arm.child(index + 1)));
                    index += 1;
                } else if (child.kind == NodeKind.Block) {
                    match_arm.body = block(child);
                    match_arm.body.attributes = attributes;
                }
                index += 1;
            }
            match_arm.span = Span(start(arm), match_arm.body.span.end);
            out.arms.append(match_arm);
        }
        return Statement.Match(out);
    }

    static_block(node: Node, index: ulong): StaticBlock {
        var out = StaticBlock();
        var keyword = node.child(index);
        out.keyword_span = span_of(keyword.leaf);
        index += 1;
        if (node.child(index).kind == NodeKind.Arguments) {
            for (var capture in node.child(index).children) {
                if (capture.kind == NodeKind.Token and capture.leaf.kind == TokenKind.Identifier) {
                    out.captures.append(Label(token_text(capture.leaf), span_of(capture.leaf)));
                }
            }
            index += 1;
        }
        var outer = copy_names(qualifiers);
        static_depth += 1;
        out.block = block(node.child(index));
        static_depth -= 1;
        qualifiers = outer;
        out.span = Span(out.keyword_span.start, out.block.span.end);
        return out;
    }

    destructure_bindings(node: Node): DestructureBinding[] {
        var out = Array<DestructureBinding>();
        for (var child in node.children) {
            if (child.kind == NodeKind.ClosureParameters) {
                var nested = DestructureBinding();
                nested.name_span = whole(child);
                nested.nested = destructure_bindings(child);
                out.append(nested);
            } else if (child.kind == NodeKind.ClosureParameter) {
                var binding = DestructureBinding();
                binding.name = token_text(child.child(0).leaf);
                binding.name_span = span_of(child.child(0).leaf);
                if (child.count > 2) {
                    binding.type_name = type_name(child.child(2));
                }
                out.append(binding);
            }
        }
        return out;
    }

    # ── Declarations ────────────────────────────────────────────────────

    # A variable, field or local from its node: `var name`, `const name`
    # or `Type name`, then `[: Type] [= value]`. `index` is past its
    # attributes and `export`.
    variable_declaration(node: Node, index: ulong, attributes: Attribute[]): VariableDecl {
        var out = VariableDecl();
        out.attributes = attributes;
        ulong decl_start = attributes.count > 0 ? attributes[0].span.start : start(node.child(index));
        var first = node.child(index);
        ulong last_end = 0;
        if (first.is_token(token_source, "var") or first.is_token(token_source, "const")) {
            out.is_const = first.is_token(token_source, "const");
        } else {
            out.type_name = type_name(first);
        }
        var name = node.child(index + 1).leaf;
        out.name = token_text(name);
        out.name_span = span_of(name);
        last_end = out.name_span.end;
        index += 2;
        while (index < node.count) {
            var child = node.child(index);
            if (child.is_token(token_source, ":")) {
                var annotation = node.child(index + 1);
                out.type_name = type_name(annotation);
                last_end = end(annotation);
                index += 2;
                continue;
            }
            if (child.is_token(token_source, "=")) {
                var value = node.child(index + 1);
                out.default_value = Optional<Expression>.Value(expression(value));
                last_end = end(value);
                index += 2;
                continue;
            }
            index += 1;
        }
        out.span = Span(decl_start, last_end);
        return out;
    }

    type_alias(node: Node, index: ulong, attributes: Attribute[]): TypeAliasDecl {
        var out = TypeAliasDecl();
        out.attributes = attributes;
        ulong decl_start = attributes.count > 0 ? attributes[0].span.start : start(node.child(index));
        var name = node.child(index + 1).leaf;
        out.name = token_text(name);
        out.name_span = span_of(name);
        index += 2;
        if (node.child(index).kind == NodeKind.GenericParameters) {
            out.generic_params = generic_parameters(node.child(index));
            index += 1;
        }
        var target = node.child(index + 1);
        out.target = type_name(target);
        out.span = Span(decl_start, end(target));
        return out;
    }

    generic_parameters(node: Node): GenericParam[] {
        var out = Array<GenericParam>();
        for (var child in node.children) {
            if (child.kind != NodeKind.GenericParameter) {
                continue;
            }
            var name = child.child(0).leaf;
            var param = GenericParam(token_text(name), span_of(name));
            ulong index = 1;
            bool defaulted = false;
            while (index < child.count) {
                var item = child.child(index);
                if (item.is_token(token_source, "=")) {
                    defaulted = true;
                } else if (item.kind == NodeKind.Type) {
                    if (defaulted) {
                        param.default = Optional<TypeName>.Value(type_name(item));
                    } else {
                        param.bounds.append(type_name(item));
                    }
                }
                index += 1;
            }
            out.append(param);
        }
        return out;
    }

    # One parameter of a function, method or constructor.
    parameter(node: Node): VariableDecl {
        var attributes = Array<Attribute>();
        ulong index = prefix(node, attributes);
        VariableDecl out;
        var first = node.child(index);
        if (first.is_token(token_source, "this")) {
            var field = node.child(index + 2).leaf;
            out = VariableDecl("this." + token_text(field));
            out.name_span = span_of(field);
            out.default_value = Optional<Expression>.Value(expression(node.child(index + 4)));
            out.span = Span(start(first), after(node));
        } else if (first.is_token(token_source, "var") or first.is_token(token_source, "const")) {
            out = variable_declaration(node, index, Array<Attribute>());
        } else if (first.kind == NodeKind.Token
            and index + 1 < node.count
            and node.child(index + 1).is_token(token_source, ":")) {
            # `name: Type [= value]`
            out = VariableDecl(token_text(first.leaf));
            out.name_span = span_of(first.leaf);
            var type_node = node.child(index + 2);
            out.type_name = type_name(type_node);
            parameter_default(out, node, index + 3, type_node);
            out.span = Span(out.name_span.start, out.span.end);
        } else {
            # `Type name [= value]`
            var name = node.child(index + 1).leaf;
            out = VariableDecl(token_text(name));
            out.name_span = span_of(name);
            out.type_name = type_name(first);
            parameter_default(out, node, index + 2, node.child(index + 1));
            out.span = Span(start(first), out.span.end);
        }
        if (attributes.count > 0) {
            out.span = Span(attributes[0].span.start, out.span.end);
            out.attributes = attributes;
        }
        return out;
    }

    # A parameter's `= value`; its span ends at the value, else at the
    # token after `last`.
    parameter_default(out: VariableDecl, node: Node, index: ulong, last: Node) {
        if (index + 1 < node.count and node.child(index).is_token(token_source, "=")) {
            var value = node.child(index + 1);
            out.default_value = Optional<Expression>.Value(expression(value));
            out.span = Span(0, end(value));
            return;
        }
        out.span = Span(0, after(last));
    }

    parameters(node: Node): VariableDecl[] {
        var out = Array<VariableDecl>();
        for (var child in node.children) {
            if (child.kind == NodeKind.Parameter) {
                out.append(parameter(child));
            }
        }
        return out;
    }

    # A function, method or trait method. `index` is past its attributes
    # and `export`.
    function_declaration(node: Node, index: ulong, attributes: Attribute[]): FunctionDecl {
        var out = FunctionDecl();
        out.attributes = attributes;
        out.return_type = TypeName.auto();
        ulong decl_start = attributes.count > 0 ? attributes[0].span.start : start(node.child(index));
        if (node.child(index).is_token(token_source, "static")) {
            out.is_static = true;
            index += 1;
        }
        var first = node.child(index);
        if (first.is_token(token_source, "[")
            and index + 1 < node.count
            and node.child(index + 1).is_token(token_source, "]")) {
            # `[](params)`: an indexer.
            out.name = "[]";
            out.name_span = Span(start(first), end(node.child(index + 1)));
            out.is_indexer = true;
            index += 2;
        } else if (first.kind == NodeKind.Token and first.leaf.kind == TokenKind.Punctuation) {
            # `==(params)`: an operator.
            out.name = token_text(first.leaf);
            out.name_span = span_of(first.leaf);
            index += 1;
        } else if (first.kind == NodeKind.Type) {
            # `Type name(params)`, or the indexer `Type [](params)`.
            if (node.child(index + 1).is_token(token_source, "[")) {
                out.return_type = type_name(first);
                out.name_span = out.return_type.span;
                out.is_indexer = true;
                index += 3;
            } else {
                out.return_type = return_type_prefix(first);
                var name = node.child(index + 1).leaf;
                out.name = token_text(name);
                out.name_span = span_of(name);
                index += 2;
            }
        } else {
            var name = first.leaf;
            out.name = token_text(name);
            out.name_span = span_of(name);
            index += 1;
        }
        while (index < node.count) {
            var child = node.child(index);
            if (child.kind == NodeKind.GenericParameters) {
                out.generic_params = generic_parameters(child);
            } else if (child.kind == NodeKind.Parameters) {
                out.parameters = parameters(child);
            } else if (child.is_token(token_source, ":")) {
                out.return_type = type_name(node.child(index + 1));
                index += 1;
            } else if (child.kind == NodeKind.Block) {
                out.body = Optional<Block>.Value(block(child));
            }
            index += 1;
        }
        if (out.is_indexer) {
            out.name = indexer_name(out.parameters);
        }
        out.span = Span(decl_start, after(node));
        return out;
    }

    # The return type written before a function's name: its name alone,
    # `[]`s appended, its span running to the token after the name.
    return_type_prefix(node: Node): TypeName {
        var name = StringBuilder();
        ulong index = 0;
        name.append(token_text(node.child(0).leaf));
        index = 1;
        while (index + 1 < node.count and node.child(index).is_token(token_source, ".")) {
            name.append(".").append(token_text(node.child(index + 1).leaf));
            index += 2;
        }
        var last_name = node.child(index - 1);
        var suffix = StringBuilder();
        while (index + 1 < node.count and node.child(index).is_token(token_source, "[")) {
            suffix.append("[]");
            index += 2;
        }
        # A type with type arguments (a method's `Array<T> items()`).
        if (node.count > 1 and node.child(1).kind == NodeKind.TypeArguments) {
            return type_name(node);
        }
        ulong type_end = in_members ? end(last_name) : after(last_name);
        return TypeName(name.to_string() + suffix.to_string(), Span(start(node), type_end));
    }

    indexer_name(parameters: VariableDecl[]): String {
        int required = 0;
        for (var parameter in parameters) {
            if (!parameter.default_value.is_value()) {
                required += 1;
            }
        }
        return required >= 2 ? "__index_set" : "__index_get";
    }

    extern_function(node: Node, index: ulong, attributes: Attribute[]): FunctionDecl {
        var out = FunctionDecl();
        out.attributes = attributes;
        out.external = true;
        ulong decl_start = attributes.count > 0 ? attributes[0].span.start : start(node.child(index));
        out.return_type = type_name(node.child(index + 1));
        var name = node.child(index + 2).leaf;
        out.name = token_text(name);
        out.name_span = span_of(name);
        var parameters = node.child(index + 3);
        for (var parameter in parameters.children) {
            if (parameter.kind != NodeKind.Parameter) {
                continue;
            }
            if (parameter.child(0).is_token(token_source, "...")) {
                out.is_variadic = true;
                continue;
            }
            var parameter_name = parameter.child(1).leaf;
            var decl = VariableDecl(token_text(parameter_name));
            decl.name_span = span_of(parameter_name);
            decl.type_name = type_name(parameter.child(0));
            decl.span = Span(decl.type_name.span.start, after(parameter));
            out.parameters.append(decl);
        }
        out.span = Span(decl_start, end(parameters));
        return out;
    }

    constructor(node: Node): FunctionDecl {
        var out = FunctionDecl("construct");
        var attributes = Array<Attribute>();
        ulong index = prefix(node, attributes);
        out.attributes = attributes;
        out.return_type = TypeName.auto();
        var keyword = node.child(index);
        out.name_span = Span(start(keyword), after(keyword));
        if (token_spells(keyword.first_token(), "new")) {
            warnings.append(
                SyntaxWarning(
                    span_of(keyword.first_token()),
                    "`new`",
                    "constructors are spelled `construct`, matching `destruct`",
                    "construct"
                )
            );
        }
        out.parameters = parameters(node.child(index + 1));
        out.body = Optional<Block>.Value(block(node.child(index + 2)));
        out.span = Span(attributes.count > 0 ? attributes[0].span.start : start(keyword), after(node));
        return out;
    }

    property(node: Node): PropertyDecl {
        var out = PropertyDecl();
        var attributes = Array<Attribute>();
        ulong index = prefix(node, attributes);
        out.attributes = attributes;
        ulong decl_start = attributes.count > 0 ? attributes[0].span.start : start(node.child(index));
        var name = node.child(index + 1).leaf;
        out.name = token_text(name);
        out.name_span = span_of(name);
        index += 2;
        Node? accessors;
        ulong end = 0;
        while (index < node.count) {
            var child = node.child(index);
            if (child.is_token(token_source, ":")) {
                out.type_name = type_name(node.child(index + 1));
                index += 1;
            } else if (child.kind == NodeKind.Accessors) {
                accessors = Optional<Node>.Value(child);
                end = end(child);
            } else if (child.is_token(token_source, "=")) {
                var value = node.child(index + 1);
                out.default_value = Optional<Expression>.Value(expression(value));
                end = end(value);
                index += 1;
            }
            index += 1;
        }
        for (var accessor in accessors.value().children) {
            if (accessor.kind != NodeKind.Accessor) {
                continue;
            }
            var keyword = accessor.child(0).leaf;
            var span = span_of(keyword);
            bool is_get = token_spells(keyword, "get");
            var function = FunctionDecl(is_get ? "__get_" + out.name : "__set_" + out.name);
            function.attributes = attributes;
            if (is_get) {
                function.name_span = out.name_span;
                function.return_type = out.type_name.copy();
            } else {
                function.name_span = span;
                var value = VariableDecl("value");
                value.name_span = span;
                value.type_name = out.type_name.copy();
                value.span = span;
                function.parameters.append(value);
                function.return_type = TypeName("void", span);
            }
            ulong function_end = span.end;
            if (accessor.child(1).kind == NodeKind.Block) {
                var body = block(accessor.child(1));
                function.body = Optional<Block>.Value(body);
                function_end = body.span.end;
            }
            function.span = Span(span.start, function_end);
            if (is_get) {
                out.getter = Optional<Accessor>.Value(Accessor(span, function));
            } else {
                out.setter = Optional<Accessor>.Value(Accessor(span, function));
            }
        }
        out.span = Span(decl_start, end);
        return out;
    }

    struct_declaration(node: Node, index: ulong, attributes: Attribute[]): StructDecl {
        var out = StructDecl();
        out.attributes = attributes;
        ulong decl_start = attributes.count > 0 ? attributes[0].span.start : start(node.child(index));
        var name = node.child(index + 1).leaf;
        out.name = token_text(name);
        out.name_span = span_of(name);
        index += 2;
        if (node.child(index).kind == NodeKind.GenericParameters) {
            out.generic_params = generic_parameters(node.child(index));
            index += 1;
        }
        in_members = true;
        var members = node.child(index);
        for (var member in members.children) {
            match (member.kind) {
                Function => {
                    var member_attributes = Array<Attribute>();
                    ulong at = prefix(member, member_attributes);
                    out.methods.append(function_declaration(member, at, member_attributes));
                }
                ExternFunction => {
                    var member_attributes = Array<Attribute>();
                    ulong at = prefix(member, member_attributes);
                    out.methods.append(extern_function(member, at, member_attributes));
                }
                Constructor => {
                    out.constructors.append(constructor(member));
                }
                Destructor => {
                    var member_attributes = Array<Attribute>();
                    ulong at = prefix(member, member_attributes);
                    out.destruct_span = Optional<Span>.Value(span_of(member.child(at).leaf));
                    var body = block(member.child(at + 1));
                    body.attributes = member_attributes;
                    if (member_attributes.count > 0) {
                        body.span = Span(member_attributes[0].span.start, body.span.end);
                    }
                    out.destructor = Optional<Block>.Value(body);
                }
                Variable => {
                    var member_attributes = Array<Attribute>();
                    ulong at = prefix(member, member_attributes);
                    out.fields.append(variable_declaration(member, at, member_attributes));
                }
                Property => {
                    out.properties.append(property(member));
                }
                else => {}
            }
        }
        out.span = Span(decl_start, end(node));
        return out;
    }

    enum_declaration(node: Node, index: ulong, attributes: Attribute[]): StructDecl {
        var out = StructDecl();
        var body = EnumBody();
        out.attributes = attributes;
        ulong decl_start = attributes.count > 0 ? attributes[0].span.start : start(node.child(index));
        var name = node.child(index + 1).leaf;
        out.name = token_text(name);
        out.name_span = span_of(name);
        index += 2;
        if (node.child(index).kind == NodeKind.GenericParameters) {
            out.generic_params = generic_parameters(node.child(index));
            index += 1;
        }
        if (node.child(index).is_token(token_source, ":")) {
            body.representation = Optional<TypeName>.Value(type_name(node.child(index + 1)));
            index += 2;
        }
        in_members = true;
        var members = node.child(index);
        for (var member in members.children) {
            match (member.kind) {
                EnumCase => {
                    body.cases.append(enum_case(member));
                }
                Function => {
                    var member_attributes = Array<Attribute>();
                    ulong at = prefix(member, member_attributes);
                    out.methods.append(function_declaration(member, at, member_attributes));
                }
                Property => {
                    out.properties.append(property(member));
                }
                else => {}
            }
        }
        out.enumeration = Optional<EnumBody>.Value(body);
        out.span = Span(decl_start, end(node));
        return out;
    }

    enum_case(node: Node): EnumCase {
        var out = EnumCase();
        var attributes = Array<Attribute>();
        ulong index = prefix(node, attributes);
        out.attributes = attributes;
        var name = node.child(index).leaf;
        out.name = token_text(name);
        out.name_span = span_of(name);
        Node last = node.child(index);
        index += 1;
        while (index < node.count) {
            var child = node.child(index);
            if (child.kind == NodeKind.Parameters) {
                out.payload = Optional<VariableDecl[]>.Value(parameters(child));
                last = child;
            } else if (child.is_token(token_source, "=")) {
                last = node.child(index + 1);
                out.value = Optional<Expression>.Value(expression(last));
                index += 1;
            }
            index += 1;
        }
        out.span = Span(attributes.count > 0 ? attributes[0].span.start : out.name_span.start, after(last));
        return out;
    }

    trait_declaration(node: Node, index: ulong, attributes: Attribute[]): TraitDecl {
        var out = TraitDecl();
        out.attributes = attributes;
        ulong decl_start = attributes.count > 0 ? attributes[0].span.start : start(node.child(index));
        var name = node.child(index + 1).leaf;
        out.name = token_text(name);
        out.name_span = span_of(name);
        index += 2;
        if (node.child(index).kind == NodeKind.GenericParameters) {
            out.generic_params = generic_parameters(node.child(index));
            index += 1;
        }
        for (var member in node.child(index).children) {
            if (member.kind == NodeKind.Function) {
                var member_attributes = Array<Attribute>();
                ulong at = prefix(member, member_attributes);
                out.methods.append(trait_method(member, at, member_attributes));
            } else if (member.kind == NodeKind.Property) {
                out.properties.append(property(member));
            }
        }
        out.span = Span(decl_start, end(node));
        return out;
    }

    # A trait's method: a `Type name` method's return type is its name
    # alone, spanning just that name.
    trait_method(node: Node, index: ulong, attributes: Attribute[]): FunctionDecl {
        var out = function_declaration(node, index, attributes);
        ulong at = index;
        if (node.child(at).is_token(token_source, "static")) {
            at += 1;
        }
        var first = node.child(at);
        if (first.kind == NodeKind.Type and !node.child(at + 1).is_token(token_source, "[")) {
            var return_type = TypeName(token_text(first.child(0).leaf), span_of(first.child(0).leaf));
            bool annotated = false;
            for (var child in node.children) {
                if (child.is_token(token_source, ":")) {
                    annotated = true;
                }
            }
            if (!annotated) {
                out.return_type = return_type;
            }
        }
        return out;
    }

    extend_declaration(node: Node, index: ulong, attributes: Attribute[]): ExtendDecl {
        var out = ExtendDecl();
        out.attributes = attributes;
        ulong decl_start = attributes.count > 0 ? attributes[0].span.start : start(node.child(index));
        var target = node.child(index + 1);
        out.target = type_name(target);
        out.target_bounds = target_bounds(target);
        index += 2;
        in_members = true;
        while (index < node.count) {
            var child = node.child(index);
            if (child.kind == NodeKind.Type) {
                out.traits.append(type_name(child));
            } else if (child.kind == NodeKind.Members) {
                for (var member in child.children) {
                    if (member.kind == NodeKind.Function) {
                        var member_attributes = Array<Attribute>();
                        ulong at = prefix(member, member_attributes);
                        out.methods.append(function_declaration(member, at, member_attributes));
                    } else if (member.kind == NodeKind.Property) {
                        out.properties.append(property(member));
                    }
                }
            }
            index += 1;
        }
        out.span = Span(decl_start, end(node));
        return out;
    }

    # The constraints an `extend` target restates on its type arguments
    # (`Box<T: Shape>`), one list per argument; none when none is.
    target_bounds(target: Node): TypeName[][] {
        var out = Array<TypeName[]>();
        bool restated = false;
        for (var child in target.children) {
            if (child.kind != NodeKind.TypeArguments) {
                continue;
            }
            TypeName[]? current;
            bool in_bounds = false;
            for (var item in child.children) {
                if (item.is_token(token_source, ":")) {
                    restated = true;
                    in_bounds = true;
                } else if (item.is_token(token_source, ",") or item.is_token(token_source, ">")) {
                    if (current.is_value()) {
                        out.append(current.value());
                    }
                    current = Optional<TypeName[]>.Empty;
                    in_bounds = false;
                } else if (item.kind == NodeKind.Type) {
                    if (in_bounds) {
                        current.value().append(type_name(item));
                    } else {
                        current = Optional<TypeName[]>.Value(Array<TypeName>());
                    }
                }
            }
        }
        if (!restated) {
            return Array<TypeName[]>();
        }
        return out;
    }

    # ── Literals ────────────────────────────────────────────────────────

    number(text: String, span: Span, negative_allowed: bool): Literal {
        bool negative = text.starts_with("-");
        var digits = negative ? text.substr_bytes(1, text.size - 1) : text;
        if (digits.starts_with("0x")) {
            var hex = digits.substr_bytes(2, digits.size - 2);
            var bits = ulong.parse(hex, 16);
            if (hex.is_empty or !bits.is_value()) {
                fail("integer literal is too large to be represented in a 64-bit integer", span);
                return Literal.Integer(0);
            }
            long value = unsafe_cast<long>(bits.value());
            return Literal.Integer(negative ? (0 as long).wrapping_sub(value) : value);
        }
        if (digits.contains(".") or digits.contains("e") or digits.contains("E")) {
            var value = double.parse(text);
            if (!value.is_value()) {
                fail($"invalid floating-point literal '{text}'", span);
                return Literal.Float(0.0);
            }
            return Literal.Float(value.value());
        }
        var value = long.parse(text);
        if (!value.is_value()) {
            fail("integer literal is too large to be represented in a 64-bit integer", span);
            return Literal.Integer(0);
        }
        return Literal.Integer(value.value());
    }

    character(token: Token): Literal {
        var text = token_text(token);
        var span = span_of(token);
        if (text.byte_at(1) == '\\') {
            var bytes = Array<u8>();
            if (text.byte_at(2) == 'x') {
                var value = ulong.parse(text.substr_bytes(3, 2), 16);
                return Literal.Char(value.is_value() ? value.value() as u8 : 0 as u8);
            }
            ulong offset = 1;
            escape(text, offset, span.start, bytes);
            return Literal.Char(bytes.count > 0 ? bytes[0] : 0 as u8);
        }
        return Literal.Char(text.byte_at(1) as u8);
    }

    # The text of a string literal token, escapes decoded.
    string_text(token: Token): String {
        var text = token_text(token);
        var bytes = Array<u8>();
        ulong offset = 1;
        while (offset + 1 < text.size) {
            var c = text.byte_at(offset);
            if (c == '\\') {
                offset = escape(text, offset, base + token.offset, bytes);
                continue;
            }
            bytes.append(c as u8);
            offset += 1;
        }
        return Utf8.decode_lossy(bytes);
    }

    # Decodes the escape sequence at `offset` of `text` (at its backslash)
    # into `bytes`, returning the offset after it. `at` is the file offset
    # of `text`, for errors.
    escape(text: String, offset: ulong, at: ulong, bytes: u8[]): ulong {
        var c = text.byte_at(offset + 1);
        if (c == 'n') {
            bytes.append('\n' as u8);
        } else if (c == 't') {
            bytes.append('\t' as u8);
        } else if (c == 'r') {
            bytes.append('\r' as u8);
        } else if (c == '0') {
            bytes.append(0 as u8);
        } else if (c == '\\' or c == '"' or c == '\'') {
            bytes.append(c as u8);
        } else if (c == 'x') {
            var value = ulong.parse(text.substr_bytes(offset + 2, 2), 16);
            if (!value.is_value() or value.value() >= 0x80) {
                fail(
                    "'\\x' escape must be ASCII (at most \\x7F); use '\\u{...}' for other characters",
                    Span(at + offset, at + offset + 4)
                );
                return offset + 4;
            }
            bytes.append(value.value() as u8);
            return offset + 4;
        } else if (c == 'u') {
            var close = offset + 3;
            while (close < text.size and text.byte_at(close) != '}') {
                close += 1;
            }
            var value = ulong.parse(text.substr_bytes(offset + 3, close - offset - 3), 16);
            if (!value.is_value()) {
                fail(
                    "'\\u{...}' escape needs 1 to 6 hexadecimal digits and a closing '}'", Span(at + offset, at + close)
                );
                return close + 1;
            }
            Utf8.append_code_point(bytes, value.value() as uint);
            return close + 1;
        } else {
            fail($"unknown escape sequence '\\{to_string(c)}'", Span(at + offset, at + offset + 2));
        }
        return offset + 2;
    }

    # ── Interpolated strings and formats ────────────────────────────────

    # `$"sum is {a + b}"`: its text and the values in braces, as written.
    interpolated_string(token: Token): Expression {
        var text = token_text(token);
        ulong literal_start = base + token.offset;
        var parts = Array<StringPart>();
        var bytes = Array<u8>();
        ulong offset = 2;
        ulong text_start = literal_start + offset;
        while (offset + 1 < text.size and error.is_empty()) {
            var c = text.byte_at(offset);
            if (c == '\\') {
                offset = escape(text, offset, literal_start, bytes);
                continue;
            }
            if (c == '{' and text.byte_at(offset + 1) == '{') {
                bytes.append('{' as u8);
                offset += 2;
                continue;
            }
            if (c == '}' and text.byte_at(offset + 1) == '}') {
                bytes.append('}' as u8);
                offset += 2;
                continue;
            }
            if (c == '{') {
                flush(parts, bytes, text_start, literal_start + offset);
                ulong close = interpolation_end(text, offset + 1);
                parts.append(hole(text, offset, close, literal_start));
                offset = close + 1;
                text_start = literal_start + offset;
                continue;
            }
            bytes.append(c as u8);
            offset += 1;
        }
        flush(parts, bytes, text_start, literal_start + offset);
        if (desugared) {
            return desugar.desugar_interpolated(parts, span_of(token));
        }
        return Expression.Interpolated(parts, span_of(token));
    }

    flush(parts: StringPart[], bytes: u8[], start: ulong, end: ulong) {
        if (bytes.count > 0) {
            parts.append(StringPart.Text(Utf8.decode_lossy(bytes), Span(start, end)));
            bytes.clear();
        }
    }

    # The value in braces from `open` (the `{`) to `close` (the `}`) of a
    # literal's `text`, which starts at file offset `at`, with its format
    # specification.
    hole(text: String, open: ulong, close: ulong, at: ulong): StringPart {
        var inner = text.substr_bytes(open + 1, close - open - 1);
        var braces = Span(at + open, at + close + 1);
        # The longest prefix ending at a top-level `:` (or the whole) that
        # is one expression: what follows its `:` is a format
        # specification.
        var cuts = top_level_colons(inner);
        cuts.append(inner.size);
        long choice = cuts.count as long - 1;
        while (choice >= 0) {
            var cut = cuts[choice as ulong];
            var expression_text = inner.substr_bytes(0, cut);
            var parsed = syntax.parse_expression(expression_text, name_list(qualifiers));
            if (parsed.is_ok()) {
                var outer_base = base;
                base = at + open + 1;
                var outer_source = token_source;
                token_source = expression_text;
                var saved = token_offsets;
                token_offsets = Array<ulong>();
                var value = expression(parsed.value());
                base = outer_base;
                token_source = outer_source;
                token_offsets = saved;
                if (cut == inner.size) {
                    return StringPart.Hole(value, braces, Optional<FormatSpec>.Empty);
                }
                var spec = format_spec(inner.substr_bytes(cut + 1, inner.size - cut - 1), at + open + 2 + cut);
                return StringPart.Hole(value, braces, Optional<FormatSpec>.Value(spec));
            }
            choice -= 1;
        }
        fail("expected an expression after '{' in interpolated string; write '{{' for a literal '{'", braces);
        return StringPart.Hole(Expression.Literal(Literal.Null, braces), braces, Optional<FormatSpec>.Empty);
    }

    # The offsets of the `:`s in `text` outside brackets and literals.
    top_level_colons(text: String): ulong[] {
        var out = Array<ulong>();
        long depth = 0;
        ulong i = 0;
        while (i < text.size) {
            var c = text.byte_at(i);
            if (c == '(' or c == '[' or c == '{') {
                depth += 1;
            } else if (c == ')' or c == ']' or c == '}') {
                depth -= 1;
            } else if (c == '"' or c == '\'') {
                i += 1;
                while (i < text.size and text.byte_at(i) != c) {
                    if (text.byte_at(i) == '\\') {
                        i += 1;
                    }
                    i += 1;
                }
            } else if (c == ':' and depth == 0) {
                out.append(i);
            }
            i += 1;
        }
        return out;
    }

    # The offset of the `}` that closes the braces opened just before
    # `from` (the Rust parser's `interpolation_end`).
    interpolation_end(text: String, from: ulong): ulong {
        long depth = 0;
        ulong i = from;
        while (i < text.size) {
            var c = text.byte_at(i);
            if (c == '{') {
                depth += 1;
            } else if (c == '}') {
                if (depth == 0) {
                    return i;
                }
                depth -= 1;
            } else if (c == '"' or c == '\'') {
                i += 1;
                while (i < text.size and text.byte_at(i) != c) {
                    if (text.byte_at(i) == '\\') {
                        i += 1;
                    }
                    i += 1;
                }
            } else if (c == '$' and i + 1 < text.size and text.byte_at(i + 1) == '"') {
                i += 2;
                while (i < text.size and text.byte_at(i) != '"') {
                    if (text.byte_at(i) == '\\') {
                        i += 2;
                    } else if (text.byte_at(i) == '{' and i + 1 < text.size and text.byte_at(i + 1) == '{') {
                        i += 2;
                    } else if (text.byte_at(i) == '{') {
                        i = interpolation_end(text, i + 1) + 1;
                    } else {
                        i += 1;
                    }
                }
            }
            i += 1;
        }
        return text.size - 1;
    }

    # A format specification's text, which starts at file offset `at`.
    format_spec(text: String, at: ulong): FormatSpec {
        var spec = FormatSpec();
        if (text.is_empty) {
            fail("expected a format specification after ':'", Span(at, at));
            return spec;
        }
        var chars = Array<String>();
        var offsets = Array<ulong>();
        ulong position = 0;
        for (var c in text) {
            chars.append(c);
            offsets.append(position);
            position += c.size;
        }
        ulong i = 0;
        if (chars.count > 1 and align_of(chars[1]) > 0) {
            spec.fill = chars[0];
            spec.align = align_of(chars[1]);
            spec.has_align = true;
            i = 2;
        } else if (align_of(chars[0]) > 0) {
            spec.align = align_of(chars[0]);
            spec.has_align = true;
            i = 1;
        }
        if (i < chars.count and chars[i] == "+") {
            spec.plus = Optional<Span>.Value(Span(at + offsets[i], at + offsets[i] + 1));
            i += 1;
        }
        if (i < chars.count and chars[i] == "0") {
            spec.zero = Optional<Span>.Value(Span(at + offsets[i], at + offsets[i] + 1));
            i += 1;
        }
        var width = StringBuilder();
        while (i < chars.count and is_digit(chars[i])) {
            width.append(chars[i]);
            i += 1;
        }
        if (!width.is_empty) {
            spec.width = long.parse(width.to_string()).value_or(0);
        }
        if (i < chars.count and chars[i] == ".") {
            spec.point = Optional<Span>.Value(Span(at + offsets[i], at + offsets[i] + 1));
            i += 1;
            var precision = StringBuilder();
            while (i < chars.count and is_digit(chars[i])) {
                precision.append(chars[i]);
                i += 1;
            }
            spec.precision = long.parse(precision.to_string()).value_or(0);
        }
        if (i < chars.count
            and (chars[i] == "d" or chars[i] == "x" or chars[i] == "X" or chars[i] == "b" or chars[i] == "o")) {
            spec.kind = chars[i];
            spec.kind_span = Span(at + offsets[i], at + offsets[i] + 1);
            i += 1;
        }
        if (i < chars.count) {
            fail(
                $"unexpected '{chars[i]}' in format specification; expected '[[fill]align][+][0][width][.precision][type]'",
                Span(at + offsets[i], at + offsets[i] + chars[i].size)
            );
        }
        return spec;
    }

    align_of(c: String): long {
        if (c == "<") {
            return 1;
        }
        if (c == "^") {
            return 2;
        }
        if (c == ">") {
            return 3;
        }
        return 0;
    }

    is_digit(c: String): bool {
        return c.size == 1 and c.byte_at(0) >= '0' and c.byte_at(0) <= '9';
    }

    # `print("{0}", x)` and `String.format("{0}", x)`: the arguments, the
    # format first as an `Expression.FormatString`, that `compiler.desugar`
    # lowers as the Rust parser lowers them; none for any other call.
    format_call(node: Node): Expression[]? {
        var callee = node.child(0);
        var arguments = node.child(1);
        if (arguments.count < 3) {
            return Optional<Expression[]>.Empty;
        }
        var first = arguments.child(1);
        bool literal = first.kind == NodeKind.Token
            and first.leaf.kind == TokenKind.String
            and !token_text(first.leaf).starts_with("$");
        if (callee.kind == NodeKind.Token and token_spells(callee.leaf, "print")) {
            if (!literal or !arguments.child(2).is_token(token_source, ",")) {
                return Optional<Expression[]>.Empty;
            }
            return Optional<Expression[]>.Value(format_arguments(arguments));
        }
        bool string_format = callee.kind == NodeKind.Member
            and callee.count == 3
            and callee.child(0).is_token(token_source, "String")
            and callee.child(2).is_token(token_source, "format");
        if (!string_format) {
            return Optional<Expression[]>.Empty;
        }
        if (!literal) {
            fail("the format of 'String.format' must be a string literal", whole(first));
            return Optional<Expression[]>.Empty;
        }
        return Optional<Expression[]>.Value(format_arguments(arguments));
    }

    # The format string, its text and the arguments it names in braces,
    # then the arguments after it.
    format_arguments(arguments: Node): Expression[] {
        var format = arguments.child(1).leaf;
        var text = token_text(format);
        ulong literal_start = base + format.offset;
        var parts = Array<StringPart>();
        var bytes = Array<u8>();
        ulong offset = 1;
        ulong text_start = literal_start + offset;
        while (offset + 1 < text.size and error.is_empty()) {
            var c = text.byte_at(offset);
            if (c == '\\') {
                offset = escape(text, offset, literal_start, bytes);
                continue;
            }
            if (c == '{' and text.byte_at(offset + 1) == '{') {
                bytes.append('{' as u8);
                offset += 2;
                continue;
            }
            if (c == '}' and text.byte_at(offset + 1) == '}') {
                bytes.append('}' as u8);
                offset += 2;
                continue;
            }
            if (c == '{') {
                flush(parts, bytes, text_start, literal_start + offset);
                ulong brace = offset;
                ulong digits = offset + 1;
                while (digits < text.size and text.byte_at(digits) >= '0' and text.byte_at(digits) <= '9') {
                    digits += 1;
                }
                var index = ulong.parse(text.substr_bytes(offset + 1, digits - offset - 1)).value_or(0);
                var index_span = Span(literal_start + offset + 1, literal_start + digits);
                ulong close = digits;
                FormatSpec? spec;
                if (text.byte_at(digits) == ':') {
                    close = digits + 1;
                    while (close < text.size and text.byte_at(close) != '}') {
                        close += 1;
                    }
                    spec = Optional<FormatSpec>.Value(
                        format_spec(text.substr_bytes(digits + 1, close - digits - 1), literal_start + digits + 1)
                    );
                }
                var braces = Span(literal_start + brace, literal_start + close + 1);
                parts.append(StringPart.Argument(index, index_span, braces, spec));
                offset = close + 1;
                text_start = literal_start + offset;
                continue;
            }
            bytes.append(c as u8);
            offset += 1;
        }
        flush(parts, bytes, text_start, literal_start + offset);
        var values = Array<Expression>();
        var value_spans = Array<Span>();
        ulong i = 2;
        while (i < arguments.count) {
            var child = arguments.child(i);
            if (child.kind != NodeKind.Token
                or !(child.is_token(token_source, ",") or child.is_token(token_source, ")"))) {
                values.append(expression(child));
                value_spans.append(whole(child));
            }
            i += 1;
        }
        var out = Array<Expression>();
        out.append(Expression.FormatString(parts, span_of(format), start(arguments), value_spans));
        for (var value in values) {
            out.append(value);
        }
        return out;
    }
}

copy_names(names: HashSet<String>): HashSet<String> {
    var out = HashSet<String>();
    for (var name in names) {
        out.insert(name);
    }
    return out;
}

name_list(names: HashSet<String>): String[] {
    var out = Array<String>();
    for (var name in names) {
        out.append(name);
    }
    return out;
}

collect_token_offsets(node: Node, out: ulong[]) {
    if (node.kind == NodeKind.Token) {
        out.append(node.leaf.offset);
        return;
    }
    for (var child in node.children) {
        collect_token_offsets(child, out);
    }
}

# Appends every token under `node` to `tokens`, and its offset to `offsets`.
collect_tokens(node: Node, offsets: ulong[], tokens: Token[]) {
    if (node.kind == NodeKind.Token) {
        offsets.append(node.leaf.offset);
        tokens.append(node.leaf);
        return;
    }
    for (var child in node.children) {
        collect_tokens(child, offsets, tokens);
    }
}

# Whether an attribute's body is a top-level `Target(...)` or
# `BuildOption(...)` call.
contains_platform_predicate(body: Expression): bool {
    if (body is Parenthesized(value, _)) {
        return contains_platform_predicate(value);
    }
    if (body is FunctionCall(function, _, _)) {
        if (function is SymbolRef(id, _)) {
            var lower = id.lower();
            return lower == "target" or lower == "buildoption";
        }
    }
    return false;
}

# Whether `e` calls `BuildOption(...)` anywhere, looking where it would
# once desugared: into the calls and operators that build an interpolated
# string or a format's text, which hold a format's arguments only when
# its braces name them once each, in order.
mentions_build_option(e: Expression): bool {
    match (e) {
        FunctionCall(function, arguments, _) => {
            if (function is SymbolRef(id, _)) {
                if (id.lower() == "buildoption") {
                    return true;
                }
            }
            if (arguments.count > 0) {
                if (arguments[0] is FormatString(parts, _, _, _)) {
                    if (!desugar.is_in_order(parts, arguments.count - 1)) {
                        return false;
                    }
                }
            }
            for (var argument in arguments) {
                if (mentions_build_option(argument)) {
                    return true;
                }
            }
            return false;
        }
        Interpolated(parts, _) => {
            for (var part in parts) {
                if (part is Hole(value, _, _)) {
                    if (mentions_build_option(value)) {
                        return true;
                    }
                }
            }
            return false;
        }
        Unary(_, _, operand, _) => {
            return mentions_build_option(operand);
        }
        Binary(lhs, _, rhs, _) => {
            return mentions_build_option(lhs) or mentions_build_option(rhs);
        }
        Parenthesized(value, _) => {
            return mentions_build_option(value);
        }
        else => {}
    }
    return false;
}
