# Doc comments: the run of `##` lines written directly above a
# declaration, in a JSDoc-like format.
#
#     ## Removes and returns the last element.
#     ##
#     ## @returns the element that was last
#     ## @panics if the Array is empty
#     pop(): T { ... }
#
# Each line's text follows `## ` (one space is dropped). A plain `#`
# comment, or a decorative `###...` line, is not documentation.
#
# The text before the first tag is the description (Markdown). Tags:
#
# - `@typeParam T description`: a generic parameter of the declaration.
# - `@param name description`: a parameter of the function or constructor.
# - `@returns description`: what a function that returns a value returns.
# - `@panics description`: when the function panics instead of returning.
# - `@example`: sample code, shown as a code block. `@example no-run`
#   marks a whole program that is built but not run (a server).
# - `@see reference`, `@note text`: related declarations, remarks.
#
# A tag's text runs until the next tag. Attributes and `export`, `private`
# or `static` may sit between the comment and the declaration; a blank
# line may not.
#
# `check_documented` is the standard every runtime library file meets:
# each public declaration (exported, by `export` or by a bare `export
# name;` in its module, and not `_`-prefixed) and each public member of
# one carries a doc comment that describes it and tags every parameter,
# generic parameter, and returned value.

import compiler.ast;
import [
    Declaration, Expression, FunctionDecl, GenericParam, Module, PropertyDecl, Span, VariableDecl
] from compiler.ast;
import compiler.diagnostic;
import [Diagnostic, Location, SourceText] from compiler.diagnostic;
import "text";

# One tag of a doc comment: `@param count how many` is kind `param`, name
# `count`, text `how many`. Tags that name nothing (`@returns`) have an
# empty name.
export struct DocTag {
    var kind: String = "";
    var name: String = "";
    var text: String = "";
    # Where the tag's name is in the source, or its `@kind` when it has
    # no name.
    var span: Span;

    construct(kind: String, name: String, text: String, span: Span) {
        this.kind = kind;
        this.name = name;
        this.text = text;
        this.span = span;
    }
}

# A parsed `##` doc comment.
export struct DocComment {
    # The text before the first tag.
    var description: String = "";
    var tags: DocTag[] = Array<DocTag>();
    # The whole comment, from its first `##` to the end of its last line.
    var span: Span;

    construct() {}

    # The tags of `kind`, in order.
    tags_of(kind: String): DocTag[] {
        var out = Array<DocTag>();
        for (var tag in tags) {
            if (tag.kind == kind) {
                out.append(tag);
            }
        }
        return out;
    }

    # Whether a tag of `kind` names `name`.
    has_tag(kind: String, name: String): bool {
        for (var tag in tags) {
            if (tag.kind == kind and tag.name == name) {
                return true;
            }
        }
        return false;
    }

    # The comment as Markdown.
    to_markdown(): String {
        var out = description;
        out = _section(out, "Type parameters", _named(tags_of("typeParam")));
        out = _section(out, "Parameters", _named(tags_of("param")));
        out = _section(out, "Returns", _plain(tags_of("returns")));
        out = _section(out, "Panics", _plain(tags_of("panics")));
        out = _section(out, "See also", _see(tags_of("see")));
        out = _section(out, "Note", _plain(tags_of("note")));
        for (var example in tags_of("example")) {
            out = out + $"\n\n**Example**\n```pepper\n{dedent(example.text)}\n```";
        }
        return out;
    }
}

# `out` followed by a section titled `title` that lists `items`; `out` as
# it is without any.
_section(out: String, title: String, items: String[]): String {
    if (items.is_empty) {
        return out;
    }
    var text = out.is_empty ? $"**{title}**" : $"{out}\n\n**{title}**";
    for (var item in items) {
        text = text + "\n- " + item;
    }
    return text;
}

# Tags whose first word is the name of something (a parameter).
_is_named_tag(kind: String): bool {
    return kind == "param" or kind == "typeParam";
}

_named(tags: DocTag[]): String[] {
    var out = Array<String>();
    for (var tag in tags) {
        out.append($"`{tag.name}` — {tag.text}");
    }
    return out;
}

_plain(tags: DocTag[]): String[] {
    var out = Array<String>();
    for (var tag in tags) {
        out.append(tag.text);
    }
    return out;
}

# `@see hash<String>` names code: shown as code, so `<...>` is not read as
# HTML.
_see(tags: DocTag[]): String[] {
    var out = Array<String>();
    for (var tag in tags) {
        if (tag.text.contains("`")) {
            out.append(tag.text);
            continue;
        }
        var space = find_space(tag.text, 0);
        if (space == tag.text.size) {
            out.append($"`{tag.text}`");
            continue;
        }
        var name = tag.text.substr_bytes(0, space);
        var rest = tag.text.substr_bytes(space + 1, tag.text.size - space - 1);
        out.append($"`{name}` {rest}");
    }
    return out;
}

# `text` with the indentation its non-blank lines share removed, so an
# `@example` written indented under its tag shows from the left margin.
export dedent(text: String): String {
    var lines = text.lines();
    ulong indent = 0;
    bool any = false;
    for (var line in lines) {
        if (line.trim().is_empty) {
            continue;
        }
        var own = line.size - line.trim_start().size;
        if (!any or own < indent) {
            indent = own;
            any = true;
        }
    }
    var out = Array<String>();
    for (var line in lines) {
        out.append(line.size < indent ? "" : line.substr_bytes(indent, line.size - indent).trim_end());
    }
    return "\n".join(out);
}

# Parses the `##` lines spanning `span` in `source`.
export parse_doc_comment(source: String, span: Span): DocComment {
    var doc = DocComment();
    doc.span = span;
    var description = StringBuilder();
    var offset = span.start;
    while (offset < span.end) {
        var line_end = find_byte(source, '\n', offset, span.end);
        var next = line_end < span.end ? line_end + 1 : span.end;
        var line_start = offset;
        offset = next;
        # The line without its line break, then without the `## ` gutter.
        var raw_end = line_end;
        while (raw_end > line_start and (source.byte_at(raw_end - 1) == '\n' or source.byte_at(raw_end - 1) == '\r')) {
            raw_end -= 1;
        }
        var column = skip_spaces(source, line_start, raw_end);
        if (starts_with_at(source, column, raw_end, "##")) {
            column += 2;
            if (column < raw_end and source.byte_at(column) == ' ') {
                column += 1;
            }
        }
        var text = source.substr_bytes(column, raw_end - column).trim_end();
        if (text.starts_with("@")) {
            doc.tags.append(_tag(text, column));
            continue;
        }
        if (doc.tags.is_empty) {
            description.append(text);
            description.append("\n");
            continue;
        }
        # A continuation line of the current tag; `@example` keeps its
        # line breaks.
        var tag = doc.tags.last();
        if (tag.kind == "example" or tag.text.is_empty) {
            if (!tag.text.is_empty) {
                tag.text = tag.text + "\n" + text;
            } else if (!text.is_empty) {
                tag.text = text;
            }
        } else if (!text.is_empty) {
            tag.text = tag.text + " " + text.trim_start();
        }
    }
    for (var tag in doc.tags) {
        tag.text = tag.text.trim_end();
    }
    doc.description = description.to_string().trim();
    return doc;
}

# The tag `text` (`@kind ...`) starts at byte `column` of its file.
_tag(text: String, column: ulong): DocTag {
    var kind_size = find_space(text, 1) - 1;
    var kind = text.substr_bytes(1, kind_size);
    var rest_start = skip_spaces(text, 1 + kind_size, text.size);
    var rest = text.substr_bytes(rest_start, text.size - rest_start);
    if (kind == "example") {
        # `@example no-run`: its name is how the example is checked; the
        # code follows on the next lines.
        return DocTag(kind, rest, "", Span(column, column + 1 + kind_size));
    }
    if (!_is_named_tag(kind)) {
        return DocTag(kind, "", rest, Span(column, column + 1 + kind_size));
    }
    var name_size = find_space(rest, 0);
    var name = rest.substr_bytes(0, name_size);
    var description = rest.substr_bytes(name_size, rest.size - name_size).trim_start();
    return DocTag(kind, name, description, Span(column + rest_start, column + rest_start + name_size));
}

# Whether parameter `p` defaults to `__caller_location()`: the compiler
# fills it with the call's location so a panic reports the caller's line.
# Callers never pass it, so the documentation leaves it out.
export is_caller_location(p: VariableDecl): bool {
    if (p.default_value.is_empty()) {
        return false;
    }
    if (p.default_value.value() is FunctionCall(function, arguments, _)) {
        return arguments.is_empty and _is_symbol(function, "__caller_location");
    }
    return false;
}

# Whether `expression` is the name `name`.
_is_symbol(expression: Expression, name: String): bool {
    if (expression is SymbolRef(id, _)) {
        return id == name;
    }
    return false;
}

# The doc comment directly above a declaration starting at `offset`: only
# line breaks and indentation, attributes (`[...]`), and `export`,
# `private` or `static` may sit between its last `##` line and `offset`. A
# blank line in between detaches the comment.
export doc_comment_before(source: String, offset: ulong): DocComment? {
    var end = offset < source.size ? offset : source.size;
    while (true) {
        ulong newlines = 0;
        while (end > 0 and is_ascii_space(source.byte_at(end - 1))) {
            if (source.byte_at(end - 1) == '\n') {
                newlines += 1;
            }
            end -= 1;
        }
        if (newlines > 1) {
            return Optional<DocComment>.Empty;
        }
        # Reached a comment line: stop (its `[...]` is text, not an
        # attribute).
        var first = skip_spaces(source, line_start_before(source, end), end);
        if (first < end and source.byte_at(first) == '#') {
            break;
        }
        var keyword = _keyword_before(source, end);
        if (keyword > 0) {
            end -= keyword;
            continue;
        }
        if (end == 0 or source.byte_at(end - 1) != ']') {
            break;
        }
        # Back over one attribute `[...]`.
        ulong depth = 0;
        var i = end;
        while (i > 0) {
            i -= 1;
            var b = source.byte_at(i);
            if (b == ']') {
                depth += 1;
            } else if (b == '[') {
                depth -= 1;
                if (depth == 0) {
                    break;
                }
            }
        }
        if (depth != 0) {
            return Optional<DocComment>.Empty;
        }
        end = i;
    }
    # `end` is now the end of the line above; gather the `##` lines that
    # end there, bottom to top.
    var block_end = end;
    bool found = false;
    ulong block_start = 0;
    while (true) {
        var line_start = line_start_before(source, end);
        var first = skip_spaces(source, line_start, end);
        if (!is_doc_line(source.substr_bytes(first, end - first))) {
            break;
        }
        found = true;
        block_start = first;
        if (line_start == 0) {
            break;
        }
        end = line_start - 1;
        if (end > 0 and source.byte_at(end - 1) == '\r') {
            end -= 1;
        }
    }
    if (!found) {
        return Optional<DocComment>.Empty;
    }
    return Optional<DocComment>.Value(parse_doc_comment(source, Span(block_start, block_end)));
}

# The size of the `export`, `private` or `static` that ends
# `source[..end]` as a word of its own; 0 when none does.
_keyword_before(source: String, end: ulong): ulong {
    for (var keyword in ["export", "private", "static"]) {
        if (end < keyword.size or !starts_with_at(source, end - keyword.size, end, keyword)) {
            continue;
        }
        var rest = end - keyword.size;
        if (rest == 0 or !is_word_byte(source.byte_at(rest - 1))) {
            return keyword.size;
        }
        return 0;
    }
    return 0;
}

# A doc comment line: `##`, then anything but another `#` (`###...` is a
# decorative rule, not documentation).
export is_doc_line(trimmed: String): bool {
    var text = trimmed.trim_end();
    return text.starts_with("##") and !text.starts_with("###");
}

# Every run of `##` lines in `source`, in order, the file's own included.
export doc_comments(source: String): DocComment[] {
    var out = Array<DocComment>();
    ulong offset = 0;
    ulong start = 0;
    ulong end = 0;
    bool inside = false;
    while (offset < source.size) {
        var line_end = find_byte(source, '\n', offset, source.size);
        var first = skip_spaces(source, offset, line_end);
        if (is_doc_line(source.substr_bytes(first, line_end - first))) {
            if (!inside) {
                start = first;
                inside = true;
            }
            end = line_end;
        } else if (inside) {
            out.append(parse_doc_comment(source, Span(start, end)));
            inside = false;
        }
        offset = line_end + 1;
    }
    if (inside) {
        out.append(parse_doc_comment(source, Span(start, end)));
    }
    return out;
}

# The `##` block that opens a file, before any code: the file's own
# documentation. It must be followed by a blank line, which keeps it apart
# from the doc comment of a declaration directly below.
export file_doc(source: String): DocComment? {
    ulong end = 0;
    ulong offset = 0;
    while (offset < source.size) {
        var line_end = find_byte(source, '\n', offset, source.size);
        var next = line_end < source.size ? line_end + 1 : source.size;
        var raw = source.substr_bytes(offset, next - offset);
        if (!is_doc_line(raw.trim())) {
            if (end == 0 or !raw.trim().is_empty) {
                return Optional<DocComment>.Empty;
            }
            break;
        }
        offset = next;
        end = offset - (raw.size - raw.trim_end().size);
    }
    if (end == 0) {
        return Optional<DocComment>.Empty;
    }
    return Optional<DocComment>.Value(parse_doc_comment(source, Span(0, end)));
}

# Where a declaration's text starts: at its first attribute, or at the
# declaration itself.
export first_attribute(attributes: ast.Attribute[], start: ulong): ulong {
    var first = start;
    for (var attribute in attributes) {
        if (attribute.span.start < first) {
            first = attribute.span.start;
        }
    }
    return first;
}

# The doc comment above `decl` in `source`, its file.
export doc_comment_of(source: String, decl: Declaration): DocComment? {
    return doc_comment_before(source, first_attribute(decl.attributes(), decl.span().start));
}

# Public: not `_`-prefixed. `_`-prefixed names (`_pep_malloc`,
# `_io_sys_open`) are runtime internals exported only between runtime
# files.
export is_public(name: String): bool {
    return !name.starts_with("_");
}

# A public method: not `_`-prefixed, or an indexer (`[](...)`, named
# `__index_get` or `__index_set` internally).
export is_public_member(f: FunctionDecl): bool {
    return f.is_indexer or is_public(f.name);
}

# The name a member is written as: `[]` for an indexer.
export member_name(f: FunctionDecl): String {
    return f.is_indexer ? "[]" : f.name;
}

# The built-in a `[__BuiltIn]` declaration named `name` declares: the
# attribute's string argument, else `name`; none without the attribute.
export built_in_name(attributes: ast.Attribute[], name: String): String? {
    for (var attribute in attributes) {
        if (attribute.name() != ast.BUILT_IN_ATTRIBUTE) {
            continue;
        }
        var spelled = _string_argument(attribute.body);
        return Optional<String>.Value(spelled.is_value() ? spelled.value() : name);
    }
    return Optional<String>.Empty;
}

# The first string literal among the arguments of the attribute `body`.
_string_argument(body: Expression): String? {
    if (body is FunctionCall(_, arguments, _)) {
        for (var argument in arguments) {
            var text = _string_literal(argument);
            if (text.is_value()) {
                return text;
            }
        }
    }
    return Optional<String>.Empty;
}

# The text of `argument` when it is a string literal, named or not.
_string_literal(argument: Expression): String? {
    var value = argument;
    if (argument is NamedArgument(_, _, named, _)) {
        value = named;
    }
    if (value is Literal(literal, _)) {
        if (literal is String(text)) {
            return Optional<String>.Value(text);
        }
    }
    return Optional<String>.Empty;
}

# Whether `decl` is exported: declared `export`, or named in
# `reexported`, the names a bare `export name;` in its module makes
# public. That export names neither an extension of the type it names
# nor an `extern`, which keeps the C library's name beside the module's
# function (`process`'s `fork`).
export is_exported(decl: Declaration, reexported: String[]): bool {
    if (decl.is_exported()) {
        return true;
    }
    if (_is_extension(decl)) {
        return false;
    }
    if (decl is Function(f)) {
        if (f.external) {
            return false;
        }
    }
    return reexported.contains(decl.declared_name());
}

# Errors for every public declaration of `module` (parsed from `source`,
# the file `name`) that does not meet the documentation standard (see the
# top of this file), rendered as clang renders them: exported, non-`_` (or
# `[__BuiltIn]`) declarations and their non-`_` members need a doc comment
# with a description, `@typeParam` for each generic parameter, `@param`
# for each parameter, and `@returns` when they return a value; and no tag
# may name a parameter that does not exist. A declaration named in
# `reexported` counts as exported (see `is_exported`).
export check_documented(module: Module, source: String, name: String, reexported: String[]): String[] {
    var checker = _Checker(source);
    ulong index = 0;
    for (var decl in module.declarations) {
        var position = index;
        index += 1;
        if (!is_exported(decl, reexported)) {
            continue;
        }
        var doc = doc_comment_of(source, decl);
        # A `[__BuiltIn]` declaration is public whatever its name (`__ptr`).
        bool built_in = ast.is_built_in(decl.attributes());
        if (!built_in and !is_public(decl.declared_name()) and !_is_extension(decl)) {
            continue;
        }
        match (decl) {
            Function(f) => {
                # A concrete override (`hash<String>` after `hash<T>`)
                # names types, not generic parameters. It has as many as
                # the generic it overrides; an overload with a different
                # count (`to_string<A, B>` beside `to_string<T>`) has
                # parameters of its own.
                var generics = _overrides(module, position, f) ? Array<GenericParam>() : f.generic_params;
                checker.function(f, f.name, doc, generics);
            }
            Struct(s) => {
                if (checker.described(doc, s.name, s.name_span)) {
                    checker.generics(doc.value(), s.name, s.generic_params, s.name_span);
                }
                if (s.enumeration.is_value()) {
                    for (var c in s.enumeration.value().cases) {
                        checker.described(doc_comment_before(source, c.span.start), $"{s.name}.{c.name}", c.name_span);
                    }
                }
                for (var field in s.fields) {
                    if (is_public(field.name)) {
                        checker.described(
                            doc_comment_before(source, field.span.start), $"{s.name}.{field.name}", field.name_span
                        );
                    }
                }
                checker.properties(s.name, s.properties);
                for (var c in s.constructors) {
                    checker.function(c, $"{s.name}.{c.name}", checker.member_doc(c), Array<GenericParam>());
                }
                checker.methods(s.name, s.methods);
            }
            Trait(t) => {
                if (checker.described(doc, t.name, t.name_span)) {
                    checker.generics(doc.value(), t.name, t.generic_params, t.name_span);
                }
                checker.properties(t.name, t.properties);
                checker.methods(t.name, t.methods);
            }
            Extend(e) => {
                checker.properties(e.target.name, e.properties);
                checker.methods(e.target.name, e.methods);
            }
            TypeAlias(t) => {
                if (checker.described(doc, t.name, t.name_span)) {
                    checker.generics(doc.value(), t.name, t.generic_params, t.name_span);
                }
            }
            Variable(v) => {
                checker.described(doc, v.name, v.name_span);
            }
            else => {}
        }
    }
    var sources = [SourceText(name, source)];
    var out = Array<String>();
    for (var error in checker.errors) {
        out.append(error.render(sources));
    }
    return out;
}

# Whether the function `f`, declaration `position` of `module`, overrides
# a generic function declared before it with as many generic parameters,
# or names only structs `module` declares (`hash<BitSet>` beside `BitSet`).
_overrides(module: Module, position: ulong, f: FunctionDecl): bool {
    if (!f.generic_params.is_empty and _names_own_structs(module, f.generic_params)) {
        return true;
    }
    ulong index = 0;
    for (var d in module.declarations) {
        var other = index;
        index += 1;
        if (other == position) {
            continue;
        }
        if (d is Function(g)) {
            if (g.name == f.name
                and g.span.start < f.span.start
                and !g.generic_params.is_empty
                and g.generic_params.count == f.generic_params.count) {
                return true;
            }
        }
    }
    return false;
}

# Whether each of `params` is the name of a struct `module` declares.
_names_own_structs(module: Module, params: GenericParam[]): bool {
    for (var p in params) {
        bool found = false;
        for (var d in module.declarations) {
            if (d is Struct(s)) {
                if (s.name == p.name) {
                    found = true;
                    break;
                }
            }
        }
        if (!found) {
            return false;
        }
    }
    return true;
}

_is_extension(decl: Declaration): bool {
    if (decl is Extend(_)) {
        return true;
    }
    return false;
}

struct _Checker {
    var source: String;
    var errors: Diagnostic[] = Array<Diagnostic>();

    construct(source: String) {
        this.source = source;
    }

    error(message: String, span: Span) {
        errors.append(Diagnostic.error(message).at(Location(0, span)));
    }

    # Reports a missing comment or description; true when `doc` exists.
    described(doc: DocComment?, what: String, span: Span): bool {
        if (doc.is_empty()) {
            error($"missing doc comment for '{what}'", span);
            return false;
        }
        var comment = doc.value();
        if (comment.description.is_empty) {
            # The comment's first `##`.
            error($"doc comment for '{what}' has no description", Span(comment.span.start, comment.span.start + 2));
        }
        return true;
    }

    member_doc(f: FunctionDecl): DocComment? {
        return doc_comment_before(source, first_attribute(f.attributes, f.span.start));
    }

    methods(owner: String, methods: FunctionDecl[]) {
        for (var m in methods) {
            if (is_public_member(m)) {
                function(m, $"{owner}.{member_name(m)}", member_doc(m), m.generic_params);
            }
        }
    }

    properties(owner: String, properties: PropertyDecl[]) {
        for (var p in properties) {
            if (is_public(p.name)) {
                described(doc_comment_before(source, p.span.start), $"{owner}.{p.name}", p.name_span);
            }
        }
    }

    generics(doc: DocComment, what: String, params: GenericParam[], span: Span) {
        for (var p in params) {
            if (!doc.has_tag("typeParam", p.name)) {
                error($"missing '@typeParam {p.name}' in the doc comment for '{what}'", span);
            }
        }
        for (var tag in doc.tags_of("typeParam")) {
            if (!_names_generic(params, tag.name)) {
                error($"'@typeParam {tag.name}' names no generic parameter of '{what}'", tag.span);
            }
        }
    }

    function(f: FunctionDecl, what: String, doc: DocComment?, generics: GenericParam[]) {
        if (!described(doc, what, f.name_span)) {
            return;
        }
        var comment = doc.value();
        this.generics(comment, what, generics, f.name_span);
        for (var p in f.parameters) {
            if (!is_caller_location(p) and !comment.has_tag("param", p.name)) {
                error($"missing '@param {p.name}' in the doc comment for '{what}'", p.name_span);
            }
        }
        for (var tag in comment.tags_of("param")) {
            var parameter = _parameter(f, tag.name);
            if (parameter.is_empty()) {
                error($"'@param {tag.name}' names no parameter of '{what}'", tag.span);
            } else if (is_caller_location(parameter.value())) {
                error(
                    $"'@param {tag.name}' documents a '__caller_location()' parameter, which callers never pass; remove it",
                    tag.span
                );
            }
        }
        _returns(f, what, comment);
        for (var tag in comment.tags) {
            if (tag.kind != "example" and tag.text.is_empty) {
                error($"'@{tag.kind}' in the doc comment for '{what}' has no description", tag.span);
            }
        }
    }

    # A function that returns a value needs `@returns`, and one that
    # returns nothing may not have it. An omitted return type (`__auto`)
    # is inferred from the body, so either way is accepted there.
    _returns(f: FunctionDecl, what: String, comment: DocComment) {
        var returned = f.return_type.name;
        if (returned == ast.AUTO_TYPE and !_is_constructor(f)) {
            return;
        }
        bool returns_value = !_is_constructor(f) and returned != "void";
        var tags = comment.tags_of("returns");
        if (tags.is_empty and returns_value) {
            var span = f.return_type.span.start == f.return_type.span.end ? f.name_span : f.return_type.span;
            error($"missing '@returns' in the doc comment for '{what}'", span);
        }
        if (!tags.is_empty and !returns_value) {
            error($"'@returns' on '{what}', which returns nothing", tags[0].span);
        }
    }
}

# The parameter of `f` named `name`.
_parameter(f: FunctionDecl, name: String): VariableDecl? {
    for (var p in f.parameters) {
        if (p.name == name) {
            return Optional<VariableDecl>.Value(p);
        }
    }
    return Optional<VariableDecl>.Empty;
}

_names_generic(params: GenericParam[], name: String): bool {
    for (var p in params) {
        if (p.name == name) {
            return true;
        }
    }
    return false;
}

_is_constructor(f: FunctionDecl): bool {
    return f.name == "new" or f.name == "construct";
}
