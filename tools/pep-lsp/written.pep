# Names the syntax tree holds in no node of their own, found in the text
# around them: a tuple's labels, a type argument written in a member's
# name (`copies.copy<T>(x)`), and the two names of `String.format(...)`,
# which the parser lowers.

import compiler.ast;
import [Expression, FunctionDecl, Module, Span, TypeName] from compiler.ast;
import "infer";
import "scope";

## A tuple's label where it is written: its name and span, and the
## element's type in a type or its value in a tuple.
export struct WrittenLabel {
    ## The label.
    var name: String;
    ## Where it is written.
    var span: Span;
    ## The element's type, in a tuple type.
    var ty: Ty?;
    ## The element's value, in a labeled tuple.
    var value: Expression?;

    ## Creates one.
    ##
    ## @param name the label
    ## @param span where it is written
    ## @param ty the element's type, if written in a type
    ## @param value the element's value, if written in a tuple
    construct(name: String, span: Span, ty: Ty?, value: Expression?) {
        this.name = name;
        this.span = span;
        this.ty = ty;
        this.value = value;
    }
}

## The tuple label at `offset`: in a labeled tuple (`(line: 3, column:
## 7)`) or a tuple type (`(line: int, column: int)`).
##
## @param module the document's syntax tree
## @param text the document's text
## @param offset the byte offset
## @returns the label; empty when none is there
export label_at(module: Module, text: String, offset: ulong): WrittenLabel? {
    var none = Optional<WrittenLabel>.Empty;
    var walk = SyntaxWalk.of_module(module);
    var found = none;
    while (walk.next() is Value(item)) {
        if (item is Expression(e)) {
            if (e is Tuple(elements, labels, _)) {
                ulong i = 0;
                while (i < labels.count and i < elements.count) {
                    if (on_name(labels[i].span, offset)) {
                        found = Optional<WrittenLabel>.Value(
                            WrittenLabel(
                                labels[i].name,
                                labels[i].span,
                                Optional<Ty>.Empty,
                                Optional<Expression>.Value(elements[i])
                            )
                        );
                    }
                    i += 1;
                }
            }
        }
    }
    if (found.is_value()) {
        return found;
    }
    var written = type_at(module, offset);
    if (written.is_empty()) {
        return none;
    }
    var ty = written.value();
    if (ty.name != ast.TUPLE_TYPE or ty.labels.count == 0) {
        return none;
    }
    var word = word_at(text, offset);
    if (word.is_empty()) {
        return none;
    }
    var span = word.value();
    if (!_colon_follows(text, span.end)) {
        return none;
    }
    var name = text.substr_bytes(span.start, span.end - span.start);
    ulong i = 0;
    while (i < ty.labels.count and i < ty.generic_types.count) {
        if (ty.labels[i] == name) {
            var element = Optional<Ty>.Value(Ty.from_ast(ty.generic_types[i]));
            return Optional<WrittenLabel>.Value(WrittenLabel(name, span, element, Optional<Expression>.Empty));
        }
        i += 1;
    }
    return none;
}

## Where the document first declares `label` of a tuple whose labels are
## `labels`: in a tuple type, else a labeled tuple value.
##
## @param module the document's syntax tree
## @param text the document's text
## @param labels the tuple's labels
## @param label the label
## @returns where it is written; empty when the document writes neither
export label_declared(module: Module, text: String, labels: String[], label: String): Span? {
    var types = Array<TypeName>();
    var values = Array<Span>();
    for (var declaration in module.declarations) {
        var functions = Array<FunctionDecl>();
        match (declaration) {
            Function(f) => {
                functions.append(f);
            }
            Struct(s) => {
                functions.append_all(s.methods);
                functions.append_all(s.constructors);
            }
            Extend(e) => {
                functions.append_all(e.methods);
            }
            Trait(t) => {
                functions.append_all(t.methods);
            }
            else => {}
        }
        for (var f in functions) {
            types.append(f.return_type);
        }
    }
    var walk = SyntaxWalk.of_module(module);
    while (walk.next() is Value(item)) {
        match (item) {
            Variable(v) => {
                types.append(v.type_name);
            }
            Expression(e) => {
                if (e is Tuple(_, written, _)) {
                    if (_same_labels(written, labels)) {
                        for (var l in written) {
                            if (l.name == label) {
                                values.append(l.span);
                            }
                        }
                    }
                }
            }
            else => {}
        }
    }
    # A type's labels have no spans: find the label and its `:` in its text.
    for (var t in types) {
        if (t.name != ast.TUPLE_TYPE or t.labels != labels) {
            continue;
        }
        var found = _label_in(text, t.span, label);
        if (found.is_value()) {
            return found;
        }
    }
    var first = Optional<Span>.Empty;
    for (var span in values) {
        if (first.is_empty() or span.start < first.value().start) {
            first = Optional<Span>.Value(span);
        }
    }
    return first;
}

## The type argument written in a member's name at `offset` (`T` of
## `copies.copy<T>(x)`): the parser keeps those in the member's name,
## after its name's span.
##
## @param module the document's syntax tree
## @param text the document's text
## @param offset the byte offset
## @returns the name written there; empty when none is
export type_argument_at(module: Module, text: String, offset: ulong): String? {
    var none = Optional<String>.Empty;
    bool inside = false;
    var walk = SyntaxWalk.of_module(module);
    while (walk.next() is Value(item)) {
        if (item is Expression(e)) {
            if (e is MemberAccess(_, name, name_span, _)) {
                if (!name.contains("<") or name_span.end > offset) {
                    continue;
                }
                var between = text.substr_bytes(name_span.end, offset - name_span.end);
                if (!between.trim().starts_with("<") or between.contains("(") or between.contains(")")) {
                    continue;
                }
                # Inside the brackets: more `<` before `offset` than `>`.
                if (_count_byte(between, '<') > _count_byte(between, '>')) {
                    inside = true;
                }
            }
        }
    }
    if (!inside) {
        return none;
    }
    var word = word_at(text, offset);
    if (word is Value(span)) {
        return Optional<String>.Value(text.substr_bytes(span.start, span.end - span.start));
    }
    return none;
}

## Which name of a `String.format(...)` call is at `offset`, `String` or
## `format`: the parser lowers the call, so neither is in the tree.
##
## @param text the document's text
## @param offset the byte offset
## @returns the name; empty for any other
export string_format_at(text: String, offset: ulong): String? {
    var none = Optional<String>.Empty;
    var word = word_at(text, offset);
    if (word.is_empty()) {
        return none;
    }
    var span = word.value();
    var name = text.substr_bytes(span.start, span.end - span.start);
    if (name == "String") {
        var after = text.substr_bytes(span.end, text.size - span.end).trim();
        if (!after.starts_with(".")) {
            return none;
        }
        after = after.substr_bytes(1, after.size - 1).trim();
        if (!after.starts_with("format")) {
            return none;
        }
        after = after.substr_bytes(6, after.size - 6).trim();
        return after.starts_with("(") ? Optional<String>.Value("String") : none;
    }
    if (name == "format") {
        var before = text.substr_bytes(0, span.start).trim();
        if (!before.ends_with(".")) {
            return none;
        }
        before = before.substr_bytes(0, before.size - 1).trim();
        var after = text.substr_bytes(span.end, text.size - span.end).trim();
        return before.ends_with("String") and after.starts_with("(") ? Optional<String>.Value("format") : none;
    }
    return none;
}

## Whether the document has a name (a reference or a member's name) at
## `offset`.
##
## @param module the document's syntax tree
## @param offset the byte offset
## @returns true when one is there
export names_at(module: Module, offset: ulong): bool {
    var found = find_expression(module, offset);
    if (found.is_empty()) {
        return false;
    }
    match (found.value()) {
        SymbolRef(_, span) => {
            return contains(span, offset);
        }
        MemberAccess(_, _, name_span, _) => {
            return contains(name_span, offset);
        }
        else => {}
    }
    return false;
}

## The identifier around `offset` in `text`.
##
## @param text the text
## @param offset the byte offset
## @returns its span; empty when no identifier is there
export word_at(text: String, offset: ulong): Span? {
    if (offset > text.size) {
        return Optional<Span>.Empty;
    }
    var start = offset;
    while (start > 0 and _is_word_byte(text.byte_at(start - 1))) {
        start -= 1;
    }
    var end = offset;
    while (end < text.size and _is_word_byte(text.byte_at(end))) {
        end += 1;
    }
    if (end <= start) {
        return Optional<Span>.Empty;
    }
    return Optional<Span>.Value(Span(start, end));
}

# Whether `written` labels a tuple as `labels` does.
_same_labels(written: ast.Label[], labels: String[]): bool {
    if (written.count != labels.count) {
        return false;
    }
    ulong i = 0;
    while (i < written.count) {
        if (written[i].name != labels[i]) {
            return false;
        }
        i += 1;
    }
    return true;
}

# Where `label`, followed by its `:`, is written in `span` of `text`.
_label_in(text: String, span: Span, label: String): Span? {
    var from = span.start;
    while (from < span.end) {
        var at = text.find(label, from);
        if (at < 0 or at as ulong + label.size > span.end) {
            return Optional<Span>.Empty;
        }
        var start = at as ulong;
        var end = start + label.size;
        var alone = start == 0 or !_is_word_byte(text.byte_at(start - 1));
        if (alone and _colon_follows(text, end)) {
            return Optional<Span>.Value(Span(start, end));
        }
        from = start + 1;
    }
    return Optional<Span>.Empty;
}

# Whether the first byte after `end`, past spaces, is a `:`.
_colon_follows(text: String, end: ulong): bool {
    var at = end;
    while (at < text.size and (text.byte_at(at) == ' ' or text.byte_at(at) == '\t')) {
        at += 1;
    }
    return at < text.size and text.byte_at(at) == ':';
}

_count_byte(text: String, b: u8): ulong {
    ulong n = 0;
    ulong i = 0;
    while (i < text.size) {
        if (text.byte_at(i) == b) {
            n += 1;
        }
        i += 1;
    }
    return n;
}

_is_word_byte(b: u8): bool {
    return (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b == '_';
}
