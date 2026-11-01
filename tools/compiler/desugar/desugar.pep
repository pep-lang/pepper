## Rewrites a module as the source wrote it into the desugared shape the
## rest of the compiler reads:
##
## - an interpolated string (`Expression.Interpolated`) becomes the
##   concatenation of its text and the `_pep_interpolate` / `_pep_format*`
##   calls that convert each hole;
## - `print("{0}", x)` and `String.format("{0}", x)`, whose first argument
##   is an `Expression.FormatString`, become the formatted text (passed to
##   `print`), binding the arguments in a `match` when the braces do not
##   name each once, in order;
## - a module-scope `static` block is followed by the module-scope
##   constants its `const`s declare, and a `static` block keeps no
##   `written_captures`;
## - parentheses (`Expression.Parenthesized`) give way to the value
##   inside them.

import compiler.ast;
import [
    Attribute,
    Block,
    Declaration,
    Expression,
    FormatSpec,
    FunctionDecl,
    Label,
    Literal,
    MatchValueArm,
    MatchExpression,
    Pattern,
    PropertyDecl,
    Span,
    Statement,
    StaticBlock,
    StringPart,
    VariableDecl
] from compiler.ast;

# The runtime functions an interpolated string calls.
const INTERPOLATE_FUNCTION = "_pep_interpolate";
const FORMAT_FUNCTION = "_pep_format";
const FORMAT_INTEGER_FUNCTION = "_pep_format_integer";
const FORMAT_FLOAT_FUNCTION = "_pep_format_float";
# The names a format's arguments are bound to: `_pep_format_0`, ...
const FORMAT_ARGUMENT_PREFIX = "_pep_format_";

## A format whose braces and arguments do not match.
export struct DesugarError {
    ## The message, worded like clang's.
    var message: String;
    ## The byte range it is about.
    var span: Span;
    ## The call whose format it is about.
    var call: Span;
    ## How far the parser had read when it finished the call: its end, or
    ## in a property's accessors, which it reads after the property's
    ## initializer, just past the property's end. Of two errors, the one
    ## with the lower order, then the call that ends first, comes first.
    var order: ulong;

    ## Creates an error.
    ##
    ## @param message what is wrong
    ## @param span where
    ## @param call the call whose format it is about
    ## @param order how far the parser had read when it finished the call
    construct(message: String = "", span: Span = Span(), call: Span = Span(), order: ulong = 0) {
        this.message = message;
        this.span = span;
        this.call = call;
        this.order = order;
    }
}

## Rewrites `module` in place into the shape `parse.parse` returns.
##
## @param module a module as `parse.parse_written` returns it
## @returns the module, or the first format whose braces and arguments do
##   not match
export desugar(module: ast.Module): Result<ast.Module, DesugarError> {
    var desugarer = _Desugarer();
    desugarer.module(module);
    if (desugarer.error.is_value()) {
        return Result<ast.Module, DesugarError>.err(desugarer.error.value());
    }
    return Result<ast.Module, DesugarError>.ok(module);
}

## Returns the span `e` has once desugared, which the parser derives the
## spans around it from, as it derives them from the lowered node: an interpolated string of one hole and no text, and a
## `String.format` whose format is just `{0}`, become the call that
## converts the value, which spans the braces (or the specification's
## `.`, type, `+` or `0`). Parentheses give way to their value, and so
## take its span. Anything else keeps its span.
##
## @param e an expression as `parse.parse_written` returns it
## @returns the span of what `desugar` makes of it
export desugared_span(e: Expression): Span {
    match (e) {
        Interpolated(parts, span) => {
            if (parts.count == 1) {
                if (parts[0] is Hole(_, braces, spec)) {
                    return _interpolation_span(braces, spec);
                }
            }
            return span;
        }
        FunctionCall(function, arguments, span) => {
            if (!(function is MemberAccess(_, _, _, _)) or arguments.count != 2) {
                return span;
            }
            if (arguments[0] is FormatString(parts, _, _, _)) {
                if (parts.count == 1) {
                    if (parts[0] is Argument(index, _, braces, spec)) {
                        return index == 0 ? _interpolation_span(braces, spec) : span;
                    }
                }
            }
            return span;
        }
        Parenthesized(value, _) => {
            return desugared_span(value);
        }
        else => {}
    }
    return e.span();
}

## Returns whether a format's braces name each of its `count` arguments
## once, in order (`"{0} and {1}"`): desugared, the arguments then take the
## braces' places, where otherwise a `match` binds them first.
##
## @param parts the format's parts
## @param count the number of arguments after the format
## @returns true when the braces name the arguments once each, in order
export is_in_order(parts: StringPart[], count: ulong): bool {
    ulong next = 0;
    for (var part in parts) {
        if (part is Argument(index, _, _, _)) {
            if (index != next) {
                return false;
            }
            next += 1;
        }
    }
    return next == count;
}

## Appends to `out` the module-scope constants a module-scope `static`
## block declares: each `const` with a value, as a constant of the same
## name bound to it. The parser of `parse.parse` applies it to each such
## block, right after the block.
##
## @param block the block
## @param out the module's declarations so far
export static_constants(block: StaticBlock, out: Declaration[]) {
    for (var statement in block.block.statements) {
        if (statement is Declaration(local)) {
            if (local is Variable(decl)) {
                _static_constant(block, decl, out);
            }
        }
    }
}

# The module-scope constant a `const` of a module-scope `static` block
# declares, if it is one with a value.
_static_constant(block: StaticBlock, local: VariableDecl, out: Declaration[]) {
    if (!local.is_const or !local.default_value.is_value()) {
        return;
    }
    var constant = VariableDecl(local.name);
    constant.attributes = block.attributes;
    constant.name_span = local.name_span;
    constant.type_name = local.type_name.copy();
    constant.default_value = Optional<Expression>.Value(Expression.SymbolRef(local.name, local.name_span));
    constant.is_const = true;
    constant.span = local.span;
    constant.is_exported = block.is_exported;
    constant.is_private = block.is_private;
    out.append(Declaration.Variable(constant));
}

# The span of the call that converts a value in braces at `braces`: see
# `_interpolation_call`.
_interpolation_span(braces: Span, spec: FormatSpec?): Span {
    if (!spec.is_value()) {
        return braces;
    }
    var s = spec.value();
    if (s.point.is_value()) {
        return s.point.value();
    }
    if (!s.kind.is_empty) {
        return s.kind_span;
    }
    if (s.plus.is_value()) {
        return s.plus.value();
    }
    if (s.zero.is_value()) {
        return s.zero.value();
    }
    return braces;
}

# The walk. Each method returns the expression or statement it is given
# when nothing in it changed (`rewrites` did not move), else one rebuilt:
# an enum's payload cannot change in place. Structs and arrays change in
# place.
struct _Desugarer {
    var error: DesugarError?;
    # How many interpolated strings and formats were rewritten so far.
    var rewrites: ulong;
    # In a property's accessors, just past the property's end
    # (`DesugarError.order`).
    var deferred: ulong;

    construct() {}

    _fail(message: String, span: Span, call: Span) {
        var order = call.end.max(deferred);
        if (error.is_value()) {
            var first = error.value();
            if (first.order < order or (first.order == order and first.call.end <= call.end)) {
                return;
            }
        }
        error = Optional<DesugarError>.Value(DesugarError(message, span, call, order));
    }

    # ── Module and declarations ─────────────────────────────────────────

    module(tree: ast.Module) {
        imports(tree);
        declarations(tree);
        attributes(tree.build_option_tests);
    }

    imports(tree: ast.Module) {
        for (var item in tree.imports) {
            attributes(item.attributes);
        }
        for (var item in tree.exports) {
            attributes(item.attributes);
        }
    }

    # Rewrites the declarations, adding each module-scope `static` block's
    # constants after it.
    declarations(tree: ast.Module) {
        bool any_static = false;
        for (var d in tree.declarations) {
            declaration(d);
            if (d is Static(_)) {
                any_static = true;
            }
        }
        if (!any_static) {
            return;
        }
        var out = Array<Declaration>();
        for (var d in tree.declarations) {
            out.append(d);
            if (d is Static(block)) {
                static_constants(block, out);
            }
        }
        tree.declarations = out;
    }

    declaration(d: Declaration) {
        match (d) {
            Variable(decl) => {
                variable(decl);
            }
            Function(decl) => {
                function(decl);
            }
            Struct(decl) => {
                attributes(decl.attributes);
                for (var field in decl.fields) {
                    variable(field);
                }
                for (var member in decl.properties) {
                    property(member);
                }
                for (var method in decl.methods) {
                    function(method);
                }
                for (var constructor in decl.constructors) {
                    function(constructor);
                }
                if (decl.destructor.is_value()) {
                    block(decl.destructor.value());
                }
                if (decl.enumeration.is_value()) {
                    for (var item in decl.enumeration.value().cases) {
                        attributes(item.attributes);
                        item.value = optional(item.value);
                        if (item.payload.is_value()) {
                            for (var value in item.payload.value()) {
                                variable(value);
                            }
                        }
                    }
                }
            }
            Trait(decl) => {
                attributes(decl.attributes);
                for (var member in decl.properties) {
                    property(member);
                }
                for (var method in decl.methods) {
                    function(method);
                }
            }
            Extend(decl) => {
                attributes(decl.attributes);
                for (var member in decl.properties) {
                    property(member);
                }
                for (var method in decl.methods) {
                    function(method);
                }
            }
            TypeAlias(decl) => {
                attributes(decl.attributes);
            }
            Static(block) => {
                static_block(block);
            }
        }
    }

    variable(decl: VariableDecl) {
        attributes(decl.attributes);
        decl.default_value = optional(decl.default_value);
    }

    function(decl: FunctionDecl) {
        attributes(decl.attributes);
        for (var parameter in decl.parameters) {
            variable(parameter);
        }
        if (decl.body.is_value()) {
            block(decl.body.value());
        }
    }

    property(decl: PropertyDecl) {
        attributes(decl.attributes);
        var outer = deferred;
        if (decl.default_value.is_value()) {
            decl.default_value = optional(decl.default_value);
            deferred = deferred.max(decl.span.end + 1);
        }
        if (decl.getter.is_value()) {
            function(decl.getter.value().function);
        }
        if (decl.setter.is_value()) {
            function(decl.setter.value().function);
        }
        deferred = outer;
    }

    static_block(decl: StaticBlock) {
        # `parse` keeps the captures that are names alone.
        decl.written_captures = Array<Expression>();
        attributes(decl.attributes);
        block(decl.block);
    }

    # An attribute can be reached more than once (a property's accessors
    # share its attributes); rewriting one again changes nothing.
    attributes(list: Attribute[]) {
        for (var attribute in list) {
            var before = rewrites;
            var body = expression(attribute.body);
            if (rewrites != before) {
                attribute.body = body;
            }
        }
    }

    # ── Statements ──────────────────────────────────────────────────────

    block(decl: Block) {
        attributes(decl.attributes);
        ulong i = 0;
        while (i < decl.statements.count) {
            var before = rewrites;
            var rewritten = statement(decl.statements[i]);
            if (rewrites != before) {
                decl.statements[i] = rewritten;
            }
            i += 1;
        }
    }

    statement(s: Statement): Statement {
        var before = rewrites;
        match (s) {
            Expression(e) => {
                var value = expression(e);
                if (rewrites != before) {
                    return Statement.Expression(value);
                }
            }
            Block(inner) => {
                block(inner);
            }
            Declaration(d) => {
                declaration(d);
            }
            Branch(condition, if_block, else_block, span) => {
                var tested = expression(condition);
                block(if_block);
                if (else_block.is_value()) {
                    block(else_block.value());
                }
                if (rewrites != before) {
                    return Statement.Branch(tested, if_block, else_block, span);
                }
            }
            While(condition, body, span) => {
                var tested = expression(condition);
                block(body);
                if (rewrites != before) {
                    return Statement.While(tested, body, span);
                }
            }
            For(binding, pattern, iterable, body, span) => {
                variable(binding);
                var iterated = expression(iterable);
                block(body);
                if (rewrites != before) {
                    return Statement.For(binding, pattern, iterated, body, span);
                }
            }
            With(binding, scope, body, else_block, span) => {
                if (binding.is_value()) {
                    variable(binding.value());
                }
                var entered = expression(scope);
                block(body);
                if (else_block.is_value()) {
                    block(else_block.value());
                }
                if (rewrites != before) {
                    return Statement.With(binding, entered, body, else_block, span);
                }
            }
            Return(value, span) => {
                var returned = optional(value);
                if (rewrites != before) {
                    return Statement.Return(returned, span);
                }
            }
            LoopBreak(_, _, _, _) => {}
            Labeled(label, label_span, loop, span) => {
                var inner = statement(loop);
                if (rewrites != before) {
                    return Statement.Labeled(label, label_span, inner, span);
                }
            }
            Destructure(bindings, value, is_const, span) => {
                var destructured = expression(value);
                if (rewrites != before) {
                    return Statement.Destructure(bindings, destructured, is_const, span);
                }
            }
            Match(m) => {
                m.value = expression(m.value);
                for (var arm in m.arms) {
                    for (var p in arm.patterns) {
                        pattern(p);
                    }
                    arm.guard = optional(arm.guard);
                    block(arm.body);
                }
                if (m.else_block.is_value()) {
                    block(m.else_block.value());
                }
            }
            Static(inner) => {
                static_block(inner);
            }
        }
        return s;
    }

    # ── Expressions ─────────────────────────────────────────────────────

    optional(e: Expression?): Expression? {
        if (!e.is_value()) {
            return e;
        }
        var before = rewrites;
        var rewritten = expression(e.value());
        if (rewrites == before) {
            return e;
        }
        return Optional<Expression>.Value(rewritten);
    }

    # Rewrites each of `list` in place.
    all(list: Expression[]) {
        ulong i = 0;
        while (i < list.count) {
            var before = rewrites;
            var rewritten = expression(list[i]);
            if (rewrites != before) {
                list[i] = rewritten;
            }
            i += 1;
        }
    }

    pattern(p: Pattern) {
        p.literal = optional(p.literal);
        p.range_end = optional(p.range_end);
        if (p.elements.is_value()) {
            for (var element in p.elements.value()) {
                pattern(element);
            }
        }
        if (p.bindings.is_value()) {
            for (var binding in p.bindings.value()) {
                pattern(binding);
            }
        }
    }

    expression(e: Expression): Expression {
        var before = rewrites;
        match (e) {
            Literal(_, _) => {}
            SymbolRef(_, _) => {}
            TypeLiteral(_) => {}
            SizeOf(_) => {}
            Unary(op, prefix, operand, span) => {
                var value = expression(operand);
                if (rewrites != before) {
                    return Expression.Unary(op, prefix, value, span);
                }
            }
            Cast(value, type_name, span, keyword_span, is_optional) => {
                var cast = expression(value);
                if (rewrites != before) {
                    return Expression.Cast(cast, type_name, span, keyword_span, is_optional);
                }
            }
            Binary(lhs, op, rhs, span) => {
                var left = expression(lhs);
                var right = expression(rhs);
                if (rewrites != before) {
                    return Expression.Binary(left, op, right, span);
                }
            }
            Ternary(condition, true_expr, false_expr, span) => {
                var tested = expression(condition);
                var yes = expression(true_expr);
                var no = expression(false_expr);
                if (rewrites != before) {
                    return Expression.Ternary(tested, yes, no, span);
                }
            }
            Index(lhs, rhs, span) => {
                var left = expression(lhs);
                var right = expression(rhs);
                if (rewrites != before) {
                    return Expression.Index(left, right, span);
                }
            }
            MemberAccess(lhs, name, name_span, span) => {
                var value = expression(lhs);
                if (rewrites != before) {
                    return Expression.MemberAccess(value, name, name_span, span);
                }
            }
            FunctionCall(function, arguments, span) => {
                var callee = expression(function);
                all(arguments);
                if (arguments.count > 0 and arguments[0] is FormatString(_, _, _, _)) {
                    rewrites += 1;
                    var lowered = desugar_format_call(callee, arguments, span);
                    if (lowered.is_err()) {
                        var problem = lowered.error();
                        _fail(problem.message, problem.span, problem.call);
                        return Expression.Literal(Literal.Null, span);
                    }
                    return lowered.value();
                }
                if (rewrites != before) {
                    return Expression.FunctionCall(callee, arguments, span);
                }
            }
            NamedArgument(name, name_span, value, span) => {
                var argument = expression(value);
                if (rewrites != before) {
                    return Expression.NamedArgument(name, name_span, argument, span);
                }
            }
            Closure(closure) => {
                for (var parameter in closure.parameters) {
                    variable(parameter);
                }
                block(closure.body);
            }
            Tuple(elements, _, _) => {
                all(elements);
            }
            ArrayLiteral(elements, _) => {
                all(elements);
            }
            MapLiteral(entries, _) => {
                for (var entry in entries) {
                    entry.key = expression(entry.key);
                    entry.value = expression(entry.value);
                }
            }
            Match(m) => {
                m.value = expression(m.value);
                for (var arm in m.arms) {
                    for (var p in arm.patterns) {
                        pattern(p);
                    }
                    arm.guard = optional(arm.guard);
                    arm.value = expression(arm.value);
                }
                m.else_value = optional(m.else_value);
            }
            Is(value, tested, keyword_span, span) => {
                var operand = expression(value);
                pattern(tested);
                if (rewrites != before) {
                    return Expression.Is(operand, tested, keyword_span, span);
                }
            }
            Interpolated(parts, span) => {
                rewrites += 1;
                var rewritten = Array<StringPart>();
                for (var part in parts) {
                    if (part is Hole(value, braces, spec)) {
                        rewritten.append(StringPart.Hole(expression(value), braces, spec));
                    } else {
                        rewritten.append(part);
                    }
                }
                return desugar_interpolated(rewritten, span);
            }
            # Only ever a call's first argument, which `desugar_format_call`
            # rewrites with the call.
            FormatString(_, _, _, _) => {}
            Parenthesized(value, _) => {
                rewrites += 1;
                return expression(value);
            }
        }
        return e;
    }
}

# ── Interpolated strings and formats ────────────────────────────────────

## Returns an interpolated string, `$"sum is {a + b}"`, desugared: the
## concatenation of its text and the calls that convert each value in
## braces. The parser of `parse.parse` applies it to each one it reads.
##
## @param parts the string's parts, each hole's value already desugared
## @param span the literal
## @returns the concatenation
export desugar_interpolated(parts: StringPart[], span: Span): Expression {
    var pieces = Array<Expression>();
    for (var part in parts) {
        match (part) {
            Text(text, text_span) => {
                pieces.append(Expression.Literal(Literal.String(text), text_span));
            }
            Hole(value, braces, spec) => {
                pieces.append(_interpolation_call(value, braces, spec));
            }
            Argument(_, _, _, _) => {}
        }
    }
    return _join_parts(pieces, span);
}

## Returns `print("{0}", x)` or `String.format("{0}", x)`, whose first
## argument is an `Expression.FormatString`, desugared: the format's text,
## passed to `print`. The parser of `parse.parse` applies it to each one
## it reads.
##
## @param callee `print`, or `String.format`
## @param arguments the format, then the arguments, already desugared
## @param span the call
## @returns the call or text, or the error when the format's braces and
##   arguments do not match
export desugar_format_call(callee: Expression, arguments: Expression[], span: Span): Result<Expression, DesugarError> {
    var text = _format_text(callee, arguments, span);
    if (text.is_err() or !(callee is SymbolRef(_, _))) {
        return text;
    }
    return Result<Expression, DesugarError>.ok(Expression.FunctionCall(callee, [text.value()], span));
}

# The format string and the arguments after it, as the concatenation
# an interpolated string would make, or a `match` that binds the
# arguments when the braces do not name each once, in order.
_format_text(callee: Expression, arguments: Expression[], span: Span): Result<Expression, DesugarError> {
    var name = "print";
    var name_span = callee.span();
    if (callee is MemberAccess(_, _, member_span, _)) {
        name = "String.format";
        name_span = member_span;
    }
    var format_parts = Array<StringPart>();
    ulong paren = 0;
    var value_spans = Array<Span>();
    if (arguments[0] is FormatString(written_parts, _, written_paren, argument_spans)) {
        format_parts = written_parts;
        paren = written_paren;
        value_spans = argument_spans;
    }
    var parts = Array<Expression>();
    var holes = Array<ulong>();
    var hole_spans = Array<Span>();
    for (var part in format_parts) {
        match (part) {
            Text(text, text_span) => {
                parts.append(Expression.Literal(Literal.String(text), text_span));
            }
            Argument(index, index_span, braces, spec) => {
                holes.append(index);
                hole_spans.append(index_span);
                var value = Expression.SymbolRef($"{FORMAT_ARGUMENT_PREFIX}{index}", index_span);
                parts.append(_interpolation_call(value, braces, spec));
            }
            Hole(_, _, _) => {}
        }
    }
    var values = Array<Expression>();
    ulong v = 1;
    while (v < arguments.count) {
        values.append(arguments[v]);
        v += 1;
    }
    var count = values.count;
    ulong h = 0;
    while (h < holes.count) {
        if (holes[h] >= count) {
            var noun = count == 1 ? "argument" : "arguments";
            return Result<Expression, DesugarError>.err(
                DesugarError(
                    $"argument index {holes[h]} is out of range for {count} {noun}", hole_spans[h], span, span.end
                )
            );
        }
        h += 1;
    }
    ulong a = 0;
    while (a < count) {
        bool used = false;
        for (var index in holes) {
            if (index == a) {
                used = true;
            }
        }
        if (!used) {
            return Result<Expression, DesugarError>.err(
                DesugarError(
                    $"argument {a} of '{name}' is not used by its format string", value_spans[a], span, span.end
                )
            );
        }
        a += 1;
    }
    if (is_in_order(format_parts, count)) {
        var next = 0 as ulong;
        var filled = Array<Expression>();
        for (var part in parts) {
            if (part is FunctionCall(function, part_arguments, part_span)) {
                var replaced = Array<Expression>();
                replaced.append(values[next]);
                next += 1;
                ulong k = 1;
                while (k < part_arguments.count) {
                    replaced.append(part_arguments[k]);
                    k += 1;
                }
                filled.append(Expression.FunctionCall(function, replaced, part_span));
            } else {
                filled.append(part);
            }
        }
        return Result<Expression, DesugarError>.ok(_join_parts(filled, span));
    }
    var elements = Array<Pattern>();
    ulong e = 0;
    while (e < count) {
        elements.append(_name_pattern($"{FORMAT_ARGUMENT_PREFIX}{e}", value_spans[e]));
        e += 1;
    }
    var tuple_span = Span(paren, span.end);
    if (count == 1) {
        values.append(Expression.Literal(Literal.Bool(false), tuple_span));
        elements.append(_name_pattern("_", tuple_span));
    }
    var tuple_pattern = Pattern();
    tuple_pattern.elements = Optional<Pattern[]>.Value(elements);
    tuple_pattern.case_span = tuple_span;
    tuple_pattern.span = tuple_span;
    var arm = MatchValueArm();
    arm.patterns.append(tuple_pattern);
    arm.value = _join_parts(parts, span);
    arm.span = span;
    var out = MatchExpression(Expression.Tuple(values, Array<Label>(), tuple_span));
    out.arms.append(arm);
    out.keyword_span = name_span;
    out.span = span;
    return Result<Expression, DesugarError>.ok(Expression.Match(out));
}

_name_pattern(name: String, span: Span): Pattern {
    var out = Pattern();
    out.case_name = name;
    out.case_span = span;
    out.span = span;
    return out;
}

# The call that converts `value`, in braces at `braces`, to text.
_interpolation_call(value: Expression, braces: Span, spec: FormatSpec?): Expression {
    if (!spec.is_value()) {
        return _format_call_of(INTERPOLATE_FUNCTION, braces, [value]);
    }
    var s = spec.value();
    var fill = Expression.Literal(Literal.String(s.fill), braces);
    var align = Expression.Literal(Literal.Integer(s.has_align ? s.align : 0), braces);
    var width = Expression.Literal(Literal.Integer(s.width), braces);
    if (s.point.is_value()) {
        return _format_call_of(
            FORMAT_FLOAT_FUNCTION,
            s.point.value(),
            [
                value,
                Expression.Literal(Literal.Integer(s.precision), braces),
                Expression.Literal(Literal.Bool(s.plus.is_value()), braces),
                fill,
                align,
                width,
                Expression.Literal(Literal.Bool(s.zero.is_value()), braces)
            ]
        );
    }
    Span? integer;
    if (!s.kind.is_empty) {
        integer = Optional<Span>.Value(s.kind_span);
    } else if (s.plus.is_value()) {
        integer = s.plus;
    } else if (s.zero.is_value()) {
        integer = s.zero;
    }
    if (!integer.is_value()) {
        return _format_call_of(FORMAT_FUNCTION, braces, [value, fill, align, width]);
    }
    var kind = s.kind.is_empty ? "d" : s.kind;
    long number_base = 10;
    if (kind == "x" or kind == "X") {
        number_base = 16;
    } else if (kind == "b") {
        number_base = 2;
    } else if (kind == "o") {
        number_base = 8;
    }
    return _format_call_of(
        FORMAT_INTEGER_FUNCTION,
        integer.value(),
        [
            value,
            Expression.Literal(Literal.Integer(number_base), braces),
            Expression.Literal(Literal.Bool(kind == "X"), braces),
            Expression.Literal(Literal.Bool(s.plus.is_value()), braces),
            fill,
            align,
            width,
            Expression.Literal(Literal.Bool(s.zero.is_value()), braces)
        ]
    );
}

_format_call_of(name: String, span: Span, arguments: Expression[]): Expression {
    return Expression.FunctionCall(Expression.SymbolRef(name, span), arguments, span);
}

# The concatenation of `parts`, covering `span`.
_join_parts(parts: Expression[], span: Span): Expression {
    if (parts.count == 0) {
        return Expression.Literal(Literal.String(""), span);
    }
    var joined = parts[0];
    ulong i = 1;
    while (i < parts.count) {
        var rhs = parts[i];
        joined = Expression.Binary(joined, "+", rhs, Span(joined.span().start, rhs.span().end));
        i += 1;
    }
    match (joined) {
        Binary(lhs, op, rhs, _) => {
            return Expression.Binary(lhs, op, rhs, span);
        }
        Literal(value, _) => {
            return Expression.Literal(value, span);
        }
        else => {}
    }
    return joined;
}
