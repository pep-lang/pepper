## The compiler's parser: reads the tokens of one source file straight into
## `compiler.ast`, with properties lowered to their accessors.
## Interpolated strings, `print` and `String.format` formats, module-scope
## `static` blocks and parentheses stay as the source writes them
## (`parse_written`), which also keeps every token and its comments;
## `parse` rewrites them with `compiler.desugar`, and keeps no tokens.
##
## The grammar is the one place Pepper's syntax is read in Pepper (pep-fmt
## lays out what `parse_written` returns). It decides by a fixed
## lookahead, with readings tried and abandoned, and reports one syntax
## error, the one furthest into the source
## unless a `;` is missing first. An error in a node that parses (a literal too large, an
## unknown escape, a bad format) is reported only when the file has no
## syntax error, and the first one is the one the compiler meets first.

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
import [is_reserved_word, SyntaxError, Token, TokenKind] from syntax;
import [Utf8] from text;
import "checks" as checks;

## An error the parser reports: what is wrong and where.
export struct ParseError {
    ## The message, worded like clang's.
    var message: String;
    ## The byte range it is about.
    var span: Span;
    ## Another place the error is about, if any: for a missing `}`, the `{`
    ## it should close (`parse_recovering` only).
    var related: Span?;
    ## What `related` is, as "to match this '{'".
    var related_message: String = "";

    ## Creates an error.
    ##
    ## @param message what is wrong
    ## @param span where
    construct(message: String = "", span: Span = Span()) {
        this.message = message;
        this.span = span;
    }
}

## Parses Pepper source into the compiler's syntax tree, desugared:
## interpolated strings and `print` and `String.format`
## formats lowered to calls, and each module-scope `static` block followed
## by the constants it declares (see `compiler.desugar`).
##
## @param source the text of one source file
## @returns the module, or the first syntax error
export parse(source: String): Result<ast.Module, ParseError> {
    return _parse(source, true);
}

## `parse` with each function body read as an empty block over its span:
## the declarations, for a file whose bodies a build does not check
## (`link.Setup.defer_bodies`). An error in a body is not found.
##
## @param source the text of one source file
## @returns the module, or the first syntax error
export parse_declarations(source: String): Result<ast.Module, ParseError> {
    return _parse(source, true, true, true);
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
## With `checked` false, only a lexical or syntax error stops it: the errors
## in nodes that parse (a literal out of range, a bad escape or hole, a
## format) and the checks after parsing are left out, as a tool that only
## lays the source out (pep-fmt) needs. So is the work that only they need:
## a string literal's text is not decoded (`Literal.String("")`), and an
## interpolated string or a format has no parts. Every node keeps its spans.
##
## @param source the text of one source file
## @param checked whether errors beyond the syntax stop it too
## @returns the module, or the first syntax error
export parse_written(source: String, checked: bool = true): Result<ast.Module, ParseError> {
    return _parse(source, false, checked);
}

## What `parse_recovering` returns: the module as far as it parses, and
## every error.
export struct Recovered {
    ## The module in `parse`'s shape, without the statements, members and
    ## declarations that did not parse.
    var module: ast.Module;
    ## Every error, in order; empty when the source parses. The first is
    ## the one `parse` reports.
    var errors: ParseError[] = Array<ParseError>();

    ## Creates a result.
    ##
    ## @param module the module as far as it parses
    construct(module: ast.Module) {
        this.module = module;
    }
}

# The most errors `parse_recovering` reports, and the most times it lexes a
# file again after blanking a line the lexer refused.
const _MOST_ERRORS: ulong = 100;

## Parses Pepper source like `parse`, but reads on past its errors, for an
## editor: the module keeps every statement, member and declaration that
## parses, and the result lists every error. A source that `parse` accepts
## costs one `parse`, and gives its module and no errors.
##
## After a syntax error the parser skips to the end of the broken
## statement, member or declaration (its `;`, its braces, or the next line)
## and goes on. A missing `}` is reported where it was due, with the `{`
## it should close as `related`. A line the lexer refuses is read as spaces.
## The errors come in `parse`'s order (lexical, syntax, errors in nodes that
## parse, then the checks after parsing), and the first is always the one
## `parse` reports, with the same message and offset. Source nested past
## `MAX_NESTING` gives that error alone, and an empty module.
##
## @param source the text of one source file
## @returns the module as far as it parses, and its errors
export parse_recovering(source: String): Recovered {
    var parsed = parse(source);
    if (parsed.is_ok()) {
        return Recovered(parsed.value());
    }
    # Past `MAX_NESTING` the reading stops at the limit, and what follows
    # only reads as unmatched braces and parentheses: that error alone.
    if (parsed.error().message == _too_deep_message()) {
        var out = Recovered(ast.Module());
        out.errors.append(parsed.error());
        return out;
    }
    var errors = Array<ParseError>();
    var text = source;
    var tokens = syntax.lex(text, false);
    while (tokens.is_err() and errors.count < _MOST_ERRORS) {
        var error = tokens.error();
        errors.append(ParseError(error.message, Span(error.offset, error.offset)));
        var blanked = _blank_line(text, error.offset);
        if (!blanked) {
            break;
        }
        text = blanked.value();
        tokens = syntax.lex(text, false);
    }
    if (tokens.is_err()) {
        var out = Recovered(ast.Module());
        out.errors = _pin_first(parsed.error(), errors);
        return out;
    }
    var parser = Parser(text, tokens.value(), true);
    parser._recovering = true;
    var module = parser.module();
    if (parser._failed) {
        parser._record(parser._position, parser._failure());
    }
    errors.append_all(parser._recovered);
    errors.append_all(parser._problems);
    var broken = checks.check_module(module);
    if (broken.is_value()) {
        var offset = broken.value().offset;
        errors.append(ParseError(broken.value().message, Span(offset, offset)));
    }
    var out = Recovered(module);
    out.errors = _pin_first(parsed.error(), errors);
    return out;
}

# `errors` with `first`, the error `parse` reports, first: in place of the
# first of them when that is the same error (keeping its related place),
# else before them.
_pin_first(first: ParseError, errors: ParseError[]): ParseError[] {
    var out = Array<ParseError>();
    out.append(first);
    ulong i = 0;
    if (errors.count > 0 and errors[0].span.start == first.span.start and errors[0].message == first.message) {
        out[0].related = errors[0].related;
        out[0].related_message = errors[0].related_message;
        i = 1;
    }
    while (i < errors.count) {
        out.append(errors[i]);
        i += 1;
    }
    return out;
}

# `text` with the line holding byte `offset`, from that byte to its end,
# made spaces, which keeps every offset; empty when there is nothing there
# but spaces.
_blank_line(text: String, offset: ulong): String? {
    ulong end = offset;
    bool changed = false;
    while (end < text.size and text.byte_at(end) != '\n') {
        int c = text.byte_at(end);
        if (c != ' ' and c != '\r') {
            changed = true;
        }
        end += 1;
    }
    if (!changed) {
        return Optional<String>.Empty;
    }
    var spaces = " ".repeat(end - offset);
    return Optional<String>.Value(text.substr_bytes(0, offset) + spaces + text.substr_bytes(end, text.size - end));
}

# Parses `source`, desugared or as written; with `checked`, the errors in
# nodes that parse and the checks after parsing are errors too.
_parse(
    source: String, desugared: bool, checked: bool = true, skip_bodies: bool = false
): Result<ast.Module, ParseError> {
    # Only the written tree keeps the comments.
    var tokens = syntax.lex(source, !desugared);
    if (tokens.is_err()) {
        var error = tokens.error();
        return Result<ast.Module, ParseError>.err(ParseError(error.message, Span(error.offset, error.offset)));
    }
    var parser = Parser(source, tokens.value(), desugared);
    parser._layout_only = !desugared and !checked;
    parser._skip_bodies = skip_bodies;
    var module = parser.module();
    if (parser._failed) {
        var error = parser._error.value();
        return Result<ast.Module, ParseError>.err(ParseError(error.message, Span(error.offset, error.offset)));
    }
    if (!checked) {
        return Result<ast.Module, ParseError>.ok(module);
    }
    if (!parser._problems.is_empty) {
        return Result<ast.Module, ParseError>.err(parser._problems[0]);
    }
    var broken = checks.check_module(module);
    if (broken.is_value()) {
        var offset = broken.value().offset;
        return Result<ast.Module, ParseError>.err(ParseError(broken.value().message, Span(offset, offset)));
    }
    return Result<ast.Module, ParseError>.ok(module);
}

## The deepest the tree of a source file may nest, as clang's
## `-fbracket-depth` bounds it: each parenthesis, block, `else if`, type
## argument, pattern, prefix operator and argument list nests one level
## deeper, and so does each operator of a chain (`a + b + c` is two levels)
## and each `.member`, call or index of a postfix chain. A call's
## arguments, and an interpolated string's holes, are one level more.
## Every stage after the parser recurses over the tree, so this bounds the
## stack they need (`STACK_SIZE`).
export const MAX_NESTING: int = 256;

# The error for source nested past `MAX_NESTING`.
_too_deep_message(): String {
    return $"code is nested too deeply: the limit is {MAX_NESTING} levels; split it into smaller expressions or functions";
}

# No token: the index `_suspect_open` holds when no block is suspect.
const _NO_TOKEN: ulong = 0xFFFFFFFFFFFFFFFF;

# A point the parser can come back to: the input position, and how full
# each list was that a reading adds to, so that an abandoned reading leaves
# nothing behind.
[Value]
struct Mark {
    var position: ulong;
    var problems: ulong;
    var joins: ulong;
    var tests: ulong;
    var warnings: ulong;
    var names: ulong;
    var deepest: int;

    construct() {}
}

# What comes before a declaration: its attributes, and an `export` or
# `private`.
struct Prefix {
    var attributes: Attribute[] = Array<Attribute>();
    var exported: bool;
    var file_private: bool;
    # The offset of the `export` or `private`.
    var modifier_start: ulong;

    construct(attributes: Attribute[]) {
        this.attributes = attributes;
    }

    # Where a declaration whose own first token starts at `own` starts: at
    # its first attribute, else at its `export` or `private`.
    start_or(own: ulong): ulong {
        if (attributes.count > 0) {
            return attributes[0].span.start;
        }
        if (exported or file_private) {
            return modifier_start;
        }
        return own;
    }
}

# The arguments of a call, and where each was written.
struct ArgumentList {
    var values: Expression[] = Array<Expression>();
    # The index of each argument's first token, and of the token after it.
    var starts: ulong[] = Array<ulong>();
    var ends: ulong[] = Array<ulong>();
    # The index of the `(`.
    var open: ulong;
    # How many problems had been found before the first argument, and
    # after it.
    var problems_before: ulong;
    var problems_after_first: ulong;

    construct() {}
}

# The members of a struct, trait, enum or extension.
struct MemberList {
    var methods: FunctionDecl[] = Array<FunctionDecl>();
    var constructors: FunctionDecl[] = Array<FunctionDecl>();
    var fields: VariableDecl[] = Array<VariableDecl>();
    var properties: PropertyDecl[] = Array<PropertyDecl>();
    var destructor: Block?;
    var destruct_span: Span?;

    construct() {}
}

# Which aggregate's members are being read.
enum MemberKind {
    Struct,
    Trait,
    Extend,
}

# What a postfix expression is so far, for the calls whose first argument
# may be a format: `print(...)` and `String.format(...)`.
enum Callee {
    Other,
    # The name `print` alone.
    Print,
    # The name `String` alone.
    StringName,
    # `String.format`, with no type arguments.
    StringFormat,
}

# Recursive descent over the token list, building the tree as it goes. On
# a syntax error a method sets `_failed` and returns an incomplete node,
# which its callers return in turn or abandon. A method that tries one
# reading and falls back to another takes a `Mark` first, and restores it
# (clearing `_failed`) when the first fails.
#
# The errors in nodes that parse, which `_problems` collects, are reported
# in the order the compiler meets them, which is the source order but for
# two cases that `_property` and `_call` put back in that order.
struct Parser {
    # Whether interpolated strings, formats, module-scope `static` blocks
    # and parentheses are desugared as they are read (`parse`), else kept as
    # written (`parse_written`).
    var desugared: bool;
    # Whether the tree is read only to lay the source out (`parse_written`
    # unchecked), so string literals, interpolated strings and formats are
    # not taken apart: no error in them is reported.
    var _layout_only: bool;
    # Whether function bodies are skipped, each read as an empty block over
    # the same span (`parse_declarations`).
    var _skip_bodies: bool = false;
    # The text the tokens point into: the file, or inside an interpolated
    # string's braces the expression's own text.
    var _source: String;
    var _tokens: Token[];
    var _position: ulong;
    var _failed: bool;
    # The syntax error furthest into the source so far.
    var _error: SyntaxError?;
    # Set by a missing `;` or by code nested too deeply, which is reported
    # over any error found further on, like the compiler's hard errors.
    var _final_error: bool;
    # The tree level of what is being read (`_enter`), the deepest level
    # the tree has reached (`_wrap`), and whether `_error` is that reading
    # went past `MAX_NESTING`.
    var _level: int;
    var _deepest: int;
    var _too_deep: bool;
    # Whether a type is being read where an expression could also start, in
    # which case `a.b` is a qualified type only when `a` names an import.
    var _probing: bool;
    # The next type arguments are an `extend` target's, which may restate
    # the struct's constraints (`extend Box<T: Shape>`).
    var _restating: bool;
    # Whether the restated type arguments were those of the target's own
    # name, and the constraints they restate, one list per argument.
    var _restated: bool;
    var _restated_bounds: TypeName[][] = Array<TypeName[]>();
    # How many types enclose the one being read.
    var _type_depth: int;
    # Whether the last named type read was qualified (`m.Box`) and had type
    # arguments, and the index of its last name.
    var _type_qualified: bool;
    var _type_generic: bool;
    var _type_last_name: ulong;
    # The names that qualify a type (`geo.Box<int>()`): imports, and inside
    # a `static` block the names its `for`s and `var`s bind.
    var _qualifiers: HashSet<String> = HashSet<String>();
    # How many `static` blocks enclose the parser, inside which the names a
    # `for` or `var` binds qualify types too (`case.Type`), as in the
    # compiler.
    var _static_depth: int;
    # The operators a method may be named after; made when first needed.
    var _operator_names: HashSet<String>;
    # Added to every token offset: the offset in the file of the text being
    # read, which is not 0 inside an interpolated string's braces.
    var _base: ulong;
    # Whether the text is an interpolated string's braces, where a span that
    # ends after the whitespace following a node ends at the node instead.
    var _in_hole: bool;
    # Whether a struct's, enum's or extension's members are being read,
    # whose `Type name()` return types end at the type's name.
    var _in_members: bool;
    # The errors in nodes that parse, in the order the compiler meets them.
    var _problems: ParseError[] = Array<ParseError>();
    # Each `>` the parser joins with the tokens after it (`>>`, `>=`, `>>=`)
    # and `!` with `!`: the first token's index, then the joined size. Kept
    # as written only, for `Module.tokens`.
    var _joins: ulong[] = Array<ulong>();
    var _build_option_tests: Attribute[] = Array<Attribute>();
    var _warnings: SyntaxWarning[] = Array<SyntaxWarning>();
    # The names that qualify a type in an interpolated string's braces, as
    # the compiler binds them: `_qualifiers`, but for the names bound in a
    # reading later abandoned. Holds a name more than once when bound more
    # than once.
    var _lowered_names: String[] = Array<String>();
    var _lowered_static_depth: int;
    # The token after the last `-1` read as one token pair by `_primary`,
    # and how many problems there were before its number was decoded.
    var _negative_end: ulong = 0xFFFFFFFFFFFFFFFF;
    var _negative_problems: ulong;
    # The type a `: Type` gave the last variable read, if any.
    var _variable_annotation: TypeName?;
    # Whether a broken statement, member or declaration is noted and
    # skipped instead of ending the parse (`parse_recovering`).
    var _recovering: bool;
    # The errors skipped past so far, and the index of the first token of
    # the item each ended (so that abandoning a reading drops its errors).
    var _recovered: ParseError[] = Array<ParseError>();
    var _recovered_items: ulong[] = Array<ulong>();
    # The `{` of the first block closed by a `}` indented unlike its own
    # line, which may have taken an outer block's `}`; `_NO_TOKEN` if none.
    var _suspect_open: ulong = _NO_TOKEN;
    # What `_nothing` returns, made when first needed.
    var _placeholder: Expression;

    construct(source: String, tokens: Token[], desugared: bool) {
        this._source = source;
        this._tokens = tokens;
        this.desugared = desugared;
    }

    # ── Token access ─────────────────────────────────────────────────────

    _peek(): Token {
        return _tokens[_position];
    }

    _peek_at(offset: ulong): Token {
        ulong index = _position + offset;
        if (index >= _tokens.count) {
            return _tokens.last();
        }
        return _tokens[index];
    }

    _advance(): Token {
        var token = _tokens[_position];
        if (token.kind != TokenKind.End) {
            _position += 1;
        }
        return token;
    }

    _at(punctuation: String): bool {
        return _peek().is(_source, punctuation);
    }

    _at_word(word: String): bool {
        return _peek().is_word(_source, word);
    }

    _at_end(): bool {
        return _peek().kind == TokenKind.End;
    }

    # Whether the next token is a name: an identifier that is not reserved.
    _at_name(): bool {
        var token = _peek();
        return token.kind == TokenKind.Identifier and !is_reserved_word(_source, token);
    }

    # Whether the token at `offset` follows the one before it with no space.
    _adjacent(offset: ulong): bool {
        return !_peek_at(offset).space_before;
    }

    _fail(message: String) {
        var offset = _peek().offset;
        if (!_final_error and (!_error or offset > _error.value().offset)) {
            _error = Optional<SyntaxError>.Value(SyntaxError(message, offset));
        }
        _failed = true;
    }

    _mark(): Mark {
        var mark = Mark();
        mark.position = _position;
        mark.problems = _problems.count;
        mark.joins = _joins.count;
        mark.tests = _build_option_tests.count;
        mark.warnings = _warnings.count;
        mark.names = _lowered_names.count;
        mark.deepest = _deepest;
        return mark;
    }

    # ── Recovery (`parse_recovering`) ─────────────────────────────────────

    # The syntax error that stopped the reading, which is cleared so that
    # reading can go on.
    _failure(): ParseError {
        var offset = _peek().offset;
        var message = "expected expression";
        if (_error.is_value()) {
            offset = _error.value().offset;
            message = _error.value().message;
        }
        _failed = false;
        _clear_error();
        return ParseError(message, Span(offset, offset));
    }

    # Forgets the syntax error found so far.
    _clear_error() {
        _error = Optional<SyntaxError>.Empty;
        _final_error = false;
        _too_deep = false;
    }

    # Notes `error`, which ended the item whose first token is `item`,
    # unless the last error noted is at its offset or there are enough.
    _record(item: ulong, error: ParseError) {
        if (_recovered.count >= _MOST_ERRORS) {
            return;
        }
        if (!_recovered.is_empty and _recovered.last().span.start == error.span.start) {
            return;
        }
        _recovered.append(error);
        _recovered_items.append(item);
    }

    # Drops the errors noted in items from token `position` on, which an
    # abandoned reading read.
    _drop_recovered(position: ulong) {
        while (!_recovered_items.is_empty and _recovered_items.last() >= position) {
            _recovered_items.pop();
            _recovered.pop();
        }
    }

    # After the item from `item` failed: notes the error, goes back to the
    # item's start and skips its tokens (`_skip_item`). `open` is the `{` of
    # the braces around the item, or `_NO_TOKEN` at the top level.
    _skip_failed(item: Mark, open: ulong) {
        var error = _failure();
        _restore(item);
        _record(item.position, error);
        _skip_item(error.span.start, open);
    }

    # Skips a broken item from the next token, with its brackets: through a
    # `;` or a braced body at depth 0, or up to a token that starts a line at
    # depth 0 at or after byte `error` (where the error was found), or up to
    # the `}` of the braces opened at `open`. Skips at least one token.
    _skip_item(error: ulong, open: ulong) {
        ulong first = _position;
        int depth = 0;
        while (!_at_end()) {
            var token = _peek();
            if (_position > first and depth == 0 and token.offset >= error and _indentation(_position) >= 0) {
                return;
            }
            if (token.kind == TokenKind.Punctuation and token.size == 1) {
                int c = _source.byte_at(token.offset);
                if (c == '(' or c == '[' or c == '{') {
                    depth += 1;
                } else if (c == ')' or c == ']' or c == '}') {
                    if (depth == 0) {
                        if (c == '}' and _position > first and _closes(open)) {
                            return;
                        }
                    } else {
                        depth -= 1;
                        if (depth == 0 and c == '}') {
                            _advance();
                            return;
                        }
                    }
                } else if (c == ';' and depth == 0) {
                    _advance();
                    return;
                }
            }
            _advance();
        }
    }

    # Whether the `}` at the input, met while recovering inside the braces
    # opened at `open` (`_NO_TOKEN` for none), closes them: unless it starts
    # a line indented deeper than the `{` line, as the `}` of a construct
    # whose `{` an error cut off does.
    _closes(open: ulong): bool {
        if (open == _NO_TOKEN) {
            return false;
        }
        var column = _indentation(_position);
        return column < 0 or column <= _line_indentation(open);
    }

    # The column of token `index` when it is the first on its line, else -1.
    _indentation(index: ulong): long {
        ulong offset = _tokens[index].offset;
        ulong start = offset;
        while (start > 0) {
            int c = _source.byte_at(start - 1);
            if (c == '\n') {
                break;
            }
            if (c != ' ' and c != '\t') {
                return -1;
            }
            start -= 1;
        }
        return (offset - start) as long;
    }

    # The column at which the line holding token `index` starts its text.
    _line_indentation(index: ulong): long {
        ulong offset = _tokens[index].offset;
        while (offset > 0 and _source.byte_at(offset - 1) != '\n') {
            offset -= 1;
        }
        ulong end = offset;
        while (end < _source.size and (_source.byte_at(end) == ' ' or _source.byte_at(end) == '\t')) {
            end += 1;
        }
        return (end - offset) as long;
    }

    # Whether the item from token `item`, in the braces opened at `open`,
    # starts a line indented no deeper than the `{` line: where the `}`
    # was due.
    _dedented(item: ulong, open: ulong): bool {
        var column = _indentation(item);
        return column >= 0 and column <= _line_indentation(open);
    }

    # Notes that the braces opened at `open` are not closed before token
    # `at`: "expected '}'" there, related to the `{` that most likely lost
    # its `}`.
    _unclosed(open: ulong, at: ulong) {
        var brace = open;
        if (_suspect_open != _NO_TOKEN and _suspect_open > open) {
            brace = _suspect_open;
        }
        _suspect_open = _NO_TOKEN;
        var offset = _tokens[at].offset + _base;
        var error = ParseError("expected '}'", Span(offset, offset));
        error.related = Optional<Span>.Value(_token_span(brace));
        error.related_message = "to match this '{'";
        # Noted as in the block, which the reading from `at` does not drop.
        _record(at - 1, error);
    }

    # After the `}` of the braces opened at `open`: notes them as suspect
    # when the `}` starts a line indented unlike the `{` line, and clears a
    # suspect inside them when it does not.
    _note_close(open: ulong) {
        var close = _position - 1;
        var column = _indentation(close);
        if (column < 0) {
            return;
        }
        if (column != _line_indentation(open)) {
            if (_suspect_open == _NO_TOKEN) {
                _suspect_open = open;
            }
        } else if (_suspect_open != _NO_TOKEN and _suspect_open > open) {
            _suspect_open = _NO_TOKEN;
        }
    }

    # Goes back to `mark`, dropping what the abandoned reading added.
    _restore(mark: Mark) {
        _position = mark.position;
        _deepest = mark.deepest;
        _failed = false;
        if (_recovering) {
            _drop_recovered(mark.position);
        }
        if (_joins.count > mark.joins) {
            _joins.truncate(mark.joins);
        }
        _discard_lowering(mark);
    }

    # Drops what was added since `mark` to the lists the compiler fills as
    # it builds the tree, for a node it never builds.
    _discard_lowering(mark: Mark) {
        if (_problems.count > mark.problems) {
            _problems.truncate(mark.problems);
        }
        if (_build_option_tests.count > mark.tests) {
            _build_option_tests.truncate(mark.tests);
        }
        if (_warnings.count > mark.warnings) {
            _warnings.truncate(mark.warnings);
        }
        if (_lowered_names.count > mark.names) {
            _lowered_names.truncate(mark.names);
        }
    }

    # Takes the punctuation `text`, or fails.
    _expect(text: String) {
        if (_at(text)) {
            _advance();
        } else {
            _fail("expected '" + text + "'");
        }
    }

    # Takes a name, or fails.
    _expect_name(what: String) {
        if (_at_name()) {
            _advance();
        } else {
            _fail("expected " + what);
        }
    }

    # Ends a simple statement or declaration: takes its `;`, or fails with
    # `expected ';'` right after its last token.
    _finish_statement() {
        if (_at(";")) {
            _advance();
            return;
        }
        var last = _tokens[_position - 1];
        _error = Optional<SyntaxError>.Value(SyntaxError("expected ';'", last.offset + last.size));
        _final_error = true;
        _too_deep = false;
        _failed = true;
    }

    # ── Nesting (`MAX_NESTING`) ──────────────────────────────────────────
    #
    # A rule that recurses into a child reads it one level deeper
    # (`_enter`, `_leave`). A loop that wraps the tree read so far in a new
    # node (`a + b + c`, `f().g()`, `T??`) measures that tree's height
    # instead: `_deepest` is the deepest level it reached, and each turn
    # makes it one level taller (`_wrap`), with the new operand read below
    # the new node (`_level` one deeper while it is read).

    # Goes one level deeper; past `MAX_NESTING`, fails at the input instead
    # and returns false (with the level unchanged).
    _enter(): bool {
        if (_level >= MAX_NESTING) {
            _fail_too_deep();
            return false;
        }
        _level += 1;
        if (_level > _deepest) {
            _deepest = _level;
        }
        return true;
    }

    _leave() {
        _level -= 1;
    }

    # Starts measuring the tree a wrapping loop reads at the current level;
    # returns the deepest level so far, for `_end_wrapping`.
    _start_wrapping(): int {
        var outer = _deepest;
        _deepest = _level;
        return outer;
    }

    # Wraps the tree read since `_start_wrapping` in one more node; past
    # `MAX_NESTING`, fails at the input instead and returns false.
    _wrap(): bool {
        if (_deepest >= MAX_NESTING) {
            _fail_too_deep();
            return false;
        }
        _deepest += 1;
        return true;
    }

    _end_wrapping(outer: int) {
        if (outer > _deepest) {
            _deepest = outer;
        }
    }

    # Fails at the input, over any other error but an earlier one of its
    # own: the first reading to go too deep names the token, as a
    # declaration read before an expression names the `int` of
    # `__ptr<__ptr<...int>> p`, not a `>` of `a < b > c`.
    _fail_too_deep() {
        if (!_too_deep) {
            _error = Optional<SyntaxError>.Value(SyntaxError(_too_deep_message(), _peek().offset));
            _final_error = true;
            _too_deep = true;
        }
        _failed = true;
    }

    # The byte length of the operator at the input, or 0 when the input is
    # not punctuation. It joins the adjacent tokens that the lexer keeps
    # apart: `>` into `>>`, `>=` and `>>=`, and `!` into the truth test
    # `!!`; since they are adjacent, the operator's text is that many bytes
    # of the source from the next token. Expressions never ask for `!!`:
    # `!!x` is two prefix `!`.
    _operator_size(): ulong {
        var token = _peek();
        if (token.kind != TokenKind.Punctuation) {
            return 0;
        }
        if (token.spells(_source, "!") and _peek_at(1).is(_source, "!") and _adjacent(1)) {
            return 2;
        }
        if (!token.spells(_source, ">")) {
            return token.size;
        }
        if (_peek_at(1).is(_source, ">") and _adjacent(1)) {
            if (_peek_at(2).is(_source, "=") and _adjacent(2)) {
                return 3;
            }
            return 2;
        }
        if (_peek_at(1).is(_source, "=") and _adjacent(1)) {
            return 2;
        }
        return 1;
    }

    # Whether the operator at the input, `size` bytes long (from
    # `_operator_size()`), is `text`.
    _operator_is(size: ulong, text: String): bool {
        return size == text.size and Token(TokenKind.Punctuation, _peek().offset, size).spells(_source, text);
    }

    # The operator at the input, `size` bytes long, as a new String.
    _operator_text(size: ulong): String {
        return _source.substr_bytes(_peek().offset, size);
    }

    # Whether the operator at the input, `size` bytes long, can name a
    # method, as `bool ==(T other)`.
    _at_operator_name(size: ulong): bool {
        if (size == 0) {
            return false;
        }
        if (_operator_names === __null) {
            _operator_names = operator_method_names();
        }
        return _operator_names.contains(_operator_text(size));
    }

    # Takes the operator at the input, `size` bytes long (from
    # `_operator_size()` or a word operator's token), as one token.
    _take_operator(size: ulong) {
        if (_peek().size == size) {
            _advance();
            return;
        }
        if (!desugared) {
            _joins.append(_position);
            _joins.append(size);
        }
        # The joined tokens are adjacent and one byte each.
        ulong i = 0;
        while (i < size) {
            _advance();
            i += 1;
        }
    }

    # ── Positions ────────────────────────────────────────────────────────

    # The file offset where the token at `index` starts.
    _start(index: ulong): ulong {
        return _base + _tokens[index].offset;
    }

    # The file offset where the token at `index` ends.
    _end_of(index: ulong): ulong {
        var token = _tokens[index];
        return _base + token.offset + token.size;
    }

    _token_span(index: ulong): Span {
        var token = _tokens[index];
        return Span(_base + token.offset, _base + token.offset + token.size);
    }

    _text(index: ulong): String {
        return _tokens[index].text(_source);
    }

    # Where the last token taken ends.
    _last_end(): ulong {
        return _end_of(_position - 1);
    }

    # Where the token after the last one taken starts: the end of a span
    # that runs on over the whitespace after it. Inside an interpolated string's braces, the end of the last
    # token.
    _after(): ulong {
        if (_in_hole) {
            return _last_end();
        }
        return _base + _tokens[_position].offset;
    }

    # `_after()` for the token at `index`.
    _after_index(index: ulong): ulong {
        if (_in_hole) {
            return _end_of(index);
        }
        return _base + _tokens[index + 1].offset;
    }

    # The names at `first`, `first + 2`, ... before `end`, joined by `.`:
    # a dotted name whose `.`s were taken with it.
    _dotted_name(first: ulong, end: ulong): String {
        if (end == first + 1) {
            return _text(first);
        }
        var name = StringBuilder();
        name.append(_text(first));
        ulong index = first + 2;
        while (index < end) {
            name.append(".").append(_text(index));
            index += 2;
        }
        return name.to_string();
    }

    # ── Errors in nodes that parse ──────────────────────────────────────

    _problem(message: String, span: Span) {
        _problems.append(ParseError(message, span));
    }

    # An attribute, noting it when it tests a build option.
    _attribute(body: Expression, span: Span): Attribute {
        var out = Attribute(body, span);
        if (contains_platform_predicate(body) and mentions_build_option(body)) {
            _build_option_tests.append(out);
        }
        return out;
    }

    # ── Types ────────────────────────────────────────────────────────────

    # A type: a function type, or a named type with array and pointer
    # suffixes.
    # A level deeper, and each `?` or `*` suffix one more.
    _type_name(): TypeName {
        if (!_enter()) {
            return TypeName();
        }
        var outer = _start_wrapping();
        _type_depth += 1;
        var out = _type_name_at_depth();
        _type_depth -= 1;
        _end_wrapping(outer);
        _leave();
        return out;
    }

    _type_name_at_depth(): TypeName {
        if (_at("(")) {
            return _function_type(_position);
        }
        if ((_at_word("shared") or _at_word("extern")) and _peek_at(1).is(_source, "(")) {
            var mark = _mark();
            ulong start = _position;
            _advance();
            var function = _function_type(start);
            if (!_failed) {
                return function;
            }
            _restore(mark);
        }
        var out = _type_base();
        if (_failed) {
            return out;
        }
        return _type_suffixes(out);
    }

    # `[]` array suffixes, `?` optional suffixes, then `*` pointer suffixes,
    # after the named type `out`. `[]` extends its name, `?` wraps it in
    # `Optional`, and each `*` wraps it in `__ptr`: C's `T*` is rewritten
    # here, so nothing after the parser sees a star in a type's name.
    _type_suffixes(out: TypeName): TypeName {
        out = _optional_suffixes(_array_suffixes(out));
        while (_at("*") or _at("**")) {
            ulong stars = _text(_position).size;
            _advance();
            ulong star_end = _last_end();
            ulong i = 0;
            while (i < stars) {
                if (!_wrap()) {
                    return out;
                }
                out = _c_pointer_to(out, star_end);
                i += 1;
            }
        }
        return out;
    }

    # `pointee*` as the one pointer type there is, `__ptr<pointee>`, ending
    # at `end` and marked as written with C's star.
    _c_pointer_to(pointee: TypeName, end: ulong): TypeName {
        var out = TypeName(ast.POINTER_TYPE, Span(pointee.span.start, end));
        out.generic_types.append(pointee);
        out.c_pointer = true;
        return out;
    }

    # Whether the `?` at the current token makes an optional type while
    # probing, where `a ? b : c` may be a ternary instead. It does when it
    # closes or separates type arguments or a tuple's or function type's
    # elements (`Array<(String, int?)>`, pepper#280), or when a name
    # follows that ends the declaration (`Node? x;`, `Node? x = y`,
    # `Node? x` at the end of the line).
    _optional_suffix_in_probe(): bool {
        var next = _peek_at(1);
        if (next.is(_source, ">") or next.is(_source, ",") or next.is(_source, ")")) {
            return true;
        }
        if (next.kind != TokenKind.Identifier or is_reserved_word(_source, next)) {
            return false;
        }
        var after = _peek_at(2);
        return after.kind == TokenKind.End
            or after.newlines_before > 0
            or next._trailing_comment !== __null
            or after.is(_source, ";")
            or after.is(_source, "}")
            or after.is(_source, "=");
    }

    # `[shared|extern] ( TYPE, ... ) => TYPE`, whose first token is at
    # `start`, or a tuple type `( TYPE, TYPE, ... )`: the compiler reads a
    # tuple where `=>` is missing after two or more types.
    _function_type(start: ulong): TypeName {
        var name = ast.FUNCTION_TYPE;
        if (_tokens[start].is_word(_source, "shared")) {
            name = ast.SHARED_FUNCTION_TYPE;
        } else if (_tokens[start].is_word(_source, "extern")) {
            name = ast.EXTERN_FUNCTION_TYPE;
        }
        _advance();
        var elements = Array<TypeName>();
        var labels = Array<String>();
        bool any_label = false;
        String label = "";
        while (true) {
            if (_at(")")) {
                _advance();
                break;
            }
            # A tuple element's label, `line:` in `(line: int, column: int)`.
            if (_at_name() and _peek_at(1).is(_source, ":")) {
                label = _text(_position);
                any_label = true;
                _advance();
                _advance();
            }
            var element = _type_name();
            if (_failed) {
                return element;
            }
            elements.append(element);
            labels.append(label);
            label = "";
            if (_at(",")) {
                _advance();
                continue;
            }
            if (_at(")")) {
                _advance();
                break;
            }
            _fail("expected ')'");
            return element;
        }
        ulong close_end = _last_end();
        var mark = _mark();
        if (!_at("=>")) {
            if (elements.count >= 2) {
                _restore(mark);
                var tuple = TypeName(ast.TUPLE_TYPE, Span(_start(start), close_end));
                tuple.generic_types = elements;
                if (any_label) {
                    tuple.labels = labels;
                }
                # `(int, String)[]` and `(int, String)?`. No `*`: a tuple has
                # no C layout to point at.
                return _optional_suffixes(_array_suffixes(tuple));
            }
            _fail("expected '=>'");
            return TypeName();
        }
        _advance();
        var result = _type_name();
        if (_failed) {
            return result;
        }
        var out = TypeName(name, Span(_start(start), result.span.end));
        out.generic_types.append(result);
        for (var element in elements) {
            out.generic_types.append(element);
        }
        return out;
    }

    # `[]` array suffixes after the type `out`, each extending its name.
    _array_suffixes(out: TypeName): TypeName {
        while (_at("[") and _peek_at(1).is(_source, "]")) {
            _advance();
            _advance();
            out.name = out.name + "[]";
            out.span = Span(out.span.start, _last_end());
        }
        return out;
    }

    # `?` optional suffixes after the type `out`, each wrapping it.
    _optional_suffixes(out: TypeName): TypeName {
        while (_at("?") and (!_probing or _optional_suffix_in_probe())) {
            if (!_wrap()) {
                return out;
            }
            _advance();
            var wrapped = TypeName(ast.OPTIONAL_TYPE, Span(out.span.start, _last_end()));
            wrapped.generic_types.append(out);
            out = wrapped;
        }
        return out;
    }

    # A name, qualified by `.name`s written directly after it, then generic
    # arguments. Sets `_type_qualified`, `_type_generic` and
    # `_type_last_name` for it.
    _type_base(): TypeName {
        if (!_at_name()) {
            _fail("expected a type");
            return TypeName();
        }
        ulong first = _position;
        _advance();
        _qualified_tail(first);
        ulong last_name = _position - 1;
        var out = TypeName(_dotted_name(first, _position), Span(_start(first), _last_end()));
        bool generic = false;
        if (_at("<")) {
            out.generic_types = _type_arguments();
            generic = true;
            if (!_failed) {
                out.span = Span(out.span.start, _last_end());
            }
        }
        _type_qualified = last_name > first;
        _type_generic = generic;
        _type_last_name = last_name;
        return out;
    }

    # `.name` segments after the name at `first`: always in a declaration,
    # and while probing only after an import's qualifier.
    _qualified_tail(first: ulong) {
        if (_probing and !_qualifiers.contains(_text(first))) {
            return;
        }
        while (_at(".")
            and _adjacent(0)
            and _adjacent(1)
            and _peek_at(1).kind == TokenKind.Identifier
            and !is_reserved_word(_source, _peek_at(1))) {
            _advance();
            _advance();
        }
    }

    # `<...>`: the type arguments, without the constraints an `extend`
    # target restates after `:`, which `_restated_bounds` gets.
    _type_arguments(): TypeName[] {
        bool restating = _restating;
        _restating = false;
        var out = Array<TypeName>();
        var bounds = Array<TypeName[]>();
        bool restated = false;
        _advance();
        while (true) {
            if (_peek_at(0).kind == TokenKind.Number) {
                # A lane count, `16` in `__simd<byte, 16>`.
                out.append(TypeName(_text(_position), _token_span(_position)));
                _advance();
            } else {
                out.append(_type_name());
            }
            if (_failed) {
                return out;
            }
            var current = Array<TypeName>();
            if (restating and _at(":")) {
                restated = true;
                _advance();
                current.append(_type_name());
                while (!_failed and _at("&")) {
                    _advance();
                    current.append(_type_name());
                }
                if (_failed) {
                    return out;
                }
            }
            bounds.append(current);
            if (_at(",")) {
                _advance();
                continue;
            }
            if (_at(">")) {
                _advance();
                if (restating and _type_depth == 1) {
                    _restated = restated;
                    _restated_bounds = bounds;
                }
                return out;
            }
            _fail("expected '>'");
            return out;
        }
        return out;
    }

    # A type where an expression could also start.
    _probe_type(): TypeName {
        bool outer = _probing;
        _probing = true;
        var out = _type_name();
        _probing = outer;
        return out;
    }

    # ── Expressions ──────────────────────────────────────────────────────

    _expression(): Expression {
        if (!_enter()) {
            return _nothing();
        }
        var out = _assignment();
        _leave();
        return out;
    }

    _assignment(): Expression {
        var lhs = _ternary();
        if (_failed) {
            return lhs;
        }
        var op = _operator_size();
        if (op > 0
            and (_operator_is(op, "*=")
                or _operator_is(op, "/=")
                or _operator_is(op, "%=")
                or _operator_is(op, "+=")
                or _operator_is(op, "-=")
                or _operator_is(op, "<<=")
                or _operator_is(op, ">>=")
                or _operator_is(op, "&=")
                or _operator_is(op, "^=")
                or _operator_is(op, "|=")
                or _operator_is(op, "="))) {
            ulong op_start = _start(_position);
            var text = _operator_text(op);
            _take_operator(op);
            # Through `_expression`, a level deeper: `a = b = c` nests.
            var rhs = _expression();
            if (_failed) {
                return rhs;
            }
            return Expression.Binary(lhs, text, rhs, Span(op_start, _last_end()));
        }
        return lhs;
    }

    _ternary(): Expression {
        var condition = _logical_or();
        if (_failed) {
            return condition;
        }
        if (!_at("?")) {
            return condition;
        }
        _advance();
        var true_value = _expression();
        if (_failed) {
            return true_value;
        }
        _expect(":");
        if (_failed) {
            return true_value;
        }
        var false_value = _expression();
        if (_failed) {
            return false_value;
        }
        return Expression.Ternary(
            condition, true_value, false_value, Span(desugar.desugared_span(condition).start, _last_end())
        );
    }

    # The byte length of the binary operator at the input for precedence
    # `level` (1 is `||`, 9 is `*`), or 0 when there is none.
    _binary_operator(level: int): ulong {
        var op = _operator_size();
        if (level == 1) {
            if (_operator_is(op, "||") or _at_word("or")) {
                return _operator_size_or_word(op);
            }
        } else if (level == 2) {
            if (_operator_is(op, "&&") or _at_word("and")) {
                return _operator_size_or_word(op);
            }
        } else if (level == 3) {
            if (_operator_is(op, "|") or _operator_is(op, "^")) {
                return op;
            }
        } else if (level == 4) {
            if (_operator_is(op, "&")) {
                return op;
            }
        } else if (level == 5) {
            if (_operator_is(op, "===")
                or _operator_is(op, "!==")
                or _operator_is(op, "==")
                or _operator_is(op, "!=")) {
                return op;
            }
        } else if (level == 6) {
            if (_operator_is(op, "<=") or _operator_is(op, ">=") or _operator_is(op, "<") or _operator_is(op, ">")) {
                return op;
            }
        } else if (level == 7) {
            if (_operator_is(op, "<<") or _operator_is(op, ">>")) {
                return op;
            }
        } else if (level == 8) {
            if (_operator_is(op, "+") or _operator_is(op, "-")) {
                return op;
            }
        } else if (level == 9) {
            if (_operator_is(op, "*") or _operator_is(op, "/") or _operator_is(op, "%")) {
                return op;
            }
        }
        return 0;
    }

    # `op`, or for a word operator (`and`, `or`), the word's length.
    _operator_size_or_word(op: ulong): ulong {
        if (op > 0) {
            return op;
        }
        return _peek().size;
    }

    _binary_operand(level: int): Expression {
        if (level == 1) {
            return _binary_level(2);
        }
        if (level == 6) {
            return _is_test();
        }
        if (level < 9) {
            return _binary_level(level + 1);
        }
        return _prefix_increment();
    }

    # `a..b` or `a..>b`, between the shift and `is` levels. Not associative.
    _range(): Expression {
        var lhs = _binary_level(7);
        if (_failed or !(_at("..>") or _at(".."))) {
            return lhs;
        }
        ulong op = _position;
        _advance();
        var rhs = _binary_level(7);
        if (_failed) {
            return rhs;
        }
        return Expression.Binary(lhs, _text(op), rhs, Span(_start(op), _last_end()));
    }

    # `value is Pattern`, between the relational and shift levels. `is` is a
    # keyword only here, so it stays usable as a name.
    _is_test(): Expression {
        var value = _range();
        if (_failed or !_at_word("is")) {
            return value;
        }
        ulong keyword = _position;
        _advance();
        var tested = _pattern();
        if (_failed) {
            return value;
        }
        return Expression.Is(
            value, tested, _token_span(keyword), Span(desugar.desugared_span(value).start, tested.span.end)
        );
    }

    # A left-associative binary level, whose chain nests a level per
    # operator.
    _binary_level(level: int): Expression {
        var outer = _start_wrapping();
        var out = _binary_chain(level);
        _end_wrapping(outer);
        return out;
    }

    _binary_chain(level: int): Expression {
        var lhs = _binary_operand(level);
        if (_failed) {
            return lhs;
        }
        while (true) {
            var op = _binary_operator(level);
            if (op == 0) {
                break;
            }
            if (!_wrap()) {
                return lhs;
            }
            ulong op_start = _start(_position);
            var text = _operator_text(op);
            _take_operator(op);
            _level += 1;
            var rhs = _binary_operand(level);
            _level -= 1;
            if (_failed) {
                return rhs;
            }
            lhs = Expression.Binary(lhs, text, rhs, Span(op_start, _last_end()));
        }
        return lhs;
    }

    _logical_or(): Expression {
        return _binary_level(1);
    }

    # Prefix `++` and `--`.
    _prefix_increment(): Expression {
        if (_at("++") or _at("--")) {
            ulong op = _position;
            _advance();
            var operand = _unary();
            if (_failed) {
                return operand;
            }
            return Expression.Unary(_text(op), true, operand, Span(_start(op), _last_end()));
        }
        return _unary();
    }

    # Prefix `+`, `-`, `~` and `!`.
    _unary(): Expression {
        if (_at("+") or _at("-") or _at("~") or _at("!")) {
            ulong op = _position;
            _advance();
            # The operand may itself be prefixed: `!!x` is `!(!x)`.
            if (!_enter()) {
                return _nothing();
            }
            var operand = _unary();
            _leave();
            if (_failed) {
                return operand;
            }
            if (_position == op + 2 and _text(op) == "-") {
                if (operand is Literal(value, _)) {
                    return _negative(op, value);
                }
            }
            return Expression.Unary(_text(op), true, operand, Span(_start(op), _last_end()));
        }
        return _cast();
    }

    # The `-` at `minus` and `value`, the number literal after it: their
    # `Unary`, or for a value past `long`'s range one literal with the
    # sign, which only `long`'s minimum fits.
    _negative(minus: ulong, value: Literal): Expression {
        var number = _token_span(minus + 1);
        var whole = Span(_start(minus), number.end);
        if (value is Unsigned(_)) {
            return Expression.Literal(_number("-" + _text(minus + 1), whole, true), whole);
        }
        return Expression.Unary("-", true, Expression.Literal(value, number), whole);
    }

    _cast(): Expression {
        var operand = _power();
        if (_failed) {
            return operand;
        }
        if (_at_word("as")) {
            var keyword = _token_span(_position);
            _advance();
            # `as?`: a trait value's conversion that may fail.
            bool optional = false;
            if (_at("?") and _adjacent(0)) {
                _advance();
                optional = true;
                keyword = Span(keyword.start, keyword.end + 1);
            }
            var cast_type = _type_name();
            if (_failed) {
                return operand;
            }
            return Expression.Cast(
                operand, cast_type, Span(desugar.desugared_span(operand).start, _last_end()), keyword, optional
            );
        }
        return operand;
    }

    # `**`, right-associative. A `-1` written as one operand is one
    # literal.
    _power(): Expression {
        var base = _postfix();
        if (_failed) {
            return base;
        }
        base = _fold_negative(base);
        if (_at("**")) {
            ulong op = _position;
            _advance();
            if (!_enter()) {
                return base;
            }
            var exponent = _power();
            _leave();
            if (_failed) {
                return exponent;
            }
            return Expression.Binary(base, "**", exponent, Span(_start(op), _last_end()));
        }
        return base;
    }

    # `e`, or when `e` is the `-1` that `_primary` just read, the one
    # literal it stands for where it is a pattern or an operand of `**`.
    _fold_negative(e: Expression): Expression {
        if (_negative_end != _position) {
            return e;
        }
        _negative_end = 0xFFFFFFFFFFFFFFFF;
        ulong minus = _position - 2;
        if (e is Unary(op, prefix, operand, span)) {
            if (op == "-" and prefix and span.start == _start(minus) and operand is Literal(_, _)) {
                # Decoded with its sign, as one literal.
                if (_problems.count > _negative_problems) {
                    _problems.truncate(_negative_problems);
                }
                var whole = Span(_start(minus), _last_end());
                return Expression.Literal(_number("-" + _text(minus + 1), whole, true), whole);
            }
        }
        return e;
    }

    # An atom and its postfix chain, which nests a level per member,
    # call, index or postfix operator.
    _postfix(): Expression {
        var outer = _start_wrapping();
        var out = _postfix_chain();
        _end_wrapping(outer);
        return out;
    }

    _postfix_chain(): Expression {
        ulong start = _position;
        var operand = _atom();
        var callee = Callee.Other;
        if (_position == start + 1) {
            if (_tokens[start].spells(_source, "print")) {
                callee = Callee.Print;
            } else if (_tokens[start].spells(_source, "String")) {
                callee = Callee.StringName;
            }
        }
        while (!_failed) {
            if (_at(".")) {
                if (!_wrap()) {
                    return operand;
                }
                _advance();
                # A tuple element, `t.0`.
                if (_peek().kind == TokenKind.Number) {
                    var element = _token_span(_position);
                    var text = _text(_position);
                    _advance();
                    operand = Expression.MemberAccess(
                        operand, text, element, Span(desugar.desugared_span(operand).start, element.end)
                    );
                    callee = Callee.Other;
                    continue;
                }
                _expect_name("member name");
                if (_failed) {
                    return operand;
                }
                ulong name_index = _position - 1;
                var name = _text(name_index);
                var name_span = _token_span(name_index);
                ulong member_end = name_span.end;
                bool has_arguments = false;
                # `x.map<long>(f)`: type arguments written right after the
                # name, with `(` right after the `>`; or `x.map<long>` as a
                # value, the expression ending after the `>`.
                if (_at("<") and _adjacent(0)) {
                    var mark = _mark();
                    # Below the new node, as the operands of a call and an
                    # index are.
                    _level += 1;
                    var arguments = _type_arguments();
                    _level -= 1;
                    var ends = _at(";")
                        or _at(",")
                        or _at(")")
                        or _at("]")
                        or _at("}")
                        or _peek().kind == TokenKind.End;
                    if (!_failed and ((_at("(") and _adjacent(0)) or ends)) {
                        var generic = TypeName(name, name_span);
                        generic.generic_types = arguments;
                        name = generic.to_string();
                        member_end = _last_end();
                        has_arguments = true;
                    } else {
                        _restore(mark);
                    }
                }
                bool format = callee == Callee.StringName
                    and !has_arguments
                    and _tokens[name_index].spells(_source, "format");
                operand = Expression.MemberAccess(
                    operand, name, name_span, Span(desugar.desugared_span(operand).start, member_end)
                );
                callee = format ? Callee.StringFormat : Callee.Other;
                continue;
            }
            if (_at("[")) {
                if (!_wrap()) {
                    return operand;
                }
                _advance();
                _level += 1;
                var index = _expression();
                _level -= 1;
                if (_failed) {
                    return index;
                }
                _expect("]");
                operand = Expression.Index(operand, index, Span(desugar.desugared_span(operand).start, _last_end()));
                callee = Callee.Other;
                continue;
            }
            if (_at("(")) {
                if (!_wrap()) {
                    return operand;
                }
                _level += 1;
                var arguments = _arguments();
                _level -= 1;
                operand = _call(operand, callee, arguments);
                callee = Callee.Other;
                continue;
            }
            if (_at("++") or _at("--") or (_at("?") and _propagates())) {
                if (!_wrap()) {
                    return operand;
                }
                var op = _text(_position);
                _advance();
                operand = Expression.Unary(
                    op, false, operand, Span(desugar.desugared_span(operand).start, _last_end())
                );
                callee = Callee.Other;
                continue;
            }
            break;
        }
        return operand;
    }

    # Whether the `?` at the current token is the postfix propagation
    # operator (`f()?`) rather than the start of a ternary's branches. It is
    # when what follows cannot start an expression, not when an operand
    # follows, and, when the next token could do either (`-`, `*`, `(`,
    # ...), unless an expression and a `:` follow.
    _propagates(): bool {
        var next = _peek_at(1);
        if (next.kind == TokenKind.End) {
            return true;
        }
        if (next.kind == TokenKind.Identifier) {
            return next.is_word(_source, "and")
                or next.is_word(_source, "or")
                or next.is_word(_source, "is")
                or next.is_word(_source, "as");
        }
        if (next.kind != TokenKind.Punctuation) {
            return false;
        }
        if (next.spells(_source, "&&") or next.spells(_source, "!=")) {
            return true;
        }
        int first = _source.byte_at(next.offset);
        if (!(first == '-'
            or first == '+'
            or first == '*'
            or first == '&'
            or first == '!'
            or next.spells(_source, "(")
            or next.spells(_source, "["))) {
            return true;
        }
        # Probe for `? expression :`, leaving no error behind.
        var mark = _mark();
        var error = _error;
        var final_error = _final_error;
        var too_deep = _too_deep;
        _advance();
        _expression();
        bool ternary = !_failed and _at(":");
        _restore(mark);
        _error = error;
        _final_error = final_error;
        _too_deep = too_deep;
        return !ternary;
    }

    _arguments(): ArgumentList {
        var out = ArgumentList();
        out.open = _position;
        _advance();
        out.problems_before = _problems.count;
        out.problems_after_first = _problems.count;
        if (!_at(")")) {
            while (true) {
                ulong first = _position;
                var value = _expression();
                out.values.append(value);
                out.starts.append(first);
                out.ends.append(_position);
                if (out.values.count == 1) {
                    out.problems_after_first = _problems.count;
                }
                if (_failed) {
                    return out;
                }
                if (_at(",")) {
                    _advance();
                    continue;
                }
                break;
            }
        }
        _expect(")");
        return out;
    }

    # A call of `function`. `print("{0}", x)` and `String.format("{0}", x)`
    # take their format as an `Expression.FormatString`, which `parse`
    # lowers; any other call's `name = value`
    # arguments are named.
    _call(function: Expression, callee: Callee, arguments: ArgumentList): Expression {
        if (_failed) {
            return function;
        }
        var span = Span(desugar.desugared_span(function).start, _last_end());
        if (arguments.values.count > 0 and callee != Callee.Other) {
            ulong first = arguments.starts[0];
            var token = _tokens[first];
            bool literal = arguments.ends[0] == first + 1
                and token.kind == TokenKind.String
                and _source.byte_at(token.offset) != '$';
            if (callee == Callee.Print and literal and _tokens[arguments.ends[0]].is(_source, ",")) {
                return _format_call(function, arguments, span);
            }
            if (callee == Callee.StringFormat) {
                if (literal) {
                    return _format_call(function, arguments, span);
                }
                # Reported before any error in the argument itself.
                _insert_problem(
                    arguments.problems_before,
                    ParseError(
                        "the format of 'String.format' must be a string literal",
                        Span(_start(first), _end_of(arguments.ends[0] - 1))
                    )
                );
            }
        }
        var values = Array<Expression>();
        ulong i = 0;
        while (i < arguments.values.count) {
            values.append(_named_argument(arguments.values[i], arguments.starts[i]));
            i += 1;
        }
        return Expression.FunctionCall(function, values, span);
    }

    # An argument whose first token is at `first`; `name = value` is a
    # named one.
    _named_argument(value: Expression, first: ulong): Expression {
        if (_tokens[first].kind != TokenKind.Identifier) {
            return value;
        }
        if (value is Binary(lhs, op, rhs, _)) {
            if (op != "=") {
                return value;
            }
            var name_span = _token_span(first);
            var lhs_span = desugar.desugared_span(lhs);
            if (lhs_span.start == name_span.start and lhs_span.end == name_span.end) {
                return Expression.NamedArgument(
                    _text(first), name_span, rhs, Span(name_span.start, desugar.desugared_span(rhs).end)
                );
            }
        }
        return value;
    }

    # `_problems` with `problem` put at `index`.
    _insert_problem(index: ulong, problem: ParseError) {
        _problems.append(problem);
        move_after(_problems, index, _problems.count - 1);
    }

    # A `print` or `String.format` call whose first argument is a string
    # literal: the format, its text and the arguments it names in braces,
    # then the arguments after it.
    _format_call(function: Expression, arguments: ArgumentList, span: Span): Expression {
        ulong format = arguments.starts[0];
        # The format's own problems are those its text has as a format.
        var later = Array<ParseError>();
        ulong i = arguments.problems_after_first;
        while (i < _problems.count) {
            later.append(_problems[i]);
            i += 1;
        }
        _problems.truncate(arguments.problems_before);
        var parts = _layout_only ? Array<StringPart>() : _format_parts(format);
        for (var problem in later) {
            _problems.append(problem);
        }
        var value_spans = Array<Span>();
        var values = Array<Expression>();
        values.append(Expression.FormatString(parts, _token_span(format), _start(arguments.open), value_spans));
        i = 1;
        while (i < arguments.values.count) {
            values.append(arguments.values[i]);
            value_spans.append(Span(_start(arguments.starts[i]), _end_of(arguments.ends[i] - 1)));
            i += 1;
        }
        if (!desugared) {
            return Expression.FunctionCall(function, values, span);
        }
        var lowered = desugar.desugar_format_call(function, values, span);
        if (lowered.is_err()) {
            _problem(lowered.error().message, lowered.error().span);
            return Expression.Literal(Literal.Null, span);
        }
        return lowered.value();
    }

    _atom(): Expression {
        if (_at("(")) {
            var mark = _mark();
            var closure = _closure_literal();
            if (!_failed) {
                return closure;
            }
            _restore(mark);
            ulong open = _position;
            _advance();
            var elements = Array<Expression>();
            var labels = Array<Label>();
            # `(line: 3, column: 7)`: a label makes it a tuple literal.
            bool labeled = _at_tuple_label();
            bool tuple = labeled;
            _tuple_element(labeled, elements, labels);
            if (_failed) {
                return closure;
            }
            # `(a, b)`: a comma makes it a tuple literal.
            if (_at(",")) {
                tuple = true;
                while (_at(",")) {
                    _advance();
                    _tuple_element(labeled, elements, labels);
                    if (_failed) {
                        return closure;
                    }
                }
            } else if (labeled) {
                _fail("expected ','");
                return closure;
            }
            _expect(")");
            if (_failed) {
                return closure;
            }
            var span = Span(_start(open), _last_end());
            if (tuple) {
                return Expression.Tuple(elements, labels, span);
            }
            if (desugared) {
                return elements[0];
            }
            return Expression.Parenthesized(elements[0], span);
        }
        if (_at("[")) {
            return _collection_literal();
        }
        return _primary();
    }

    # `[a, b]`, an array literal, or `[k: v]` / `[:]`, a map literal: a `:`
    # after the first element makes it a map.
    _collection_literal(): Expression {
        ulong open = _position;
        _advance();
        var entries = Array<MapEntry>();
        if (_at(":")) {
            _advance();
            _expect("]");
            return Expression.MapLiteral(entries, Span(_start(open), _last_end()));
        }
        var elements = Array<Expression>();
        bool map = false;
        bool first = true;
        while (!_at("]")) {
            var item = _expression();
            if (_failed) {
                return item;
            }
            if (first and _at(":")) {
                map = true;
            }
            first = false;
            if (map) {
                _expect(":");
                if (_failed) {
                    return item;
                }
                var value = _expression();
                entries.append(MapEntry(item, value));
                if (_failed) {
                    return item;
                }
            } else {
                elements.append(item);
            }
            if (!_at(",")) {
                break;
            }
            _advance();
        }
        _expect("]");
        var span = Span(_start(open), _last_end());
        if (map) {
            return Expression.MapLiteral(entries, span);
        }
        return Expression.ArrayLiteral(elements, span);
    }

    _at_tuple_label(): bool {
        return _at_name() and _peek_at(1).is(_source, ":");
    }

    # One element of a tuple literal: `label: expression` when `labeled`,
    # else an expression alone.
    _tuple_element(labeled: bool, elements: Expression[], labels: Label[]) {
        if (!labeled) {
            elements.append(_expression());
            return;
        }
        if (!_at_tuple_label()) {
            _fail("expected a label ('name: value'), as the first element has one");
            return;
        }
        labels.append(Label(_text(_position), _token_span(_position)));
        _advance();
        _advance();
        elements.append(_expression());
    }

    _primary(): Expression {
        var token = _peek();
        if (token.is_word(_source, "match")) {
            return _match_expression();
        }
        if (token.is_word(_source, "true")
            or token.is_word(_source, "false")
            or token.is_word(_source, "__null")
            or token.kind == TokenKind.Number
            or token.kind == TokenKind.String
            or token.kind == TokenKind.Character) {
            ulong index = _position;
            _advance();
            return _token_expression(index);
        }
        # A `-` written directly before a number is part of the literal.
        if (token.is(_source, "-") and _peek_at(1).kind == TokenKind.Number and _adjacent(1)) {
            ulong minus = _position;
            _advance();
            _advance();
            _negative_problems = _problems.count;
            _negative_end = _position;
            return _negative(minus, _number(_text(minus + 1), _token_span(minus + 1), false));
        }
        if (token.is_word(_source, "sizeof")) {
            _advance();
            _expect("<");
            if (_failed) {
                return _nothing();
            }
            var measured = _type_name();
            if (_failed) {
                return _nothing();
            }
            _expect(">");
            if (_failed) {
                return _nothing();
            }
            if (_at("(")) {
                _advance();
                _expect(")");
            }
            return Expression.SizeOf(measured);
        }
        if (!_at_name()) {
            _fail("expected expression");
            return _nothing();
        }
        var mark = _mark();
        ulong name = _position;
        # `m.Box<int>()`: a generic type of an imported module.
        if (_peek_at(1).is(_source, ".") and _adjacent(1) and _qualifiers.contains(token.text(_source))) {
            var probe = _probe_type();
            if (!_failed and _type_qualified and _type_generic and (_at("(") or _at("."))) {
                return Expression.TypeLiteral(probe);
            }
            _restore(mark);
        }
        _advance();
        if (_at("<")) {
            var after = _mark();
            _restore(mark);
            var probe = _probe_type();
            if (!_failed) {
                return Expression.TypeLiteral(probe);
            }
            _restore(after);
        }
        return _token_expression(name);
    }

    # A stand-in for the node a failed reading would have built: one per
    # parser, since an expression is a large allocation and a failed
    # reading (a `(` tried as a closure first) is common.
    _nothing(): Expression {
        if (_placeholder === __null) {
            _placeholder = Expression.Literal(Literal.Null, Span());
        }
        return _placeholder;
    }

    # The expression a lone token is.
    _token_expression(index: ulong): Expression {
        var token = _tokens[index];
        var span = _token_span(index);
        match (token.kind) {
            Number => {
                return Expression.Literal(_number(_text(index), span, false), span);
            }
            String => {
                if (_source.byte_at(token.offset) == '$') {
                    return _interpolated_string(index);
                }
                if (_layout_only) {
                    return Expression.Literal(Literal.String(""), span);
                }
                return Expression.Literal(Literal.String(_string_text(index)), span);
            }
            Character => {
                return Expression.Literal(_character(index), span);
            }
            Identifier => {
                if (token.spells(_source, "true")) {
                    return Expression.Literal(Literal.Bool(true), span);
                }
                if (token.spells(_source, "false")) {
                    return Expression.Literal(Literal.Bool(false), span);
                }
                if (token.spells(_source, "__null")) {
                    return Expression.Literal(Literal.Null, span);
                }
                return Expression.SymbolRef(_text(index), span);
            }
            else => {}
        }
        _problem($"unexpected '{_text(index)}'", span);
        return Expression.Literal(Literal.Null, span);
    }

    _closure_literal(): Expression {
        ulong open = _position;
        var out = ast.ClosureLiteral();
        _advance();
        while (true) {
            if (_at(")")) {
                _advance();
                break;
            }
            if (!_at_name()) {
                _fail("expected parameter name");
                return _nothing();
            }
            ulong name = _position;
            _advance();
            var parameter = VariableDecl(_text(name));
            parameter.name_span = _token_span(name);
            if (_at(":")) {
                _advance();
                parameter.type_name = _type_name();
                if (_failed) {
                    return _nothing();
                }
            }
            parameter.span = Span(parameter.name_span.start, _after());
            out.parameters.append(parameter);
            if (_at(",")) {
                _advance();
                continue;
            }
            if (_at(")")) {
                _advance();
                break;
            }
            _fail("expected ')'");
            return _nothing();
        }
        if (_at(":")) {
            _advance();
            out.return_type = _type_name();
            if (_failed) {
                return _nothing();
            }
        }
        if (!_at("=>")) {
            _fail("expected '=>'");
            return _nothing();
        }
        _advance();
        if (_at("{")) {
            out.body = _block(Array<Attribute>());
        } else {
            var value = _expression();
            var span = desugar.desugared_span(value);
            var wrapper = Block(span);
            wrapper.statements.append(Statement.Return(Optional<Expression>.Value(value), span));
            out.body = wrapper;
            out.expression_body = true;
        }
        if (_failed) {
            return _nothing();
        }
        out.span = Span(_start(open), _last_end());
        return Expression.Closure(out);
    }

    # ── Statements ───────────────────────────────────────────────────────

    _attributes(): Attribute[] {
        var list = Array<Attribute>();
        # `[]` starts a Pepper-style indexer (`[](index: ulong): T`).
        while (_at("[") and !_peek_at(1).is(_source, "]")) {
            ulong open = _position;
            _advance();
            var body = _expression();
            if (_failed) {
                return list;
            }
            _expect("]");
            if (_failed) {
                return list;
            }
            list.append(_attribute(body, Span(_start(open), _last_end())));
        }
        return list;
    }

    # `{ statement... }`, after the attributes `attributes` when the block
    # has any, a level deeper.
    _block(attributes: Attribute[]): Block {
        if (!_enter()) {
            return Block();
        }
        var out = _block_at_depth(attributes);
        _leave();
        return out;
    }

    _block_at_depth(attributes: Attribute[]): Block {
        var out = Block();
        out.attributes = attributes;
        ulong open = _position;
        _expect("{");
        if (_failed) {
            return out;
        }
        if (_recovering) {
            _recovering_statements(out, open);
            return out;
        }
        while (true) {
            if (_at("}") or _at_end()) {
                break;
            }
            if (_at(";")) {
                _advance();
                continue;
            }
            var statement = _statement();
            if (_failed) {
                return out;
            }
            if (ends_in_semicolon(statement)) {
                _finish_statement();
            }
            out.statements.append(statement);
        }
        _expect("}");
        if (_failed) {
            return out;
        }
        out.span = Span(attributes.count > 0 ? attributes[0].span.start : _start(open), _last_end());
        return out;
    }

    # `_block`'s statements and `}` for `parse_recovering`, into `out`, after
    # the `{` at `open`: a broken statement is noted and skipped.
    _recovering_statements(out: Block, open: ulong) {
        var attributes = out.attributes;
        # Whether a statement of the block failed.
        bool broken = false;
        while (true) {
            if (_at("}") or _at_end()) {
                # After an error, a `}` indented deeper than the `{` line is
                # one whose `{` the error cut off.
                if (broken and _at("}") and !_closes(open)) {
                    _advance();
                    continue;
                }
                break;
            }
            if (_at(";")) {
                _advance();
                continue;
            }
            var item = _mark();
            var statement = _statement();
            if (_failed) {
                # A statement indented no deeper than the `{` line, such as
                # the next function's header: the `}` is missing before it.
                if (_dedented(item.position, open)) {
                    _restore(item);
                    _clear_error();
                    _unclosed(open, item.position);
                    out.span = Span(attributes.count > 0 ? attributes[0].span.start : _start(open), _last_end());
                    return;
                }
                _skip_failed(item, open);
                broken = true;
                continue;
            }
            if (ends_in_semicolon(statement)) {
                _finish_statement();
                if (_failed) {
                    if (_dedented(item.position, open)) {
                        _restore(item);
                        _clear_error();
                        _unclosed(open, item.position);
                        out.span = Span(attributes.count > 0 ? attributes[0].span.start : _start(open), _last_end());
                        return;
                    }
                    _record(item.position, _failure());
                }
            }
            out.statements.append(statement);
        }
        if (_at_end()) {
            _unclosed(open, _position);
            out.span = Span(attributes.count > 0 ? attributes[0].span.start : _start(open), _last_end());
            return;
        }
        _expect("}");
        if (_failed) {
            return;
        }
        _note_close(open);
        out.span = Span(attributes.count > 0 ? attributes[0].span.start : _start(open), _last_end());
    }

    # A stand-in for the statement a failed reading would have built.
    _no_statement(): Statement {
        return Statement.Block(Block());
    }

    _statement(): Statement {
        if (_at("[")) {
            var list = _attributes();
            if (_failed) {
                return _no_statement();
            }
            # `[Likely]` or `[Unlikely]` above an `if`.
            if (_at_word("if")) {
                return _if_statement(list);
            }
            return Statement.Block(_block(list));
        }
        if (_at("{")) {
            return Statement.Block(_block(Array<Attribute>()));
        }
        if (_at_word("if")) {
            return _if_statement(Array<Attribute>());
        }
        if (_at_word("while")) {
            ulong keyword = _position;
            _advance();
            var condition = _expression();
            if (_failed) {
                return _no_statement();
            }
            var body = _block(Array<Attribute>());
            return Statement.While(condition, body, Span(_start(keyword), body.span.end));
        }
        if (_at_word("for")) {
            return _for_statement();
        }
        if (_at_word("with")) {
            return _with_statement();
        }
        if (_at_word("static") and (_peek_at(1).is(_source, "(") or _peek_at(1).is(_source, "{"))) {
            return Statement.Static(_static_block());
        }
        if (_at_word("match")) {
            return _match_statement();
        }
        if (_at_word("return")) {
            var keyword = _token_span(_position);
            _advance();
            if (!_at(";") and !_at("}")) {
                var value = _expression();
                return Statement.Return(
                    Optional<Expression>.Value(value), Span(keyword.start, desugar.desugared_span(value).end)
                );
            }
            return Statement.Return(Optional<Expression>.Empty, keyword);
        }
        if (_at_word("break") or _at_word("continue")) {
            bool is_continue = _at_word("continue");
            var keyword = _token_span(_position);
            _advance();
            return Statement.LoopBreak(is_continue, keyword);
        }
        if ((_at_word("var") or _at_word("const")) and _peek_at(1).is(_source, "(")) {
            return _destructure();
        }
        var token = _peek();
        # A `(` may start a tuple type (`(String, int)[] a = ...;`) or an
        # expression (`(a, b) = (b, a);`): the declaration is tried first.
        bool declaration = token.is(_source, "(")
            or token.is_word(_source, "var")
            or token.is_word(_source, "const")
            or (token.is_word(_source, "extern") and _peek_at(1).is(_source, "("))
            or (token.kind == TokenKind.Identifier and !is_statement_keyword(_source, token));
        if (declaration) {
            var mark = _mark();
            var variable = _variable_declaration(Prefix(Array<Attribute>()));
            if (!_failed and _declaration_boundary()) {
                _bind_qualifier(variable.name);
                return Statement.Declaration(Declaration.Variable(variable));
            }
            _restore(mark);
        }
        return Statement.Expression(_expression());
    }

    # Inside a `static` block, makes the name a `var` or `for` binds a
    # qualifier.
    _bind_qualifier(name: String) {
        if (_static_depth > 0) {
            _qualifiers.insert(name);
        }
        if (_lowered_static_depth > 0) {
            _lowered_names.append(name);
        }
    }

    _if_statement(attributes: Attribute[]): Statement {
        ulong keyword = _position;
        _advance();
        var condition = _expression();
        if (_failed) {
            return _no_statement();
        }
        var if_block = _block(Array<Attribute>());
        if (_failed) {
            return _no_statement();
        }
        Block? else_block;
        ulong end = if_block.span.end;
        if (_at_word("else")) {
            _advance();
            # `else [Unlikely] if`.
            var list = _attributes();
            if (_failed) {
                return _no_statement();
            }
            if (_at_word("if") or list.count > 0) {
                # A level deeper, as the block it stands for.
                if (!_enter()) {
                    return _no_statement();
                }
                var inner = _if_statement(list);
                _leave();
                if (_failed) {
                    return _no_statement();
                }
                if (inner is Branch(_, _, _, inner_span)) {
                    var wrapper = Block(inner_span);
                    wrapper.statements.append(inner);
                    else_block = Optional<Block>.Value(wrapper);
                    end = inner_span.end;
                }
            } else {
                var other = _block(Array<Attribute>());
                if (_failed) {
                    return _no_statement();
                }
                else_block = Optional<Block>.Value(other);
                end = other.span.end;
            }
        }
        ulong branch_start = _start(keyword);
        if (attributes.count > 0) {
            branch_start = attributes[0].span.start;
            if_block.attributes = attributes;
        }
        return Statement.Branch(condition, if_block, else_block, Span(branch_start, end));
    }

    _for_statement(): Statement {
        ulong keyword = _position;
        _advance();
        bool parenthesized = _at("(");
        if (parenthesized) {
            _advance();
        }
        VariableDecl binding;
        var pattern = Array<DestructureBinding>();
        if (_at_word("var") and _peek_at(1).is(_source, "(")) {
            # `for (var (k, v) in pairs)`: a pattern.
            ulong header = _position;
            _advance();
            pattern = _binding_pattern();
            binding = VariableDecl("");
            if (!_failed) {
                var span = Span(_start(header), _last_end());
                binding.name_span = span;
                binding.span = span;
            }
        } else {
            binding = _variable_declaration(Prefix(Array<Attribute>()));
            if (!_failed) {
                _bind_qualifier(binding.name);
            }
        }
        if (_failed) {
            return _no_statement();
        }
        if (!_at_word("in")) {
            _fail("expected 'in'");
            return _no_statement();
        }
        _advance();
        var iterable = _expression();
        if (_failed) {
            return _no_statement();
        }
        if (parenthesized) {
            _expect(")");
            if (_failed) {
                return _no_statement();
            }
        }
        var body = _block(Array<Attribute>());
        return Statement.For(binding, pattern, iterable, body, Span(_start(keyword), body.span.end));
    }

    # `static [(captures)] { ... }`.
    _static_block(): StaticBlock {
        var out = StaticBlock();
        out.keyword_span = _token_span(_position);
        _advance();
        if (_at("(")) {
            # The captures are names; the compiler builds no expression for
            # them.
            var lowering = _mark();
            var arguments = _arguments();
            _discard_lowering(lowering);
            if (_failed) {
                return out;
            }
            if (!desugared) {
                out.written_captures = arguments.values;
            }
            ulong i = 0;
            while (i < arguments.values.count) {
                ulong first = arguments.starts[i];
                if (arguments.ends[i] == first + 1 and _tokens[first].kind == TokenKind.Identifier) {
                    out.captures.append(Label(_text(first), _token_span(first)));
                }
                i += 1;
            }
        }
        # The names the block binds qualify types only inside it.
        var outer = HashSet<String>();
        for (var name in _qualifiers) {
            outer.insert(name);
        }
        ulong names = _lowered_names.count;
        _static_depth += 1;
        _lowered_static_depth += 1;
        out.block = _block(Array<Attribute>());
        _static_depth -= 1;
        _lowered_static_depth -= 1;
        _qualifiers = outer;
        if (_lowered_names.count > names) {
            _lowered_names.truncate(names);
        }
        out.span = Span(out.keyword_span.start, out.block.span.end);
        return out;
    }

    _with_statement(): Statement {
        ulong keyword = _position;
        _advance();
        bool parenthesized = _at("(");
        if (parenthesized) {
            _advance();
        }
        var mark = _mark();
        bool is_var = _at_word("var") or _at_word("const");
        var binding = _variable_declaration(Prefix(Array<Attribute>()));
        VariableDecl? bound;
        Expression scope;
        if (!_failed and binding.default_value.is_value() and !binding.is_const) {
            scope = binding.default_value.value();
            binding.default_value = Optional<Expression>.Empty;
            bound = Optional<VariableDecl>.Value(binding);
        } else if (is_var) {
            if (!_failed) {
                _fail("expected '='");
            }
            return _no_statement();
        } else {
            _restore(mark);
            scope = _expression();
            if (_failed) {
                return _no_statement();
            }
        }
        if (parenthesized) {
            _expect(")");
            if (_failed) {
                return _no_statement();
            }
        }
        var body = _block(Array<Attribute>());
        if (_failed) {
            return _no_statement();
        }
        Block? else_block;
        ulong end = body.span.end;
        if (_at_word("else")) {
            _advance();
            var other = _block(Array<Attribute>());
            if (_failed) {
                return _no_statement();
            }
            else_block = Optional<Block>.Value(other);
            end = other.span.end;
        }
        return Statement.With(bound, scope, body, else_block, Span(_start(keyword), end));
    }

    _match_statement(): Statement {
        ulong keyword = _position;
        _advance();
        var value = _expression();
        if (_failed) {
            return _no_statement();
        }
        var out = Match(value);
        out.keyword_span = _token_span(keyword);
        _expect("{");
        while (!_failed) {
            if (_at("}") or _at_end()) {
                break;
            }
            ulong arm_start = _position;
            # `[Likely]` or `[Unlikely]` above the arm.
            var attributes = _attributes();
            if (_failed) {
                return _no_statement();
            }
            bool is_else = false;
            var arm = MatchArm();
            if (_at_word("else")) {
                out.else_span = _token_span(_position);
                is_else = true;
                _advance();
            } else {
                arm.patterns.append(_pattern());
                while (!_failed and _at(",")) {
                    _advance();
                    arm.patterns.append(_pattern());
                }
                # A guard: `if condition`.
                if (!_failed and _at_word("if")) {
                    _advance();
                    arm.guard = Optional<Expression>.Value(_expression());
                }
            }
            if (_failed) {
                return _no_statement();
            }
            _expect("=>");
            if (_failed) {
                return _no_statement();
            }
            var body = _block(Array<Attribute>());
            if (_failed) {
                break;
            }
            body.attributes = attributes;
            if (is_else) {
                out.else_block = Optional<Block>.Value(body);
                continue;
            }
            arm.body = body;
            arm.span = Span(_start(arm_start), body.span.end);
            out.arms.append(arm);
        }
        if (_failed) {
            return _no_statement();
        }
        _expect("}");
        if (_failed) {
            return _no_statement();
        }
        out.span = Span(out.keyword_span.start, _last_end());
        return Statement.Match(out);
    }

    # A `match` that produces a value: `match (x) { A, B => 1, else => 0 }`.
    # Each arm is patterns, `=>`, a value, and a `,` (optional after the
    # last).
    _match_expression(): Expression {
        ulong keyword = _position;
        _advance();
        var value = _expression();
        if (_failed) {
            return _nothing();
        }
        var out = MatchExpression(value);
        out.keyword_span = _token_span(keyword);
        _expect("{");
        while (!_failed) {
            if (_at("}") or _at_end()) {
                break;
            }
            ulong arm_start = _position;
            bool is_else = false;
            var arm = MatchValueArm();
            if (_at_word("else")) {
                out.else_span = _token_span(_position);
                is_else = true;
                _advance();
            } else {
                arm.patterns.append(_pattern());
                while (!_failed and _at(",")) {
                    _advance();
                    arm.patterns.append(_pattern());
                }
                # A guard: `if condition`.
                if (!_failed and _at_word("if")) {
                    _advance();
                    arm.guard = Optional<Expression>.Value(_expression());
                }
            }
            if (_failed) {
                return _nothing();
            }
            _expect("=>");
            if (_failed) {
                return _nothing();
            }
            var arm_value = _expression();
            if (_failed) {
                return _nothing();
            }
            if (is_else) {
                out.else_value = Optional<Expression>.Value(arm_value);
            } else {
                arm.value = arm_value;
                arm.span = Span(_start(arm_start), desugar.desugared_span(arm_value).end);
                out.arms.append(arm);
            }
            if (_at(",")) {
                _advance();
            } else if (!_at("}")) {
                _expect("}");
                return _nothing();
            }
        }
        if (_failed) {
            return _nothing();
        }
        _expect("}");
        if (_failed) {
            return _nothing();
        }
        out.span = Span(out.keyword_span.start, _last_end());
        return Expression.Match(out);
    }

    # A case pattern: `Case`, `Enum.Case`, `module.Enum.Case`, or
    # `Case(x, _)`, whose values are patterns too (`Value(Text(t))`); a
    # literal: a number (`-1` too), string, character, `true` or `false`,
    # or a range of them (`1..9`); or a tuple pattern of two or more,
    # `(Case, x, 0)`. A level deeper.
    _pattern(): Pattern {
        if (!_enter()) {
            return Pattern();
        }
        var out = _pattern_at_depth();
        _leave();
        return out;
    }

    _pattern_at_depth(): Pattern {
        var out = Pattern();
        ulong start = _position;
        if (_at("(")) {
            _advance();
            var elements = Array<Pattern>();
            while (true) {
                elements.append(_pattern());
                if (_failed) {
                    return out;
                }
                if (_at(",")) {
                    _advance();
                    continue;
                }
                break;
            }
            if (elements.count < 2) {
                _fail("expected ','");
                return out;
            }
            _expect(")");
            if (_failed) {
                return out;
            }
            out.elements = Optional<Pattern[]>.Value(elements);
            out.span = Span(_start(start), _last_end());
            out.case_span = out.span;
            return out;
        }
        var token = _peek();
        if (token.is_word(_source, "true")
            or token.is_word(_source, "false")
            or token.kind == TokenKind.Number
            or token.kind == TokenKind.String
            or token.kind == TokenKind.Character
            or (token.is(_source, "-") and _peek_at(1).kind == TokenKind.Number and _adjacent(1))) {
            var literal = _fold_negative(_primary());
            out.literal = Optional<Expression>.Value(literal);
            var span = desugar.desugared_span(literal);
            if (!_failed and (_at("..") or _at("..>"))) {
                out.range_inclusive = _at("..>");
                _advance();
                var range_end = _unary();
                if (_failed) {
                    return out;
                }
                out.range_end = Optional<Expression>.Value(range_end);
                span = Span(span.start, desugar.desugared_span(range_end).end);
            }
            out.span = span;
            out.case_span = span;
            return out;
        }
        _expect_name("a case name");
        while (!_failed and _at(".") and _adjacent(0) and _peek_at(1).kind == TokenKind.Identifier and _adjacent(1)) {
            _advance();
            _advance();
        }
        if (_failed) {
            return out;
        }
        ulong last = _position - 1;
        ulong pattern_start = _start(start);
        if (_at("..") or _at("..>")) {
            # A range from a named constant: `MIN..MAX`.
            Expression low = Expression.SymbolRef(_text(start), _token_span(start));
            ulong segment = start + 2;
            # Each segment nests a level, as in an expression.
            var outer = _start_wrapping();
            while (segment <= last) {
                if (!_wrap()) {
                    return out;
                }
                var segment_span = _token_span(segment);
                low = Expression.MemberAccess(low, _text(segment), segment_span, Span(pattern_start, segment_span.end));
                segment += 2;
            }
            _end_wrapping(outer);
            out.literal = Optional<Expression>.Value(low);
            out.range_inclusive = _at("..>");
            _advance();
            var range_end = _unary();
            if (_failed) {
                return out;
            }
            out.range_end = Optional<Expression>.Value(range_end);
            out.span = Span(pattern_start, _last_end());
            out.case_span = out.span;
            return out;
        }
        var case_type = TypeName(_dotted_name(start, last + 1), Span(pattern_start, _end_of(last)));
        # A type pattern's type arguments, over a trait value: `Box<int>(b)`.
        if (_at("<") and _adjacent(0)) {
            case_type.generic_types = _type_arguments();
            if (_failed) {
                return out;
            }
            case_type.span = Span(pattern_start, _last_end());
        }
        out.case_name = _text(last);
        out.case_span = _token_span(last);
        if (last > start) {
            out.qualifier = Optional<TypeName>.Value(
                TypeName(_dotted_name(start, last - 1), Span(pattern_start, _end_of(last - 2)))
            );
        }
        out.type_name = Optional<TypeName>.Value(case_type);
        if (!_at("(")) {
            out.span = Span(pattern_start, _last_end());
            return out;
        }
        _advance();
        var bindings = Array<Pattern>();
        while (!_failed) {
            if (_at(")")) {
                break;
            }
            bindings.append(_pattern());
            if (_at(",")) {
                _advance();
                continue;
            }
            break;
        }
        _expect(")");
        if (_failed) {
            return out;
        }
        out.bindings = Optional<Pattern[]>.Value(bindings);
        out.span = Span(pattern_start, _last_end());
        return out;
    }

    # What may follow a `Type name` statement. After a line break it is one
    # whose `;` is missing, which `_finish_statement` then reports.
    _declaration_boundary(): bool {
        return _at_end() or _at(";") or _at("}") or _peek().newlines_before > 0;
    }

    # `(var | const) PATTERN = value`.
    _destructure(): Statement {
        ulong keyword = _position;
        bool is_const = _at_word("const");
        _advance();
        var bindings = _binding_pattern();
        if (_failed) {
            return _no_statement();
        }
        _expect("=");
        if (_failed) {
            return _no_statement();
        }
        var value = _expression();
        if (_failed) {
            return _no_statement();
        }
        return Statement.Destructure(bindings, value, is_const, Span(_start(keyword), _last_end()));
    }

    # `( binding, ... )` of a destructuring, where a binding is
    # `name [: Type]` or a nested pattern.
    _binding_pattern(): DestructureBinding[] {
        var out = Array<DestructureBinding>();
        _advance();
        while (true) {
            if (_at("(")) {
                ulong open = _position;
                var nested = DestructureBinding();
                nested.nested = _binding_pattern();
                if (_failed) {
                    return out;
                }
                nested.name_span = Span(_start(open), _last_end());
                out.append(nested);
            } else {
                if (!_at_name()) {
                    _fail("expected variable name");
                    return out;
                }
                var binding = DestructureBinding();
                binding.name = _text(_position);
                binding.name_span = _token_span(_position);
                _advance();
                if (_at(":")) {
                    _advance();
                    binding.type_name = _type_name();
                    if (_failed) {
                        return out;
                    }
                }
                out.append(binding);
            }
            if (_at(",")) {
                _advance();
                continue;
            }
            _expect(")");
            return out;
        }
        return out;
    }

    # `var name`, `const name` or `Type name`, then `[: Type] [= value]`,
    # after `prefix`. Sets `_variable_annotation`.
    _variable_declaration(prefix: Prefix): VariableDecl {
        var out = VariableDecl();
        out.attributes = prefix.attributes;
        ulong own = _start(_position);
        if (_at_word("var") or _at_word("const")) {
            out.is_const = _at_word("const");
            _advance();
            _expect_name("variable name");
            if (_failed) {
                return out;
            }
        } else {
            out.type_name = _probe_type();
            if (_failed) {
                return out;
            }
            if (_at("(")) {
                _fail("expected variable name");
                return out;
            }
            _expect_name("variable name");
            if (_failed) {
                return out;
            }
        }
        out.name = _text(_position - 1);
        out.name_span = _token_span(_position - 1);
        ulong last_end = out.name_span.end;
        TypeName? annotation;
        if (_at(":")) {
            _advance();
            out.type_name = _type_name();
            if (_failed) {
                return out;
            }
            annotation = Optional<TypeName>.Value(out.type_name);
            last_end = _last_end();
        }
        if (_at("=")) {
            _advance();
            out.default_value = Optional<Expression>.Value(_expression());
            last_end = _last_end();
        }
        out.span = Span(prefix.start_or(own), last_end);
        _variable_annotation = annotation;
        return out;
    }

    # ── Declarations ─────────────────────────────────────────────────────

    _generic_parameters(): GenericParam[] {
        var out = Array<GenericParam>();
        _advance();
        while (true) {
            if (_at(">")) {
                _advance();
                return out;
            }
            _expect_name("generic parameter name");
            if (_failed) {
                return out;
            }
            var parameter = GenericParam(_text(_position - 1), _token_span(_position - 1));
            # Constraints: `T: Shape & Named`.
            if (_at(":")) {
                _advance();
                parameter.bounds.append(_type_name());
                while (!_failed and _at("&")) {
                    _advance();
                    parameter.bounds.append(_type_name());
                }
                if (_failed) {
                    return out;
                }
            }
            if (_at("=")) {
                _advance();
                parameter.default = Optional<TypeName>.Value(_type_name());
                if (_failed) {
                    return out;
                }
            }
            out.append(parameter);
            if (_at(",")) {
                _advance();
                continue;
            }
            _expect(">");
            return out;
        }
        return out;
    }

    # `( parameter, ... )` of a function, method or constructor.
    _parameters(): VariableDecl[] {
        var out = Array<VariableDecl>();
        _expect("(");
        if (_failed) {
            return out;
        }
        while (true) {
            if (_at(")")) {
                _advance();
                return out;
            }
            out.append(_parameter());
            if (_failed) {
                return out;
            }
            if (_at(",")) {
                _advance();
                continue;
            }
            _expect(")");
            return out;
        }
        return out;
    }

    _parameter(): VariableDecl {
        # Attributes on a parameter (`[Move] value: T`).
        var attributes = _attributes();
        if (_failed) {
            return VariableDecl();
        }
        var out = _parameter_body(attributes);
        if (_failed) {
            return out;
        }
        if (attributes.count > 0) {
            out.span = Span(attributes[0].span.start, out.span.end);
            out.attributes = attributes;
        }
        return out;
    }

    _parameter_body(attributes: Attribute[]): VariableDecl {
        if (_at_word("this")) {
            ulong keyword = _position;
            _advance();
            _expect(".");
            if (_failed) {
                return VariableDecl();
            }
            _expect_name("field name");
            if (_failed) {
                return VariableDecl();
            }
            ulong field = _position - 1;
            _expect("=");
            if (_failed) {
                return VariableDecl();
            }
            var value = _expression();
            if (_failed) {
                return VariableDecl();
            }
            var out = VariableDecl("this." + _text(field));
            out.name_span = _token_span(field);
            out.default_value = Optional<Expression>.Value(value);
            out.span = Span(_start(keyword), _after());
            return out;
        }
        if (_at_word("var") or _at_word("const")) {
            return _variable_declaration(Prefix(Array<Attribute>()));
        }
        # `name: Type`
        var mark = _mark();
        if (_at_name() and _peek_at(1).is(_source, ":")) {
            ulong name = _position;
            _advance();
            _advance();
            var parameter_type = _type_name();
            if (!_failed) {
                var out = VariableDecl(_text(name));
                out.name_span = _token_span(name);
                out.type_name = parameter_type;
                _parameter_default(out);
                out.span = Span(out.name_span.start, out.span.end);
                return out;
            }
            _restore(mark);
        }
        # `Type name`
        ulong first = _position;
        var parameter_type = _type_name();
        if (_failed) {
            return VariableDecl();
        }
        _expect_name("parameter name");
        if (_failed) {
            return VariableDecl();
        }
        var out = VariableDecl(_text(_position - 1));
        out.name_span = _token_span(_position - 1);
        out.type_name = parameter_type;
        _parameter_default(out);
        out.span = Span(_start(first), out.span.end);
        return out;
    }

    # A parameter's `= value`; its span ends at the value, else at the
    # token after the parameter.
    _parameter_default(out: VariableDecl) {
        if (_at("=")) {
            _advance();
            out.default_value = Optional<Expression>.Value(_expression());
            out.span = Span(0, _last_end());
            return;
        }
        out.span = Span(0, _after());
    }

    # C parameters of an `extern` function, into `out`: `Type name`, or a
    # final `...`.
    _extern_parameters(out: FunctionDecl) {
        _expect("(");
        if (_failed) {
            return;
        }
        while (true) {
            if (_at(")")) {
                _advance();
                return;
            }
            if (_at("...")) {
                _advance();
                out.is_variadic = true;
                _expect(")");
                return;
            }
            var parameter_type = _type_name();
            if (_failed) {
                return;
            }
            _expect_name("parameter name");
            if (_failed) {
                return;
            }
            var parameter = VariableDecl(_text(_position - 1));
            parameter.name_span = _token_span(_position - 1);
            parameter.type_name = parameter_type;
            parameter.span = Span(parameter_type.span.start, _after());
            out.parameters.append(parameter);
            if (_at(",")) {
                _advance();
                continue;
            }
            _expect(")");
            return;
        }
    }

    _extern_function(prefix: Prefix): FunctionDecl {
        var out = FunctionDecl();
        out.attributes = prefix.attributes;
        out.external = true;
        ulong decl_start = prefix.start_or(_start(_position));
        _advance();
        out.return_type = _type_name();
        if (_failed) {
            return out;
        }
        _expect_name("function name");
        if (_failed) {
            return out;
        }
        out.name = _text(_position - 1);
        out.name_span = _token_span(_position - 1);
        _extern_parameters(out);
        if (_failed) {
            return out;
        }
        out.span = Span(decl_start, _last_end());
        _finish_statement();
        return out;
    }

    # The body of a function: a block, or `;` where `bodyless` allows one (a
    # trait's requirement) or after a parameter list (a compiler built-in's
    # `[__BuiltIn]` declaration; the compiler rejects it anywhere else).
    _function_body(out: FunctionDecl, bodyless: bool, has_parameters: bool) {
        if ((bodyless or has_parameters) and _at(";")) {
            _advance();
            return;
        }
        if (_skip_bodies and _at("{")) {
            out.body = Optional<Block>.Value(_skipped_block());
            return;
        }
        out.body = Optional<Block>.Value(_block(Array<Attribute>()));
    }

    # A body `_skip_bodies` passes over: an empty block spanning its braces,
    # as `_block` spans them. Interpolated strings are single tokens, so
    # every brace token is one the body opens or closes.
    _skipped_block(): Block {
        var out = Block();
        ulong open = _position;
        ulong depth = 0;
        while (true) {
            if (_at_end()) {
                _fail("expected '}'");
                return out;
            }
            if (_at("{")) {
                depth += 1;
            } else if (_at("}")) {
                depth -= 1;
            }
            _advance();
            if (depth == 0) {
                break;
            }
        }
        out.span = Span(_start(open), _last_end());
        return out;
    }

    # The function's name when it is an indexer, and its span, which runs
    # to the token after it.
    _finish_function(out: FunctionDecl, decl_start: ulong): FunctionDecl {
        if (out.is_indexer) {
            out.name = indexer_name(out.parameters);
        }
        out.span = Span(decl_start, _after());
        return out;
    }

    # A top-level function: `name[<T>](params)[: Type] { }` or
    # `Type name(params)[: Type] { }`.
    _function(prefix: Prefix): FunctionDecl {
        var out = FunctionDecl();
        out.attributes = prefix.attributes;
        out.return_type = TypeName.auto();
        if (!_at_name()) {
            _fail("expected declaration");
            return out;
        }
        ulong decl_start = prefix.start_or(_start(_position));
        ulong first = _position;
        _advance();
        _qualified_tail(first);
        ulong last_name = _position - 1;
        bool qualified = last_name > first;
        if (_at("(") or _at("<")) {
            if (qualified) {
                _fail("expected function name");
                return out;
            }
            out.name = _text(first);
            out.name_span = _token_span(first);
            if (_at("<")) {
                out.generic_params = _generic_parameters();
                if (_failed) {
                    return out;
                }
            }
            bool has_parameters = _at("(");
            if (has_parameters) {
                out.parameters = _parameters();
                if (_failed) {
                    return out;
                }
            }
            _return_annotation(out);
            if (_failed) {
                return out;
            }
            _function_body(out, false, has_parameters);
            if (_failed) {
                return out;
            }
            return _finish_function(out, decl_start);
        }
        if (!_at_name() and !_at("[")) {
            _fail("expected function name");
            return out;
        }
        var name = _dotted_name(first, last_name + 1);
        while (_at("[") and _peek_at(1).is(_source, "]")) {
            _advance();
            _advance();
            name = name + "[]";
        }
        out.return_type = TypeName(name, Span(_start(first), _after_index(last_name)));
        _expect_name("function name");
        if (_failed) {
            return out;
        }
        out.name = _text(_position - 1);
        out.name_span = _token_span(_position - 1);
        bool has_parameters = _at("(");
        if (has_parameters) {
            out.parameters = _parameters();
            if (_failed) {
                return out;
            }
        }
        _return_annotation(out);
        if (_failed) {
            return out;
        }
        _function_body(out, false, has_parameters);
        if (_failed) {
            return out;
        }
        return _finish_function(out, decl_start);
    }

    # An optional `: Type` after a parameter list. Returns whether there was
    # one.
    _return_annotation(out: FunctionDecl): bool {
        if (_at(":")) {
            _advance();
            out.return_type = _type_name();
            return true;
        }
        return false;
    }

    # A function with `attributes`, `static` when `is_static`.
    _new_method(attributes: Attribute[], is_static: bool): FunctionDecl {
        var out = FunctionDecl();
        out.attributes = attributes;
        out.return_type = TypeName.auto();
        out.is_static = is_static;
        return out;
    }

    # A method of a struct, extension or trait (`bodyless` for a trait).
    _method(attributes: Attribute[], bodyless: bool): FunctionDecl {
        ulong decl_start = attributes.count > 0 ? attributes[0].span.start : _start(_position);
        bool is_static = false;
        if (_at_word("static")) {
            _advance();
            is_static = true;
        }
        var mark = _mark();

        # Pepper-style indexer or operator method: `[](params)[: Type] { }`,
        # `==(params)[: Type] { }`.
        var out = _new_method(attributes, is_static);
        bool pepper_style = false;
        if (_at("[") and _peek_at(1).is(_source, "]")) {
            out.name = "[]";
            out.name_span = Span(_start(_position), _end_of(_position + 1));
            out.is_indexer = true;
            _advance();
            _advance();
            pepper_style = true;
        } else {
            var leading = _operator_size();
            if (_at_operator_name(leading)) {
                out.name = _operator_text(leading);
                out.name_span = Span(_start(_position), _start(_position) + leading);
                _take_operator(leading);
                pepper_style = true;
            }
        }
        if (pepper_style) {
            if (_at("(")) {
                out.parameters = _parameters();
                if (_failed) {
                    return out;
                }
                _return_annotation(out);
                if (_failed) {
                    return out;
                }
                _function_body(out, bodyless, true);
                if (_failed) {
                    return out;
                }
                return _finish_function(out, decl_start);
            }
            _restore(mark);
        }

        # Indexer: `T [](params) { }`
        var index_type = _type_base();
        if (!_failed) {
            if (_at("[") and _peek_at(1).is(_source, "]") and _peek_at(2).is(_source, "(")) {
                out = _new_method(attributes, is_static);
                out.return_type = index_type;
                out.name_span = index_type.span;
                out.is_indexer = true;
                _advance();
                _advance();
                out.parameters = _parameters();
                if (_failed) {
                    return out;
                }
                _function_body(out, false, true);
                if (_failed) {
                    return out;
                }
                return _finish_function(out, decl_start);
            }
        }
        _restore(mark);

        # `name[<T>](params)[: Type] { }`
        if (_at_name()) {
            ulong name = _position;
            _advance();
            bool generic = false;
            var generics = Array<GenericParam>();
            if (_at("<")) {
                var after_name = _mark();
                generics = _generic_parameters();
                if (!_failed and _at("(")) {
                    generic = true;
                } else {
                    _restore(after_name);
                }
            }
            if (_at("(") or generic) {
                out = _new_method(attributes, is_static);
                out.name = _text(name);
                out.name_span = _token_span(name);
                if (generic) {
                    out.generic_params = generics;
                }
                out.parameters = _parameters();
                if (_failed) {
                    return out;
                }
                _return_annotation(out);
                if (_failed) {
                    return out;
                }
                _function_body(out, bodyless, true);
                if (_failed) {
                    return out;
                }
                return _finish_function(out, decl_start);
            }
        }

        # `Type name(params) { }`, where the name may be an operator.
        _restore(mark);
        out = _new_method(attributes, is_static);
        ulong type_start = _position;
        var return_type = _type_base();
        if (_failed) {
            return out;
        }
        out.return_type = _return_type_prefix(return_type, type_start);
        # A trait's method returns its type's first name alone.
        var first_name = TypeName(_text(type_start), _token_span(type_start));
        var op = _operator_size();
        if (_at_name()) {
            out.name = _text(_position);
            out.name_span = _token_span(_position);
            _advance();
        } else if (_at_operator_name(op)) {
            out.name = _operator_text(op);
            out.name_span = Span(_start(_position), _start(_position) + op);
            _take_operator(op);
        } else {
            _fail("expected method name");
            return out;
        }
        bool has_parameters = _at("(");
        if (has_parameters) {
            out.parameters = _parameters();
            if (_failed) {
                return out;
            }
        }
        bool annotated = _return_annotation(out);
        if (_failed) {
            return out;
        }
        _function_body(out, bodyless, has_parameters);
        if (_failed) {
            return out;
        }
        if (bodyless and !annotated) {
            out.return_type = first_name;
        }
        return _finish_function(out, decl_start);
    }

    # The return type written before a method's name (`_type_base`'s
    # `base`, from the token at `start`): with type arguments and no
    # qualifier, the whole type; else its name alone, its span running to
    # the name's end in members and to the token after the name elsewhere.
    _return_type_prefix(base: TypeName, start: ulong): TypeName {
        if (_type_generic and !_type_qualified) {
            return base;
        }
        ulong last_name = _type_last_name;
        ulong end = _in_members ? _end_of(last_name) : _after_index(last_name);
        return TypeName(_dotted_name(start, last_name + 1), Span(_start(start), end));
    }

    # `{ member... }` of a struct, trait or extension, into `out`.
    _members(kind: MemberKind, out: MemberList) {
        ulong open = _position;
        _expect("{");
        if (_failed) {
            return;
        }
        if (_recovering) {
            _recovering_members(kind, out, open);
            return;
        }
        while (true) {
            if (_at("}") or _at_end()) {
                break;
            }
            if (_at(";")) {
                _advance();
                continue;
            }
            _member(kind, out);
            if (_failed) {
                return;
            }
        }
        _expect("}");
    }

    # `_members`' members and `}` for `parse_recovering`, into `out`, after
    # the `{` at `open`: a broken member is noted and skipped.
    _recovering_members(kind: MemberKind, out: MemberList, open: ulong) {
        while (true) {
            if (_at("}") or _at_end()) {
                break;
            }
            if (_at(";")) {
                _advance();
                continue;
            }
            var item = _mark();
            _member(kind, out);
            if (_failed) {
                if (_dedented(item.position, open)) {
                    _restore(item);
                    _clear_error();
                    _unclosed(open, item.position);
                    return;
                }
                _skip_failed(item, open);
            }
        }
        if (_at_end()) {
            _unclosed(open, _position);
            return;
        }
        _expect("}");
        if (!_failed) {
            _note_close(open);
        }
    }

    # One member of a struct, trait or extension, with its attributes, into
    # `out`.
    _member(kind: MemberKind, out: MemberList) {
        var attributes = _attributes();
        if (_failed) {
            return;
        }
        if (kind != MemberKind.Struct and _at_word("var")) {
            var variable = _variable_declaration(Prefix(attributes));
            if (_failed) {
                return;
            }
            if (!_at("{")) {
                _fail("expected '{'");
                return;
            }
            var property = _property(variable);
            if (_failed) {
                return;
            }
            out.properties.append(property);
            return;
        }
        if (kind != MemberKind.Struct) {
            var method = _method(attributes, kind == MemberKind.Trait);
            if (_failed) {
                return;
            }
            out.methods.append(method);
            return;
        }
        if (_at_word("construct") or _at_word("new")) {
            ulong keyword = _position;
            _advance();
            var parameters = _parameters();
            if (_failed) {
                return;
            }
            var body = _block(Array<Attribute>());
            if (_failed) {
                return;
            }
            out.constructors.append(_constructor(attributes, keyword, parameters, body));
            return;
        }
        if (_at_word("destruct")) {
            var keyword = _token_span(_position);
            _advance();
            var body = _block(Array<Attribute>());
            if (_failed) {
                return;
            }
            out.destruct_span = Optional<Span>.Value(keyword);
            body.attributes = attributes;
            if (attributes.count > 0) {
                body.span = Span(attributes[0].span.start, body.span.end);
            }
            out.destructor = Optional<Block>.Value(body);
            return;
        }
        if (_at_word("extern") and !_peek_at(1).is(_source, "(")) {
            var function = _extern_function(Prefix(attributes));
            if (_failed) {
                return;
            }
            out.methods.append(function);
            return;
        }
        var mark = _mark();
        var member = _method(attributes, false);
        if (!_failed) {
            out.methods.append(member);
            return;
        }
        _restore(mark);
        var field = _variable_declaration(Prefix(attributes));
        if (_failed) {
            return;
        }
        if (_at("{")) {
            var property = _property(field);
            if (_failed) {
                return;
            }
            out.properties.append(property);
            return;
        }
        if (!_declaration_boundary()) {
            _fail("expected ';'");
            return;
        }
        _finish_statement();
        if (_failed and _recovering) {
            _record(_position - 1, _failure());
        }
        out.fields.append(field);
    }

    # A constructor, whose `construct` (or `new`) is at `keyword`.
    _constructor(attributes: Attribute[], keyword: ulong, parameters: VariableDecl[], body: Block): FunctionDecl {
        var out = FunctionDecl("construct");
        out.attributes = attributes;
        out.return_type = TypeName.auto();
        out.name_span = Span(_start(keyword), _after_index(keyword));
        if (_tokens[keyword].spells(_source, "new")) {
            _warnings.append(
                SyntaxWarning(
                    _token_span(keyword),
                    "`new`",
                    "constructors are spelled `construct`, matching `destruct`",
                    "construct"
                )
            );
        }
        out.parameters = parameters;
        out.body = Optional<Block>.Value(body);
        out.span = Span(attributes.count > 0 ? attributes[0].span.start : _start(keyword), _after());
        return out;
    }

    # The rest of a property after `var name: Type` (read as `variable`):
    # its accessors, then `[= value ;]`. Its getter and setter are functions
    # named `__get_name` and `__set_name`.
    _property(variable: VariableDecl): PropertyDecl {
        var out = PropertyDecl();
        out.attributes = variable.attributes;
        out.name = variable.name;
        out.name_span = variable.name_span;
        if (_variable_annotation.is_value()) {
            out.type_name = _variable_annotation.value();
        }
        out.default_value = variable.default_value;
        ulong accessors_start = _problems.count;
        ulong tests_start = _build_option_tests.count;
        var keywords = Array<ulong>();
        var bodies = Array<Block?>();
        _advance();
        while (!_at("}")) {
            if (_at_end() or !(_at_word("get") or _at_word("set"))) {
                _fail("expected 'get' or 'set'");
                return out;
            }
            keywords.append(_position);
            _advance();
            if (_at(";")) {
                _advance();
                bodies.append(Optional<Block>.Empty);
            } else {
                var body = _block(Array<Attribute>());
                if (_failed) {
                    return out;
                }
                bodies.append(Optional<Block>.Value(body));
            }
        }
        _advance();
        ulong end = _last_end();
        ulong accessors_end = _problems.count;
        ulong tests_end = _build_option_tests.count;
        if (_at("=")) {
            _advance();
            var value = _expression();
            if (_failed) {
                return out;
            }
            out.default_value = Optional<Expression>.Value(value);
            end = _last_end();
            _finish_statement();
        }
        # The compiler reads the accessors' bodies after the value.
        move_after(_problems, accessors_start, accessors_end);
        move_after(_build_option_tests, tests_start, tests_end);
        ulong i = 0;
        while (i < keywords.count) {
            _accessor(out, keywords[i], bodies[i]);
            i += 1;
        }
        out.span = Span(variable.span.start, end);
        return out;
    }

    # The getter or setter whose `get` or `set` is at `keyword`.
    _accessor(out: PropertyDecl, keyword: ulong, body: Block?) {
        var span = _token_span(keyword);
        bool is_get = _tokens[keyword].spells(_source, "get");
        var function = FunctionDecl(is_get ? "__get_" + out.name : "__set_" + out.name);
        function.attributes = out.attributes;
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
        if (body.is_value()) {
            function.body = body;
            function_end = body.value().span.end;
        }
        function.span = Span(span.start, function_end);
        if (is_get) {
            out.getter = Optional<Accessor>.Value(Accessor(span, function));
        } else {
            out.setter = Optional<Accessor>.Value(Accessor(span, function));
        }
    }

    # `struct Name<T> { ... }`.
    _struct(prefix: Prefix): StructDecl {
        var out = StructDecl();
        out.attributes = prefix.attributes;
        ulong decl_start = prefix.start_or(_start(_position));
        _advance();
        _expect_name("name");
        if (_failed) {
            return out;
        }
        out.name = _text(_position - 1);
        out.name_span = _token_span(_position - 1);
        if (_at("<")) {
            out.generic_params = _generic_parameters();
            if (_failed) {
                return out;
            }
        }
        var members = MemberList();
        _in_members = true;
        _members(MemberKind.Struct, members);
        _in_members = false;
        if (_failed) {
            return out;
        }
        out.methods = members.methods;
        out.constructors = members.constructors;
        out.fields = members.fields;
        out.properties = members.properties;
        out.destructor = members.destructor;
        out.destruct_span = members.destruct_span;
        out.span = Span(decl_start, _last_end());
        return out;
    }

    # `trait Name<T> { ... }`.
    _trait(prefix: Prefix): TraitDecl {
        var out = TraitDecl();
        out.attributes = prefix.attributes;
        ulong decl_start = prefix.start_or(_start(_position));
        _advance();
        _expect_name("name");
        if (_failed) {
            return out;
        }
        out.name = _text(_position - 1);
        out.name_span = _token_span(_position - 1);
        if (_at("<")) {
            out.generic_params = _generic_parameters();
            if (_failed) {
                return out;
            }
        }
        var members = MemberList();
        _members(MemberKind.Trait, members);
        if (_failed) {
            return out;
        }
        out.methods = members.methods;
        out.properties = members.properties;
        out.span = Span(decl_start, _last_end());
        return out;
    }

    # `enum Name [: Type] { cases, methods and properties }`, a struct with
    # an enum body. A case list ends at a case without a `,`, or at a name
    # that starts a method or a property.
    _enum(prefix: Prefix): StructDecl {
        var out = StructDecl();
        var body = EnumBody();
        out.attributes = prefix.attributes;
        ulong decl_start = prefix.start_or(_start(_position));
        _advance();
        _expect_name("an enum name");
        if (_failed) {
            return out;
        }
        out.name = _text(_position - 1);
        out.name_span = _token_span(_position - 1);
        if (_at("<")) {
            out.generic_params = _generic_parameters();
            if (_failed) {
                return out;
            }
        }
        if (_at(":")) {
            _advance();
            body.representation = Optional<TypeName>.Value(_type_name());
            if (_failed) {
                return out;
            }
        }
        _expect("{");
        if (_failed) {
            return out;
        }
        _in_members = true;
        _enum_members(out, body);
        _in_members = false;
        if (_failed) {
            return out;
        }
        out.enumeration = Optional<EnumBody>.Value(body);
        out.span = Span(decl_start, _last_end());
        return out;
    }

    # An enum's cases, then its methods and properties, and its `}`.
    _enum_members(out: StructDecl, body: EnumBody) {
        # The `{`, which the caller took.
        ulong open = _position - 1;
        while (true) {
            if (_at("}") or _at_end()) {
                break;
            }
            var mark = _mark();
            var attributes = _attributes();
            if (_failed) {
                return;
            }
            if (!_at_name() or _at_word("static") or _at_word("var")) {
                _restore(mark);
                break;
            }
            var item = EnumCase();
            item.attributes = attributes;
            item.name = _text(_position);
            item.name_span = _token_span(_position);
            _advance();
            if (_at("(")) {
                var payload = _parameters();
                if (_failed or _at(":") or _at("{")) {
                    # A method: the cases are over.
                    _restore(mark);
                    break;
                }
                item.payload = Optional<VariableDecl[]>.Value(payload);
            } else if (_at(":") or _at("{") or _at("<")) {
                _restore(mark);
                break;
            }
            if (_at("=")) {
                _advance();
                item.value = Optional<Expression>.Value(_expression());
                if (_failed) {
                    return;
                }
            }
            item.span = Span(attributes.count > 0 ? attributes[0].span.start : item.name_span.start, _after());
            body.cases.append(item);
            if (_at(",")) {
                _advance();
                continue;
            }
            break;
        }
        while (true) {
            if (_at("}") or _at_end()) {
                break;
            }
            if (_at(";")) {
                _advance();
                continue;
            }
            Mark item;
            if (_recovering) {
                item = _mark();
            }
            _enum_member(out);
            if (!_failed) {
                continue;
            }
            if (!_recovering) {
                return;
            }
            if (_dedented(item.position, open)) {
                _restore(item);
                _clear_error();
                _unclosed(open, item.position);
                return;
            }
            _skip_failed(item, open);
        }
        if (_recovering and _at_end()) {
            _unclosed(open, _position);
            return;
        }
        _expect("}");
        if (_recovering and !_failed) {
            _note_close(open);
        }
    }

    # One method or property of an enum, with its attributes, into `out`.
    _enum_member(out: StructDecl) {
        var attributes = _attributes();
        if (_failed) {
            return;
        }
        if (_at_word("var")) {
            var variable = _variable_declaration(Prefix(attributes));
            if (_failed) {
                return;
            }
            var property = _property(variable);
            if (_failed) {
                return;
            }
            out.properties.append(property);
        } else {
            var method = _method(attributes, false);
            if (_failed) {
                return;
            }
            out.methods.append(method);
        }
    }

    _extension(prefix: Prefix): ExtendDecl {
        var out = ExtendDecl();
        out.attributes = prefix.attributes;
        ulong decl_start = prefix.start_or(_start(_position));
        _advance();
        _restating = true;
        _restated = false;
        _restated_bounds = Array<TypeName[]>();
        out.target = _type_name();
        _restating = false;
        if (_failed) {
            return out;
        }
        if (_restated) {
            out.target_bounds = _restated_bounds;
        }
        if (_at_word("with")) {
            _advance();
            while (true) {
                out.traits.append(_type_name());
                if (_failed) {
                    return out;
                }
                if (_at(",")) {
                    _advance();
                    continue;
                }
                break;
            }
            # `extend X with Trait;` has no body.
            if (_at(";")) {
                _advance();
                out.span = Span(decl_start, _last_end());
                return out;
            }
        }
        var members = MemberList();
        _in_members = true;
        _members(MemberKind.Extend, members);
        _in_members = false;
        if (_failed) {
            return out;
        }
        out.methods = members.methods;
        out.properties = members.properties;
        out.span = Span(decl_start, _last_end());
        return out;
    }

    _type_alias(prefix: Prefix): TypeAliasDecl {
        var out = TypeAliasDecl();
        out.attributes = prefix.attributes;
        ulong decl_start = prefix.start_or(_start(_position));
        _advance();
        _expect_name("type name");
        if (_failed) {
            return out;
        }
        out.name = _text(_position - 1);
        out.name_span = _token_span(_position - 1);
        if (_at("<")) {
            out.generic_params = _generic_parameters();
            if (_failed) {
                return out;
            }
        }
        _expect("=");
        if (_failed) {
            return out;
        }
        out.target = _type_name();
        if (_failed) {
            return out;
        }
        out.span = Span(decl_start, _last_end());
        return out;
    }

    # A stand-in for the declaration a failed reading would have built.
    _no_declaration(): Declaration {
        return Declaration.Function(FunctionDecl());
    }

    _declaration(): Declaration {
        var prefix = Prefix(_attributes());
        if (_failed) {
            return _no_declaration();
        }
        while (_at_word("export") or _at_word("private")) {
            bool is_export = _at_word("export");
            if ((is_export and prefix.exported) or (!is_export and prefix.file_private)) {
                _fail(is_export ? "duplicate 'export' modifier" : "duplicate 'private' modifier");
                return _no_declaration();
            }
            if (prefix.exported or prefix.file_private) {
                _fail("a declaration cannot be both 'export' and 'private'");
                return _no_declaration();
            }
            prefix.exported = is_export;
            prefix.file_private = !is_export;
            prefix.modifier_start = _start(_position);
            _advance();
            if (_at("[")) {
                _fail(is_export ? "'export' goes after the attributes" : "'private' goes after the attributes");
                return _no_declaration();
            }
        }
        if (_at_word("struct")) {
            var declaration = _struct(prefix);
            declaration.is_exported = prefix.exported;
            declaration.is_private = prefix.file_private;
            return Declaration.Struct(declaration);
        }
        if (_at_word("trait")) {
            var declaration = _trait(prefix);
            declaration.is_exported = prefix.exported;
            declaration.is_private = prefix.file_private;
            return Declaration.Trait(declaration);
        }
        if (_at_word("enum")) {
            var declaration = _enum(prefix);
            declaration.is_exported = prefix.exported;
            declaration.is_private = prefix.file_private;
            return Declaration.Struct(declaration);
        }
        if (_at_word("extend")) {
            var declaration = _extension(prefix);
            declaration.is_exported = prefix.exported;
            declaration.is_private = prefix.file_private;
            return Declaration.Extend(declaration);
        }
        if (_at_word("type")) {
            var declaration = _type_alias(prefix);
            declaration.is_exported = prefix.exported;
            declaration.is_private = prefix.file_private;
            return Declaration.TypeAlias(declaration);
        }
        if (_at_word("static") and (_peek_at(1).is(_source, "(") or _peek_at(1).is(_source, "{"))) {
            ulong own = _start(_position);
            var block = _static_block();
            block.attributes = prefix.attributes;
            block.span = Span(prefix.start_or(own), block.span.end);
            block.is_exported = prefix.exported;
            block.is_private = prefix.file_private;
            return Declaration.Static(block);
        }
        if (_at_word("extern") and !_peek_at(1).is(_source, "(")) {
            var function = _extern_function(prefix);
            function.is_exported = prefix.exported;
            function.is_private = prefix.file_private;
            return Declaration.Function(function);
        }
        var mark = _mark();
        var function = _function(prefix);
        if (!_failed) {
            function.is_exported = prefix.exported;
            function.is_private = prefix.file_private;
            return Declaration.Function(function);
        }
        _restore(mark);
        var variable = _variable_declaration(prefix);
        variable.is_exported = prefix.exported;
        variable.is_private = prefix.file_private;
        if (!_failed and _declaration_boundary()) {
            return Declaration.Variable(variable);
        }
        if (!_failed) {
            _fail("expected declaration");
        }
        return Declaration.Variable(variable);
    }

    # `import ...`, or `export * from ...` / `export [...] from ...`, which
    # has the same shape but requires `*` or a list and takes no alias.
    _import_declaration(attributes: Attribute[]): Import {
        var out = Import();
        out.attributes = attributes;
        bool reexport = _at_word("export");
        out.reexport = reexport;
        ulong keyword = _position;
        _advance();
        if (reexport and _at("*")) {
            _advance();
            if (!_at_word("from")) {
                _fail("expected 'from'");
                return out;
            }
            _advance();
        }
        bool list = _at("[");
        if (list) {
            _advance();
            var symbols = Array<ImportedSymbol>();
            bool any = false;
            while (true) {
                if (_at("]") and !any) {
                    break;
                }
                any = true;
                _expect_name("name");
                if (_failed) {
                    return out;
                }
                var symbol = ImportedSymbol();
                symbol.name = _text(_position - 1);
                symbol.name_span = _token_span(_position - 1);
                if (_at_word("as")) {
                    _advance();
                    _expect_name("name");
                    if (_failed) {
                        return out;
                    }
                    symbol.alias = Optional<String>.Value(_text(_position - 1));
                    symbol.span = Span(symbol.name_span.start, _last_end());
                } else {
                    symbol.span = Span(symbol.name_span.start, _after());
                }
                symbols.append(symbol);
                if (_at(",")) {
                    _advance();
                    continue;
                }
                break;
            }
            _expect("]");
            if (_failed) {
                return out;
            }
            out.symbols = Optional<ImportedSymbol[]>.Value(symbols);
            if (!_at_word("from")) {
                _fail("expected 'from'");
                return out;
            }
            _advance();
        }
        ulong first = _position;
        var name = _peek();
        if (name.kind == TokenKind.String) {
            _advance();
            out.name = _string_text(first);
            out.is_local = true;
        } else {
            _expect_name("module name");
            if (_failed) {
                return out;
            }
            # `import http.client`: a module inside a package, which binds
            # its last name.
            while (_at(".")) {
                _advance();
                name = _peek();
                _expect_name("module name");
                if (_failed) {
                    return out;
                }
            }
            out.name = _dotted_name(first, _position);
        }
        out.name_span = Span(_start(first), _last_end());
        ulong end = out.name_span.end;
        var mark = _mark();
        if (!reexport and _at_word("as")) {
            _advance();
            var alias = _peek();
            _expect_name("name");
            if (_failed) {
                return out;
            }
            _qualifiers.insert(alias.text(_source));
            out.alias = Optional<String>.Value(alias.text(_source));
            end = _last_end();
        } else {
            _restore(mark);
            if (!list and !reexport and name.kind != TokenKind.String) {
                _qualifiers.insert(name.text(_source));
            }
        }
        out.span = Span(attributes.count > 0 ? attributes[0].span.start : _start(keyword), end);
        return out;
    }

    # Whether `export` is followed by `*` or `[`: an `export ... from`.
    _at_export_from(): bool {
        return _at_word("export") and (_peek_at(1).is(_source, "*") or _peek_at(1).is(_source, "["));
    }

    # `export name[.name] [as alias];`, a re-export. Fails (so the caller
    # reads a declaration instead) unless an `as` or `;` follows the name.
    _export_alias(attributes: Attribute[]): ExportAlias {
        var out = ExportAlias();
        out.attributes = attributes;
        ulong keyword = _position;
        _advance();
        if (!_at_name()) {
            _fail("expected name");
            return out;
        }
        ulong first = _position;
        _advance();
        bool outer = _probing;
        _probing = false;
        _qualified_tail(first);
        _probing = outer;
        out.symbol = _dotted_name(first, _position);
        out.symbol_span = Span(_start(first), _last_end());
        ulong end = out.symbol_span.end;
        if (_at_word("as")) {
            _advance();
            _expect_name("name");
            if (_failed) {
                return out;
            }
            out.alias = Optional<String>.Value(_text(_position - 1));
            end = _last_end();
        } else if (!_at(";")) {
            _fail("expected ';'");
            return out;
        }
        out.span = Span(attributes.count > 0 ? attributes[0].span.start : _start(keyword), end);
        return out;
    }

    module(): ast.Module {
        var out = ast.Module();
        while (true) {
            if (_at_end()) {
                break;
            }
            if (_at(";")) {
                _advance();
                continue;
            }
            var mark = _mark();
            var attributes = _attributes();
            if (_failed) {
                if (!_recovering) {
                    return out;
                }
                _skip_failed(mark, _NO_TOKEN);
                continue;
            }
            if (_at_word("import") or _at_export_from()) {
                var item = _import_declaration(attributes);
                if (_failed) {
                    if (!_recovering) {
                        return out;
                    }
                    _skip_failed(mark, _NO_TOKEN);
                    continue;
                }
                _finish_statement();
                if (_failed and _recovering) {
                    _record(mark.position, _failure());
                }
                out.imports.append(item);
                # The names that qualify a type in an interpolated
                # string's braces.
                if (item.symbols.is_empty() and !item.reexport) {
                    if (item.alias.is_value()) {
                        _lowered_names.append(item.alias.value());
                    } else if (!item.is_local) {
                        var segments = item.name.split(".");
                        _lowered_names.append(segments[segments.count - 1]);
                    }
                }
                continue;
            }
            if (_at_word("export")) {
                var after_attributes = _mark();
                var item = _export_alias(attributes);
                if (!_failed) {
                    _finish_statement();
                    if (_failed and _recovering) {
                        _record(mark.position, _failure());
                    }
                    out.exports.append(item);
                    continue;
                }
                _restore(after_attributes);
            }
            _restore(mark);
            var declaration = _declaration();
            if (_failed) {
                if (!_recovering) {
                    return out;
                }
                _skip_failed(mark, _NO_TOKEN);
                continue;
            }
            if (declaration is Variable(_)) {
                _finish_statement();
            } else if (declaration is TypeAlias(_)) {
                _finish_statement();
            }
            if (_failed and _recovering) {
                _record(mark.position, _failure());
            }
            out.declarations.append(declaration);
            if (desugared) {
                if (declaration is Static(module_block)) {
                    desugar.static_constants(module_block, out.declarations);
                }
            }
        }
        # An attribute is listed once, however often it was read.
        var starts = HashSet<ulong>();
        for (var test in _build_option_tests) {
            if (!starts.contains(test.span.start)) {
                starts.insert(test.span.start);
                out.build_option_tests.append(test);
            }
        }
        out.warnings = _warnings;
        if (!desugared) {
            out.tokens = Optional<ast.SourceTokens>.Value(ast.SourceTokens(_source, _written_tokens()));
        }
        return out;
    }

    # Every token as the tree has it: the lexer's, with the tokens the
    # parser joined (`>>`, `>=`, `>>=`, `!!`) made one. With none joined,
    # the lexer's own table, which the parser no longer needs.
    _written_tokens(): Token[] {
        if (_joins.is_empty) {
            return _tokens;
        }
        var out = Array<Token>();
        out.reserve(_tokens.count);
        ulong index = 0;
        ulong join = 0;
        while (index < _tokens.count) {
            if (join < _joins.count and _joins[join] == index) {
                ulong size = _joins[join + 1];
                var first = _tokens[index];
                var merged = Token(TokenKind.Punctuation, first.offset, size);
                merged.newlines_before = first.newlines_before;
                merged.newlines_after_comments = first.newlines_after_comments;
                merged.space_before = first.space_before;
                if (first.has_leading_comments()) {
                    merged._leading_comments = first._leading_comments;
                }
                merged._trailing_comment = _tokens[index + size - 1]._trailing_comment;
                out.append(merged);
                index += size;
                join += 2;
                continue;
            }
            out.append(_tokens[index]);
            index += 1;
        }
        return out;
    }

    # ── Literals ─────────────────────────────────────────────────────────

    _number(text: String, span: Span, negative_allowed: bool): Literal {
        bool negative = text.starts_with("-");
        var digits = negative ? text.substr_bytes(1, text.size - 1) : text;
        if (digits.starts_with("0x")) {
            var hex = digits.substr_bytes(2, digits.size - 2);
            var bits = ulong.parse(hex, 16);
            if (hex.is_empty or !bits.is_value()) {
                _problem("integer literal is too large to be represented in a 64-bit integer", span);
                return Literal.Integer(0);
            }
            long value = unsafe_cast<long>(bits.value());
            return Literal.Integer(negative ? (0 as long).wrapping_sub(value) : value);
        }
        if (digits.contains(".") or digits.contains("e") or digits.contains("E")) {
            var value = double.parse(text);
            if (!value.is_value()) {
                _problem($"invalid floating-point literal '{text}'", span);
                return Literal.Float(0.0);
            }
            return Literal.Float(value.value());
        }
        var value = long.parse(text);
        if (value.is_value()) {
            return Literal.Integer(value.value());
        }
        var unsigned = negative ? Optional<ulong>.Empty : ulong.parse(text);
        if (!unsigned.is_value()) {
            _problem("integer literal is too large to be represented in a 64-bit integer", span);
            return Literal.Integer(0);
        }
        return Literal.Unsigned(unsigned.value());
    }

    _character(index: ulong): Literal {
        var text = _text(index);
        var span = _token_span(index);
        if (text.byte_at(1) == '\\') {
            var bytes = Array<u8>();
            if (text.byte_at(2) == 'x') {
                # `'\xHH'`: both digits come before the closing quote.
                var value = text.size == 6 ? ulong.parse(text.substr_bytes(3, 2), 16) : Optional<ulong>.Empty;
                if (!value.is_value()) {
                    _problem("expected two hex digits after '\\x'", Span(span.start + 1, span.start + text.size - 1));
                    return Literal.Char(0 as u8);
                }
                return Literal.Char(value.value() as u8);
            }
            _escape(text, 1, span.start, bytes);
            return Literal.Char(bytes.count > 0 ? bytes[0] : 0 as u8);
        }
        return Literal.Char(text.byte_at(1) as u8);
    }

    # The text of the string literal at `index`, escapes decoded.
    _string_text(index: ulong): String {
        var text = _text(index);
        var bytes = Array<u8>();
        ulong offset = 1;
        while (offset + 1 < text.size) {
            var c = text.byte_at(offset);
            if (c == '\\') {
                offset = _escape(text, offset, _start(index), bytes, true);
                continue;
            }
            bytes.append(c as u8);
            offset += 1;
        }
        # The bytes as they are: `\x80` to `\xFF` may make them not UTF-8,
        # which sema allows only in a `StringConstant` or a C string
        # (`check_string_bytes`).
        return bytes.count == 0 ? String() : String(unsafe_cast<__ptr<char>>(bytes.data()), bytes.count);
    }

    # Decodes the escape sequence at `offset` of `text` (at its backslash)
    # into `bytes`, returning the offset after it. `at` is the file offset
    # of `text`, for errors. With `any_byte`, `\x80` to `\xFF` write that
    # byte; otherwise `\x` stops at `\x7F`.
    _escape(text: String, offset: ulong, at: ulong, bytes: u8[], any_byte: bool = false): ulong {
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
            # The literal's last byte is its closing quote; both digits come before it.
            var value = offset + 4 < text.size ?
                ulong.parse(text.substr_bytes(offset + 2, 2), 16) :
                Optional<ulong>.Empty;
            if (!value.is_value()) {
                var end = offset + 4 < text.size ? offset + 4 : text.size - 1;
                _problem("expected two hex digits after '\\x'", Span(at + offset, at + end));
                return end;
            }
            if (value.value() >= 0x80 and !any_byte) {
                _problem(
                    "'\\x' escape in an interpolated or format string must be ASCII (at most \\x7F); use '\\u{...}' for other characters",
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
                _problem(
                    "'\\u{...}' escape needs 1 to 6 hexadecimal digits and a closing '}'", Span(at + offset, at + close)
                );
                return close + 1;
            }
            Utf8.append_code_point(bytes, value.value() as uint);
            return close + 1;
        } else {
            _problem($"unknown escape sequence '\\{to_string(c)}'", Span(at + offset, at + offset + 2));
        }
        return offset + 2;
    }

    # ── Interpolated strings and formats ────────────────────────────────

    # `$"sum is {a + b}"` at `index`: its text and the values in braces.
    _interpolated_string(index: ulong): Expression {
        if (_layout_only) {
            return Expression.Interpolated(Array<StringPart>(), _token_span(index));
        }
        var text = _text(index);
        ulong literal_start = _start(index);
        var parts = Array<StringPart>();
        var bytes = Array<u8>();
        ulong offset = 2;
        ulong text_start = literal_start + offset;
        # The compiler stops reading a literal at its first error.
        ulong problems = _problems.count;
        while (offset + 1 < text.size and _problems.count == problems) {
            var c = text.byte_at(offset);
            if (c == '\\') {
                offset = _escape(text, offset, literal_start, bytes);
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
                parts.append(_hole(text, offset, close, literal_start));
                offset = close + 1;
                text_start = literal_start + offset;
                continue;
            }
            bytes.append(c as u8);
            offset += 1;
        }
        flush(parts, bytes, text_start, literal_start + offset);
        if (desugared) {
            return desugar.desugar_interpolated(parts, _token_span(index));
        }
        return Expression.Interpolated(parts, _token_span(index));
    }

    # The value in braces from `open` (the `{`) to `close` (the `}`) of a
    # literal's `text`, which starts at file offset `at`, with its format
    # specification.
    _hole(text: String, open: ulong, close: ulong, at: ulong): StringPart {
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
            var value = _parse_hole(inner.substr_bytes(0, cut), at + open + 1);
            if (value.is_value()) {
                if (cut == inner.size) {
                    return StringPart.Hole(value.value(), braces, Optional<FormatSpec>.Empty);
                }
                var spec = _format_spec(inner.substr_bytes(cut + 1, inner.size - cut - 1), at + open + 2 + cut);
                return StringPart.Hole(value.value(), braces, Optional<FormatSpec>.Value(spec));
            }
            choice -= 1;
        }
        _problem("expected an expression after '{' in interpolated string; write '{{' for a literal '{'", braces);
        return StringPart.Hole(Expression.Literal(Literal.Null, braces), braces, Optional<FormatSpec>.Empty);
    }

    # `text`, at file offset `base`, read as one whole expression, or none
    # when it is not one. What reading it found is added to this parser's
    # lists.
    _parse_hole(text: String, base: ulong): Expression? {
        var tokens = syntax.lex(text, false);
        if (tokens.is_err()) {
            return Optional<Expression>.Empty;
        }
        var parser = Parser(text, tokens.value(), desugared);
        parser._base = base;
        parser._in_hole = true;
        for (var name in _lowered_names) {
            parser._qualifiers.insert(name);
            parser._lowered_names.append(name);
        }
        parser._lowered_static_depth = _lowered_static_depth;
        # Two levels, as a call: desugaring makes the hole an argument.
        parser._level = _level + 1;
        parser._deepest = parser._level;
        var value = parser._expression();
        if (parser._too_deep and parser._failed) {
            # Reported once, at the token, with nothing else read.
            _problem(
                parser._error.value().message,
                Span(base + parser._error.value().offset, base + parser._error.value().offset)
            );
            return Optional<Expression>.Value(_nothing());
        }
        if (parser._failed or !parser._at_end()) {
            return Optional<Expression>.Empty;
        }
        if (parser._deepest > _deepest) {
            _deepest = parser._deepest;
        }
        for (var problem in parser._problems) {
            _problems.append(problem);
        }
        for (var test in parser._build_option_tests) {
            _build_option_tests.append(test);
        }
        for (var warning in parser._warnings) {
            _warnings.append(warning);
        }
        ulong i = _lowered_names.count;
        while (i < parser._lowered_names.count) {
            _lowered_names.append(parser._lowered_names[i]);
            i += 1;
        }
        return Optional<Expression>.Value(value);
    }

    # A format specification's text, which starts at file offset `at`.
    _format_spec(text: String, at: ulong): FormatSpec {
        var spec = FormatSpec();
        if (text.is_empty) {
            _problem("expected a format specification after ':'", Span(at, at));
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
        while (i < chars.count and is_digit_text(chars[i])) {
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
            while (i < chars.count and is_digit_text(chars[i])) {
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
            _problem(
                $"unexpected '{chars[i]}' in format specification; expected '[[fill]align][+][0][width][.precision][type]'",
                Span(at + offsets[i], at + offsets[i] + chars[i].size)
            );
        }
        return spec;
    }

    # The parts of the format string at `index`: its text, and the
    # arguments it names in braces.
    _format_parts(index: ulong): StringPart[] {
        var text = _text(index);
        ulong literal_start = _start(index);
        var parts = Array<StringPart>();
        var bytes = Array<u8>();
        ulong offset = 1;
        ulong text_start = literal_start + offset;
        # The compiler stops reading a format at its first error.
        ulong problems = _problems.count;
        while (offset + 1 < text.size and _problems.count == problems) {
            var c = text.byte_at(offset);
            if (c == '\\') {
                offset = _escape(text, offset, literal_start, bytes);
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
                var argument = ulong.parse(text.substr_bytes(offset + 1, digits - offset - 1)).value_or(0);
                var index_span = Span(literal_start + offset + 1, literal_start + digits);
                ulong close = digits;
                FormatSpec? spec;
                if (text.byte_at(digits) == ':') {
                    close = digits + 1;
                    while (close < text.size and text.byte_at(close) != '}') {
                        close += 1;
                    }
                    spec = Optional<FormatSpec>.Value(
                        _format_spec(text.substr_bytes(digits + 1, close - digits - 1), literal_start + digits + 1)
                    );
                }
                var braces = Span(literal_start + brace, literal_start + close + 1);
                parts.append(StringPart.Argument(argument, index_span, braces, spec));
                offset = close + 1;
                text_start = literal_start + offset;
                continue;
            }
            bytes.append(c as u8);
            offset += 1;
        }
        flush(parts, bytes, text_start, literal_start + offset);
        return parts;
    }
}

# Returns whether `token` is one of the words that stop a statement from
# being read as a `Type name` declaration (in `_statement`), compared in
# place.
is_statement_keyword(source: String, token: Token): bool {
    if (token.kind != TokenKind.Identifier) {
        return false;
    }
    int first = source.byte_at(token.offset);
    if (first == 'a') {
        return token.spells(source, "and");
    } else if (first == 'b') {
        return token.spells(source, "break");
    } else if (first == 'c') {
        return token.spells(source, "continue") or token.spells(source, "construct");
    } else if (first == 'd') {
        return token.spells(source, "destruct");
    } else if (first == 'e') {
        return token.spells(source, "extern") or token.spells(source, "extend") or token.spells(source, "enum");
    } else if (first == 'f') {
        return token.spells(source, "false");
    } else if (first == 'i') {
        return token.spells(source, "if") or token.spells(source, "import");
    } else if (first == 'm') {
        return token.spells(source, "match");
    } else if (first == 'n') {
        return token.spells(source, "new");
    } else if (first == 'o') {
        return token.spells(source, "or");
    } else if (first == 'r') {
        return token.spells(source, "return");
    } else if (first == 's') {
        return token.spells(source, "struct") or token.spells(source, "sizeof") or token.spells(source, "static");
    } else if (first == 't') {
        return token.spells(source, "true") or token.spells(source, "trait");
    } else if (first == 'w') {
        return token.spells(source, "while") or token.spells(source, "with");
    }
    return false;
}

# Returns the operators a method may be named after, as `bool ==(T other)`.
operator_method_names(): HashSet<String> {
    return [
        "<<=",
        ">>=",
        "==",
        "!=",
        "!!",
        "<=",
        ">=",
        "+=",
        "-=",
        "*=",
        "/=",
        "%=",
        "++",
        "--",
        "<<",
        ">>",
        "**",
        "&&",
        "||",
        "&=",
        "|=",
        "^=",
        "+",
        "-",
        "*",
        "/",
        "%",
        "<",
        ">",
        "&",
        "|",
        "^",
        "!",
        "~"
    ];
}

# Whether `statement` ends in `;` rather than in a block.
ends_in_semicolon(statement: Statement): bool {
    match (statement) {
        Expression(_) => {
            return true;
        }
        Declaration(_) => {
            return true;
        }
        Return(_, _) => {
            return true;
        }
        LoopBreak(_, _) => {
            return true;
        }
        Destructure(_, _, _, _) => {
            return true;
        }
        else => {}
    }
    return false;
}

# Moves `items[first..middle]` to the end, after the items that follow
# them.
move_after<T>(items: T[], first: ulong, middle: ulong) {
    if (first >= middle or middle >= items.count) {
        return;
    }
    var moved = Array<T>();
    ulong i = first;
    while (i < middle) {
        moved.append(items[i]);
        i += 1;
    }
    var rest = Array<T>();
    while (i < items.count) {
        rest.append(items[i]);
        i += 1;
    }
    items.truncate(first);
    for (var item in rest) {
        items.append(item);
    }
    for (var item in moved) {
        items.append(item);
    }
}

# Appends the text `bytes` hold, from file offset `start` to `end`, to
# `parts`, and empties `bytes`.
flush(parts: StringPart[], bytes: u8[], start: ulong, end: ulong) {
    if (bytes.count > 0) {
        parts.append(StringPart.Text(Utf8.decode_lossy(bytes), Span(start, end)));
        bytes.clear();
    }
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

# The offset of the `}` that closes the braces opened just before `from`
# (`interpolation_end`).
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

# Whether `c`, one character, is an ASCII digit.
is_digit_text(c: String): bool {
    return c.size == 1 and c.byte_at(0) >= '0' and c.byte_at(0) <= '9';
}

# The name of an indexer with `parameters`: a setter when two or more are
# required.
indexer_name(parameters: VariableDecl[]): String {
    int required = 0;
    for (var parameter in parameters) {
        if (!parameter.default_value.is_value()) {
            required += 1;
        }
    }
    return required >= 2 ? "__index_set" : "__index_get";
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
