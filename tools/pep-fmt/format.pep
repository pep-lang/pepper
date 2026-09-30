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
    int kind = node.kind;
    if (kind == syntax.NODE_STRUCT
        or kind == syntax.NODE_TRAIT
        or kind == syntax.NODE_EXTEND
        or kind == syntax.NODE_ENUM) {
        return true;
    }
    return kind == syntax.NODE_FUNCTION and node.child(node.count() - 1).kind == syntax.NODE_BLOCK;
}

# Orders two Strings by their bytes: negative, zero or positive.
export compare_text(a: String, b: String): int {
    var left = a.c_str();
    var right = b.c_str();
    ulong i = 0;
    while (i < a.size() and i < b.size()) {
        int x = left[i];
        int y = right[i];
        if (x != y) {
            return x - y;
        }
        i += 1;
    }
    if (a.size() < b.size()) {
        return -1;
    }
    if (a.size() > b.size()) {
        return 1;
    }
    return 0;
}

# Whether `item` is an import that sorting may move: not an `export ...
# from`, whose order decides which of two colliding re-exports is reported.
is_sortable_import(item: syntax.Node): bool {
    if (item.kind != syntax.NODE_IMPORT) {
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
        if (child.kind != syntax.NODE_TOKEN or child.is_token(";")) {
            continue;
        }
        # The name is the last token that is not an `as` alias.
        if (i >= 2 and item.child(i - 1).is_token("as")) {
            i -= 1;
            continue;
        }
        var name = child.leaf;
        if (name.kind == syntax.TOKEN_STRING) {
            return "1" + name.text;
        }
        return "0" + name.text;
    }
    return "";
}

# Sorts each group of adjacent imports (no blank line or comment between
# them) in place, by `import_key`. The comments above a group stay above it.
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
            first.leading_comments = Array<syntax.Comment>();
            ulong i = start + 1;
            while (i < end) {
                ulong j = i;
                while (j > start and compare_text(import_key(items[j - 1]), import_key(items[j])) > 0) {
                    items.swap(j - 1, j);
                    j -= 1;
                }
                i += 1;
            }
            var new_first = items[start].first_token();
            new_first.leading_comments = comments;
            new_first.newlines_before = newlines;
        }
        start = end;
    }
}

## Builds the layout of a syntax tree in the standard style.
export struct Formatter {
    ## Creates a formatter.
    construct() {}

    ## Returns the layout of a whole file.
    ##
    ## @param module the root of a syntax tree, a `NODE_MODULE`
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
        ulong index = 0;
        while (index < items.count()) {
            var item = items[index];
            if (index > 0) {
                var previous = items[index - 1];
                if (item.kind == syntax.NODE_EMPTY and item.first_token().newlines_before == 0) {
                    result.add(_token_doc(item.first_token()));
                    index += 1;
                    continue;
                }
                result.add(hardline());
                if (blank_before(item) or is_big(item) or is_big(previous)) {
                    result.add(hardline());
                }
            }
            result.add(_leading(item.first_token()));
            result.add(_node(item));
            index += 1;
        }
        var end = module.child(module.count() - 1).leaf;
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
        int kind = item.kind;
        if (kind == syntax.NODE_TOKEN) {
            return _leaf(item);
        }
        if (kind == syntax.NODE_IMPORT) {
            return _import_declaration(item);
        }
        if (kind == syntax.NODE_EXPORT_ALIAS) {
            return _export_alias(item);
        }
        if (kind == syntax.NODE_STRUCT or kind == syntax.NODE_TRAIT) {
            return _aggregate(item);
        }
        if (kind == syntax.NODE_EXTEND) {
            return _extension(item);
        }
        if (kind == syntax.NODE_ENUM) {
            return _enum(item);
        }
        if (kind == syntax.NODE_ENUM_CASE) {
            return _enum_case(item);
        }
        if (kind == syntax.NODE_MATCH_ARM) {
            return _match_arm(item);
        }
        if (kind == syntax.NODE_PATTERN) {
            return _pattern(item);
        }
        if (kind == syntax.NODE_TYPE_ALIAS) {
            return _type_alias(item);
        }
        if (kind == syntax.NODE_EXTERN_FUNCTION) {
            return _extern_function(item);
        }
        if (kind == syntax.NODE_FUNCTION) {
            return _function(item);
        }
        if (kind == syntax.NODE_CONSTRUCTOR or kind == syntax.NODE_DESTRUCTOR) {
            return _special_member(item);
        }
        if (kind == syntax.NODE_VARIABLE or kind == syntax.NODE_PARAMETER) {
            return _variable(item, 0, false);
        }
        if (kind == syntax.NODE_BLOCK or kind == syntax.NODE_MEMBERS or kind == syntax.NODE_MATCH_ARMS) {
            return _braced(item);
        }
        if (kind == syntax.NODE_IF
            or kind == syntax.NODE_WHILE
            or kind == syntax.NODE_FOR
            or kind == syntax.NODE_WITH
            or kind == syntax.NODE_MATCH) {
            return _control(item);
        }
        if (kind == syntax.NODE_RETURN
            or kind == syntax.NODE_JUMP
            or kind == syntax.NODE_EXPRESSION_STATEMENT
            or kind == syntax.NODE_DESTRUCTURE
            or kind == syntax.NODE_EMPTY) {
            return _simple_statement(item);
        }
        if (kind == syntax.NODE_TYPE or kind == syntax.NODE_TYPE_ARGUMENTS) {
            return _type_name(item);
        }
        if (kind == syntax.NODE_GENERIC_PARAMETERS) {
            return _generic_parameters(item);
        }
        if (kind == syntax.NODE_ATTRIBUTE) {
            return _attribute(item);
        }
        if (kind == syntax.NODE_PARAMETERS
            or kind == syntax.NODE_ARGUMENTS
            or kind == syntax.NODE_IMPORT_LIST
            or kind == syntax.NODE_CLOSURE_PARAMETERS) {
            return _delimited(item, false);
        }
        return _expression(item);
    }

    # The attributes (one per line) and `export` at the start of a
    # declaration, added to `result`. Returns the index of the next child.
    _prefix(item: syntax.Node, result: Doc): ulong {
        ulong i = 0;
        while (i < item.count() and item.child(i).kind == syntax.NODE_ATTRIBUTE) {
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
                if (child.kind == syntax.NODE_IMPORT_LIST) {
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
            if (child.kind == syntax.NODE_MEMBERS) {
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
            if (child.kind == syntax.NODE_GENERIC_PARAMETERS) {
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
            } else if (child.kind == syntax.NODE_PARAMETERS) {
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
            result.add(_leaf(child));
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
            if (child.kind == syntax.NODE_GENERIC_PARAMETERS) {
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
    # grammar allows it: C-style `R name(T x)` becomes `name(x: T): R`.
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
        if (first.kind == syntax.NODE_TYPE) {
            # `R name(...)`, `R ==(...)` or `R [](...)`, optionally with
            # `: R2`, which wins. The name may span several tokens.
            ulong j = i + 1;
            var name = concat();
            while (j < item.count()
                and item.child(j).kind == syntax.NODE_TOKEN
                and !item.child(j).is_token(":")
                and !item.child(j).is_token(";")) {
                name.add(_leaf(item.child(j)));
                j += 1;
            }
            syntax.Node parameters = __null;
            if (j < item.count() and item.child(j).kind == syntax.NODE_PARAMETERS) {
                parameters = item.child(j);
                j += 1;
            }
            bool annotated = j < item.count() and item.child(j).is_token(":");
            if (!annotated or !first.has_comments()) {
                result.add(_leading(first.first_token()));
                result.add(name);
                if (parameters === __null) {
                    result.add(text("()"));
                } else {
                    result.add(_delimited(parameters, true));
                }
                if (annotated) {
                    result.add(_leaf(item.child(j)));
                    result.add(text(" "));
                    result.add(_type_name(item.child(j + 1)));
                    j += 2;
                } else {
                    result.add(text(": "));
                    result.add(_type_name(first));
                }
                _function_rest(item, j, result);
                return result;
            }
            result.add(_type_name(first));
            result.add(text(" "));
            i += 1;
            while (i < item.count() and item.child(i).kind == syntax.NODE_TOKEN and !item.child(i).is_token(";")) {
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

    # The generic parameters, parameters, return annotation and body of a
    # function, from child `start` on.
    _function_rest(item: syntax.Node, start: ulong, result: Doc) {
        ulong i = start;
        while (i < item.count()) {
            var child = item.child(i);
            int kind = child.kind;
            if (kind == syntax.NODE_GENERIC_PARAMETERS) {
                result.add(_generic_parameters(child));
            } else if (kind == syntax.NODE_PARAMETERS) {
                result.add(_delimited(child, true));
            } else if (child.is_token(":")) {
                result.add(_leaf(child));
                result.add(text(" "));
            } else if (kind == syntax.NODE_TYPE) {
                result.add(_type_name(child));
            } else if (kind == syntax.NODE_BLOCK) {
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
            if (child.kind == syntax.NODE_PARAMETERS) {
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
            if (child.kind == syntax.NODE_GENERIC_PARAMETER) {
                for (var part in child.children) {
                    result.add(_node(part));
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
        if (item.kind == syntax.NODE_PARAMETER) {
            # A parameter's attributes precede it on its line.
            while (i < item.count() and item.child(i).kind == syntax.NODE_ATTRIBUTE) {
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
        } else if (first.kind == syntax.NODE_TYPE) {
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
                if (child.kind == syntax.NODE_PARAMETER and pepper_style) {
                    entry.add(_variable(child, 0, true));
                } else if (child.kind == syntax.NODE_IMPORT_SYMBOL) {
                    entry.add(_import_symbol(child));
                } else if (child.kind == syntax.NODE_CLOSURE_PARAMETER) {
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
        while (item.child(i).kind == syntax.NODE_ATTRIBUTE) {
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
            and (items[0].kind == syntax.NODE_RETURN or items[0].kind == syntax.NODE_JUMP)) {
            # One trivial statement written on one line stays there.
            var body = concat().add(_leaf(open)).add(indent(concat().add(line()).add(_node(items[0])))).add(line());
            return result.add(group(body.add(_leaf(close))));
        }
        result.add(_leaf(open));
        var body = concat();
        ulong index = 0;
        while (index < items.count()) {
            var entry = items[index];
            if (index > 0 and entry.kind == syntax.NODE_EMPTY and entry.first_token().newlines_before == 0) {
                body.add(_leaf(entry.child(0)));
                index += 1;
                continue;
            }
            body.add(hardline());
            if (index > 0 and blank_before(entry)) {
                body.add(hardline());
            }
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
            if (child.kind == syntax.NODE_VARIABLE) {
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
            if (child.kind == syntax.NODE_TYPE) {
                result.add(_type_name(child));
            } else if (child.kind == syntax.NODE_TYPE_ARGUMENTS) {
                result.add(_type_name(child));
            } else if (child.is_token(",")) {
                result.add(_leaf(child)).add(text(" "));
            } else if (child.is_token("=>")) {
                result.add(text(" ")).add(_leaf(child)).add(text(" "));
            } else if (child.is_token(":")) {
                # A tuple element's label: `line: int`.
                result.add(_leaf(child)).add(text(" "));
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
        int kind = item.kind;
        if (kind == syntax.NODE_TOKEN) {
            return _leaf(item);
        }
        if (kind == syntax.NODE_BINARY) {
            return _binary(item);
        }
        if ((kind == syntax.NODE_CALL or kind == syntax.NODE_MEMBER) and called_members(item) >= 3) {
            return _member_chain(item);
        }
        if (kind == syntax.NODE_CALL) {
            return concat().add(_expression(item.child(0))).add(_delimited(item.child(1), false));
        }
        if (kind == syntax.NODE_TUPLE) {
            return _delimited(item, false);
        }
        if (kind == syntax.NODE_TUPLE_ELEMENT) {
            # `line: 3`
            return concat()
                .add(_leaf(item.child(0)))
                .add(_leaf(item.child(1)))
                .add(text(" "))
                .add(_expression(item.child(2)));
        }
        if (kind == syntax.NODE_MEMBER
            or kind == syntax.NODE_INDEX
            or kind == syntax.NODE_POSTFIX
            or kind == syntax.NODE_PARENTHESIZED
            or kind == syntax.NODE_SIZEOF) {
            var result = concat();
            for (var child in item.children) {
                result.add(_node(child));
            }
            return result;
        }
        if (kind == syntax.NODE_PREFIX) {
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
        if (kind == syntax.NODE_CAST) {
            var result = concat().add(_expression(item.child(0))).add(text(" ")).add(_leaf(item.child(1)));
            return result.add(text(" ")).add(_type_name(item.child(2)));
        }
        if (kind == syntax.NODE_TERNARY) {
            var rest = concat().add(text(" ")).add(_leaf(item.child(1))).add(line()).add(_expression(item.child(2)));
            rest.add(text(" ")).add(_leaf(item.child(3))).add(line()).add(_expression(item.child(4)));
            return group(concat().add(_expression(item.child(0))).add(indent(rest)));
        }
        if (kind == syntax.NODE_TYPE_LITERAL) {
            return _type_name(item.child(0));
        }
        if (kind == syntax.NODE_CLOSURE) {
            var result = concat();
            for (var child in item.children) {
                if (child.kind == syntax.NODE_CLOSURE_PARAMETERS) {
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
        # Any other construct: its parts, one after another.
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
        while (base.kind == syntax.NODE_CALL or base.kind == syntax.NODE_MEMBER or base.kind == syntax.NODE_INDEX) {
            links.append(base);
            base = base.child(0);
        }
        links.reverse();
        var rest = concat();
        ulong i = 0;
        while (i < links.count()) {
            var link = links[i];
            bool called = i + 1 < links.count() and links[i + 1].kind == syntax.NODE_CALL;
            if (link.kind == syntax.NODE_MEMBER and called) {
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
        if (level == 0) {
            var result = concat().add(_expression(item.child(0))).add(text(" ")).add(_leaf(item.child(1)));
            return result.add(text(" ")).add(_expression(item.child(2)));
        }
        # Flatten `a + b + c`, which is ((a + b) + c), into its operands.
        var operands = Array<syntax.Node>();
        var operators = Array<syntax.Node>();
        var current = item;
        while (current.kind == syntax.NODE_BINARY and precedence(current.child(1).leaf.text) == level) {
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
    while (current.kind == syntax.NODE_CALL
        or current.kind == syntax.NODE_MEMBER
        or current.kind == syntax.NODE_INDEX) {
        if (current.kind == syntax.NODE_CALL and current.child(0).kind == syntax.NODE_MEMBER) {
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
    var lines = Array<String>();
    var data = printed.c_str();
    ulong start = 0;
    ulong i = 0;
    while (i < printed.size()) {
        if (data[i] == '\n') {
            if (i > start) {
                lines.append(String(data + start, i - start));
            } else {
                lines.append("");
            }
            start = i + 1;
        }
        i += 1;
    }
    if (start < printed.size()) {
        lines.append(String(data + start, printed.size() - start));
    }
    var codes = Array<String>();
    var comments = Array<String>();
    for (var entry in lines) {
        long mark = entry.find(comment_mark());
        if (mark < 0) {
            codes.append(entry);
            comments.append("");
        } else {
            var bytes = entry.c_str();
            var code = "";
            if (mark > 0) {
                code = trim_end(String(bytes, mark as ulong));
            }
            ulong after = mark as ulong + 1;
            codes.append(code);
            comments.append(String(bytes + after, entry.size() - after));
        }
    }
    var result = "";
    ulong index = 0;
    while (index < lines.count()) {
        if (comments[index].empty() or codes[index].empty()) {
            result += codes[index];
            if (!comments[index].empty()) {
                result += comments[index];
            }
            result += newline;
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
            result += code;
            ulong pad = code.length();
            while (pad < column) {
                result += " ";
                pad += 1;
            }
            result += comments[index];
            result += newline;
            index += 1;
        }
    }
    return result;
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
    if (first_break > 0 and source.c_str()[(first_break - 1) as ulong] == '\r') {
        newline = "\r\n";
    }
    var layout = Formatter().format(tree.value());
    return Result<String, syntax.SyntaxError>.ok(align_trailing_comments(render(layout, LINE_WIDTH), newline));
}
