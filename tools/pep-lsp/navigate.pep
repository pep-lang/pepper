# Hover and go-to-definition: what the name at an offset of a document is,
# and where it is declared. Each answer starts from the syntax tree of the
# document's current text (`scope.pep`); names reached through imports
# follow what linking recorded (`imports.pep`), and members of a value
# follow the type sema gave it (`compiler.sema`'s `member_at`), when the
# document's last analysis is of the same text.

import compiler.ast;
import [Declaration, Expression, FunctionDecl, Module, Span, StructDecl] from compiler.ast;
import [built_in_name, doc_comment_before, doc_comment_of, first_attribute, DocComment] from compiler.doc;
import compiler.link;
import lsp;
import compiler.sema;
import "hints";
import "imports";
import "infer";
import "scope";
import "symbols";
import "written";

## Separates a hover's signature from the doc comment after it.
export const DOC_SEPARATOR = "\n\n---\n\n";

## What an answer is computed from: the document and, when its last
## analysis is of the same text, the program it loaded and the model sema
## checked.
export struct Context {
    ## The document.
    var document: lsp.TextDocument;
    ## The syntax tree of its text.
    var module: Module;
    ## The program rooted at it, when it loaded.
    var program: link.Program?;
    ## The checked model, when the program passed sema.
    var model: sema.Module?;
    ## What sema's passes recorded, with `model`.
    var state: sema.PassState?;

    ## Creates a context with no program.
    ##
    ## @param document the document
    ## @param module the syntax tree of its text
    construct(document: lsp.TextDocument, module: Module) {
        this.document = document;
        this.module = module;
        this.program = Optional<link.Program>.Empty;
        this.model = Optional<sema.Module>.Empty;
        this.state = Optional<sema.PassState>.Empty;
    }

    # The source of program file `file`: the document's text for file 0.
    _source(file: ulong): String? {
        if (file == 0) {
            return Optional<String>.Value(document.text);
        }
        if (program is Value(p)) {
            if (file < p.files.count) {
                return Optional<String>.Value(p.files[file].source);
            }
        }
        return Optional<String>.Empty;
    }

    # The syntax tree of program file `file`: the document's own parse for
    # file 0, whose names linking did not rewrite.
    _module(file: ulong): Module? {
        if (file == 0) {
            return Optional<Module>.Value(module);
        }
        if (program is Value(p)) {
            if (file < p.files.count) {
                return Optional<Module>.Value(p.files[file].module);
            }
        }
        return Optional<Module>.Empty;
    }

    # How many files there are to search: the program's, or the document.
    _file_count(): ulong {
        return program.is_value() ? program.value().files.count : 1;
    }

    # Where `span` of program file `file` is.
    _location(file: ulong, span: Span): lsp.Location? {
        if (file == 0) {
            return Optional<lsp.Location>.Value(lsp.Location(document.uri, document.range_of(span.start, span.end)));
        }
        if (program is Value(p)) {
            if (file < p.files.count) {
                var f = p.files[file];
                var other = lsp.TextDocument(lsp.path_to_uri(f.name), f.source);
                return Optional<lsp.Location>.Value(lsp.Location(other.uri, other.range_of(span.start, span.end)));
            }
        }
        return Optional<lsp.Location>.Empty;
    }

    # The overload a call or function value of the document resolved to,
    # when the name at `offset` names an overload set: the chosen member,
    # and how many other members its set has.
    _overload(offset: ulong): (sema.FunctionDef, ulong)? {
        var none = Optional<(sema.FunctionDef, ulong)>.Empty;
        if (model.is_empty()) {
            return none;
        }
        var m = model.value();
        var callee = Optional<String>.Empty;
        ulong narrowest = 0;
        for (var (loc, name) in m.call_targets) {
            if (loc.file != 0 or loc.span.start > offset or offset > loc.span.end) {
                continue;
            }
            var width = loc.span.end - loc.span.start;
            if (callee.is_empty() or width < narrowest) {
                callee = Optional<String>.Value(name);
                narrowest = width;
            }
        }
        if (callee.is_empty()) {
            return none;
        }
        var target = callee.value();
        # A method is `Struct.member` (`Point.move$2`).
        var dot = target.rfind(".");
        if (dot >= 0) {
            var owner = target.substr_bytes(0, dot as ulong);
            var method = target.substr_bytes(dot as ulong + 1, target.size - dot as ulong - 1);
            for (var st in m.structs) {
                if (st.ty.to_string() != owner) {
                    continue;
                }
                var set = sema.set_name(method);
                var found = Optional<sema.FunctionDef>.Empty;
                ulong members = 0;
                for (var f in st.method_members) {
                    if (f.name == method) {
                        found = Optional<sema.FunctionDef>.Value(f);
                    }
                    if (sema.set_name(f.name) == set) {
                        members += 1;
                    }
                }
                if (found is Value(f)) {
                    return Optional<(sema.FunctionDef, ulong)>.Value((f, members - 1));
                }
                return none;
            }
            return none;
        }
        # A generic member's call names its specialization (`f$2<int>`).
        var angle = target.find("<");
        var member = angle < 0 ? target : target.substr_bytes(0, angle as ulong);
        for (var f in m.functions) {
            if (f.name != member) {
                continue;
            }
            ulong others = 0;
            for (var (_, members) in m.overload_sets) {
                if (members.contains(member)) {
                    others = members.count - 1;
                }
            }
            return Optional<(sema.FunctionDef, ulong)>.Value((f, others));
        }
        return none;
    }

    # The member sema found at `offset`: the field or method the owner's
    # type declares.
    _member(offset: ulong): sema.FoundMember? {
        if (model.is_empty() or state.is_empty()) {
            return Optional<sema.FoundMember>.Empty;
        }
        return sema.member_at(model.value(), state.value(), 0, document.text, offset);
    }
}

## The hover at `offset` of the context's document: what the name there
## is (a type, a signature, a value's type), with its doc comment.
##
## @param context the document and its analysis
## @param offset the byte offset
## @returns the hover; empty when nothing is named there
export hover_at(context: Context, offset: ulong): lsp.Hover? {
    var text = _hover_text(context, offset);
    var value = text.is_value() ? _spelled_as_written(context, text.value()) : "";
    # A value an `[Implicit]` constructor converts says so below.
    if (context.model is Value(model)) {
        var conversion = conversion_at(model, offset);
        if (conversion is Value(c)) {
            value = value == "" ? conversion_note(c) : value + DOC_SEPARATOR + conversion_note(c);
        }
    }
    if (value == "") {
        return Optional<lsp.Hover>.Empty;
    }
    return Optional<lsp.Hover>.Value(lsp.Hover(lsp.MarkupContent(lsp.MARKDOWN, value)));
}

# `text` with the names linking mangled (`Path@io/path`) spelled as
# written. Only the part before a doc comment is rewritten, and only with
# the program's own namespaces, longest first so one never cuts another.
_spelled_as_written(context: Context, text: String): String {
    if (context.program.is_empty()) {
        return text;
    }
    var namespaces = Array<String>();
    for (var file in context.program.value().files) {
        if (!file.namespace.is_empty) {
            namespaces.append(file.namespace);
        }
    }
    namespaces.sort((a: String, b: String) => b.size as int - a.size as int);
    var split = text.find(DOC_SEPARATOR);
    var head = split < 0 ? text : text.substr_bytes(0, split as ulong);
    var rest = split < 0 ? "" : text.substr_bytes(split as ulong, text.size - split as ulong);
    for (var namespace in namespaces) {
        head = head.replace("@" + namespace, "");
    }
    return head + rest;
}

_hover_text(context: Context, offset: ulong): String? {
    var none = Optional<String>.Empty;
    var module = context.module;
    if (context.program is Value(program)) {
        var found = in_imports(program, module, offset);
        if (found.is_empty()) {
            found = named_type(program, module, offset);
        }
        if (found is Value(name)) {
            return _target_hover(context, name);
        }
        # A use of a compiler built-in, which its `[__BuiltIn]` declaration
        # in the runtime documents (`reflect.name<T>()`).
        var built_in = _built_in_at(context, program, offset);
        if (built_in is Value(name)) {
            return _target_hover(context, name);
        }
    }
    # An enum's case (`Color.Red`), with its value or the values it
    # carries; its constructor is no overload to show.
    var case = _case_access_at(context, offset);
    if (case is Value((name, shown))) {
        return Optional<String>.Value(_head("." + name, shown));
    }
    # A name that resolved to one overload of a set shows that member.
    var chosen = context._overload(offset);
    if (chosen is Value((function, others))) {
        return Optional<String>.Value(_method_hover(context, function, others));
    }
    # A built-in type (`int`, `u8`), which no file declares.
    var written = type_at(module, offset);
    if (written is Value(t)) {
        var base = base_type_name(t.name);
        if (sema.is_integral_name(base)) {
            return Optional<String>.Value($"`{base}` — built-in type");
        }
        # A generic parameter used as a type.
        var generic = generic_param_at(module, offset, (p: ast.GenericParam) => p.name == base);
        if (generic is Value(symbol)) {
            return Optional<String>.Value(_head(symbol.name, symbol.type_text));
        }
    }
    var text = context.document.text;
    var typer = Typer(module, context.program, context.model);
    # A case a pattern names, or a name it binds.
    var hit = typer.pattern_at(offset);
    if (hit is Value(h)) {
        match (h) {
            Case(found) => {
                return Optional<String>.Value(_typed_hover(context, found));
            }
            Binding(name, _, ty) => {
                return Optional<String>.Value(_head(name, _ty_text(ty)));
            }
        }
    }
    # A tuple's label where it is written.
    var label = label_at(module, text, offset);
    if (label is Value(l)) {
        var ty = l.ty;
        if (l.value is Value(value)) {
            ty = typer.type_of(value, offset);
        }
        return Optional<String>.Value(_head(l.name, _ty_text(ty)));
    }
    var declared = declared_at(module, offset);
    if (declared is Value(d)) {
        var doc = d.owner.is_value() ?
            _member_doc(context, d.owner, d.symbol.name) :
            _declaration_doc_at(context, 0, d.symbol.name_span);
        var shown = _symbol_type(context, d.symbol);
        if (shown == "unknown") {
            shown = _ty_text(typer.local_type_of(d.symbol));
        }
        return Optional<String>.Value(with_doc(_head(d.symbol.name, shown), doc));
    }
    # A type argument in a member's name (`T` of `copies.copy<T>(x)`).
    var argument = type_argument_at(module, text, offset);
    if (argument is Value(name)) {
        var generic = generic_param_at(module, offset, (p: ast.GenericParam) => p.name == name);
        if (generic is Value(symbol)) {
            return Optional<String>.Value(_head(symbol.name, symbol.type_text));
        }
        if (context.program is Value(program)) {
            var target = declaration_named(program, name);
            if (target is Value(t)) {
                return _target_hover(context, Found(name, t));
            }
        }
    }
    # `String.format(...)`, which the parser lowers.
    var lowered = string_format_at(text, offset);
    if (lowered is Value(name)) {
        if (!names_at(module, offset)) {
            if (name == "format") {
                return Optional<String>.Value(FORMAT_HOVER);
            }
            if (context.program is Value(program)) {
                var target = declaration_named(program, "String");
                if (target is Value(t)) {
                    return _target_hover(context, Found("String", t));
                }
            }
        }
    }
    var found_expression = find_expression(module, offset);
    if (found_expression.is_empty()) {
        return none;
    }
    var e = found_expression.value();
    var names = _Names(module, offset, typer);
    if (context.program is Value(program)) {
        var bare_member = context._member(offset).is_value();
        var imported = in_expression(program, module, e, (id: String) => bare_member or names.is_local(id));
        if (imported is Value(name)) {
            return _target_hover(context, name);
        }
    }
    match (e) {
        Literal(value, _) => {
            return Optional<String>.Value(_head(value.to_string(), literal_type(value)));
        }
        SymbolRef(id, _) => {
            return Optional<String>.Value(_symbol_hover(context, names, id, offset));
        }
        MemberAccess(lhs, name, _, _) => {
            return Optional<String>.Value(_member_hover(context, names, lhs, name, offset));
        }
        FunctionCall(function, _, _) => {
            if (function is SymbolRef(id, _)) {
                return Optional<String>.Value(_symbol_hover(context, names, id, offset));
            }
            if (function is MemberAccess(lhs, name, _, _)) {
                return Optional<String>.Value(_member_hover(context, names, lhs, name, offset));
            }
        }
        else => {}
    }
    return none;
}

# What hover shows for the bare name `id` used at `offset`: a local's,
# member's or declaration's type, or the member of `this` sema found.
_symbol_hover(context: Context, names: _Names, id: String, offset: ulong): String {
    var local = names.local(id);
    if (local is Value(symbol)) {
        var shown = _symbol_type(context, symbol);
        if (shown == "unknown") {
            shown = _ty_text(names.typer.symbol_type(id, offset));
        }
        return _head(id, shown);
    }
    var member = names.member(id);
    if (member is Value(symbol)) {
        var owner = names.owner_name();
        return with_doc(_head(id, symbol.type_text), _member_doc(context, owner, id));
    }
    # A bare member of `this` the document cannot see (in an extension's
    # method), by the type sema gave `this`.
    var found = context._member(offset);
    if (found is Value(m)) {
        return _sema_member_hover(context, m, id, extended_at(context.module, offset));
    }
    var global = names.global(id);
    if (global is Value(symbol)) {
        var head = _head(id, _symbol_type(context, symbol)) + _fresh_note(context, id);
        return with_doc(head, _declaration_doc_at(context, 0, symbol.name_span));
    }
    # A method of `this` sema did not check (in generic code).
    var bare = names.typer.bare_member(id, offset);
    if (bare is Value(typed)) {
        return _typed_hover(context, typed);
    }
    if (id == "print") {
        return "`print` — built-in function\n\nPrints each argument on a line of its own.";
    }
    return _head(id, _ty_text(names.typer.symbol_type(id, offset)));
}

# The note under a function whose result shares nothing with its inputs,
# which may cross a lock or go to a `[Move]` parameter.
_fresh_note(context: Context, id: String): String {
    if (context.model is Value(model)) {
        var fresh = sema.returns_fresh(model, link.Target(), id);
        if (fresh is Value(yes)) {
            if (yes) {
                return "\n\nReturns a fresh value: it shares nothing with the arguments.";
            }
        }
    }
    return "";
}

# What hover shows for `.name` of `lhs`: the method or field the owner's
# type has, as sema found it, else the member of the struct around it.
_member_hover(context: Context, names: _Names, lhs: Expression, name: String, offset: ulong): String {
    var found = context._member(offset);
    if (found is Value(m)) {
        return _sema_member_hover(context, m, "." + name, Optional<String>.Empty);
    }
    # `this.name` in a struct's own code.
    if (lhs is SymbolRef(id, _)) {
        if (id == "this") {
            var member = names.member(name);
            if (member is Value(symbol)) {
                return with_doc(_head("." + name, symbol.type_text), _member_doc(context, names.owner_name(), name));
            }
        }
    }
    # The member as the syntax types the owner (in generic code sema did
    # not check, or a static call).
    var typed = names.typer.member_access(lhs, name, offset);
    if (typed is Value(t)) {
        return _typed_hover(context, t);
    }
    return _head("." + name, "unknown");
}

# What hover shows for a member sema found: a method's signature as its
# file declares it, or a field's type, each with its doc comment.
_sema_member_hover(context: Context, member: sema.FoundMember, spelled: String, owner: String?): String {
    match (member) {
        Method(method) => {
            return _method_hover(context, method);
        }
        Field(field) => {
            var doc = _doc_before_name(context, field.loc.file as ulong, field.loc.span);
            return with_doc(_head(spelled, field.ty.to_string()), doc);
        }
    }
    return _head(spelled, "unknown");
}

# A method's hover: its name, its signature as declared (parameter names
# included), and its doc comment.
_method_hover(context: Context, method: sema.FunctionDef, others: ulong = 0): String {
    var name = link.demangle_name(method.name);
    var more = others == 0 ? "" : (others == 1 ? " (+1 overload)" : $" (+{others} overloads)");
    var file = method.loc.file as ulong;
    var declared = _function_declared(context, file, method.loc.span);
    if (declared is Value(f)) {
        var source = context._source(file).value();
        var start = first_attribute(f.attributes, f.span.start < f.name_span.start ? f.span.start : f.name_span.start);
        var comment = doc_comment_before(source, start);
        var doc = _markdown(comment);
        return with_doc(_head(name, function_signature(f)) + more, doc);
    }
    return _head(name, method.ty.to_string()) + more;
}

# The function, method or constructor of program file `file` whose name is
# at `name_span`.
_function_declared(context: Context, file: ulong, name_span: Span): FunctionDecl? {
    var module = context._module(file);
    if (module.is_empty()) {
        return Optional<FunctionDecl>.Empty;
    }
    for (var declaration in module.value().declarations) {
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
            if (f.name_span.start == name_span.start and f.name_span.end == name_span.end) {
                return Optional<FunctionDecl>.Value(f);
            }
        }
    }
    return Optional<FunctionDecl>.Empty;
}

# The hover for a name reached through an import: the declaration's type
# and the file it is from, with its doc comment, or the file itself.
_target_hover(context: Context, found: Found): String? {
    var target = found.target;
    var from = target.file == 0 ? "" : $"\n\nfrom `{_file_label(context, target.file)}`";
    if (target.symbol is Value(symbol)) {
        var doc = _declaration_doc_at(context, target.file, symbol.name_span);
        return Optional<String>.Value(with_doc(_head(found.spelled, symbol.type_text) + from, doc));
    }
    return Optional<String>.Value(_head(found.spelled, _file_label(context, target.file)));
}

# A program file's path as hovers show it: its folder and file name
# (`geo/module.pep`), which name a module file and its module.
_file_label(context: Context, file: ulong): String {
    if (file == 0 or context.program.is_empty()) {
        return "";
    }
    var name = context.program.value().files[file].name.replace("\\", "/");
    var slash = name.rfind("/");
    if (slash <= 0) {
        return name;
    }
    var folder = name.substr_bytes(0, slash as ulong).rfind("/");
    var start = folder < 0 ? 0 : folder as ulong + 1;
    return name.substr_bytes(start, name.size - start);
}

## The go-to-definition at `offset` of the context's document: where the
## name there is declared.
##
## @param context the document and its analysis
## @param offset the byte offset
## @returns the declaration's locations; empty when nothing is named there
export definition_at(context: Context, offset: ulong): lsp.Location[] {
    var out = Array<lsp.Location>();
    var found = _definition(context, offset);
    if (found is Value(location)) {
        out.append(location);
    }
    return out;
}

_definition(context: Context, offset: ulong): lsp.Location? {
    var none = Optional<lsp.Location>.Empty;
    var module = context.module;
    if (context.program is Value(program)) {
        var found = in_imports(program, module, offset);
        if (found.is_empty()) {
            found = named_type(program, module, offset);
        }
        if (found is Value(name)) {
            return _target_location(context, name.target);
        }
        var built_in = _built_in_at(context, program, offset);
        if (built_in is Value(name)) {
            return _target_location(context, name.target);
        }
    }
    # A name that resolved to one overload of a set goes to that member.
    var chosen = context._overload(offset);
    if (chosen is Value((function, _))) {
        return context._location(function.loc.file as ulong, function.loc.span);
    }
    var text = context.document.text;
    var typer = Typer(module, context.program, context.model);
    # A case a pattern names goes to the case; a name it binds, to itself.
    var hit = typer.pattern_at(offset);
    if (hit is Value(h)) {
        match (h) {
            Case(found) => {
                return _typed_location(context, found);
            }
            Binding(_, span, _) => {
                return context._location(0, span);
            }
        }
    }
    # `String.format(...)`, which the parser lowers: both names go to
    # `String`.
    if (string_format_at(text, offset).is_value() and !names_at(module, offset)) {
        if (context.program is Value(program)) {
            var target = declaration_named(program, "String");
            if (target is Value(t)) {
                return _target_location(context, t);
            }
        }
    }
    # A tuple's label where it is written.
    var label = label_at(module, text, offset);
    if (label is Value(l)) {
        return context._location(0, l.span);
    }
    # A type argument in a member's name (`T` of `copies.copy<T>(x)`).
    var argument = type_argument_at(module, text, offset);
    if (argument is Value(name)) {
        var generic = generic_param_at(module, offset, (p: ast.GenericParam) => p.name == name);
        if (generic is Value(symbol)) {
            return context._location(0, symbol.name_span);
        }
        if (context.program is Value(program)) {
            var target = declaration_named(program, name);
            if (target is Value(t)) {
                return _target_location(context, t);
            }
        }
    }
    # A name where it is declared goes to itself.
    var declared = declared_at(module, offset);
    if (declared is Value(d)) {
        return context._location(0, d.symbol.name_span);
    }
    # A generic parameter used as a type goes to the parameter.
    var written = type_at(module, offset);
    if (written is Value(t)) {
        var base = base_type_name(t.name);
        var generic = generic_param_at(module, offset, (p: ast.GenericParam) => p.name == base);
        if (generic is Value(symbol)) {
            return context._location(0, symbol.name_span);
        }
    }
    # A member of any expression (`x.y.z`, `f().m()`), by its owner's type
    # in the sema model.
    var member = context._member(offset);
    if (member is Value(m)) {
        var loc = sema.member_loc(m);
        return context._location(loc.file as ulong, loc.span);
    }
    var found_expression = find_expression(module, offset);
    if (found_expression.is_empty()) {
        return none;
    }
    var e = found_expression.value();
    var names = _Names(module, offset, typer);
    if (context.program is Value(program)) {
        var imported = in_expression(program, module, e, (id: String) => names.is_local(id));
        if (imported is Value(name)) {
            return _target_location(context, name.target);
        }
    }
    # An enum's case (`Backend.Automatic`), declared in any file.
    if (e is MemberAccess(lhs, name, name_span, _)) {
        if (name_span.start <= offset) {
            var enum_name = _enum_named(lhs);
            if (enum_name is Value(owner)) {
                var case = _enum_case_declared(context, owner, name);
                if (case.is_value()) {
                    return case;
                }
            }
        }
    }
    match (e) {
        SymbolRef(id, _) => {
            var symbol = names.any(id);
            if (symbol is Value(s)) {
                return context._location(0, s.name_span);
            }
        }
        FunctionCall(function, _, _) => {
            if (function is SymbolRef(id, _)) {
                var symbol = names.any(id);
                if (symbol is Value(s)) {
                    return context._location(0, s.name_span);
                }
            }
        }
        MemberAccess(lhs, name, _, _) => {
            if (lhs is SymbolRef(id, _)) {
                if (id == "this") {
                    var symbol = names.member(name);
                    if (symbol is Value(s)) {
                        return context._location(0, s.name_span);
                    }
                }
            }
        }
        else => {}
    }
    # What the syntax finds where sema has no answer: a member of an owner
    # it types (in generic code sema did not check, or a static call), or a
    # member of `this` named bare.
    var typed = Optional<TypedMember>.Empty;
    match (e) {
        SymbolRef(id, _) => {
            typed = typer.bare_member(id, offset);
        }
        MemberAccess(lhs, name, name_span, _) => {
            if (name_span.start <= offset) {
                typed = typer.member_access(lhs, name, offset);
            }
        }
        FunctionCall(function, _, _) => {
            if (function is MemberAccess(lhs, name, name_span, _)) {
                if (name_span.start <= offset) {
                    typed = typer.member_access(lhs, name, offset);
                }
            }
        }
        else => {}
    }
    if (typed is Value(t)) {
        # A tuple's label: where the document writes a tuple type or value
        # with the owner's labels.
        if (t.kind is Element(label, _)) {
            var labels = typer.member_owner_labels(e, offset);
            if (labels.is_empty()) {
                return none;
            }
            var span = label_declared(module, text, labels.value(), label);
            return span.is_value() ? context._location(0, span.value()) : none;
        }
        return _typed_location(context, t);
    }
    return none;
}

# Where a name reached through an import leads: its declaration, or the
# start of the file.
_target_location(context: Context, target: Target): lsp.Location? {
    var span = target.symbol.is_value() ? target.symbol.value().name_span : Span(0, 0);
    return context._location(target.file, span);
}

# The names in scope at an offset of a document: locals and parameters,
# the members of the struct around it, and its top-level declarations.
struct _Names {
    var locals: Symbol[];
    var members: Symbol[];
    var globals: Symbol[];
    var owner: StructDecl?;
    # The syntax's typing, where sema has no answer.
    var typer: Typer;

    construct(module: Module, offset: ulong, typer: Typer) {
        this.typer = typer;
        this.locals = scope_locals(module, offset);
        this.globals = collect_globals(module);
        this.members = Array<Symbol>();
        this.owner = Optional<StructDecl>.Empty;
        var enclosing = body_at(module, offset);
        if (enclosing is Value(found)) {
            this.owner = found.owner;
            if (found.owner is Value(s)) {
                this.members = collect_struct_members(s);
            }
        }
    }

    # Whether a local, parameter or member binds `id` here.
    is_local(id: String): bool {
        return local(id).is_value() or member(id).is_value() or global(id).is_value();
    }

    # The innermost local or parameter named `id`.
    local(id: String): Symbol? {
        long i = locals.count as long - 1;
        while (i >= 0) {
            if (locals[i as ulong].name == id) {
                return Optional<Symbol>.Value(locals[i as ulong]);
            }
            i -= 1;
        }
        return Optional<Symbol>.Empty;
    }

    # The member of the struct around the offset named `id`.
    member(id: String): Symbol? {
        return _named(members, id);
    }

    # The document's top-level declaration named `id`.
    global(id: String): Symbol? {
        return _named(globals, id);
    }

    # What `id` names here: a local, else a member, else a declaration.
    any(id: String): Symbol? {
        var found = local(id);
        if (found.is_empty()) {
            found = member(id);
        }
        if (found.is_empty()) {
            found = global(id);
        }
        return found;
    }

    # The struct around the offset, by name.
    owner_name(): String? {
        if (owner is Value(s)) {
            return Optional<String>.Value(s.name);
        }
        return Optional<String>.Empty;
    }

    _named(symbols: Symbol[], id: String): Symbol? {
        for (var symbol in symbols) {
            if (symbol.name == id) {
                return Optional<Symbol>.Value(symbol);
            }
        }
        return Optional<Symbol>.Empty;
    }
}

# `name — type`, as a hover's first line shows a declaration.
_head(name: String, type_text: String): String {
    return $"`{name}` — `{type_text}`";
}

## `value` followed by `doc`, the Markdown of a declaration's doc comment.
##
## @param value the hover's first line
## @param doc the doc comment, if any
## @returns the hover's text
export with_doc(value: String, doc: String?): String {
    if (doc is Value(text)) {
        if (!text.is_empty) {
            return value + DOC_SEPARATOR + text;
        }
    }
    return value;
}

# A symbol's type: as written, or as sema inferred it for a local
# (`var worker = _async_worker()`); `unknown` when neither says.
_symbol_type(context: Context, symbol: Symbol): String {
    if (!symbol.type_text.is_empty and symbol.type_text != "unknown") {
        return symbol.type_text;
    }
    if (context.model is Value(model)) {
        var inferred = sema.local_type(model, 0, symbol.name_span.start);
        if (inferred is Value(t)) {
            return t.to_string();
        }
    }
    return "unknown";
}

# The doc comment of the top-level declaration of program file `file`
# whose name is at `name_span`, as Markdown.
_declaration_doc_at(context: Context, file: ulong, name_span: Span): String? {
    var module = context._module(file);
    var source = context._source(file);
    if (module.is_empty() or source.is_empty()) {
        return Optional<String>.Empty;
    }
    for (var declaration in module.value().declarations) {
        var span = declaration.name_span();
        if (span.start != name_span.start or span.end != name_span.end) {
            continue;
        }
        var comment = doc_comment_of(source.value(), declaration);
        return _markdown(comment);
    }
    return Optional<String>.Empty;
}

# The doc comment of the member whose name is at `name_span` in program
# file `file`: a field, a case or a method of any type there.
_doc_before_name(context: Context, file: ulong, name_span: Span): String? {
    var module = context._module(file);
    var source = context._source(file);
    if (module.is_empty() or source.is_empty()) {
        return Optional<String>.Empty;
    }
    for (var declaration in module.value().declarations) {
        var start = _member_start(
            declaration, (member: String, span: Span) => span.start == name_span.start and span.end == name_span.end
        );
        if (start is Value(at)) {
            var comment = doc_comment_before(source.value(), at);
            return _markdown(comment);
        }
    }
    return Optional<String>.Empty;
}

# The doc comment of member `name` of the struct, trait or extension of
# `owner`, as Markdown. With no owner, only a member name that one type
# alone declares has a doc to show.
_member_doc(context: Context, owner: String?, name: String): String? {
    var none = Optional<String>.Empty;
    var found = Optional<(ulong, ulong)>.Empty;
    ulong count = 0;
    ulong file = 0;
    while (file < context._file_count()) {
        var module = context._module(file).value();
        for (var declaration in module.declarations) {
            var type_name = _owner_name(declaration);
            if (type_name.is_empty()) {
                continue;
            }
            if (owner is Value(wanted)) {
                if (link.demangle_name(type_name.value()) != wanted) {
                    continue;
                }
            }
            var start = _member_named(declaration, name);
            if (start is Value(at)) {
                found = Optional<(ulong, ulong)>.Value((file, at));
                count += 1;
            }
        }
        # The document's own type comes first and hides another file's.
        if (file == 0 and owner.is_value() and count > 0) {
            break;
        }
        file += 1;
    }
    if (count != 1) {
        return none;
    }
    var (in_file, start) = found.value();
    var comment = doc_comment_before(context._source(in_file).value(), start);
    return _markdown(comment);
}

# The type a declaration declares members of.
_owner_name(declaration: Declaration): String? {
    match (declaration) {
        Struct(s) => {
            return Optional<String>.Value(s.name);
        }
        Trait(t) => {
            return Optional<String>.Value(t.name);
        }
        Extend(e) => {
            return Optional<String>.Value(e.target.name);
        }
        else => {}
    }
    return Optional<String>.Empty;
}

# Where the text of member `name` of `declaration` starts, attributes
# included.
_member_named(declaration: Declaration, name: String): ulong? {
    return _member_start(declaration, (member: String, span: Span) => member == name);
}

# Where the text of the member of `declaration` that `wanted` picks (by its
# name and where the name is) starts, attributes included.
_member_start(declaration: Declaration, wanted: (String, Span) => bool): ulong? {
    match (declaration) {
        Struct(s) => {
            for (var field in s.fields) {
                if (wanted(field.name, field.name_span)) {
                    return Optional<ulong>.Value(first_attribute(field.attributes, field.span.start));
                }
            }
            if (s.enumeration is Value(body)) {
                for (var case in body.cases) {
                    if (wanted(case.name, case.name_span)) {
                        return Optional<ulong>.Value(first_attribute(case.attributes, case.span.start));
                    }
                }
            }
            return _method_start(s.methods, wanted);
        }
        Trait(t) => {
            return _method_start(t.methods, wanted);
        }
        Extend(e) => {
            return _method_start(e.methods, wanted);
        }
        else => {}
    }
    return Optional<ulong>.Empty;
}

_method_start(methods: FunctionDecl[], wanted: (String, Span) => bool): ulong? {
    for (var m in methods) {
        if (wanted(m.name, m.name_span)) {
            var start = m.span.start < m.name_span.start ? m.span.start : m.name_span.start;
            return Optional<ulong>.Value(first_attribute(m.attributes, start));
        }
    }
    return Optional<ulong>.Empty;
}

# A doc comment as Markdown.
_markdown(comment: DocComment?): String? {
    if (comment is Value(c)) {
        return Optional<String>.Value(c.to_markdown());
    }
    return Optional<String>.Empty;
}

# The compiler built-in used at `offset` (`reflect.properties`, `__null`,
# `sizeof`), and its `[__BuiltIn]` declaration in the program.
_built_in_at(context: Context, program: link.Program, offset: ulong): Found? {
    var none = Optional<Found>.Empty;
    var spelled = _built_in_spelled(context, offset);
    if (spelled.is_empty()) {
        return none;
    }
    var name = spelled.value();
    ulong file = 0;
    while (file < program.files.count) {
        var module = program.files[file].module;
        for (var declaration in module.declarations) {
            var built_in = built_in_name(declaration.attributes(), declaration.declared_name());
            if (built_in.is_empty() or built_in.value() != name) {
                continue;
            }
            for (var symbol in collect_globals(module)) {
                if (symbol.name_span == declaration.name_span()) {
                    return Optional<Found>.Value(Found(name, Target(file, Optional<Symbol>.Value(symbol))));
                }
            }
        }
        file += 1;
    }
    return none;
}

# How the source spells the name at `offset` as a built-in would be named:
# `q.name` for a member of a name, a name, a type, `__null` for `null`.
_built_in_spelled(context: Context, offset: ulong): String? {
    var text = context.document.text;
    # `sizeof<T>()` spans only its type.
    var start = offset;
    while (start > 0 and _is_name_byte(text.byte_at(start - 1))) {
        start -= 1;
    }
    var end = offset;
    while (end < text.size and _is_name_byte(text.byte_at(end))) {
        end += 1;
    }
    if (text.substr_bytes(start, end - start) == "sizeof") {
        return Optional<String>.Value("sizeof");
    }
    var spelled = "";
    var found = find_expression(context.module, offset);
    if (found is Value(e)) {
        match (e) {
            MemberAccess(lhs, name, name_span, _) => {
                if (name_span.start > offset) {
                    return Optional<String>.Empty;
                }
                if (lhs is SymbolRef(id, _)) {
                    spelled = id + "." + name;
                } else {
                    return Optional<String>.Empty;
                }
            }
            SymbolRef(id, _) => {
                spelled = id;
            }
            TypeLiteral(t) => {
                spelled = t.name;
            }
            Literal(value, _) => {
                if (value is Null) {
                    spelled = "__null";
                }
            }
            else => {}
        }
    }
    if (spelled == "") {
        var written = type_at(context.module, offset);
        if (written.is_empty()) {
            return Optional<String>.Empty;
        }
        spelled = written.value().name;
    }
    var angle = spelled.find("<");
    return Optional<String>.Value(angle < 0 ? spelled : spelled.substr_bytes(0, angle as ulong));
}

_is_name_byte(b: u8): bool {
    return (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b == '_';
}

# The case at `offset` of `E.case`, and what hover shows for it.
_case_access_at(context: Context, offset: ulong): (String, String)? {
    var none = Optional<(String, String)>.Empty;
    var found = find_expression(context.module, offset);
    if (found.is_empty()) {
        return none;
    }
    if (found.value() is MemberAccess(lhs, name, name_span, _)) {
        if (!on_name(name_span, offset)) {
            return none;
        }
        var enum_name = _enum_named(lhs);
        if (enum_name.is_empty()) {
            return none;
        }
        var shown = Optional<String>.Empty;
        if (context.model is Value(model)) {
            shown = _enum_case_named(model, enum_name.value(), name);
        }
        if (shown.is_empty()) {
            shown = _enum_case_in(context.module, enum_name.value(), name);
        }
        if (shown is Value(text)) {
            return Optional<(String, String)>.Value((name, text));
        }
    }
    return none;
}

# The enum `lhs` names in `lhs.case`: `Color`, or `_IoWait` in
# `io._IoWait`, qualified by its module.
_enum_named(lhs: Expression): String? {
    match (lhs) {
        SymbolRef(id, _) => {
            return Optional<String>.Value(id);
        }
        MemberAccess(inner, name, _, _) => {
            if (inner is SymbolRef(_, _)) {
                return Optional<String>.Value(name);
            }
        }
        else => {}
    }
    return Optional<String>.Empty;
}

# What hover shows for case `name` of the enum named `id`, as sema has it:
# `Color.Red = 0`, or `Doc.Text(text: String)` for a case that carries
# values.
_enum_case_named(model: sema.Module, id: String, name: String): String? {
    var none = Optional<String>.Empty;
    var st = _sema_struct(model, id);
    if (st is Value(s)) {
        if (s.enum_cases is Value(cases)) {
            for (var case in cases) {
                if (case.name != name) {
                    continue;
                }
                if (case.payload.count == 0) {
                    return Optional<String>.Value($"{id}.{name}");
                }
                var values = Array<String>();
                for (var (value, _) in case.payload) {
                    var field = sema.payload_field(case.name, value);
                    var ty = "";
                    for (var f in s.field_members) {
                        if (f.name == field) {
                            ty = f.ty.display();
                        }
                    }
                    values.append($"{value}: {ty}");
                }
                var listed = ", ".join(values);
                return Optional<String>.Value($"{id}.{name}({listed})");
            }
            return none;
        }
    }
    var found = Optional<sema.EnumDef>.Empty;
    for (var e in model.enums) {
        if (e.loc.file == 0 and link.demangle_name(e.name) == id) {
            found = Optional<sema.EnumDef>.Value(e);
            break;
        }
    }
    if (found.is_empty()) {
        for (var e in model.enums) {
            if (e.name == id or link.demangle_name(e.name) == id) {
                found = Optional<sema.EnumDef>.Value(e);
                break;
            }
        }
    }
    if (found.is_empty()) {
        return none;
    }
    for (var case in found.value().cases) {
        if (case.name == name) {
            return Optional<String>.Value($"{id}.{name} = {case.value}");
        }
    }
    return none;
}

# Case `name` of the enum named `id` in the document alone, while the
# program does not build: `Color.Red`, without its value.
_enum_case_in(module: Module, id: String, name: String): String? {
    for (var declaration in module.declarations) {
        if (declaration is Struct(s)) {
            if (s.name != id or s.enumeration.is_empty()) {
                continue;
            }
            for (var case in s.enumeration.value().cases) {
                if (case.name != name) {
                    continue;
                }
                if (case.payload is Value(values)) {
                    var listed = Array<String>();
                    for (var v in values) {
                        listed.append($"{v.name}: {v.type_name.to_string()}");
                    }
                    var joined = ", ".join(listed);
                    return Optional<String>.Value($"{id}.{name}({joined})");
                }
                return Optional<String>.Value($"{id}.{name}");
            }
        }
    }
    return Optional<String>.Empty;
}

# The struct sema has for `name`: the document's, else one named so, else
# another file's export under its module's namespace.
_sema_struct(model: sema.Module, name: String): sema.StructDef? {
    for (var s in model.structs) {
        if (s.loc.file == 0 and link.demangle_name(s.name) == name) {
            return Optional<sema.StructDef>.Value(s);
        }
    }
    for (var s in model.structs) {
        if (s.name == name) {
            return Optional<sema.StructDef>.Value(s);
        }
    }
    for (var s in model.structs) {
        if (link.demangle_name(s.name) == name) {
            return Optional<sema.StructDef>.Value(s);
        }
    }
    return Optional<sema.StructDef>.Empty;
}

# The hover for `String.format`, which no file declares.
const FORMAT_HOVER = "`format` — `static format(format: String, values...): String`\n\nBuilt in: the format string with each `{index}` replaced by that value, formatted as in an interpolated string.";

# A type the syntax found, or `unknown`.
_ty_text(ty: Ty?): String {
    if (ty is Value(t)) {
        return t.to_string();
    }
    return "unknown";
}

# What hover shows for a member the syntax found: its name, what it is,
# and its doc comment.
_typed_hover(context: Context, found: TypedMember): String {
    var name = "";
    var start = Optional<ulong>.Empty;
    match (found.kind) {
        Field(v) => {
            name = "." + v.name;
            start = Optional<ulong>.Value(first_attribute(v.attributes, v.span.start));
        }
        Property(p) => {
            name = "." + p.name;
            start = Optional<ulong>.Value(first_attribute(p.attributes, p.span.start));
        }
        Method(f) => {
            name = link.demangle_name(f.name);
            var at = f.span.start < f.name_span.start ? f.span.start : f.name_span.start;
            start = Optional<ulong>.Value(first_attribute(f.attributes, at));
        }
        Case(c) => {
            name = c.name;
            start = Optional<ulong>.Value(c.span.start);
        }
        EnumMethod(_, method) => {
            name = method;
        }
        Element(label, _) => {
            return _head("." + label, found.describe());
        }
    }
    var doc = Optional<String>.Empty;
    var source = context._source(found.file);
    if (source.is_value() and start.is_value()) {
        doc = _markdown(doc_comment_before(source.value(), start.value()));
    }
    return with_doc(_head(name, found.describe()), doc);
}

# Where a member the syntax found is declared.
_typed_location(context: Context, found: TypedMember): lsp.Location? {
    var span = found.name_span();
    if (span.is_empty()) {
        return Optional<lsp.Location>.Empty;
    }
    return context._location(found.file, span.value());
}

# Where enum `owner`'s case `name` is declared, in any program file.
# Linking spells another module's declarations with its namespace
# (`Backend@async`).
_enum_case_declared(context: Context, owner: String, name: String): lsp.Location? {
    var none = Optional<lsp.Location>.Empty;
    if (context.program.is_empty()) {
        return none;
    }
    var program = context.program.value();
    ulong file = 0;
    while (file < program.files.count) {
        for (var declaration in program.files[file].module.declarations) {
            if (declaration is Struct(s)) {
                if (link.demangle_name(s.name) != owner or s.enumeration.is_empty()) {
                    continue;
                }
                for (var case in s.enumeration.value().cases) {
                    if (case.name == name) {
                        return context._location(file, case.name_span);
                    }
                }
            }
        }
        file += 1;
    }
    return none;
}
