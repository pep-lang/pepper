# Completion: what may be typed at an offset. After `Enum.`, the enum's
# cases and static methods; otherwise the keywords, the names in scope
# (locals, the members of the struct around, the file's declarations and
# those of the other files of its module) and, inside a call's argument
# list, the parameter names to pass by name.

import [Declaration, Expression, FunctionDecl, Module, Span, StructDecl] from compiler.ast;
import compiler.link;
import lsp;
import compiler.parse;
import compiler.sema;
import "analysis";
import "edits";
import "scope";
import "symbols";

## The words completion offers anywhere, separated by spaces.
export const KEYWORDS = "import from struct var const if else while for in return extern and or construct destruct static sizeof true false trait extend export private shared enum match is";

## The completions at `offset` of `document`.
##
## @param document the document as the editor holds it
## @param latest its last analysis, if any
## @param ready its newest analysis that passed sema, if any
## @param offset the byte offset in its text
## @returns the items, in no particular order
export completion_at(
    document: lsp.TextDocument, latest: Analysis?, ready: Analysis?, offset: ulong
): lsp.CompletionItem[] {
    var items = Array<lsp.CompletionItem>();
    var module = _parse_while_typing(document.text, offset);
    if (module.is_empty()) {
        return _keywords(items);
    }
    var program = _program(latest, ready);
    # After `Enum.`, the enum's cases alone.
    var cases = enum_cases_before(module.value(), program, document.text, offset);
    if (cases.is_value()) {
        return cases.value();
    }
    _keywords(items);
    var site = _Site(document, module.value(), program, ready, offset);
    for (var item in site.argument_names()) {
        items.append(item);
    }
    var symbols = scope_locals(module.value(), offset);
    var around = body_at(module.value(), offset);
    if (around is Value(enclosing)) {
        if (enclosing.owner is Value(owner)) {
            symbols.append_all(collect_struct_members(owner));
        }
    }
    symbols.append_all(collect_globals(module.value()));
    if (program is Value(p)) {
        symbols.append_all(module_globals(p));
    }
    for (var symbol in symbols) {
        var item = lsp.CompletionItem(symbol.name, _kind(symbol.type_text));
        item.detail = Optional<String>.Value(symbol.type_text);
        items.append(item);
    }
    return items;
}

## The cases of the enum whose name ends the text before `offset` with a
## `.` (`Color.|`), then its static methods, and `from_value` when its
## cases carry no values.
##
## @param module the document's syntax tree
## @param program its loaded program, if any, for enums other files declare
## @param text the document's text
## @param offset the byte offset
## @returns the items; empty when no enum's name is before the `.`
export enum_cases_before(module: Module, program: link.Program?, text: String, offset: ulong): lsp.CompletionItem[]? {
    var none = Optional<Array<lsp.CompletionItem>>.Empty;
    if (offset == 0 or offset > text.size or text.byte_at(offset - 1) != '.') {
        return none;
    }
    var name = text.substr_bytes(_name_start(text, offset - 1), offset - 1 - _name_start(text, offset - 1));
    var found = _struct_named(module, program, name);
    if (found.is_empty() or found.value().enumeration.is_empty()) {
        return none;
    }
    var s = found.value();
    var items = Array<lsp.CompletionItem>();
    var carries_values = false;
    for (var case in s.enumeration.value().cases) {
        var item = lsp.CompletionItem(case.name, lsp.COMPLETION_ENUM_MEMBER);
        var detail = $"{name}.{case.name}";
        if (case.payload is Value(values)) {
            carries_values = true;
            var listed = Array<String>();
            for (var v in values) {
                listed.append($"{v.name}: {v.type_name.to_string()}");
            }
            detail = detail + "(" + ", ".join(listed) + ")";
        }
        item.detail = Optional<String>.Value(detail);
        items.append(item);
    }
    for (var m in s.methods) {
        if (!m.is_static) {
            continue;
        }
        var item = lsp.CompletionItem(m.name, lsp.COMPLETION_METHOD);
        item.detail = Optional<String>.Value("static " + function_signature(m));
        items.append(item);
    }
    if (!carries_values) {
        var item = lsp.CompletionItem("from_value", lsp.COMPLETION_METHOD);
        item.detail = Optional<String>.Value($"static from_value(value): Result<{name}>");
        items.append(item);
    }
    return Optional<Array<lsp.CompletionItem>>.Value(items);
}

## The top-level declarations of the other files of the module of
## `program.files[0]`, which it sees with no import, spelled as written
## (linking mangles them). A `private` one stays in its file.
##
## @param program the loaded program
## @returns the declarations
export module_globals(program: link.Program): Symbol[] {
    var out = Array<Symbol>();
    var root = program.files[0].module_root;
    if (root.is_empty()) {
        return out;
    }
    var key = root.value().to_string();
    ulong file = 1;
    while (file < program.files.count) {
        var f = program.files[file];
        file += 1;
        if (f.module_root.is_empty() or f.module_root.value().to_string() != key) {
            continue;
        }
        var private_names = Array<ulong>();
        for (var declaration in f.module.declarations) {
            if (declaration.is_private()) {
                private_names.append(declaration.name_span().start);
            }
        }
        for (var symbol in collect_globals(f.module)) {
            if (private_names.contains(symbol.name_span.start)) {
                continue;
            }
            symbol.name = link.demangle_name(symbol.name);
            out.append(symbol);
        }
    }
    return out;
}

# What finds the call around an offset and the functions it may call.
struct _Site {
    var document: lsp.TextDocument;
    var module: Module;
    var program: link.Program?;
    var ready: Analysis?;
    var offset: ulong;

    construct(document: lsp.TextDocument, module: Module, program: link.Program?, ready: Analysis?, offset: ulong) {
        this.document = document;
        this.module = module;
        this.program = program;
        this.ready = ready;
        this.offset = offset;
    }

    # The parameter names, and their other names, of the functions the
    # call whose argument list holds the offset may call, less those
    # already passed by name: items that insert `name = `.
    argument_names(): lsp.CompletionItem[] {
        var items = Array<lsp.CompletionItem>();
        var text = document.text;
        # A name being typed, after `(` or `,`; a number is not a name.
        var start = _name_start(text, offset);
        if (start < offset and _is_digit(text.byte_at(start))) {
            return items;
        }
        var before = start;
        while (before > 0 and _is_space(text.byte_at(before - 1))) {
            before -= 1;
        }
        if (before == 0 or (text.byte_at(before - 1) != '(' and text.byte_at(before - 1) != ',')) {
            return items;
        }
        var call = _call_around(module, offset);
        if (call.is_empty()) {
            return items;
        }
        var (function, arguments) = call.value();
        var named = Array<String>();
        for (var argument in arguments) {
            if (argument is NamedArgument(name, name_span, _, _)) {
                if (name_span.end < offset or name_span.start > offset) {
                    named.append(name);
                }
            }
        }
        for (var callee in _callees(function)) {
            var parameters = Array<String>();
            for (var p in callee.parameters) {
                if (p.name != "this") {
                    parameters.append(p.name.starts_with("this.") ? p.name.substr_bytes(5, p.name.size - 5) : p.name);
                }
            }
            ulong index = 0;
            for (var p in callee.parameters) {
                if (p.name == "this") {
                    continue;
                }
                var name = parameters[index];
                index += 1;
                _offer(items, named, name, $"{name}: {p.type_name.to_string()}");
            }
            for (var other in sema.other_names(callee.attributes, parameters, 0)) {
                if (other.is_err() or other.value().deprecated) {
                    continue;
                }
                var alias = other.value();
                _offer(items, named, alias.name, $"another name for '{parameters[alias.parameter]}'");
            }
        }
        return items;
    }

    # The functions a call of `function` may call: a method of the value
    # before the `.`, a bare method of the struct around, else the
    # functions and constructors of that name.
    _callees(function: Expression): FunctionDecl[] {
        var out = Array<FunctionDecl>();
        match (function) {
            SymbolRef(id, _) => {
                var around = body_at(module, offset);
                if (around is Value(enclosing)) {
                    if (enclosing.owner is Value(owner)) {
                        _methods_named(owner, id, out);
                        if (out.count > 0) {
                            return out;
                        }
                    }
                }
                for (var m in _modules()) {
                    for (var declaration in m.declarations) {
                        _declared_callees(declaration, id, out);
                    }
                }
            }
            MemberAccess(lhs, name, _, _) => {
                var owner = _type_of(lhs);
                if (owner.is_empty()) {
                    return out;
                }
                var s = _struct_named(module, program, owner.value());
                if (s.is_value()) {
                    _methods_named(s.value(), name, out);
                }
            }
            else => {}
        }
        return out;
    }

    # The document's syntax tree, then the other files of its program.
    _modules(): Module[] {
        var out = Array<Module>();
        out.append(module);
        if (program is Value(p)) {
            ulong file = 1;
            while (file < p.files.count) {
                out.append(p.files[file].module);
                file += 1;
            }
        }
        return out;
    }

    # The name of the struct `lhs` is a value of: `this`, a local or
    # parameter with its type written, one sema typed in the passed
    # analysis, or one a constructor call initializes.
    _type_of(lhs: Expression): String? {
        var none = Optional<String>.Empty;
        if (lhs is SymbolRef(id, _)) {
            if (id == "this") {
                var around = body_at(module, offset);
                if (around is Value(enclosing)) {
                    if (enclosing.owner is Value(owner)) {
                        return Optional<String>.Value(owner.name);
                    }
                }
                return none;
            }
            for (var local in scope_locals(module, offset)) {
                if (local.name != id) {
                    continue;
                }
                if (local.type_text != "" and local.type_text != "unknown") {
                    return Optional<String>.Value(_base_name(local.type_text));
                }
                var typed = _sema_type(local.name_span);
                if (typed.is_value()) {
                    return typed;
                }
                return _constructed(local.name_span);
            }
        }
        return none;
    }

    # The type sema gave the local declared at `name`, in the passed
    # analysis, when the declaration's line is outside the edit since.
    _sema_type(name: Span): String? {
        var none = Optional<String>.Empty;
        if (ready.is_empty() or ready.value().model.is_empty()) {
            return none;
        }
        var r = ready.value();
        var earlier = Optional<ulong>.Value(name.start);
        if (r.text != document.text) {
            earlier = EditMap(r.text, document.text).to_earlier(document.text, name.start);
        }
        if (earlier.is_empty()) {
            return none;
        }
        var ty = sema.local_type(r.model.value(), 0, earlier.value());
        if (ty.is_empty()) {
            return none;
        }
        return Optional<String>.Value(link.demangle_name(_base_name(ty.value().to_string())));
    }

    # The struct whose constructor initializes the local declared at
    # `name`: `var w = Window(640, 480)`.
    _constructed(name: Span): String? {
        var none = Optional<String>.Empty;
        var text = document.text;
        var at = name.end;
        while (at < text.size and _is_space(text.byte_at(at))) {
            at += 1;
        }
        if (at >= text.size or text.byte_at(at) != '=') {
            return none;
        }
        at += 1;
        while (at < text.size and _is_space(text.byte_at(at))) {
            at += 1;
        }
        var end = at;
        while (end < text.size and _is_name_byte(text.byte_at(end))) {
            end += 1;
        }
        if (end == at or end >= text.size or (text.byte_at(end) != '(' and text.byte_at(end) != '<')) {
            return none;
        }
        var id = text.substr_bytes(at, end - at);
        if (_struct_named(module, program, id).is_empty()) {
            return none;
        }
        return Optional<String>.Value(id);
    }
}

# Adds an item that passes `name` by name, unless it is passed already or
# offered.
_offer(items: lsp.CompletionItem[], named: String[], name: String, detail: String) {
    if (named.contains(name)) {
        return;
    }
    for (var item in items) {
        if (item.label == name) {
            return;
        }
    }
    var item = lsp.CompletionItem(name, lsp.COMPLETION_FIELD);
    item.detail = Optional<String>.Value(detail);
    item.insert_text = Optional<String>.Value(name + " = ");
    item.sort_text = Optional<String>.Value("0" + name);
    items.append(item);
}

# Adds the methods of `s` named `name` to `out`.
_methods_named(s: StructDecl, name: String, out: FunctionDecl[]) {
    for (var m in s.methods) {
        if (m.name == name) {
            out.append(m);
        }
    }
}

# Adds what `declaration` declares under the name `id` that a call runs:
# the function, or the struct's constructors.
_declared_callees(declaration: Declaration, id: String, out: FunctionDecl[]) {
    match (declaration) {
        Function(f) => {
            if (link.demangle_name(f.name) == id) {
                out.append(f);
            }
        }
        Struct(s) => {
            if (link.demangle_name(s.name) == id) {
                out.append_all(s.constructors);
            }
        }
        else => {}
    }
}

# The innermost call whose argument list holds `offset`: what it calls,
# and its arguments.
_call_around(module: Module, offset: ulong): (Expression, Expression[])? {
    var found = Optional<(Expression, Expression[])>.Empty;
    ulong found_start = 0;
    var stack = outer_expressions(module, offset);
    while (stack.count > 0) {
        var e = stack.pop();
        if (!contains(e.extent(), offset)) {
            continue;
        }
        if (e is FunctionCall(function, arguments, span)) {
            if (function.span().end < offset
                and offset < span.end
                and (found.is_empty() or found_start <= span.start)) {
                found = Optional<(Expression, Expression[])>.Value((function, arguments));
                found_start = span.start;
            }
        }
        stack.append_all(children(e));
    }
    return found;
}

# The struct or enum named `name`: the document's, else one another file
# of the program declares.
_struct_named(module: Module, program: link.Program?, name: String): StructDecl? {
    for (var declaration in module.declarations) {
        if (declaration is Struct(s)) {
            if (s.name == name) {
                return Optional<StructDecl>.Value(s);
            }
        }
    }
    if (program is Value(p)) {
        for (var f in p.files) {
            for (var declaration in f.module.declarations) {
                if (declaration is Struct(s)) {
                    if (link.demangle_name(s.name) == name) {
                        return Optional<StructDecl>.Value(s);
                    }
                }
            }
        }
    }
    return Optional<StructDecl>.Empty;
}

# The program to look in for other files' declarations: the last
# analysis's, else the last passed one's.
_program(latest: Analysis?, ready: Analysis?): link.Program? {
    if (latest is Value(l)) {
        if (l.program.is_value()) {
            return l.program;
        }
    }
    if (ready is Value(r)) {
        return r.program;
    }
    return Optional<link.Program>.Empty;
}

# The document's syntax tree while a name is typed: `Color.` and `f(a, `
# do not parse until the name is written, so a placeholder stands in.
_parse_while_typing(text: String, offset: ulong): Module? {
    var parsed = parse.parse(text);
    if (parsed.is_ok()) {
        return Optional<Module>.Value(parsed.value());
    }
    if (offset > text.size) {
        return Optional<Module>.Empty;
    }
    var placeheld = text.substr_bytes(0, offset) + "_" + text.substr_bytes(offset, text.size - offset);
    parsed = parse.parse(placeheld);
    if (parsed.is_err()) {
        return Optional<Module>.Empty;
    }
    return Optional<Module>.Value(parsed.value());
}

# Adds the keywords to `items`; returns them.
_keywords(items: lsp.CompletionItem[]): lsp.CompletionItem[] {
    for (var keyword in KEYWORDS.split(" ")) {
        items.append(lsp.CompletionItem(keyword, lsp.COMPLETION_KEYWORD));
    }
    return items;
}

# The completion kind for a symbol of type or signature `type_text`.
_kind(type_text: String): int {
    if (type_text.contains("(")) {
        return lsp.COMPLETION_FUNCTION;
    }
    if (type_text.starts_with("enum")) {
        return lsp.COMPLETION_ENUM;
    }
    if (type_text.starts_with("struct")) {
        return lsp.COMPLETION_STRUCT;
    }
    return lsp.COMPLETION_VARIABLE;
}

# A type's name without its generic arguments, pointer stars or array
# brackets: `Window` of `Window<int>*`.
_base_name(type_text: String): String {
    var angle = type_text.find("<");
    var name = angle < 0 ? type_text : type_text.substr_bytes(0, angle as ulong);
    var end = name.size;
    while (end > 0 and !_is_name_byte(name.byte_at(end - 1))) {
        end -= 1;
    }
    return name.substr_bytes(0, end);
}

# Where the name that ends at `end` of `text` starts.
_name_start(text: String, end: ulong): ulong {
    var start = end;
    while (start > 0 and _is_name_byte(text.byte_at(start - 1))) {
        start -= 1;
    }
    return start;
}

_is_name_byte(b: u8): bool {
    return (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or _is_digit(b) or b == '_';
}

_is_digit(b: u8): bool {
    return b >= '0' and b <= '9';
}

_is_space(b: u8): bool {
    return b == ' ' or b == '\t' or b == '\n' or b == '\r';
}
