## Turns a syntax tree into a layout `Doc` in the standard Pepper style.
##
## The style: 4-space indentation, lines of at most 120 columns, braces on
## the line of the construct that owns them (`} else {`), one attribute per
## line above its target, at most one blank line in a row and one between
## top-level declarations, imports sorted within each group, trailing
## comments aligned, and Pepper functions declared as `f(x: int): int`
## (C-style `int f(int x)` is for `extern` functions only). Semicolons,
## parentheses around conditions, and line endings are kept as written.

import syntax;
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

# Whether a line break precedes `node` in the source with a blank line
# between, counting from the first comment above it.
blank_before(node: syntax.Node): bool {
    var token = node.first_token();
    if (token.leading_comments.count() > 0) {
        return token.leading_comments[0].newlines_before >= 2;
    }
    return token.newlines_before >= 2;
}

# Whether a top-level declaration spans several lines (a struct, trait,
# extension, or a function with a body), so it gets blank lines around it.
is_big(node: syntax.Node): bool {
    match (node.kind) {
        Struct, Trait, Extend, Enum => {
            return true;
        }
        Function => {
            return node.child(node.count() - 1).kind == syntax.NodeKind.Block;
        }
        else => {
            return false;
        }
    }
    return false;
}

# Whether `node` is a bare `void`, with no comments to keep, which a
# function's signature leaves out.
is_void(node: syntax.Node): bool {
    return node.kind == syntax.NodeKind.Type
        and node.count() == 1
        and node.child(0).is_token("void")
        and !node.has_comments();
}

# Whether `item` is an import that sorting may move: not an `export ...
# from`, whose order decides which of two colliding re-exports is reported.
is_sortable_import(item: syntax.Node): bool {
    if (item.kind != syntax.NodeKind.Import) {
        return false;
    }
    for (var child in item.children) {
        if (child.is_token("export")) {
            return false;
        }
    }
    return true;
}

# The sort key of an import: modules (`import io`) before files of this
# module (`import "util"`), each by name.
import_key(item: syntax.Node): String {
    ulong i = item.count();
    while (i > 0) {
        i -= 1;
        var child = item.child(i);
        if (child.kind != syntax.NodeKind.Token or child.is_token(";")) {
            continue;
        }
        # The name is the last token that is not an `as` alias.
        if (i >= 2 and item.child(i - 1).is_token("as")) {
            i -= 1;
            continue;
        }
        var name = child.leaf;
        if (name.kind == syntax.TokenKind.String) {
            return "1" + name.text;
        }
        return "0" + name.text;
    }
    return "";
}

# Sorts each group of adjacent imports (no blank line or comment between
# them) in place, by `import_key`. The comments above a group, and the
# blank line after them, stay above it.
sort_imports(items: syntax.Node[]) {
    ulong start = 0;
    while (start < items.count()) {
        if (!is_sortable_import(items[start])) {
            start += 1;
            continue;
        }
        ulong end = start + 1;
        while (end < items.count()
            and is_sortable_import(items[end])
            and !blank_before(items[end])
            and items[end].first_token().leading_comments.count() == 0) {
            end += 1;
        }
        if (end - start > 1) {
            var first = items[start].first_token();
            var comments = first.leading_comments;
            int newlines = first.newlines_before;
            int after_comments = first.newlines_after_comments;
            # The group's first import may move into the middle: it keeps
            # none of the spacing that belongs to the group's start.
            first.leading_comments = Array<syntax.Comment>();
            first.newlines_before = 1;
            first.newlines_after_comments = 0;
            var group = Array<syntax.Node>();
            ulong i = start;
            while (i < end) {
                group.append(items[i]);
                i += 1;
            }
            group.sort((a, b) => import_key(a).compare(import_key(b)));
            i = start;
            while (i < end) {
                items[i] = group[i - start];
                i += 1;
            }
            var new_first = items[start].first_token();
            new_first.leading_comments = comments;
            new_first.newlines_before = newlines;
            new_first.newlines_after_comments = after_comments;
        }
        start = end;
    }
}

# The index of the first comment above `token`, from `start` on, that reads
# `# format: <word>`, or -1.
directive_index(token: syntax.Token, word: String, start: ulong): long {
    var directive = "# format: " + word;
    ulong i = start;
    while (i < token.leading_comments.count()) {
        if (token.leading_comments[i].text == directive) {
            return i as long;
        }
        i += 1;
    }
    return -1;
}

# Removes the first `count` comments above `token`. When none are left, the
# line breaks after them become the token's own.
drop_comments(token: syntax.Token, count: ulong) {
    var kept = Array<syntax.Comment>();
    ulong i = count;
    while (i < token.leading_comments.count()) {
        kept.append(token.leading_comments[i]);
        i += 1;
    }
    token.leading_comments = kept;
    if (kept.empty()) {
        token.newlines_before = token.newlines_after_comments;
        token.newlines_after_comments = 0;
    }
}

# The offset of the end of the line holding `offset` in `source`, before
# its line break and any trailing whitespace.
line_end(source: String, offset: ulong): ulong {
    var data = source.c_str();
    var end = source.size();
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

## Builds the layout of a syntax tree in the standard style.
export struct Formatter {
    # The text being formatted, which `# format: off` regions copy.
    String _source = "";

    ## Creates a formatter.
    ##
    ## @param source the text the tree was parsed from, which
    ##     `# format: off` regions are copied from
    construct(source: String = "") {
        _source = source;
    }

    ## Returns the layout of a whole file.
    ##
    ## @param module the root of a syntax tree, a `NodeKind.Module`
    ## @returns the file's layout, to `render` at `LINE_WIDTH`
    format(module: syntax.Node): Doc {
        var items = Array<syntax.Node>();
        ulong i = 0;
        while (i + 1 < module.count()) {
            items.append(module.child(i));
            i += 1;
        }
        sort_imports(items);
        var result = concat();
        var end = module.child(module.count() - 1).leaf;
        ulong index = 0;
        bool after_region = false;
        while (index < items.count()) {
            var item = items[index];
            if (after_region) {
                result.add(hardline());
                if (blank_before(item)) {
                    result.add(hardline());
                }
            } else if (index > 0) {
                var previous = items[index - 1];
                if (item.kind == syntax.NodeKind.Empty and item.first_token().newlines_before == 0) {
                    result.add(_token_doc(item.first_token()));
                    index += 1;
                    continue;
                }
                result.add(hardline());
                if (blank_before(item) or is_big(item) or is_big(previous)) {
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
            result.add(_leading(item.first_token()));
            result.add(_node(item));
            index += 1;
        }
        ulong c = 0;
        while (c < end.leading_comments.count()) {
            var comment = end.leading_comments[c];
            if (items.count() > 0 or c > 0) {
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

    # ── format: off ──────────────────────────────────────────────────────────

    # The `# format: off` region that starts above `items[index]`, if one
    # does: the comments above it are laid out as usual, then everything
    # from `# format: off` through the matching `# format: on` is copied as
    # written. Without a `# format: on` among the items, the region ends at
    # one above `close` or else with the last item. The comments the region
    # covers are removed from the item after it, which lays out as usual.
    _format_off(items: syntax.Node[], index: ulong, close: syntax.Token): Region? {
        var first = items[index].first_token();
        long off = directive_index(first, "off", 0);
        if (off < 0) {
            return Optional<Region>.none();
        }
        var start = first.leading_comments[off as ulong].offset;
        var layout = _leading_part(first, off as ulong);
        # Find the `# format: on`: above this item after the `off`, above a
        # later item, or above `close`.
        ulong next = index;
        long on = directive_index(first, "on", off as ulong + 1);
        while (on < 0 and next + 1 < items.count()) {
            next += 1;
            on = directive_index(items[next].first_token(), "on", 0);
        }
        ulong end = 0;
        if (on >= 0) {
            var token = items[next].first_token();
            end = line_end(_source, token.leading_comments[on as ulong].offset);
            drop_comments(token, on as ulong + 1);
        } else {
            next = items.count();
            on = directive_index(close, "on", 0);
            if (on >= 0) {
                end = line_end(_source, close.leading_comments[on as ulong].offset);
                drop_comments(close, on as ulong + 1);
            } else {
                end = line_end(_source, items[items.count() - 1].last_token().offset);
            }
        }
        layout.add(text(source_text(_source, start, end)));
        return Optional<Region>.some(Region(layout, next));
    }

    # The first `count` comments above `token`, each on its own line, with
    # the blank line after them if the next comment has one. They are removed
    # from the token.
    _leading_part(token: syntax.Token, count: ulong): Doc {
        var result = concat();
        ulong i = 0;
        while (i < count) {
            var comment = token.leading_comments[i];
            if (i > 0 and comment.newlines_before >= 2) {
                result.add(hardline());
            }
            result.add(text(comment.text));
            result.add(hardline());
            i += 1;
        }
        if (count > 0 and token.leading_comments[count].newlines_before >= 2) {
            result.add(hardline());
        }
        var kept = Array<syntax.Comment>();
        while (i < token.leading_comments.count()) {
            kept.append(token.leading_comments[i]);
            i += 1;
        }
        token.leading_comments = kept;
        return result;
    }

    # ── Tokens and comments ──────────────────────────────────────────────────

    # The comments above `token`, each on its own line, then a line break.
    # They are removed from the token, so printing it later omits them.
    _leading(token: syntax.Token): Doc {
        var result = concat();
        ulong count = token.leading_comments.count();
        if (count == 0) {
            return result;
        }
        ulong i = 0;
        while (i < count) {
            var comment = token.leading_comments[i];
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
        token.leading_comments = Array<syntax.Comment>();
        return result;
    }

    # A token with its comments.
    _token_doc(token: syntax.Token): Doc {
        var result = concat();
        result.add(_leading(token));
        result.add(text(token.text));
        if (!token.trailing_comment.empty()) {
            result.add(trailing_comment(token.trailing_comment));
            token.trailing_comment = "";
        }
        return result;
    }

    # A token leaf with its comments.
    _leaf(node: syntax.Node): Doc {
        return _token_doc(node.leaf);
    }

    # The comments above a closing token (`}` or the end of a list), indented
    # inside the construct it closes.
    _inner_comments(close: syntax.Token, after_items: bool): Doc {
        var result = concat();
        ulong i = 0;
        while (i < close.leading_comments.count()) {
            var comment = close.leading_comments[i];
            result.add(hardline());
            if (comment.newlines_before >= 2 and (after_items or i > 0)) {
                result.add(hardline());
            }
            result.add(text(comment.text));
            i += 1;
        }
        close.leading_comments = Array<syntax.Comment>();
        return indent(result);
    }

    # ── Dispatch ─────────────────────────────────────────────────────────────

    _node(item: syntax.Node): Doc {
        match (item.kind) {
            Token => {
                return _leaf(item);
            }
            Import => {
                return _import_declaration(item);
            }
            ExportAlias => {
                return _export_alias(item);
            }
            Struct, Trait => {
                return _aggregate(item);
            }
            Extend => {
                return _extension(item);
            }
            Enum => {
                return _enum(item);
            }
            EnumCase => {
                return _enum_case(item);
            }
            MatchArm => {
                return _match_arm(item);
            }
            Pattern => {
                return _pattern(item);
            }
            TypeAlias => {
                return _type_alias(item);
            }
            ExternFunction => {
                return _extern_function(item);
            }
            Function => {
                return _function(item);
            }
            Constructor, Destructor => {
                return _special_member(item);
            }
            Variable, Parameter => {
                return _variable(item, 0, false);
            }
            Block, Members, MatchArms => {
                return _braced(item);
            }
            If, While, For, With, Match => {
                return _control(item);
            }
            Return, Jump, ExpressionStatement, Destructure, Empty => {
                return _simple_statement(item);
            }
            Type, TypeArguments => {
                return _type_name(item);
            }
            GenericParameters => {
                return _generic_parameters(item);
            }
            Attribute => {
                return _attribute(item);
            }
            Parameters, Arguments, ImportList, ClosureParameters => {
                return _delimited(item, false);
            }
            else => {
                return _expression(item);
            }
        }
        return _expression(item);
    }

    # The attributes (one per line) and `export` at the start of a
    # declaration, added to `result`. Returns the index of the next child.
    _prefix(item: syntax.Node, result: Doc): ulong {
        ulong i = 0;
        while (i < item.count() and item.child(i).kind == syntax.NodeKind.Attribute) {
            result.add(_attribute(item.child(i)));
            result.add(hardline());
            i += 1;
        }
        if (i < item.count() and item.child(i).is_token("export")) {
            result.add(_leaf(item.child(i)));
            result.add(text(" "));
            i += 1;
        }
        return i;
    }

    _attribute(item: syntax.Node): Doc {
        return concat().add(_leaf(item.child(0))).add(_expression(item.child(1))).add(_leaf(item.child(2)));
    }

    # ── Declarations ─────────────────────────────────────────────────────────

    _import_declaration(item: syntax.Node): Doc {
        var result = concat();
        # `prefix` takes the `export` of an `export ... from`, with its space.
        ulong i = _prefix(item, result);
        bool first = true;
        if (item.child(i).is_token("import")) {
            result.add(_leaf(item.child(i)));
            first = false;
            i += 1;
        }
        while (i < item.count()) {
            var child = item.child(i);
            if (child.is_token(";")) {
                result.add(_leaf(child));
            } else {
                if (!first) {
                    result.add(text(" "));
                }
                if (child.kind == syntax.NodeKind.ImportList) {
                    result.add(_delimited(child, false));
                } else {
                    result.add(_leaf(child));
                }
            }
            first = false;
            i += 1;
        }
        return result;
    }

    _import_symbol(item: syntax.Node): Doc {
        var result = concat();
        ulong i = 0;
        while (i < item.count()) {
            if (i > 0) {
                result.add(text(" "));
            }
            result.add(_leaf(item.child(i)));
            i += 1;
        }
        return result;
    }

    _export_alias(item: syntax.Node): Doc {
        var result = concat();
        # `prefix` takes the `export` keyword with the attributes.
        ulong i = _prefix(item, result);
        while (i < item.count()) {
            var child = item.child(i);
            if (child.is_token("as")) {
                result.add(text(" ")).add(_leaf(child)).add(text(" "));
            } else {
                result.add(_leaf(child));
            }
            i += 1;
        }
        return result;
    }

    _aggregate(item: syntax.Node): Doc {
        var result = concat();
        ulong i = _prefix(item, result);
        result.add(_leaf(item.child(i)));
        result.add(text(" "));
        result.add(_leaf(item.child(i + 1)));
        i += 2;
        while (i < item.count()) {
            var child = item.child(i);
            if (child.kind == syntax.NodeKind.Members) {
                result.add(text(" "));
            }
            result.add(_node(child));
            i += 1;
        }
        return result;
    }

    # `enum Name: T {`, then one case per line, then the methods.
    _enum(item: syntax.Node): Doc {
        var result = concat();
        ulong i = _prefix(item, result);
        result.add(_leaf(item.child(i)));
        result.add(text(" "));
        result.add(_leaf(item.child(i + 1)));
        i += 2;
        while (i < item.count()) {
            var child = item.child(i);
            if (child.kind == syntax.NodeKind.GenericParameters) {
                result.add(_generic_parameters(child));
            } else if (child.is_token(":")) {
                result.add(_leaf(child));
            } else {
                result.add(text(" "));
                result.add(_node(child));
            }
            i += 1;
        }
        return result;
    }

    # `Name(payload) = value,`, with its attributes one per line above it.
    _enum_case(item: syntax.Node): Doc {
        var result = concat();
        ulong i = _prefix(item, result);
        while (i < item.count()) {
            var child = item.child(i);
            if (child.is_token("=")) {
                result.add(text(" ")).add(_leaf(child)).add(text(" "));
            } else if (child.kind == syntax.NodeKind.Parameters) {
                result.add(_delimited(child, false));
            } else {
                result.add(_node(child));
            }
            i += 1;
        }
        return result;
    }

    # `A, B => { ... }` or `else => { ... }`.
    _match_arm(item: syntax.Node): Doc {
        var result = concat();
        ulong i = 0;
        while (i < item.count()) {
            var child = item.child(i);
            if (child.is_token("=>")) {
                result.add(text(" ")).add(_leaf(child)).add(text(" "));
            } else {
                if (i > 0 and item.child(i - 1).is_token(",")) {
                    result.add(text(" "));
                }
                result.add(_node(child));
            }
            i += 1;
        }
        return result;
    }

    # `Enum.Case(x, y)`: tight, with a space after each binding's `,`.
    _pattern(item: syntax.Node): Doc {
        var result = concat();
        for (var child in item.children) {
            result.add(_node(child));
            if (child.is_token(",")) {
                result.add(text(" "));
            }
        }
        return result;
    }

    _extension(item: syntax.Node): Doc {
        var result = concat();
        ulong i = _prefix(item, result);
        result.add(_leaf(item.child(i)));
        i += 1;
        while (i < item.count()) {
            var child = item.child(i);
            if (child.is_token(",")) {
                result.add(_leaf(child));
            } else {
                result.add(text(" "));
                result.add(_node(child));
            }
            i += 1;
        }
        return result;
    }

    _type_alias(item: syntax.Node): Doc {
        var result = concat();
        ulong i = _prefix(item, result);
        result.add(_leaf(item.child(i)));
        result.add(text(" "));
        result.add(_leaf(item.child(i + 1)));
        i += 2;
        while (i < item.count()) {
            var child = item.child(i);
            if (child.kind == syntax.NodeKind.GenericParameters) {
                result.add(_generic_parameters(child));
            } else if (child.is_token(";")) {
                result.add(_leaf(child));
            } else {
                result.add(text(" "));
                result.add(_node(child));
            }
            i += 1;
        }
        return result;
    }

    _extern_function(item: syntax.Node): Doc {
        var result = concat();
        ulong i = _prefix(item, result);
        result.add(_leaf(item.child(i)));
        result.add(text(" "));
        result.add(_type_name(item.child(i + 1)));
        result.add(text(" "));
        result.add(_leaf(item.child(i + 2)));
        result.add(_delimited(item.child(i + 3), false));
        i += 4;
        if (i < item.count()) {
            result.add(_leaf(item.child(i)));
        }
        return result;
    }

    # A function or method, in the Pepper form `name(x: T): R` wherever the
    # grammar allows it: C-style `R name(T x)` becomes `name(x: T): R`, and
    # a `void` return type is left out when a body can infer it.
    # Operator methods and indexers keep their return type in front, since
    # the grammar has no other way to write them.
    _function(item: syntax.Node): Doc {
        var result = concat();
        ulong i = _prefix(item, result);
        if (item.child(i).is_token("static")) {
            result.add(_leaf(item.child(i)));
            result.add(text(" "));
            i += 1;
        }
        var first = item.child(i);
        if (first.kind == syntax.NodeKind.Type) {
            # `R name(...)`, `R ==(...)` or `R [](...)`, optionally with
            # `: R2`, which wins. The name may span several tokens.
            ulong j = i + 1;
            var name = concat();
            while (j < item.count()
                and item.child(j).kind == syntax.NodeKind.Token
                and !item.child(j).is_token(":")
                and !item.child(j).is_token(";")) {
                name.add(_leaf(item.child(j)));
                j += 1;
            }
            syntax.Node? parameters;
            if (j < item.count() and item.child(j).kind == syntax.NodeKind.Parameters) {
                parameters = Optional<syntax.Node>.some(item.child(j));
                j += 1;
            }
            bool annotated = j < item.count() and item.child(j).is_token(":");
            if (!annotated or !first.has_comments()) {
                result.add(_leading(first.first_token()));
                result.add(name);
                if (parameters) {
                    result.add(_delimited(parameters.value(), true));
                } else {
                    result.add(text("()"));
                }
                if (annotated) {
                    if (!_void_return(item, item.child(j + 1))) {
                        result.add(_leaf(item.child(j)));
                        result.add(text(" "));
                        result.add(_type_name(item.child(j + 1)));
                    }
                    j += 2;
                } else if (!_void_return(item, first)) {
                    result.add(text(": "));
                    result.add(_type_name(first));
                }
                _function_rest(item, j, result);
                return result;
            }
            result.add(_type_name(first));
            result.add(text(" "));
            i += 1;
            while (i < item.count() and item.child(i).kind == syntax.NodeKind.Token and !item.child(i).is_token(";")) {
                result.add(_leaf(item.child(i)));
                i += 1;
            }
        } else {
            result.add(_leaf(first));
            i += 1;
        }
        _function_rest(item, i, result);
        return result;
    }

    # Whether `return_type`, of function `item`, can be left out:
    # it is `void` and `item` has a body to infer it from. A declaration
    # without one (a trait method) keeps it.
    _void_return(item: syntax.Node, return_type: syntax.Node): bool {
        return is_void(return_type) and item.child(item.count() - 1).kind == syntax.NodeKind.Block;
    }

    # The generic parameters, parameters, return annotation and body of a
    # function, from child `start` on.
    _function_rest(item: syntax.Node, start: ulong, result: Doc) {
        ulong i = start;
        while (i < item.count()) {
            var child = item.child(i);
            var kind = child.kind;
            if (kind == syntax.NodeKind.GenericParameters) {
                result.add(_generic_parameters(child));
            } else if (kind == syntax.NodeKind.Parameters) {
                result.add(_delimited(child, true));
            } else if (child.is_token(":")) {
                if (i + 1 < item.count() and _void_return(item, item.child(i + 1))) {
                    # `: void` says nothing: a function whose body returns
                    # nothing infers `void`.
                    i += 2;
                    continue;
                }
                result.add(_leaf(child));
                result.add(text(" "));
            } else if (kind == syntax.NodeKind.Type) {
                result.add(_type_name(child));
            } else if (kind == syntax.NodeKind.Block) {
                result.add(text(" "));
                result.add(_braced(child));
            } else {
                result.add(_leaf(child));
            }
            i += 1;
        }
    }

    # A constructor or destructor.
    _special_member(item: syntax.Node): Doc {
        var result = concat();
        ulong i = _prefix(item, result);
        result.add(_leaf(item.child(i)));
        i += 1;
        while (i < item.count()) {
            var child = item.child(i);
            if (child.kind == syntax.NodeKind.Parameters) {
                result.add(_delimited(child, true));
            } else {
                result.add(text(" "));
                result.add(_braced(child));
            }
            i += 1;
        }
        return result;
    }

    _generic_parameters(item: syntax.Node): Doc {
        var result = concat();
        for (var child in item.children) {
            if (child.kind == syntax.NodeKind.GenericParameter) {
                # `T=Error`, but `T: Shape & Named = Square` once constrained.
                bool constrained = false;
                for (var part in child.children) {
                    if (part.is_token(":")) {
                        constrained = true;
                        result.add(_leaf(part));
                        result.add(text(" "));
                    } else if (part.is_token("&") or (constrained and part.is_token("="))) {
                        result.add(text(" "));
                        result.add(_leaf(part));
                        result.add(text(" "));
                    } else {
                        result.add(_node(part));
                    }
                }
            } else {
                result.add(_leaf(child));
                if (child.is_token(",")) {
                    result.add(text(" "));
                }
            }
        }
        return result;
    }

    # A variable, field, parameter or binding, from child `start` on. With
    # `pepper_style`, a C-style `T name` parameter becomes `name: T`.
    _variable(item: syntax.Node, start: ulong, pepper_style: bool): Doc {
        var result = concat();
        ulong i = start;
        if (item.kind == syntax.NodeKind.Parameter) {
            # A parameter's attributes precede it on its line.
            while (i < item.count() and item.child(i).kind == syntax.NodeKind.Attribute) {
                result.add(_attribute(item.child(i)));
                result.add(text(" "));
                i += 1;
            }
        } else if (start == 0) {
            i = _prefix(item, result);
        }
        var first = item.child(i);
        if (first.is_token("this")) {
            # `this.field = value`
            result.add(_leaf(first));
            result.add(_leaf(item.child(i + 1)));
            result.add(_leaf(item.child(i + 2)));
            i += 3;
        } else if (first.kind == syntax.NodeKind.Type) {
            var name = item.child(i + 1);
            bool annotated = i + 2 < item.count() and item.child(i + 2).is_token(":");
            if (pepper_style and !annotated) {
                result.add(_leading(first.first_token()));
                result.add(_leaf(name));
                result.add(text(": "));
                result.add(_type_name(first));
            } else {
                result.add(_type_name(first));
                result.add(text(" "));
                result.add(_leaf(name));
            }
            i += 2;
        } else if (first.is_token("var") or first.is_token("const")) {
            result.add(_leaf(first));
            result.add(text(" "));
            result.add(_leaf(item.child(i + 1)));
            i += 2;
        } else {
            result.add(_leaf(first));
            i += 1;
        }
        while (i < item.count()) {
            var child = item.child(i);
            if (child.is_token(":")) {
                result.add(_leaf(child));
                result.add(text(" "));
            } else if (child.is_token("=")) {
                result.add(text(" "));
                result.add(_leaf(child));
                result.add(text(" "));
            } else if (child.is_token(";")) {
                result.add(_leaf(child));
            } else {
                result.add(_node(child));
            }
            i += 1;
        }
        return result;
    }

    # ── Lists ────────────────────────────────────────────────────────────────

    # A bracketed, comma-separated list (arguments, parameters, an import
    # list): on one line if it fits, else all items on one indented line,
    # else one item per line. With `pepper_style`, parameters are written
    # `name: T`.
    _delimited(item: syntax.Node, pepper_style: bool): Doc {
        var open = item.child(0);
        var close = item.child(item.count() - 1);
        var items = Array<Doc>();
        bool comments = open.leaf.has_comments();
        ulong i = 1;
        while (i + 1 < item.count()) {
            var child = item.child(i);
            if (child.is_token(",")) {
                if (child.has_comments()) {
                    comments = true;
                }
                items.last().add(_leaf(child));
            } else {
                if (child.has_comments()) {
                    comments = true;
                }
                var entry = concat();
                if (child.kind == syntax.NodeKind.Parameter and pepper_style) {
                    entry.add(_variable(child, 0, true));
                } else if (child.kind == syntax.NodeKind.ImportSymbol) {
                    entry.add(_import_symbol(child));
                } else if (child.kind == syntax.NodeKind.ClosureParameter) {
                    entry.add(_closure_parameter(child));
                } else {
                    entry.add(_node(child));
                }
                items.append(entry);
            }
            i += 1;
        }
        if (close.leaf.leading_comments.count() > 0) {
            comments = true;
        }
        var result = concat().add(_leaf(open));
        if (items.empty()) {
            result.add(_inner_comments(close.leaf, false));
            if (comments) {
                result.add(hardline());
            }
            return result.add(_leaf(close));
        }
        var options = choice();
        if (!comments) {
            var flat = concat();
            var continued = concat();
            ulong k = 0;
            while (k < items.count()) {
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
        while (k < items.count()) {
            broken.add(hardline());
            broken.add(items[k]);
            k += 1;
        }
        broken.add(_inner_comments(close.leaf, true));
        options.add(concat().add(indent(broken)).add(hardline()));
        result.add(options);
        return result.add(_leaf(close));
    }

    _closure_parameter(item: syntax.Node): Doc {
        var result = concat();
        for (var child in item.children) {
            if (child.is_token(":")) {
                result.add(_leaf(child));
                result.add(text(" "));
            } else {
                result.add(_node(child));
            }
        }
        return result;
    }

    # ── Blocks and statements ────────────────────────────────────────────────

    # A block or member list: `{`, the items one per line, `}`.
    _braced(item: syntax.Node): Doc {
        var result = concat();
        ulong i = 0;
        while (item.child(i).kind == syntax.NodeKind.Attribute) {
            result.add(_attribute(item.child(i)));
            result.add(hardline());
            i += 1;
        }
        var open = item.child(i);
        var close = item.child(item.count() - 1);
        var items = Array<syntax.Node>();
        i += 1;
        while (i + 1 < item.count()) {
            items.append(item.child(i));
            i += 1;
        }
        if (items.empty() and close.leaf.leading_comments.count() == 0) {
            return result.add(_leaf(open)).add(_leaf(close));
        }
        if (items.count() == 1
            and !item.has_comments()
            and items[0].first_token().newlines_before == 0
            and close.leaf.newlines_before == 0
            and (items[0].kind == syntax.NodeKind.Return or items[0].kind == syntax.NodeKind.Jump)) {
            # One trivial statement written on one line stays there.
            var body = concat().add(_leaf(open)).add(indent(concat().add(line()).add(_node(items[0])))).add(line());
            return result.add(group(body.add(_leaf(close))));
        }
        result.add(_leaf(open));
        var body = concat();
        ulong index = 0;
        bool after_region = false;
        while (index < items.count()) {
            var entry = items[index];
            if (index > 0
                and !after_region
                and entry.kind == syntax.NodeKind.Empty
                and entry.first_token().newlines_before == 0) {
                body.add(_leaf(entry.child(0)));
                index += 1;
                continue;
            }
            body.add(hardline());
            if ((index > 0 or after_region) and blank_before(entry)) {
                body.add(hardline());
            }
            var region = _format_off(items, index, close.leaf);
            if (region) {
                body.add(region.value().layout);
                index = region.value().next;
                after_region = true;
                continue;
            }
            after_region = false;
            body.add(_leading(entry.first_token()));
            body.add(_node(entry));
            index += 1;
        }
        result.add(indent(body));
        result.add(_inner_comments(close.leaf, !items.empty()));
        result.add(hardline());
        return result.add(_leaf(close));
    }

    # `if`, `while`, `for` and `with`: keywords and parts separated by one
    # space, `(`/`)` and the `for` binding kept tight.
    _control(item: syntax.Node): Doc {
        var result = concat();
        ulong i = 0;
        while (i < item.count()) {
            var child = item.child(i);
            if (i > 0 and !child.is_token(")") and !item.child(i - 1).is_token("(")) {
                result.add(text(" "));
            }
            if (child.kind == syntax.NodeKind.Variable) {
                result.add(_variable(child, 0, false));
            } else {
                result.add(_node(child));
            }
            i += 1;
        }
        return result;
    }

    _simple_statement(item: syntax.Node): Doc {
        var result = concat();
        ulong i = 0;
        while (i < item.count()) {
            var child = item.child(i);
            if (i > 0 and !child.is_token(";")) {
                result.add(text(" "));
            }
            result.add(_node(child));
            i += 1;
        }
        return result;
    }

    # ── Types ────────────────────────────────────────────────────────────────

    _type_name(item: syntax.Node): Doc {
        var result = concat();
        for (var child in item.children) {
            if (child.kind == syntax.NodeKind.Type) {
                result.add(_type_name(child));
            } else if (child.kind == syntax.NodeKind.TypeArguments) {
                result.add(_type_name(child));
            } else if (child.is_token(",")) {
                result.add(_leaf(child)).add(text(" "));
            } else if (child.is_token("=>")) {
                result.add(text(" ")).add(_leaf(child)).add(text(" "));
            } else if (child.is_token(":")) {
                # A tuple element's label, `line: int`, or a restated
                # constraint, `extend Box<T: Shape>`.
                result.add(_leaf(child)).add(text(" "));
            } else if (child.is_token("&")) {
                result.add(text(" ")).add(_leaf(child)).add(text(" "));
            } else if (child.is_token("shared") or child.is_token("extern")) {
                result.add(_leaf(child)).add(text(" "));
            } else {
                result.add(_leaf(child));
            }
        }
        return result;
    }

    # ── Expressions ──────────────────────────────────────────────────────────

    _expression(item: syntax.Node): Doc {
        match (item.kind) {
            Token => {
                return _leaf(item);
            }
            Binary => {
                return _binary(item);
            }
            Call => {
                if (called_members(item) >= 3) {
                    return _member_chain(item);
                }
                return concat().add(_expression(item.child(0))).add(_delimited(item.child(1), false));
            }
            Member => {
                if (called_members(item) >= 3) {
                    return _member_chain(item);
                }
                return _parts(item);
            }
            Tuple, Array, Map => {
                return _delimited(item, false);
            }
            MapEntry => {
                # `"key": value`
                return concat()
                    .add(_expression(item.child(0)))
                    .add(_leaf(item.child(1)))
                    .add(text(" "))
                    .add(_expression(item.child(2)));
            }
            TupleElement => {
                # `line: 3`
                return concat()
                    .add(_leaf(item.child(0)))
                    .add(_leaf(item.child(1)))
                    .add(text(" "))
                    .add(_expression(item.child(2)));
            }
            Prefix => {
                var result = concat().add(_leaf(item.child(0)));
                var op = item.child(0).leaf.text;
                var operand = item.child(1);
                var next = operand.first_token().text;
                # `- -x` must not print as the `--` operator.
                if ((op == "-" or op == "+") and (next.starts_with("-") or next.starts_with("+"))) {
                    result.add(text(" "));
                }
                return result.add(_expression(operand));
            }
            Cast => {
                var result = concat().add(_expression(item.child(0))).add(text(" ")).add(_leaf(item.child(1)));
                return result.add(text(" ")).add(_type_name(item.child(2)));
            }
            Ternary => {
                var rest = concat()
                    .add(text(" "))
                    .add(_leaf(item.child(1)))
                    .add(line())
                    .add(_expression(item.child(2)));
                rest.add(text(" ")).add(_leaf(item.child(3))).add(line()).add(_expression(item.child(4)));
                return group(concat().add(_expression(item.child(0))).add(indent(rest)));
            }
            TypeLiteral => {
                return _type_name(item.child(0));
            }
            Match => {
                return _control(item);
            }
            Pattern => {
                return _pattern(item);
            }
            Closure => {
                var result = concat();
                for (var child in item.children) {
                    if (child.kind == syntax.NodeKind.ClosureParameters) {
                        result.add(_delimited(child, false));
                    } else if (child.is_token(":")) {
                        result.add(_leaf(child)).add(text(" "));
                    } else if (child.is_token("=>")) {
                        result.add(text(" ")).add(_leaf(child)).add(text(" "));
                    } else {
                        result.add(_node(child));
                    }
                }
                return result;
            }
            else => {
                return _parts(item);
            }
        }
        return _parts(item);
    }

    # Any other construct: its parts, one after another.
    _parts(item: syntax.Node): Doc {
        var result = concat();
        for (var child in item.children) {
            result.add(_node(child));
        }
        return result;
    }

    # `a.b(x).c(y).d(z)`, three calls or more: on one line if it fits, else
    # a line break before each called member, indented under the first
    # operand.
    _member_chain(item: syntax.Node): Doc {
        var links = Array<syntax.Node>();
        var base = item;
        while (base.kind == syntax.NodeKind.Call
            or base.kind == syntax.NodeKind.Member
            or base.kind == syntax.NodeKind.Index) {
            links.append(base);
            base = base.child(0);
        }
        links.reverse();
        var rest = concat();
        ulong i = 0;
        while (i < links.count()) {
            var link = links[i];
            bool called = i + 1 < links.count() and links[i + 1].kind == syntax.NodeKind.Call;
            if (link.kind == syntax.NodeKind.Member and called) {
                rest.add(softline());
            }
            ulong k = 1;
            while (k < link.count()) {
                rest.add(_node(link.child(k)));
                k += 1;
            }
            i += 1;
        }
        return group(concat().add(_expression(base)).add(indent(rest)));
    }

    # A binary expression. A chain of operators of one precedence breaks
    # before each operator.
    _binary(item: syntax.Node): Doc {
        var op = item.child(1).leaf.text;
        int level = precedence(op);
        if (op == ".." or op == "..>") {
            # A range reads as one unit: `0..count`.
            return concat().add(_expression(item.child(0))).add(_leaf(item.child(1))).add(_expression(item.child(2)));
        }
        if (level == 0) {
            var result = concat().add(_expression(item.child(0))).add(text(" ")).add(_leaf(item.child(1)));
            return result.add(text(" ")).add(_expression(item.child(2)));
        }
        # Flatten `a + b + c`, which is ((a + b) + c), into its operands.
        var operands = Array<syntax.Node>();
        var operators = Array<syntax.Node>();
        var current = item;
        while (current.kind == syntax.NodeKind.Binary and precedence(current.child(1).leaf.text) == level) {
            operands.append(current.child(2));
            operators.append(current.child(1));
            current = current.child(0);
        }
        operands.append(current);
        operands.reverse();
        operators.reverse();
        var rest = concat();
        ulong i = 0;
        while (i < operators.count()) {
            rest.add(line());
            rest.add(_leaf(operators[i]));
            rest.add(text(" "));
            rest.add(_expression(operands[i + 1]));
            i += 1;
        }
        return group(concat().add(_expression(operands[0])).add(indent(rest)));
    }
}

# The number of members in the chain `item` heads that are called, as the
# two in `a.b(x).c(y)`.
called_members(item: syntax.Node): int {
    int count = 0;
    var current = item;
    while (current.kind == syntax.NodeKind.Call
        or current.kind == syntax.NodeKind.Member
        or current.kind == syntax.NodeKind.Index) {
        if (current.kind == syntax.NodeKind.Call and current.child(0).kind == syntax.NodeKind.Member) {
            count += 1;
        }
        current = current.child(0);
    }
    return count;
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
            comments.append(entry.substr_bytes(after, entry.size() - after));
        }
    }
    var result = StringBuilder();
    ulong index = 0;
    while (index < lines.count()) {
        if (comments[index].empty() or codes[index].empty()) {
            result.append(codes[index]).append(comments[index]).append(newline);
            index += 1;
            continue;
        }
        ulong end = index;
        ulong column = 0;
        while (end < lines.count() and !comments[end].empty() and !codes[end].empty()) {
            if (codes[end].length() > column) {
                column = codes[end].length();
            }
            end += 1;
        }
        column += 2;
        while (index < end) {
            var code = codes[index];
            result.append(code).append(" ".repeat(column - code.length())).append(comments[index]).append(newline);
            index += 1;
        }
    }
    return result.to_string();
}

## Formats Pepper source text in the standard style.
##
## @param source the text of a Pepper source file
## @returns the formatted text, or the syntax error that stopped it
export format_source(source: String): Result<String, syntax.SyntaxError> {
    var tree = syntax.parse(source);
    if (tree.is_err()) {
        return Result<String, syntax.SyntaxError>.err(tree.error());
    }
    if (source.empty()) {
        return Result<String, syntax.SyntaxError>.ok("");
    }
    var newline = "\n";
    long first_break = source.find("\n");
    if (first_break > 0 and source.byte_at((first_break - 1) as ulong) == '\r') {
        newline = "\r\n";
    }
    var layout = Formatter(source).format(tree.value());
    return Result<String, syntax.SyntaxError>.ok(align_trailing_comments(render(layout, LINE_WIDTH), newline));
}
