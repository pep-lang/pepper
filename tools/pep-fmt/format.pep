## Turns a module, as `compiler.parse.parse_written` reads it, into a layout
## `Doc` in the standard Pepper style.
##
## The style: 4-space indentation, lines of at most 120 columns, braces on
## the line of the construct that owns them (`} else {`), one attribute per
## line above its target, at most one blank line in a row and one between
## top-level declarations, imports sorted within each group, trailing
## comments aligned, and Pepper functions declared as `f(x: int): int`
## (C-style `int f(int x)` is for `extern` functions only). Semicolons,
## parentheses around conditions, and line endings are kept as written.
##
## The formatter walks the tree in source order and takes each token of the
## module's token table (`Module.tokens`) where the grammar puts it, so every
## token prints as written, with the comments the lexer attached to it. A
## comment is removed from its token once it is laid out.

import compiler.ast;
import [
    Attribute,
    Block,
    Declaration,
    DestructureBinding,
    EnumCase,
    ExportAlias,
    Expression,
    ExtendDecl,
    FunctionDecl,
    GenericParam,
    Import,
    Match,
    MatchArm,
    MatchExpression,
    MatchValueArm,
    PropertyDecl,
    Span,
    Statement,
    StaticBlock,
    StructDecl,
    TraitDecl,
    TypeAliasDecl,
    VariableDecl
] from compiler.ast;
import compiler.parse;
import [Comment, SyntaxError, Token, TokenKind] from syntax;
import "doc";

## The maximum line width, in columns.
export const LINE_WIDTH = 120;

# The precedence of a binary operator, 1 (`or`) to 9 (`*`), or 0 for an
# assignment or `**`, which are never flattened into a chain.
precedence(op: String): int {
    if (op == "or" or op == "||") {
        return 1;
    }
    if (op == "and" or op == "&&") {
        return 2;
    }
    if (op == "|" or op == "^") {
        return 3;
    }
    if (op == "&") {
        return 4;
    }
    if (op == "==" or op == "!=" or op == "===" or op == "!==") {
        return 5;
    }
    if (op == "<" or op == "<=" or op == ">" or op == ">=") {
        return 6;
    }
    if (op == "<<" or op == ">>") {
        return 7;
    }
    if (op == "+" or op == "-") {
        return 8;
    }
    if (op == "*" or op == "/" or op == "%") {
        return 9;
    }
    return 0;
}

# The index of the first comment above `token`, from `start` on, that reads
# `# format: <word>`, or -1.
directive_index(token: Token, word: String, start: ulong): long {
    if (!token.has_leading_comments()) {
        return -1;
    }
    var directive = "# format: " + word;
    var comments = token.leading_comments;
    ulong i = start;
    while (i < comments.count) {
        if (comments[i].text == directive) {
            return i as long;
        }
        i += 1;
    }
    return -1;
}

# The offset of the end of the line holding `offset` in `source`, before
# its line break and any trailing whitespace.
line_end(source: String, offset: ulong): ulong {
    var data = source.c_str();
    var end = source.size;
    var line_break = source.find("\n", offset);
    if (line_break >= 0) {
        end = line_break as ulong;
    }
    while (end > offset and (data[end - 1] == ' ' or data[end - 1] == '\t' or data[end - 1] == '\r')) {
        end -= 1;
    }
    return end;
}

# `source` from `start` to `end`, with `\r\n` line breaks as `\n`, the form
# the renderer works in.
source_text(source: String, start: ulong, end: ulong): String {
    return source.substr_bytes(start, end - start).replace("\r\n", "\n");
}

# The smaller of a node's start and its first attribute's.
start_of(span: Span, attributes: Attribute[]): ulong {
    if (attributes.count > 0 and attributes[0].span.start < span.start) {
        return attributes[0].span.start;
    }
    return span.start;
}

# Whether `statement` takes the `;` after it.
statement_takes_semicolon(statement: Statement): bool {
    match (statement) {
        Expression(_), Declaration(_), Return(_, _), LoopBreak(_, _), Destructure(_, _, _, _) => {
            return true;
        }
        else => {
            return false;
        }
    }
    return false;
}

# The number of members in the chain `item` heads that are called, as the
# two in `a.b(x).c(y)`.
called_members(item: Expression): int {
    int count = 0;
    var current = item;
    while (true) {
        if (current is FunctionCall(function, _, _)) {
            if (function is MemberAccess(_, _, _, _)) {
                count += 1;
            }
            current = function;
        } else if (current is MemberAccess(lhs, _, _, _)) {
            current = lhs;
        } else if (current is Index(lhs, _, _)) {
            current = lhs;
        } else {
            break;
        }
    }
    return count;
}

# Whether `e` is a call, a member or an index: a link of a member chain.
is_link(e: Expression): bool {
    return e is FunctionCall(_, _, _) or e is MemberAccess(_, _, _, _) or e is Index(_, _, _);
}

# What one item of a module, a body, a property's accessors or a match is.
enum Entry {
    Empty,
    Import(item: Import),
    Export(item: ExportAlias),
    Declaration(declaration: Declaration),
    Statement(statement: Statement),
    Method(decl: FunctionDecl),
    Property(decl: PropertyDecl),
    Field(decl: VariableDecl),
    Constructor(decl: FunctionDecl),
    Case(item: EnumCase),
    Destructor(body: Block),
    Accessor(item: ast.Accessor),
    Arm(arm: MatchArm),
    ElseArm(body: Block),
    ValueArm(arm: MatchValueArm),
    ElseValue(value: Expression),
}

# One item of a module or a braced body, and its first and last tokens.
struct Item {
    var entry: Entry;
    var first: ulong;
    var last: ulong;
    # Whether a `;` right after the item is its own, not an empty statement.
    var takes_semicolon: bool;

    construct(entry: Entry, first: ulong, takes_semicolon: bool) {
        this.entry = entry;
        this.first = first;
        this.last = first;
        this.takes_semicolon = takes_semicolon;
    }

    # Whether the item is a `;` that ends nothing.
    is_empty(): bool {
        return entry is Empty;
    }

    # Whether the item is a `return`, `break` or `continue`.
    is_jump(): bool {
        if (entry is Statement(statement)) {
            return statement is Return(_, _) or statement is LoopBreak(_, _);
        }
        return false;
    }

    # Whether the item is an import that sorting may move: not an `export
    # ... from`, whose order decides which of two colliding re-exports is
    # reported.
    is_sortable_import(): bool {
        if (entry is Import(item)) {
            return !item.reexport;
        }
        return false;
    }
}

# Sorts `items` by their first token, keeping the order of equal ones.
sort_items(items: Item[]) {
    ulong i = 1;
    while (i < items.count) {
        var item = items[i];
        ulong j = i;
        while (j > 0 and items[j - 1].first > item.first) {
            items[j] = items[j - 1];
            j -= 1;
        }
        items[j] = item;
        i += 1;
    }
}

# A `# format: off` region: its text as written, and the index of the first
# item after it.
struct Region {
    Doc layout;
    ulong next;

    construct(layout: Doc, next: ulong) {
        this.layout = layout;
        this.next = next;
    }
}

# A bracketed, comma-separated list being laid out: its open bracket,
# whether a comment forces one item per line, and the items so far.
struct ListLayout {
    var open: ulong;
    var comments: bool;
    var items: Doc[] = Array<Doc>();
    # The first token of the item being laid out.
    var start: ulong;

    construct(open: ulong, comments: bool) {
        this.open = open;
        this.comments = comments;
    }
}

## Builds the layout of a module in the standard style.
export struct Formatter {
    # The text being formatted, which `# format: off` regions copy.
    var _source: String;
    # The tokens, with the comments not yet laid out.
    var _tokens: Token[];
    # For each token index, how many tokens before it were parsed with a
    # comment, then the count for them all.
    var _commented_before: ulong[] = Array<ulong>();
    # For each bracket token, the index of the bracket that matches it.
    var _partners: ulong[] = Array<ulong>();
    # The index of the next token to take.
    var _next: ulong;
    ## Empty, or what the tree and the tokens disagreed on: source the tree
    ## does not keep, such as a second destructor or a property's value
    ## before its accessors, which the compiler rejects.
    var error: String = "";
    ## Where `error` was found, as a byte offset.
    var error_offset: ulong;

    ## Creates a formatter, which takes over the table: it removes each
    ## comment from its token as it lays it out.
    ##
    ## @param tokens the module's tokens, with the source they point into
    construct(tokens: ast.SourceTokens) {
        _source = tokens.source;
        _tokens = tokens.tokens;
        _pair_brackets();
    }

    ## Returns the layout of a whole file.
    ##
    ## @param module the module, as `compiler.parse.parse_written` returns it
    ## @returns the file's layout, to `render` at `LINE_WIDTH`
    format(module: ast.Module): Doc {
        var candidates = Array<Item>();
        for (var item in module.imports) {
            candidates.append(Item(Entry.Import(item), _index(start_of(item.span, item.attributes)), true));
        }
        for (var item in module.exports) {
            candidates.append(Item(Entry.Export(item), _index(start_of(item.span, item.attributes)), true));
        }
        for (var declaration in module.declarations) {
            var first = _index(start_of(declaration.span(), declaration.attributes()));
            candidates.append(Item(Entry.Declaration(declaration), first, _declaration_takes_semicolon(declaration)));
        }
        var end = _end_index();
        var items = _items(candidates, 0, end);
        _sort_imports(items);
        var result = concat();
        ulong index = 0;
        bool after_region = false;
        while (index < items.count) {
            var item = items[index];
            if (after_region) {
                result.add(hardline());
                if (_blank_before(item.first)) {
                    result.add(hardline());
                }
            } else if (index > 0) {
                var previous = items[index - 1];
                if (item.is_empty() and _tokens[item.first].newlines_before == 0) {
                    result.add(_token_doc(item.first));
                    index += 1;
                    continue;
                }
                result.add(hardline());
                if (_blank_before(item.first) or _is_big(item) or _is_big(previous)) {
                    result.add(hardline());
                }
            }
            var region = _format_off(items, index, end);
            if (region) {
                result.add(region.value().layout);
                index = region.value().next;
                after_region = true;
                continue;
            }
            after_region = false;
            result.add(_leading(item.first));
            result.add(_item(item));
            index += 1;
        }
        ulong c = 0;
        var end_comments = _tokens[end].leading_comments;
        while (c < end_comments.count) {
            var comment = end_comments[c];
            if (items.count > 0 or c > 0) {
                result.add(hardline());
                if (comment.newlines_before >= 2) {
                    result.add(hardline());
                }
            }
            result.add(text(comment.text));
            c += 1;
        }
        return result;
    }

    # ── Tokens ───────────────────────────────────────────────────────────────

    # Finds the partner of every bracket, and counts the tokens with
    # comments.
    _pair_brackets() {
        var open = Array<ulong>();
        _partners.reserve(_tokens.count);
        _commented_before.reserve(_tokens.count + 1);
        ulong commented = 0;
        ulong i = 0;
        while (i < _tokens.count) {
            _partners.append(0);
            _commented_before.append(commented);
            var token = _tokens[i];
            if (token.has_comments()) {
                commented += 1;
            }
            if (token.kind == TokenKind.Punctuation and token.size == 1) {
                int c = _source.byte_at(token.offset);
                if (c == '(' or c == '[' or c == '{') {
                    open.append(i);
                } else if ((c == ')' or c == ']' or c == '}') and !open.is_empty) {
                    var partner = open.pop();
                    _partners[partner] = i;
                    _partners[i] = partner;
                }
            }
            i += 1;
        }
        _commented_before.append(commented);
    }

    # The index of a statement's first token.
    _statement_first(statement: Statement): ulong {
        match (statement) {
            Expression(value) => {
                return _expression_first(value);
            }
            Declaration(declaration) => {
                return _index(start_of(declaration.span(), declaration.attributes()));
            }
            Branch(_, if_block, _, span) => {
                return _index(start_of(span, if_block.attributes));
            }
            else => {
                return _index(statement.span().start);
            }
        }
        return _index(statement.span().start);
    }

    # The index of an expression's first token.
    _expression_first(value: Expression): ulong {
        match (value) {
            SizeOf(type_name) => {
                # `sizeof<T>`, whose span is the type's.
                return _index(type_name.span.start) - 2;
            }
            Unary(_, prefix, operand, span) => {
                return prefix ? _index(span.start) : _expression_first(operand);
            }
            Cast(operand, _, _, _, _) => {
                return _expression_first(operand);
            }
            Binary(lhs, _, _, _) => {
                return _expression_first(lhs);
            }
            Ternary(condition, _, _, _) => {
                return _expression_first(condition);
            }
            Index(lhs, _, _) => {
                return _expression_first(lhs);
            }
            MemberAccess(lhs, _, _, _) => {
                return _expression_first(lhs);
            }
            FunctionCall(function, _, _) => {
                return _expression_first(function);
            }
            Is(operand, _, _, _) => {
                return _expression_first(operand);
            }
            else => {
                return _index(value.extent().start);
            }
        }
        return _index(value.extent().start);
    }

    # The index of the `End` token.
    _end_index(): ulong {
        return _tokens.count - 1;
    }

    # The index of the first token at or after `offset`.
    _index(offset: ulong): ulong {
        ulong low = 0;
        ulong high = _tokens.count - 1;
        while (low < high) {
            var middle = low + (high - low) / 2;
            if (_tokens[middle].offset < offset) {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        return low;
    }

    # Notes that the tree and the tokens disagree at the next token.
    _fail(message: String) {
        if (!error.is_empty) {
            return;
        }
        error_offset = _next < _tokens.count ? _tokens[_next].offset : _source.size;
        error = message;
    }

    # Whether token `index` is spelled `text`.
    _spells(index: ulong, text: String): bool {
        return index < _end_index() and _tokens[index].spells(_source, text);
    }

    # Whether the next token is spelled `text`.
    _at(text: String): bool {
        return _spells(_next, text);
    }

    # Whether token `index` carries a comment not yet laid out.
    _has_comments(index: ulong): bool {
        return _tokens[index].has_comments();
    }

    # Whether a token from `first` up to `end` carries a comment not yet laid
    # out.
    _range_has_comments(first: ulong, end: ulong): bool {
        ulong i = first;
        while (i < end) {
            if (_tokens[i].has_comments()) {
                return true;
            }
            i += 1;
        }
        return false;
    }

    # Whether a token from `first` up to `end` was parsed with a comment.
    _had_comments(first: ulong, end: ulong): bool {
        return end > first and _commented_before[end] > _commented_before[first];
    }

    # Whether a line break precedes token `index` in the source with a blank
    # line between, counting from the first comment above it.
    _blank_before(index: ulong): bool {
        var token = _tokens[index];
        if (token.has_leading_comments()) {
            return token.leading_comments[0].newlines_before >= 2;
        }
        return token.newlines_before >= 2;
    }

    # Replaces the comments above token `index`.
    _set_leading(index: ulong, comments: Comment[]) {
        var token = _tokens[index];
        token.leading_comments = comments;
        _tokens[index] = token;
    }

    # The comments above token `index`, each on its own line, then a line
    # break. They are removed from the token, so printing it later omits
    # them.
    _leading(index: ulong): Doc {
        var result = concat();
        var token = _tokens[index];
        if (!token.has_leading_comments()) {
            return result;
        }
        var comments = token.leading_comments;
        ulong i = 0;
        while (i < comments.count) {
            var comment = comments[i];
            if (i > 0 and comment.newlines_before >= 2) {
                result.add(hardline());
            }
            result.add(text(comment.text));
            result.add(hardline());
            i += 1;
        }
        if (token.newlines_after_comments >= 2) {
            result.add(hardline());
        }
        _set_leading(index, Array<Comment>());
        return result;
    }

    # Token `index` with its comments.
    _token_doc(index: ulong): Doc {
        var token = _tokens[index];
        if (!token.has_comments()) {
            return text(token.text(_source));
        }
        var result = concat();
        if (token.has_leading_comments()) {
            result.add(_leading(index));
            token = _tokens[index];
        }
        result.add(text(token.text(_source)));
        if (token.has_trailing_comment()) {
            result.add(trailing_comment(token.trailing_comment));
            token.trailing_comment = "";
            _tokens[index] = token;
        }
        return result;
    }

    # Takes the next token, which must be spelled `spelling`.
    _take(spelling: String): Doc {
        if (!_at(spelling)) {
            _fail($"expected '{spelling}'");
        }
        return _take_any();
    }

    # Takes the next token.
    _take_any(): Doc {
        if (_next >= _end_index()) {
            _fail("unexpected end of the tokens");
            return concat();
        }
        var result = _token_doc(_next);
        _next += 1;
        return result;
    }

    # The tokens before byte `end`, from the next one, one after another.
    _tokens_until(end: ulong): Doc {
        if (_next >= _end_index() or _tokens[_next].offset >= end) {
            _fail("expected a token");
            return concat();
        }
        # One token, the most common case (a name or a literal), needs no
        # sequence around it.
        if (_next + 1 >= _end_index() or _tokens[_next + 1].offset >= end) {
            return _take_any();
        }
        var result = concat();
        while (_next < _end_index() and _tokens[_next].offset < end) {
            result.add(_take_any());
        }
        return result;
    }

    # The tokens of `span`, which must start at the next token, one after
    # another.
    _span(span: Span): Doc {
        if (_next >= _end_index() or _tokens[_next].offset != span.start) {
            _fail($"expected a token at byte {span.start}");
        }
        return _tokens_until(span.end);
    }

    # ── format: off ──────────────────────────────────────────────────────────

    # The `# format: off` region that starts above `items[index]`, if one
    # does: the comments above it are laid out as usual, then everything
    # from `# format: off` through the matching `# format: on` is copied as
    # written. Without a `# format: on` among the items, the region ends at
    # one above `close` or else with the last item. The comments the region
    # covers are removed from the item after it, which lays out as usual.
    _format_off(items: Item[], index: ulong, close: ulong): Region? {
        var first = items[index].first;
        long off = directive_index(_tokens[first], "off", 0);
        if (off < 0) {
            return Optional<Region>.Empty;
        }
        var start = _tokens[first].leading_comments[off as ulong].offset;
        var layout = _leading_part(first, off as ulong);
        # Find the `# format: on`: above this item after the `off`, above a
        # later item, or above `close`.
        ulong next = index;
        long on = directive_index(_tokens[first], "on", off as ulong + 1);
        while (on < 0 and next + 1 < items.count) {
            next += 1;
            on = directive_index(_tokens[items[next].first], "on", 0);
        }
        ulong end = 0;
        if (on >= 0) {
            var token = items[next].first;
            end = line_end(_source, _tokens[token].leading_comments[on as ulong].offset);
            _drop_comments(token, on as ulong + 1);
        } else {
            next = items.count;
            on = directive_index(_tokens[close], "on", 0);
            if (on >= 0) {
                end = line_end(_source, _tokens[close].leading_comments[on as ulong].offset);
                _drop_comments(close, on as ulong + 1);
            } else {
                end = line_end(_source, _tokens[items[items.count - 1].last].offset);
            }
        }
        layout.add(text(source_text(_source, start, end)));
        return Optional<Region>.Value(Region(layout, next));
    }

    # The first `count` comments above token `index`, each on its own line,
    # with the blank line after them if the next comment has one. They are
    # removed from the token.
    _leading_part(index: ulong, count: ulong): Doc {
        var comments = _tokens[index].leading_comments;
        var result = concat();
        ulong i = 0;
        while (i < count) {
            var comment = comments[i];
            if (i > 0 and comment.newlines_before >= 2) {
                result.add(hardline());
            }
            result.add(text(comment.text));
            result.add(hardline());
            i += 1;
        }
        if (count > 0 and comments[count].newlines_before >= 2) {
            result.add(hardline());
        }
        var kept = Array<Comment>();
        while (i < comments.count) {
            kept.append(comments[i]);
            i += 1;
        }
        _set_leading(index, kept);
        return result;
    }

    # Removes the first `count` comments above token `index`. When none are
    # left, the line breaks after them become the token's own.
    _drop_comments(index: ulong, count: ulong) {
        var token = _tokens[index];
        var comments = token.leading_comments;
        var kept = Array<Comment>();
        ulong i = count;
        while (i < comments.count) {
            kept.append(comments[i]);
            i += 1;
        }
        token.leading_comments = kept;
        if (kept.is_empty) {
            token.newlines_before = token.newlines_after_comments;
            token.newlines_after_comments = 0;
        }
        _tokens[index] = token;
    }

    # ── Items ────────────────────────────────────────────────────────────────

    # The items of a module or a body whose items run from token `start` up
    # to `close`: `candidates`, in source order, with their last tokens, and
    # each `;` that ends nothing as an item of its own.
    _items(candidates: Item[], start: ulong, close: ulong): Item[] {
        sort_items(candidates);
        var out = Array<Item>();
        ulong position = start;
        ulong i = 0;
        while (i < candidates.count) {
            var item = candidates[i];
            _empty_items(position, item.first, out);
            ulong next = i + 1 < candidates.count ? candidates[i + 1].first : close;
            if (next <= item.first) {
                _next = item.first;
                _fail("expected the next item later");
                return out;
            }
            ulong last = next - 1;
            while (last > item.first and _spells(last, ";")) {
                last -= 1;
            }
            if (item.takes_semicolon and last + 1 < next) {
                last += 1;
            }
            item.last = last;
            out.append(item);
            position = last + 1;
            i += 1;
        }
        _empty_items(position, close, out);
        return out;
    }

    # Adds the tokens from `start` up to `end`, `;`s that end nothing, to
    # `out`.
    _empty_items(start: ulong, end: ulong, out: Item[]) {
        ulong position = start;
        while (position < end) {
            if (!_spells(position, ";")) {
                _next = position;
                _fail("expected ';'");
            }
            out.append(Item(Entry.Empty, position, false));
            position += 1;
        }
    }

    # Whether a declaration takes the `;` after it.
    _declaration_takes_semicolon(declaration: Declaration): bool {
        match (declaration) {
            Variable(_), TypeAlias(_) => {
                return true;
            }
            Function(decl) => {
                return !decl.body.is_value();
            }
            Extend(decl) => {
                return _extension_open(decl) < 0;
            }
            else => {
                return false;
            }
        }
        return false;
    }

    # The index of the `{` of an extension, or -1 for `extend X with T;`.
    _extension_open(decl: ExtendDecl): long {
        Span last = decl.target.span;
        if (decl.traits.count > 0) {
            last = decl.traits[decl.traits.count - 1].span;
        }
        var after = _index(last.end);
        if (_spells(after, "{")) {
            return after as long;
        }
        return -1;
    }

    # Whether a top-level item spans several lines (a struct, trait,
    # extension, or a function with a body), so it gets blank lines around
    # it.
    _is_big(item: Item): bool {
        if (item.entry is Declaration(declaration)) {
            return _is_big_declaration(declaration);
        }
        return false;
    }

    # `_is_big` of a declaration.
    _is_big_declaration(declaration: Declaration): bool {
        match (declaration) {
            Struct(_), Trait(_), Static(_) => {
                return true;
            }
            Extend(decl) => {
                # `extend X with Trait;` is one line.
                var open = _extension_open(decl);
                if (open < 0) {
                    return false;
                }
                if (decl.traits.count > 0) {
                    return !_is_empty_body(open as ulong);
                }
                return true;
            }
            Function(decl) => {
                return !decl.external and decl.body.is_value();
            }
            else => {
                return false;
            }
        }
        return false;
    }

    # Whether the `{` at `open` and its `}` hold nothing, and no comments
    # inside, which an extension that adopts a trait writes as `;`.
    _is_empty_body(open: ulong): bool {
        var close = _partners[open];
        if (close != open + 1) {
            return false;
        }
        var first = _tokens[open];
        return !first.has_leading_comments()
            and !first.has_trailing_comment()
            and !_tokens[close].has_leading_comments();
    }

    # The sort key of an import: modules (`import io`) before files of this
    # module (`import "util"`), each by name.
    _import_key(item: Item): String {
        if (item.entry is Import(declaration)) {
            var last = _index(declaration.name_span.end) - 1;
            var name = _tokens[last];
            if (name.kind == TokenKind.String) {
                return "1" + name.text(_source);
            }
            return "0" + name.text(_source);
        }
        return "";
    }

    # Sorts each group of adjacent imports (no blank line or comment between
    # them) in place, by `_import_key`. The comments above a group, and the
    # blank line after them, stay above it.
    _sort_imports(items: Item[]) {
        ulong start = 0;
        while (start < items.count) {
            if (!items[start].is_sortable_import()) {
                start += 1;
                continue;
            }
            ulong end = start + 1;
            while (end < items.count
                and items[end].is_sortable_import()
                and !_blank_before(items[end].first)
                and !_tokens[items[end].first].has_leading_comments()) {
                end += 1;
            }
            if (end - start > 1) {
                var first = _tokens[items[start].first];
                var comments = first.leading_comments;
                int newlines = first.newlines_before;
                int after_comments = first.newlines_after_comments;
                # The group's first import may move into the middle: it keeps
                # none of the spacing that belongs to the group's start.
                first.leading_comments = Array<Comment>();
                first.newlines_before = 1;
                first.newlines_after_comments = 0;
                _tokens[items[start].first] = first;
                var group = Array<Item>();
                ulong i = start;
                while (i < end) {
                    group.append(items[i]);
                    i += 1;
                }
                group.sort((a, b) => _import_key(a).compare(_import_key(b)));
                i = start;
                while (i < end) {
                    items[i] = group[i - start];
                    i += 1;
                }
                var new_first = _tokens[items[start].first];
                new_first.leading_comments = comments;
                new_first.newlines_before = newlines;
                new_first.newlines_after_comments = after_comments;
                _tokens[items[start].first] = new_first;
            }
            start = end;
        }
    }

    # The layout of one item, which starts at its first token.
    _item(item: Item): Doc {
        _next = item.first;
        var result = _entry(item.entry);
        if (_next != item.last + 1) {
            _fail("the item does not end where expected");
        }
        return result;
    }

    _entry(entry: Entry): Doc {
        match (entry) {
            Empty => {
                return _take(";");
            }
            Import(item) => {
                return _import_declaration(item);
            }
            Export(item) => {
                return _export_alias(item);
            }
            Declaration(declaration) => {
                return _declaration(declaration);
            }
            Statement(statement) => {
                return _statement(statement);
            }
            Method(decl) => {
                if (decl.external) {
                    return _extern_function(decl);
                }
                return _function(decl);
            }
            Property(decl) => {
                return _property(decl);
            }
            Field(decl) => {
                return _variable_statement(decl);
            }
            Constructor(decl) => {
                return _constructor(decl);
            }
            Case(item) => {
                return _enum_case(item);
            }
            Destructor(body) => {
                return _destructor(body);
            }
            Accessor(item) => {
                return _accessor(item);
            }
            Arm(arm) => {
                return _match_arm(arm);
            }
            ElseArm(body) => {
                return _else_arm(body);
            }
            ValueArm(arm) => {
                return _match_value_arm(arm);
            }
            ElseValue(value) => {
                return _else_value(value);
            }
        }
        return concat();
    }

    # ── Comments inside ──────────────────────────────────────────────────────

    # The comments above a closing token (`}` or the end of a list), indented
    # inside the construct it closes.
    _inner_comments(close: ulong, after_items: bool): Doc {
        var result = concat();
        if (!_tokens[close].has_leading_comments()) {
            return indent(result);
        }
        var comments = _tokens[close].leading_comments;
        ulong i = 0;
        while (i < comments.count) {
            var comment = comments[i];
            result.add(hardline());
            if (comment.newlines_before >= 2 and (after_items or i > 0)) {
                result.add(hardline());
            }
            result.add(text(comment.text));
            i += 1;
        }
        _set_leading(close, Array<Comment>());
        return indent(result);
    }

    # ── Prefixes ─────────────────────────────────────────────────────────────

    # The attributes (one per line) and `export` or `private` at the start
    # of a declaration, added to `result`.
    _prefix(attributes: Attribute[], exported: bool, file_private: bool, result: Doc) {
        for (var attribute in attributes) {
            result.add(_attribute(attribute));
            result.add(hardline());
        }
        if (exported) {
            result.add(_take("export"));
            result.add(text(" "));
        } else if (file_private) {
            result.add(_take("private"));
            result.add(text(" "));
        }
    }

    _attribute(attribute: Attribute): Doc {
        return concat().add(_take("[")).add(_expression(attribute.body)).add(_take("]"));
    }

    # ── Declarations ─────────────────────────────────────────────────────────

    _declaration(declaration: Declaration): Doc {
        match (declaration) {
            Variable(decl) => {
                return _variable_statement(decl);
            }
            Function(decl) => {
                if (decl.external) {
                    return _extern_function(decl);
                }
                return _function(decl);
            }
            Struct(decl) => {
                if (decl.enumeration.is_value()) {
                    return _enum(decl);
                }
                return _struct(decl);
            }
            Trait(decl) => {
                return _trait(decl);
            }
            Extend(decl) => {
                return _extension(decl);
            }
            TypeAlias(decl) => {
                return _type_alias(decl);
            }
            Static(block) => {
                return _static_block(block);
            }
        }
        return concat();
    }

    _import_declaration(item: Import): Doc {
        var result = concat();
        for (var attribute in item.attributes) {
            result.add(_attribute(attribute));
            result.add(hardline());
        }
        bool first = true;
        if (item.reexport) {
            # Like the `export` of a declaration, with its space.
            result.add(_take("export"));
            result.add(text(" "));
        } else {
            result.add(_take("import"));
            first = false;
        }
        var parts = Array<Doc>();
        var spellings = Array<String>();
        if (_at("*")) {
            parts.append(_take("*"));
            spellings.append("*");
            parts.append(_take("from"));
            spellings.append("from");
        }
        if (item.symbols.is_value()) {
            parts.append(_import_list(item.symbols.value()));
            spellings.append("[");
            parts.append(_take("from"));
            spellings.append("from");
        }
        if (_next >= _end_index() or _tokens[_next].offset != item.name_span.start) {
            _fail("expected the module name");
        }
        while (_next < _end_index() and _tokens[_next].offset < item.name_span.end) {
            spellings.append(_tokens[_next].text(_source));
            parts.append(_take_any());
        }
        if (_at("as")) {
            parts.append(_take("as"));
            spellings.append("as");
            spellings.append("");
            parts.append(_take_any());
        }
        if (_at(";")) {
            parts.append(_take(";"));
            spellings.append(";");
        }
        bool dotted = false;
        ulong i = 0;
        while (i < parts.count) {
            var spelling = spellings[i];
            # `import http.client`: the dot and the name after it stay tight.
            if (spelling == ";" or spelling == "." or dotted) {
                dotted = spelling == ".";
                result.add(parts[i]);
            } else {
                if (!first) {
                    result.add(text(" "));
                }
                result.add(parts[i]);
            }
            first = false;
            i += 1;
        }
        return result;
    }

    # `[a, b as c]` of an import.
    _import_list(symbols: ast.ImportedSymbol[]): Doc {
        var list = _open_list();
        ulong i = 0;
        for (var symbol in symbols) {
            if (i > 0) {
                _list_comma(list);
            }
            _item_start(list);
            # `name as alias`: the words separated by spaces.
            var entry = concat();
            bool first = true;
            if (_next >= _end_index() or _tokens[_next].offset != symbol.span.start) {
                _fail("expected an imported name");
            }
            while (_next < _end_index() and _tokens[_next].offset < symbol.span.end) {
                if (!first) {
                    entry.add(text(" "));
                }
                entry.add(_take_any());
                first = false;
            }
            _item_end(list, entry);
            i += 1;
        }
        _optional_comma(list);
        return _close_list(list);
    }

    _export_alias(item: ExportAlias): Doc {
        var result = concat();
        _prefix(item.attributes, true, false, result);
        result.add(_span(item.symbol_span));
        if (_at("as")) {
            result.add(text(" ")).add(_take("as")).add(text(" ")).add(_take_any());
        }
        if (_at(";")) {
            result.add(_take(";"));
        }
        return result;
    }

    # The `{ ... }` of a struct, trait, extension or enum, from the `{` at
    # the next token: `candidates` are its members.
    _members(candidates: Item[]): Doc {
        var open = _next;
        var close = _partners[open];
        var items = _items(candidates, open + 1, close);
        return _braced(concat(), items, open, close);
    }

    # The methods and properties of a member list, as items.
    _member_items(methods: FunctionDecl[], properties: PropertyDecl[]): Item[] {
        var out = Array<Item>();
        for (var method in methods) {
            out.append(Item(Entry.Method(method), _index(method.span.start), !method.body.is_value()));
        }
        for (var property in properties) {
            out.append(
                Item(
                    Entry.Property(property),
                    _index(start_of(property.span, property.attributes)),
                    property.default_value.is_value()
                )
            );
        }
        return out;
    }

    # The fields, constructors and destructor of a struct or enum, added to
    # `out`.
    _struct_items(decl: StructDecl, out: Item[]) {
        for (var field in decl.fields) {
            out.append(Item(Entry.Field(field), _index(start_of(field.span, field.attributes)), true));
        }
        for (var constructor in decl.constructors) {
            out.append(
                Item(Entry.Constructor(constructor), _index(start_of(constructor.span, constructor.attributes)), false)
            );
        }
        if (decl.destructor.is_value()) {
            var body = decl.destructor.value();
            out.append(
                Item(Entry.Destructor(body), _index(start_of(decl.destruct_span.value(), body.attributes)), false)
            );
        }
    }

    _struct(decl: StructDecl): Doc {
        var result = concat();
        _prefix(decl.attributes, decl.is_exported, decl.is_private, result);
        result.add(_take("struct"));
        result.add(text(" "));
        result.add(_take_any());
        if (_at("<")) {
            result.add(_generic_parameters(decl.generic_params));
        }
        var items = _member_items(decl.methods, decl.properties);
        _struct_items(decl, items);
        result.add(text(" "));
        result.add(_members(items));
        return result;
    }

    _trait(decl: TraitDecl): Doc {
        var result = concat();
        _prefix(decl.attributes, decl.is_exported, decl.is_private, result);
        result.add(_take("trait"));
        result.add(text(" "));
        result.add(_take_any());
        if (_at("<")) {
            result.add(_generic_parameters(decl.generic_params));
        }
        result.add(text(" "));
        result.add(_members(_member_items(decl.methods, decl.properties)));
        return result;
    }

    # `enum Name: T {`, then one case per line, then the methods.
    _enum(decl: StructDecl): Doc {
        var result = concat();
        _prefix(decl.attributes, decl.is_exported, decl.is_private, result);
        result.add(_take("enum"));
        result.add(text(" "));
        result.add(_take_any());
        if (_at("<")) {
            result.add(_generic_parameters(decl.generic_params));
        }
        var body = decl.enumeration.value();
        if (_at(":")) {
            result.add(_take(":"));
            result.add(text(" "));
            result.add(_type(body.representation.value().span));
        }
        var items = _member_items(decl.methods, decl.properties);
        _struct_items(decl, items);
        for (var item in body.cases) {
            items.append(Item(Entry.Case(item), _index(start_of(item.span, item.attributes)), false));
        }
        result.add(text(" "));
        result.add(_members(items));
        return result;
    }

    # `Name(payload) = value,`, with its attributes one per line above it.
    _enum_case(item: EnumCase): Doc {
        var result = concat();
        _prefix(item.attributes, false, false, result);
        result.add(_take_any());
        if (item.payload.is_value() and _at("(")) {
            result.add(_parameter_list(item.payload.value(), false, false));
        }
        if (_at("=")) {
            result.add(text(" ")).add(_take("=")).add(text(" "));
            result.add(_expression(item.value.value()));
        }
        if (_at(",")) {
            result.add(_take(","));
        }
        return result;
    }

    _extension(decl: ExtendDecl): Doc {
        var result = concat();
        _prefix(decl.attributes, decl.is_exported, decl.is_private, result);
        result.add(_take("extend"));
        result.add(text(" "));
        result.add(_type(decl.target.span));
        bool adopts = false;
        if (_at("with")) {
            adopts = true;
            result.add(text(" "));
            result.add(_take("with"));
            ulong i = 0;
            for (var adopted in decl.traits) {
                if (i > 0) {
                    result.add(_take(","));
                }
                result.add(text(" "));
                result.add(_type(adopted.span));
                i += 1;
            }
        }
        if (_at(";")) {
            result.add(_take(";"));
            return result;
        }
        if (adopts and _is_empty_body(_next)) {
            # `extend X with Trait {}` is written `extend X with Trait;`.
            var close = _next + 1;
            result.add(text(";"));
            var token = _tokens[close];
            if (token.has_trailing_comment()) {
                result.add(trailing_comment(token.trailing_comment));
                token.trailing_comment = "";
                _tokens[close] = token;
            }
            _next = close + 1;
            return result;
        }
        result.add(text(" "));
        result.add(_members(_member_items(decl.methods, decl.properties)));
        return result;
    }

    _type_alias(decl: TypeAliasDecl): Doc {
        var result = concat();
        _prefix(decl.attributes, decl.is_exported, decl.is_private, result);
        result.add(_take("type"));
        result.add(text(" "));
        result.add(_take_any());
        if (_at("<")) {
            result.add(_generic_parameters(decl.generic_params));
        }
        result.add(text(" "));
        result.add(_take("="));
        result.add(text(" "));
        result.add(_type(decl.target.span));
        if (_at(";")) {
            result.add(_take(";"));
        }
        return result;
    }

    _extern_function(decl: FunctionDecl): Doc {
        var result = concat();
        _prefix(decl.attributes, decl.is_exported, decl.is_private, result);
        result.add(_take("extern"));
        result.add(text(" "));
        result.add(_type(decl.return_type.span));
        result.add(text(" "));
        result.add(_take_any());
        result.add(_parameter_list(decl.parameters, false, decl.is_variadic));
        if (_at(";")) {
            result.add(_take(";"));
        }
        return result;
    }

    # A function or method, in the Pepper form `name(x: T): R` wherever the
    # grammar allows it: C-style `R name(T x)` becomes `name(x: T): R`, and
    # a `void` return type is left out when a body can infer it.
    # Operator methods and indexers keep their return type in front, since
    # the grammar has no other way to write them.
    _function(decl: FunctionDecl): Doc {
        var result = concat();
        _prefix(decl.attributes, decl.is_exported, decl.is_private, result);
        if (decl.is_static) {
            result.add(_take("static"));
            result.add(text(" "));
        }
        ulong first = _next;
        if (_at("[") or (!decl.is_indexer and _tokens[first].offset == decl.name_span.start)) {
            # `name(...)`, `==(...)` or `[](...)`.
            result.add(_take_any());
            if (_at("]")) {
                result.add(_take("]"));
            }
            _function_rest(decl, result);
            return result;
        }
        # `R name(...)`, `R ==(...)` or `R [](...)`, optionally with `: R2`,
        # which wins.
        ulong name = decl.is_indexer ? _index(decl.name_span.end) : _index(decl.name_span.start);
        ulong after_name = decl.is_indexer ? name + 2 : name + 1;
        bool has_parameters = _spells(after_name, "(");
        ulong after_parameters = has_parameters ? _partners[after_name] + 1 : after_name;
        bool annotated = _spells(after_parameters, ":");
        if (!annotated or !_range_has_comments(first, name)) {
            result.add(_leading(first));
            ulong i = name;
            while (i < after_name) {
                result.add(_token_doc(i));
                i += 1;
            }
            _next = after_name;
            if (has_parameters) {
                result.add(_parameter_list(decl.parameters, true, false));
            } else {
                result.add(text("()"));
            }
            if (annotated) {
                var colon = _next;
                var type_end = _index(decl.return_type.span.end);
                if (!_void_return(decl, colon + 1, type_end)) {
                    result.add(_token_doc(colon));
                    result.add(text(" "));
                    _next = colon + 1;
                    result.add(_type(decl.return_type.span));
                }
                _next = type_end;
            } else if (!_void_return(decl, first, name)) {
                result.add(text(": "));
                result.add(_type_range(first, name));
            }
            _function_body(decl, result);
            return result;
        }
        result.add(_type_range(first, name));
        result.add(text(" "));
        _next = name;
        while (_next < after_name) {
            result.add(_take_any());
        }
        if (!has_parameters) {
            # `R name: R2 { ... }`: the `:` stays against the name.
            result.add(_take(":"));
            result.add(_type(decl.return_type.span));
            _function_body(decl, result);
            return result;
        }
        _function_rest(decl, result);
        return result;
    }

    # Whether the return type in tokens `first` up to `end`, of function
    # `decl`, can be left out: it is `void` and `decl` has a body to infer it
    # from. A declaration without one (a trait method) keeps it.
    _void_return(decl: FunctionDecl, first: ulong, end: ulong): bool {
        return end == first + 1 and _spells(first, "void") and !_has_comments(first) and decl.body.is_value();
    }

    # The generic parameters, parameters, return annotation and body of a
    # function, from the next token on.
    _function_rest(decl: FunctionDecl, result: Doc) {
        if (_at("<")) {
            result.add(_generic_parameters(decl.generic_params));
        }
        if (_at("(")) {
            result.add(_parameter_list(decl.parameters, true, false));
        }
        if (_at(":")) {
            var colon = _next;
            var type_end = _index(decl.return_type.span.end);
            if (_void_return(decl, colon + 1, type_end)) {
                # `: void` says nothing: a function whose body returns
                # nothing infers `void`.
                _next = type_end;
            } else {
                result.add(_take(":"));
                result.add(text(" "));
                result.add(_type(decl.return_type.span));
            }
        }
        _function_body(decl, result);
    }

    # A function's body, or the `;` of one without.
    _function_body(decl: FunctionDecl, result: Doc) {
        if (decl.body.is_value()) {
            result.add(text(" "));
            result.add(_block(decl.body.value(), false));
        } else if (_at(";")) {
            result.add(_take(";"));
        }
    }

    _constructor(decl: FunctionDecl): Doc {
        var result = concat();
        _prefix(decl.attributes, false, false, result);
        result.add(_take_any());
        result.add(_parameter_list(decl.parameters, true, false));
        result.add(text(" "));
        result.add(_block(decl.body.value(), false));
        return result;
    }

    _destructor(body: Block): Doc {
        var result = concat();
        _prefix(body.attributes, false, false, result);
        result.add(_take("destruct"));
        result.add(text(" "));
        result.add(_block(body, false));
        return result;
    }

    _generic_parameters(list: GenericParam[]): Doc {
        var result = concat();
        result.add(_take("<"));
        ulong i = 0;
        for (var item in list) {
            if (i > 0) {
                result.add(_take(","));
                result.add(text(" "));
            }
            result.add(_take_any());
            # `T=Error`, but `T: Shape & Named = Square` once constrained.
            ulong b = 0;
            for (var bound in item.bounds) {
                if (b == 0) {
                    result.add(_take(":"));
                    result.add(text(" "));
                } else {
                    result.add(text(" "));
                    result.add(_take("&"));
                    result.add(text(" "));
                }
                result.add(_type(bound.span));
                b += 1;
            }
            if (item.default.is_value()) {
                if (item.bounds.count > 0) {
                    result.add(text(" "));
                    result.add(_take("="));
                    result.add(text(" "));
                } else {
                    result.add(_take("="));
                }
                result.add(_type(item.default.value().span));
            }
            i += 1;
        }
        if (_at(",")) {
            result.add(_take(","));
            result.add(text(" "));
        }
        result.add(_take(">"));
        return result;
    }

    # A variable, field or parameter with its value, without its `;`. With
    # `pepper_style`, a C-style `T name` parameter becomes `name: T`.
    _variable(decl: VariableDecl, value: Expression?, parameter: bool, pepper_style: bool): Doc {
        var result = concat();
        if (parameter) {
            # A parameter's attributes precede it on its line.
            for (var attribute in decl.attributes) {
                result.add(_attribute(attribute));
                result.add(text(" "));
            }
        } else {
            _prefix(decl.attributes, decl.is_exported, decl.is_private, result);
        }
        if (_at("this")) {
            # `this.field = value`
            result.add(_take("this"));
            result.add(_take("."));
            result.add(_take_any());
        } else if (_at("var") or _at("const")) {
            result.add(_take_any());
            result.add(text(" "));
            result.add(_take_any());
        } else if (_next < _end_index() and _tokens[_next].offset != decl.name_span.start and !_at("...")) {
            # `T name`
            var first = _next;
            var name = _index(decl.name_span.start);
            bool annotated = _spells(name + 1, ":");
            if (pepper_style and !annotated) {
                result.add(_leading(first));
                result.add(_token_doc(name));
                result.add(text(": "));
                result.add(_type_range(first, name));
            } else {
                result.add(_type_range(first, name));
                result.add(text(" "));
                result.add(_token_doc(name));
            }
            _next = name + 1;
        } else {
            result.add(_take_any());
        }
        if (_at(":")) {
            result.add(_take(":"));
            result.add(text(" "));
            result.add(_type(decl.type_name.span));
        }
        if (_at("=")) {
            result.add(text(" "));
            result.add(_take("="));
            result.add(text(" "));
            result.add(_expression(value.value()));
        }
        return result;
    }

    # A variable or field and its `;`.
    _variable_statement(decl: VariableDecl): Doc {
        var result = _variable(decl, decl.default_value, false, false);
        if (_at(";")) {
            result.add(_take(";"));
        }
        return result;
    }

    # ── Lists ────────────────────────────────────────────────────────────────

    # Starts a bracketed list at its open bracket, the next token.
    _open_list(): ListLayout {
        var list = ListLayout(_next, _has_comments(_next));
        _next += 1;
        return list;
    }

    # Marks the next token as the start of a list item.
    _item_start(list: ListLayout) {
        list.start = _next;
    }

    # Adds an item, whose tokens end before the next token.
    _item_end(list: ListLayout, item: Doc) {
        if (_had_comments(list.start, _next)) {
            list.comments = true;
        }
        # A wrapper, so that the `,` after the item stays outside its groups.
        list.items.append(concat().add(item));
    }

    # Adds the `,` after the last item to it.
    _list_comma(list: ListLayout) {
        if (_has_comments(_next)) {
            list.comments = true;
        }
        list.items.last().add(_take(","));
    }

    # Adds a `,` after the last item when there is one.
    _optional_comma(list: ListLayout) {
        if (_at(",") and !list.items.is_empty) {
            _list_comma(list);
        }
    }

    # Ends a list at its close bracket, the next token: on one line if it
    # fits, else all items on one indented line, else one item per line.
    _close_list(list: ListLayout): Doc {
        var close = _next;
        if (close != _partners[list.open]) {
            _fail("expected the end of the list");
        }
        _next = close + 1;
        bool comments = list.comments;
        var items = list.items;
        if (_tokens[close].has_leading_comments()) {
            comments = true;
        }
        var result = concat().add(_token_doc(list.open));
        if (items.is_empty) {
            result.add(_inner_comments(close, false));
            if (comments) {
                result.add(hardline());
            }
            return result.add(_token_doc(close));
        }
        var options = choice();
        if (!comments) {
            var flat = concat();
            var continued = concat();
            ulong k = 0;
            while (k < items.count) {
                if (k > 0) {
                    flat.add(text(" "));
                    continued.add(text(" "));
                }
                flat.add(items[k]);
                continued.add(items[k]);
                k += 1;
            }
            options.add(flat);
            options.add(concat().add(indent(concat().add(hardline()).add(continued))).add(hardline()));
        }
        var broken = concat();
        ulong k = 0;
        while (k < items.count) {
            broken.add(hardline());
            broken.add(items[k]);
            k += 1;
        }
        broken.add(_inner_comments(close, true));
        options.add(concat().add(indent(broken)).add(hardline()));
        result.add(options);
        return result.add(_token_doc(close));
    }

    # The parameters of a function, constructor, extern or enum case. With
    # `pepper_style`, they are written `name: T`; with `variadic`, a `...`
    # ends them.
    _parameter_list(parameters: VariableDecl[], pepper_style: bool, variadic: bool): Doc {
        var list = _open_list();
        ulong i = 0;
        for (var parameter in parameters) {
            if (i > 0) {
                _list_comma(list);
            }
            _item_start(list);
            _item_end(list, _variable(parameter, parameter.default_value, true, pepper_style));
            i += 1;
        }
        if (variadic) {
            if (i > 0) {
                _list_comma(list);
            }
            _item_start(list);
            _item_end(list, _take("..."));
        }
        _optional_comma(list);
        return _close_list(list);
    }

    # A list of expressions in brackets: arguments, an array, captures.
    _expression_list(elements: Expression[]): Doc {
        var list = _open_list();
        ulong i = 0;
        for (var element in elements) {
            if (i > 0) {
                _list_comma(list);
            }
            _item_start(list);
            _item_end(list, _expression(element));
            i += 1;
        }
        _optional_comma(list);
        return _close_list(list);
    }

    # The `(a, b: T)` of a closure.
    _closure_parameters(parameters: VariableDecl[]): Doc {
        var list = _open_list();
        ulong i = 0;
        for (var parameter in parameters) {
            if (i > 0) {
                _list_comma(list);
            }
            _item_start(list);
            var entry = concat().add(_take_any());
            if (_at(":")) {
                entry.add(_take(":")).add(text(" ")).add(_type(parameter.type_name.span));
            }
            _item_end(list, entry);
            i += 1;
        }
        _optional_comma(list);
        return _close_list(list);
    }

    # The `(a, (b, c: T))` of a destructuring.
    _bindings(bindings: DestructureBinding[]): Doc {
        var list = _open_list();
        ulong i = 0;
        for (var binding in bindings) {
            if (i > 0) {
                _list_comma(list);
            }
            _item_start(list);
            if (binding.name.is_empty) {
                _item_end(list, _bindings(binding.nested));
            } else {
                var entry = concat().add(_take_any());
                if (_at(":")) {
                    entry.add(_take(":")).add(text(" ")).add(_type(binding.type_name.span));
                }
                _item_end(list, entry);
            }
            i += 1;
        }
        _optional_comma(list);
        return _close_list(list);
    }

    # ── Blocks and statements ────────────────────────────────────────────────

    # A block from the next token: its attributes (when `attributes`, one
    # per line), then `{`, the statements one per line, `}`.
    _block(block: Block, attributes: bool): Doc {
        var result = concat();
        if (attributes) {
            for (var attribute in block.attributes) {
                result.add(_attribute(attribute));
                result.add(hardline());
            }
        }
        var open = _next;
        if (!_at("{")) {
            _fail("expected '{'");
        }
        var close = _partners[open];
        var candidates = Array<Item>();
        for (var statement in block.statements) {
            candidates.append(
                Item(Entry.Statement(statement), _statement_first(statement), statement_takes_semicolon(statement))
            );
        }
        return _braced(result, _items(candidates, open + 1, close), open, close);
    }

    # A braced body, added to `result`: `{`, the items one per line, `}`.
    _braced(result: Doc, items: Item[], open: ulong, close: ulong): Doc {
        _next = close + 1;
        if (items.is_empty and !_tokens[close].has_leading_comments()) {
            return result.add(_token_doc(open)).add(_token_doc(close));
        }
        if (items.count == 1
            and !_range_has_comments(open, close + 1)
            and _tokens[items[0].first].newlines_before == 0
            and _tokens[close].newlines_before == 0
            and items[0].is_jump()) {
            # One trivial statement written on one line stays there.
            var line_body = concat().add(_token_doc(open));
            line_body.add(indent(concat().add(line()).add(_item(items[0])))).add(line());
            _next = close + 1;
            return result.add(group(line_body.add(_token_doc(close))));
        }
        result.add(_token_doc(open));
        var body = concat();
        ulong index = 0;
        bool after_region = false;
        while (index < items.count) {
            var entry = items[index];
            if (index > 0 and !after_region and entry.is_empty() and _tokens[entry.first].newlines_before == 0) {
                body.add(_token_doc(entry.first));
                index += 1;
                continue;
            }
            body.add(hardline());
            if ((index > 0 or after_region) and _blank_before(entry.first)) {
                body.add(hardline());
            }
            var region = _format_off(items, index, close);
            if (region) {
                body.add(region.value().layout);
                index = region.value().next;
                after_region = true;
                continue;
            }
            after_region = false;
            body.add(_leading(entry.first));
            body.add(_item(entry));
            index += 1;
        }
        result.add(indent(body));
        result.add(_inner_comments(close, !items.is_empty));
        result.add(hardline());
        _next = close + 1;
        return result.add(_token_doc(close));
    }

    # `var name: T { get; set; } = value;`: the accessors on the line when
    # none has a body, one per line otherwise.
    _property(decl: PropertyDecl): Doc {
        var result = concat();
        _prefix(decl.attributes, false, false, result);
        result.add(_take("var")).add(text(" ")).add(_take_any());
        result.add(_take(":")).add(text(" ")).add(_type(decl.type_name.span));
        result.add(text(" ")).add(_accessors(decl));
        if (_at("=")) {
            result.add(text(" ")).add(_take("=")).add(text(" "));
            result.add(_expression(decl.default_value.value()));
            if (_at(";")) {
                result.add(_take(";"));
            }
        }
        return result;
    }

    _accessors(decl: PropertyDecl): Doc {
        var open = _next;
        var close = _partners[open];
        var accessors = Array<ast.Accessor>();
        bool getter_first = decl.getter.is_value()
            and (!decl.setter.is_value() or decl.getter.value().span.start < decl.setter.value().span.start);
        if (getter_first) {
            accessors.append(decl.getter.value());
        }
        if (decl.setter.is_value()) {
            accessors.append(decl.setter.value());
        }
        if (decl.getter.is_value() and !getter_first) {
            accessors.append(decl.getter.value());
        }
        bool bodies = false;
        for (var accessor in accessors) {
            if (accessor.function.body.is_value()) {
                bodies = true;
            }
        }
        if (bodies or _range_has_comments(open, close + 1)) {
            var items = Array<Item>();
            for (var accessor in accessors) {
                items.append(
                    Item(Entry.Accessor(accessor), _index(accessor.span.start), !accessor.function.body.is_value())
                );
            }
            return _braced(concat(), _items(items, open + 1, close), open, close);
        }
        var result = concat();
        result.add(_take("{"));
        for (var accessor in accessors) {
            result.add(text(" "));
            result.add(_accessor(accessor));
        }
        result.add(text(" "));
        result.add(_take("}"));
        return result;
    }

    # `get;` or `set { ... }`.
    _accessor(item: ast.Accessor): Doc {
        var result = concat().add(_take_any());
        if (item.function.body.is_value()) {
            result.add(text(" "));
            result.add(_block(item.function.body.value(), false));
        } else {
            result.add(_take(";"));
        }
        return result;
    }

    _statement(statement: Statement): Doc {
        match (statement) {
            Expression(value) => {
                var result = concat().add(_expression(value));
                if (_at(";")) {
                    result.add(_take(";"));
                }
                return result;
            }
            Block(block) => {
                return _block(block, true);
            }
            Declaration(declaration) => {
                return _declaration(declaration);
            }
            Branch(condition, if_block, else_block, _) => {
                var result = concat();
                _prefix(if_block.attributes, false, false, result);
                return _branch(condition, if_block, else_block, result);
            }
            While(condition, body, _) => {
                var result = concat().add(_take("while")).add(text(" ")).add(_expression(condition));
                return result.add(text(" ")).add(_block(body, false));
            }
            For(binding, pattern, iterable, body, _) => {
                var result = concat().add(_take("for")).add(text(" "));
                bool parenthesized = _at("(");
                if (parenthesized) {
                    result.add(_take("("));
                }
                if (pattern.count > 0) {
                    result.add(_take_any()).add(text(" ")).add(_bindings(pattern));
                } else {
                    result.add(_variable(binding, binding.default_value, false, false));
                }
                result.add(text(" ")).add(_take("in")).add(text(" ")).add(_expression(iterable));
                if (parenthesized) {
                    result.add(_take(")"));
                }
                return result.add(text(" ")).add(_block(body, false));
            }
            With(binding, scope, body, else_block, _) => {
                var result = concat().add(_take("with")).add(text(" "));
                bool parenthesized = _at("(");
                if (parenthesized) {
                    result.add(_take("("));
                }
                if (binding.is_value()) {
                    result.add(_variable(binding.value(), Optional<Expression>.Value(scope), false, false));
                } else {
                    result.add(_expression(scope));
                }
                if (parenthesized) {
                    result.add(_take(")"));
                }
                result.add(text(" ")).add(_block(body, false));
                if (else_block.is_value()) {
                    result.add(text(" ")).add(_take("else")).add(text(" ")).add(_block(else_block.value(), false));
                }
                return result;
            }
            Return(value, _) => {
                var result = concat().add(_take("return"));
                if (value.is_value()) {
                    result.add(text(" ")).add(_expression(value.value()));
                }
                if (_at(";")) {
                    result.add(_take(";"));
                }
                return result;
            }
            LoopBreak(_, _) => {
                var result = concat().add(_take_any());
                if (_at(";")) {
                    result.add(_take(";"));
                }
                return result;
            }
            Destructure(bindings, value, _, _) => {
                var result = concat().add(_take_any()).add(text(" ")).add(_bindings(bindings));
                result.add(text(" ")).add(_take("=")).add(text(" ")).add(_expression(value));
                if (_at(";")) {
                    result.add(_take(";"));
                }
                return result;
            }
            Match(m) => {
                return _match_statement(m);
            }
            Static(block) => {
                return _static_block(block);
            }
        }
        return concat();
    }

    # `if condition { ... } else ...`, from the `if`, added to `result`.
    _branch(condition: Expression, if_block: Block, else_block: Block?, result: Doc): Doc {
        result.add(_take("if")).add(text(" ")).add(_expression(condition));
        result.add(text(" ")).add(_block(if_block, false));
        if (!else_block.is_value()) {
            return result;
        }
        result.add(text(" ")).add(_take("else")).add(text(" "));
        var other = else_block.value();
        if (other.statements.count == 1 and _at_branch(other)) {
            if (other.statements[0] is Branch(inner_condition, inner_block, inner_else, _)) {
                # `else [Unlikely] if (x)`: the attributes stay on the line.
                var inner = concat();
                for (var attribute in inner_block.attributes) {
                    inner.add(_attribute(attribute)).add(text(" "));
                }
                result.add(_branch(inner_condition, inner_block, inner_else, inner));
            }
            return result;
        }
        return result.add(_block(other, true));
    }

    # Whether `other`, an `else` block, stands for an `else if`: a block
    # that only holds the `if`, spanning just that.
    _at_branch(other: Block): bool {
        if (other.statements[0] is Branch(_, _, _, span)) {
            return span.start == other.span.start and span.end == other.span.end;
        }
        return false;
    }

    # `static (captures) { ... }`, with a module-scope block's attributes
    # and `export`.
    _static_block(block: StaticBlock): Doc {
        var result = concat();
        _prefix(block.attributes, block.is_exported, block.is_private, result);
        result.add(_take("static"));
        if (_at("(")) {
            var list = _open_list();
            ulong i = 0;
            for (var capture in block.written_captures) {
                if (i > 0) {
                    _list_comma(list);
                }
                _item_start(list);
                _item_end(list, _expression(capture));
                i += 1;
            }
            _optional_comma(list);
            result.add(text(" ")).add(_close_list(list));
        }
        return result.add(text(" ")).add(_block(block.block, false));
    }

    # `match value { arms }`, a statement.
    _match_statement(m: Match): Doc {
        var result = concat().add(_take("match")).add(text(" ")).add(_expression(m.value)).add(text(" "));
        var open = _next;
        var close = _partners[open];
        var candidates = Array<Item>();
        for (var arm in m.arms) {
            candidates.append(Item(Entry.Arm(arm), _index(start_of(arm.span, arm.body.attributes)), false));
        }
        if (m.else_block.is_value()) {
            var body = m.else_block.value();
            candidates.append(Item(Entry.ElseArm(body), _index(start_of(m.else_span, body.attributes)), false));
        }
        return result.add(_braced(concat(), _items(candidates, open + 1, close), open, close));
    }

    # `match value { arms }`, an expression.
    _match_expression(m: MatchExpression): Doc {
        var result = concat().add(_take("match")).add(text(" ")).add(_expression(m.value)).add(text(" "));
        var open = _next;
        var close = _partners[open];
        var candidates = Array<Item>();
        for (var arm in m.arms) {
            candidates.append(Item(Entry.ValueArm(arm), _index(arm.span.start), false));
        }
        if (m.else_value.is_value()) {
            candidates.append(Item(Entry.ElseValue(m.else_value.value()), _index(m.else_span.start), false));
        }
        return result.add(_braced(concat(), _items(candidates, open + 1, close), open, close));
    }

    # `A, B if x > 0 =>`, the start of an arm, added to `result`.
    _arm_patterns(patterns: ast.Pattern[], guard: Expression?, result: Doc) {
        ulong i = 0;
        for (var item in patterns) {
            if (i > 0) {
                result.add(_take(","));
                result.add(text(" "));
            }
            result.add(_pattern(item));
            i += 1;
        }
        if (guard.is_value()) {
            result.add(text(" ")).add(_take("if")).add(text(" ")).add(_expression(guard.value()));
        }
        result.add(text(" ")).add(_take("=>")).add(text(" "));
    }

    # `A, B => { ... }`, with `[Likely]` or `[Unlikely]` on its own line
    # above it.
    _match_arm(arm: MatchArm): Doc {
        var result = concat();
        for (var attribute in arm.body.attributes) {
            result.add(_attribute(attribute)).add(hardline());
        }
        _arm_patterns(arm.patterns, arm.guard, result);
        result.add(_block(arm.body, false));
        if (_at(",")) {
            result.add(_take(","));
        }
        return result;
    }

    _else_arm(body: Block): Doc {
        var result = concat();
        for (var attribute in body.attributes) {
            result.add(_attribute(attribute)).add(hardline());
        }
        result.add(_take("else")).add(text(" ")).add(_take("=>")).add(text(" "));
        result.add(_block(body, false));
        if (_at(",")) {
            result.add(_take(","));
        }
        return result;
    }

    _match_value_arm(arm: MatchValueArm): Doc {
        var result = concat();
        _arm_patterns(arm.patterns, arm.guard, result);
        result.add(_expression(arm.value));
        if (_at(",")) {
            result.add(_take(","));
        }
        return result;
    }

    _else_value(value: Expression): Doc {
        var result = concat().add(_take("else")).add(text(" ")).add(_take("=>")).add(text(" "));
        result.add(_expression(value));
        if (_at(",")) {
            result.add(_take(","));
        }
        return result;
    }

    # `Enum.Case(x, y)`: tight, with a space after each `,`.
    _pattern(item: ast.Pattern): Doc {
        var result = concat();
        if (item.elements.is_value()) {
            result.add(_take("("));
            ulong i = 0;
            for (var element in item.elements.value()) {
                if (i > 0) {
                    result.add(_take(",")).add(text(" "));
                }
                result.add(_pattern(element));
                i += 1;
            }
            return result.add(_take(")"));
        }
        if (item.literal.is_value()) {
            result.add(_expression(item.literal.value()));
            if (item.range_end.is_value()) {
                result.add(_take_any());
                result.add(_expression(item.range_end.value()));
            }
            return result;
        }
        result.add(_take_any());
        while (_at(".") and !_tokens[_next].space_before and !_tokens[_next + 1].space_before) {
            result.add(_take(".")).add(_take_any());
        }
        if (_at("<") and !_tokens[_next].space_before) {
            # A type pattern's type arguments, `Box<int>(b)`.
            var close = _angle_end(_next);
            result.add(_type_range(_next, close + 1));
            _next = close + 1;
        }
        if (item.bindings.is_value()) {
            result.add(_take("("));
            for (var binding in item.bindings.value()) {
                result.add(_pattern(binding));
                if (_at(",")) {
                    result.add(_take(",")).add(text(" "));
                }
            }
            result.add(_take(")"));
        }
        return result;
    }

    # The index of the `>` that closes the `<` at `open`.
    _angle_end(open: ulong): ulong {
        int depth = 0;
        ulong i = open;
        while (i < _end_index()) {
            if (_spells(i, "<")) {
                depth += 1;
            } else if (_spells(i, ">")) {
                depth -= 1;
                if (depth == 0) {
                    return i;
                }
            }
            i += 1;
        }
        _fail("expected '>'");
        return open;
    }

    # ── Types ────────────────────────────────────────────────────────────────

    # Token `index` of a type, with the spaces around it: `, ` between
    # arguments, ` => ` and ` & ` spaced, `: ` after a label or a
    # constraint, and a space after `shared` or `extern`.
    _type_token(index: ulong): Doc {
        var token = _token_doc(index);
        if (_spells(index, ",") or _spells(index, ":") or _spells(index, "shared") or _spells(index, "extern")) {
            return token.add(text(" "));
        }
        if (_spells(index, "=>") or _spells(index, "&")) {
            return concat().add(text(" ")).add(token).add(text(" "));
        }
        return token;
    }

    # The type in tokens `first` up to `end`.
    _type_range(first: ulong, end: ulong): Doc {
        var result = concat();
        ulong i = first;
        while (i < end) {
            result.add(_type_token(i));
            i += 1;
        }
        return result;
    }

    # The type written at `span`, from the next token.
    _type(span: Span): Doc {
        if (_next >= _end_index() or _tokens[_next].offset != span.start) {
            _fail($"expected a type at byte {span.start}");
        }
        var first = _next;
        while (_next < _end_index() and _tokens[_next].offset < span.end) {
            _next += 1;
        }
        return _type_range(first, _next);
    }

    # ── Expressions ──────────────────────────────────────────────────────────

    _expression(item: Expression): Doc {
        match (item) {
            Literal(_, span) => {
                return _span(span);
            }
            SymbolRef(_, span) => {
                return _span(span);
            }
            Interpolated(_, span) => {
                return _span(span);
            }
            FormatString(_, span, _, _) => {
                return _span(span);
            }
            TypeLiteral(type_name) => {
                return _type(type_name.span);
            }
            SizeOf(type_name) => {
                var result = concat().add(_take("sizeof")).add(_take("<")).add(_type(type_name.span)).add(_take(">"));
                if (_at("(")) {
                    result.add(_take("(")).add(_take(")"));
                }
                return result;
            }
            Unary(op, prefix, operand, _) => {
                if (!prefix) {
                    return concat().add(_expression(operand)).add(_take(op));
                }
                var result = concat().add(_take(op));
                var next = _tokens[_next].text(_source);
                # `- -x` must not print as the `--` operator.
                if ((op == "-" or op == "+") and (next.starts_with("-") or next.starts_with("+"))) {
                    result.add(text(" "));
                }
                return result.add(_expression(operand));
            }
            Cast(value, type_name, _, _, optional) => {
                var result = concat().add(_expression(value)).add(text(" ")).add(_take("as"));
                # `as?` keeps its `?` against the keyword.
                if (optional) {
                    result.add(_take("?"));
                }
                return result.add(text(" ")).add(_type(type_name.span));
            }
            Binary(_, _, _, _) => {
                return _binary(item);
            }
            Ternary(condition, true_value, false_value, _) => {
                var head = _expression(condition);
                var rest = concat().add(text(" ")).add(_take("?")).add(line()).add(_expression(true_value));
                rest.add(text(" ")).add(_take(":")).add(line()).add(_expression(false_value));
                return group(concat().add(head).add(indent(rest)));
            }
            Index(lhs, rhs, _) => {
                return concat().add(_expression(lhs)).add(_take("[")).add(_expression(rhs)).add(_take("]"));
            }
            MemberAccess(lhs, _, _, _) => {
                if (called_members(item) >= 3) {
                    return _member_chain(item);
                }
                return concat().add(_expression(lhs)).add(_member_tail(item));
            }
            FunctionCall(function, arguments, _) => {
                if (called_members(item) >= 3) {
                    return _member_chain(item);
                }
                return concat().add(_expression(function)).add(_expression_list(arguments));
            }
            NamedArgument(_, _, value, _) => {
                var result = concat().add(_take_any()).add(text(" ")).add(_take("="));
                return result.add(text(" ")).add(_expression(value));
            }
            Closure(closure) => {
                var result = concat().add(_closure_parameters(closure.parameters));
                if (_at(":")) {
                    result.add(_take(":")).add(text(" ")).add(_type(closure.return_type.span));
                }
                result.add(text(" ")).add(_take("=>")).add(text(" "));
                if (closure.expression_body) {
                    if (closure.body.statements[0] is Return(value, _)) {
                        result.add(_expression(value.value()));
                    }
                    return result;
                }
                return result.add(_block(closure.body, false));
            }
            Tuple(elements, labels, _) => {
                var list = _open_list();
                ulong i = 0;
                ulong label = 0;
                for (var element in elements) {
                    if (i > 0) {
                        _list_comma(list);
                    }
                    _item_start(list);
                    var entry = concat();
                    if (label < labels.count and _tokens[_next].offset == labels[label].span.start) {
                        # `line: 3`
                        entry.add(_take_any()).add(_take(":")).add(text(" "));
                        label += 1;
                    }
                    entry.add(_expression(element));
                    _item_end(list, entry);
                    i += 1;
                }
                _optional_comma(list);
                return _close_list(list);
            }
            ArrayLiteral(elements, _) => {
                return _expression_list(elements);
            }
            MapLiteral(entries, _) => {
                var list = _open_list();
                if (entries.is_empty) {
                    # `[:]`
                    _item_start(list);
                    _item_end(list, _take(":"));
                }
                ulong i = 0;
                for (var entry in entries) {
                    if (i > 0) {
                        _list_comma(list);
                    }
                    _item_start(list);
                    # `"key": value`
                    var pair = concat().add(_expression(entry.key)).add(_take(":")).add(text(" "));
                    _item_end(list, pair.add(_expression(entry.value)));
                    i += 1;
                }
                _optional_comma(list);
                return _close_list(list);
            }
            Match(m) => {
                return _match_expression(m);
            }
            Is(value, pattern, _, _) => {
                var result = concat().add(_expression(value)).add(text(" ")).add(_take("is"));
                return result.add(text(" ")).add(_pattern(pattern));
            }
            Parenthesized(value, _) => {
                return concat().add(_take("(")).add(_expression(value)).add(_take(")"));
            }
        }
        return concat();
    }

    # `.name` and the type arguments after it, from the `.`.
    _member_tail(item: Expression): Doc {
        var result = concat();
        if (item is MemberAccess(_, _, name_span, span)) {
            result.add(_take("."));
            if (_next >= _end_index() or _tokens[_next].offset != name_span.start) {
                _fail("expected the member's name");
            }
            result.add(_take_any());
            var first = _next;
            while (_next < _end_index() and _tokens[_next].offset < span.end) {
                _next += 1;
            }
            result.add(_type_range(first, _next));
        }
        return result;
    }

    # `a.b(x).c(y).d(z)`, three calls or more: on one line if it fits, else
    # a line break before each called member, indented under the first
    # operand.
    _member_chain(item: Expression): Doc {
        var links = Array<Expression>();
        var base = item;
        while (is_link(base)) {
            links.append(base);
            if (base is FunctionCall(function, _, _)) {
                base = function;
            } else if (base is MemberAccess(lhs, _, _, _)) {
                base = lhs;
            } else if (base is Index(lhs, _, _)) {
                base = lhs;
            }
        }
        links.reverse();
        var head = _expression(base);
        var rest = concat();
        ulong i = 0;
        while (i < links.count) {
            var link = links[i];
            bool called = i + 1 < links.count and links[i + 1] is FunctionCall(_, _, _);
            if (link is MemberAccess(_, _, _, _)) {
                if (called) {
                    rest.add(softline());
                }
                rest.add(_member_tail(link));
            } else if (link is FunctionCall(_, arguments, _)) {
                rest.add(_expression_list(arguments));
            } else if (link is Index(_, index, _)) {
                rest.add(_take("[")).add(_expression(index)).add(_take("]"));
            }
            i += 1;
        }
        return group(concat().add(head).add(indent(rest)));
    }

    # A binary expression. A chain of operators of one precedence breaks
    # before each operator.
    _binary(item: Expression): Doc {
        match (item) {
            Binary(lhs, op, rhs, _) => {
                return _binary_parts(item, lhs, op, rhs);
            }
            else => {
                return concat();
            }
        }
        return concat();
    }

    # `_binary` of `item`, which is `lhs op rhs`.
    _binary_parts(item: Expression, lhs: Expression, op: String, rhs: Expression): Doc {
        int level = precedence(op);
        if (op == ".." or op == "..>") {
            # A range reads as one unit: `0..count`.
            return concat().add(_expression(lhs)).add(_take(op)).add(_expression(rhs));
        }
        if (level == 0) {
            var result = concat().add(_expression(lhs)).add(text(" ")).add(_take(op));
            return result.add(text(" ")).add(_expression(rhs));
        }
        # Flatten `a + b + c`, which is ((a + b) + c), into its operands.
        var operands = Array<Expression>();
        var operators = Array<String>();
        var current = item;
        while (true) {
            if (current is Binary(left, operator, right, _)) {
                if (precedence(operator) == level) {
                    operands.append(right);
                    operators.append(operator);
                    current = left;
                    continue;
                }
            }
            break;
        }
        operands.append(current);
        operands.reverse();
        operators.reverse();
        var head = _expression(operands[0]);
        var rest = concat();
        ulong i = 0;
        while (i < operators.count) {
            rest.add(line());
            rest.add(_take(operators[i]));
            rest.add(text(" "));
            rest.add(_expression(operands[i + 1]));
            i += 1;
        }
        return group(concat().add(head).add(indent(rest)));
    }
}

## Aligns trailing comments on consecutive lines to one column, and removes
## the `comment_mark()`s that `render` put before them.
##
## @param printed the output of `render`
## @param newline the line ending to write, `"\n"` or `"\r\n"`
## @returns the final text
export align_trailing_comments(printed: String, newline: String): String {
    var lines = printed.lines();
    var codes = Array<String>();
    var comments = Array<String>();
    for (var entry in lines) {
        long mark = entry.find(comment_mark());
        if (mark < 0) {
            codes.append(entry);
            comments.append("");
        } else {
            ulong after = mark as ulong + 1;
            codes.append(entry.substr_bytes(0, mark as ulong).trim_end());
            comments.append(entry.substr_bytes(after, entry.size - after));
        }
    }
    var result = StringBuilder();
    ulong index = 0;
    while (index < lines.count) {
        if (comments[index].is_empty or codes[index].is_empty) {
            result.append(codes[index]).append(comments[index]).append(newline);
            index += 1;
            continue;
        }
        ulong end = index;
        ulong column = 0;
        while (end < lines.count and !comments[end].is_empty and !codes[end].is_empty) {
            if (codes[end].length > column) {
                column = codes[end].length;
            }
            end += 1;
        }
        column += 2;
        while (index < end) {
            var code = codes[index];
            result.append(code).append(" ".repeat(column - code.length)).append(comments[index]).append(newline);
            index += 1;
        }
    }
    return result.to_string();
}

## Formats Pepper source text in the standard style.
##
## @param source the text of a Pepper source file
## @returns the formatted text, or the syntax error that stopped it
export format_source(source: String): Result<String, SyntaxError> {
    var parsed = parse.parse_written(source, false);
    if (parsed.is_err()) {
        var error = parsed.error();
        return Result<String, SyntaxError>.err(SyntaxError(error.message, error.span.start));
    }
    if (source.is_empty) {
        return Result<String, SyntaxError>.ok("");
    }
    var newline = "\n";
    long first_break = source.find("\n");
    if (first_break > 0 and source.byte_at((first_break - 1) as ulong) == '\r') {
        newline = "\r\n";
    }
    var module = parsed.value();
    var formatter = Formatter(module.tokens.value());
    var layout = formatter.format(module);
    if (!formatter.error.is_empty) {
        return Result<String, SyntaxError>.err(
            SyntaxError("cannot lay out this file: " + formatter.error, formatter.error_offset)
        );
    }
    return Result<String, SyntaxError>.ok(align_trailing_comments(render(layout, LINE_WIDTH), newline));
}
