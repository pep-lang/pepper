# Following names through imports: `q.x` after `import m as q`, `y` after
# `import [x as y] from m`, an unqualified export of `import "file"`, and
# the imports and re-exports themselves. Linking records what each such
# spelling denotes (`link.FileScope`); this file finds the spelling under
# the cursor and the declaration or file it leads to.

import compiler.ast;
import [Expression, Module, Span] from compiler.ast;
import compiler.link;
import "scope";

## Where a name reached through an import leads: a top-level declaration
## of a program file, or a file itself (`import "shapes"`, or a module,
## whose `module.pep` it is).
export struct Target {
    ## The program file.
    var file: ulong;
    ## The declaration; empty when the target is the file itself.
    var symbol: Symbol?;

    ## Creates a target.
    ##
    ## @param file the program file
    ## @param symbol the declaration in it, if any
    construct(file: ulong, symbol: Symbol? = Optional<Symbol>.Empty) {
        this.file = file;
        this.symbol = symbol;
    }
}

## A name under the cursor, as written, and where it leads.
export struct Found {
    ## The name as the document spells it.
    var spelled: String;
    ## Where it leads.
    var target: Target;

    ## Creates one.
    ##
    ## @param spelled the name as written
    ## @param target where it leads
    construct(spelled: String, target: Target) {
        this.spelled = spelled;
        this.target = target;
    }
}

## The top-level declaration `name` denotes, and the program file
## declaring it. The merged program keeps the first definition of a name,
## so the first file declaring it wins.
##
## @param program the loaded program
## @param name the declaration's name
## @returns where it is declared; empty when no file declares it
export declaration_named(program: link.Program, name: String): Target? {
    ulong file = 0;
    while (file < program.files.count) {
        for (var symbol in collect_globals(program.files[file].module)) {
            if (symbol.name == name) {
                return Optional<Target>.Value(Target(file, Optional<Symbol>.Value(symbol)));
            }
        }
        file += 1;
    }
    return Optional<Target>.Empty;
}

# The declaration `name` in the module the qualifier `q` imports, exported
# or not: the runtime's files reach each other's `_`-prefixed helpers
# (`io._IO_READABLE`).
_module_member(program: link.Program, document: Module, q: String, name: String): Target? {
    var imported = _qualifier_import(program, document, q);
    if (imported.is_empty()) {
        return imported;
    }
    var index = imported.value().file;
    var root = program.files[index].module_root;
    ulong file = 0;
    while (file < program.files.count) {
        var f = program.files[file];
        var same_module = root.is_value()
            and f.module_root.is_value()
            and f.module_root.value().to_string() == root.value().to_string();
        if (file == index or same_module) {
            for (var symbol in collect_globals(f.module)) {
                if (link.demangle_name(symbol.name) == name) {
                    return Optional<Target>.Value(Target(file, Optional<Symbol>.Value(symbol)));
                }
            }
        }
        file += 1;
    }
    return Optional<Target>.Empty;
}

# The file the document's (`program.files[0]`) import `index` resolved to.
_imported_file(program: link.Program, index: ulong): Target? {
    var imports = program.files[0].imports;
    if (index >= imports.count or imports[index].is_empty()) {
        return Optional<Target>.Empty;
    }
    return Optional<Target>.Value(Target(imports[index].value()));
}

# The import of the document that binds the qualifier `q`.
_qualifier_import(program: link.Program, document: Module, q: String): Target? {
    ulong index = 0;
    while (index < document.imports.count) {
        var qualifier = document.imports[index].qualifier();
        if (qualifier.is_value() and qualifier.value() == q) {
            return _imported_file(program, index);
        }
        index += 1;
    }
    return Optional<Target>.Empty;
}

# What the spelling at `span` denotes: a reference linking rewrote, or the
# name of an `import [...]` entry or re-export.
_linked(program: link.Program, span: Span): Target? {
    var scope = program.scopes[0];
    var name = scope.imported.try_get(span.start);
    if (name.is_empty()) {
        name = scope.named.try_get(span.start);
    }
    if (name.is_empty()) {
        return Optional<Target>.Empty;
    }
    return declaration_named(program, name.value());
}

# `target` under the name `spelled`.
_found(spelled: String, target: Target?): Found? {
    if (target.is_empty()) {
        return Optional<Found>.Empty;
    }
    return Optional<Found>.Value(Found(spelled, target.value()));
}

## The name at `offset` in an import or re-export of `document` (the
## parse of `program.files[0]`): the spelling under the cursor, and where
## it leads.
##
## @param program the loaded program
## @param document the document's syntax tree
## @param offset the byte offset
## @returns the name and its target; empty when none is there
export in_imports(program: link.Program, document: Module, offset: ulong): Found? {
    var none = Optional<Found>.Empty;
    var source = program.files[0].source;
    ulong index = 0;
    while (index < document.imports.count) {
        var import_ = document.imports[index];
        if (!contains(import_.span, offset)) {
            index += 1;
            continue;
        }
        if (contains(import_.name_span, offset)) {
            return _found(import_.name, _imported_file(program, index));
        }
        # The alias of `import "util" as u`.
        if (import_.alias is Value(alias)) {
            var written = source.substr_bytes(import_.name_span.end, import_.span.end - import_.name_span.end);
            var at = written.rfind(alias);
            if (at >= 0) {
                var start = import_.name_span.end + at as ulong;
                if (contains(Span(start, start + alias.size), offset)) {
                    return _found(alias, _imported_file(program, index));
                }
            }
        }
        if (import_.symbols is Value(symbols)) {
            for (var s in symbols) {
                if (contains(s.span, offset)) {
                    return _found(s.local_name(), _linked(program, s.span));
                }
            }
        }
        return none;
    }
    for (var export_ in document.exports) {
        if (!contains(export_.span, offset)) {
            continue;
        }
        # The qualifier of `export q.x as y` leads to the module.
        var dot = export_.symbol.find(".");
        if (dot >= 0 and offset < export_.symbol_span.start + dot as ulong) {
            var q = export_.symbol.substr_bytes(0, dot as ulong);
            return _found(q, _qualifier_import(program, document, q));
        }
        return _found(export_.exported_name(), _linked(program, export_.symbol_span));
    }
    return none;
}

## The expression `e` as a name reached through an import: a qualifier
## (`q` of `q.x`), a qualified reference, or an unqualified one.
##
## @param program the loaded program
## @param document the document's syntax tree
## @param e the expression under the cursor
## @param is_local whether a local, parameter or member binds a name
##   there, which hides a qualifier or declaration of the same name
## @returns the name and its target; empty when it names no import
export in_expression(program: link.Program, document: Module, e: Expression, is_local: (String) => bool): Found? {
    var none = Optional<Found>.Empty;
    match (e) {
        SymbolRef(id, span) => {
            if (!is_local(id)) {
                var qualifier = _qualifier_import(program, document, id);
                if (qualifier.is_value()) {
                    return _found(id, qualifier);
                }
            }
            var linked = _linked(program, span);
            if (linked.is_value()) {
                return _found(id, linked);
            }
            # A name another file of the program declares (the runtime's
            # private helpers are visible to the runtime's files).
            if (is_local(id)) {
                return none;
            }
            for (var declaration in document.declarations) {
                if (declaration.declared_name() == id) {
                    return none;
                }
            }
            return _found(id, declaration_named(program, id));
        }
        # Only a qualifier's member: `p.x` on an imported value `p` is a
        # struct member, recorded under the same span start as `p`.
        MemberAccess(lhs, name, _, span) => {
            if (lhs is SymbolRef(id, _)) {
                if (is_local(id) or _qualifier_import(program, document, id).is_empty()) {
                    return none;
                }
                var linked = _linked(program, span);
                if (linked.is_empty()) {
                    linked = _module_member(program, document, id, name);
                }
                return _found(name, linked);
            }
        }
        else => {}
    }
    return none;
}

## The type name at `offset` and the declaration it names: `q` of
## `q.Point` leads to the module; `q.Point`, an alias or an unqualified
## import, to the declaration linking recorded; any other name, to the
## type this file or another declares.
##
## @param program the loaded program
## @param document the document's syntax tree
## @param offset the byte offset
## @returns the name and its target; empty when no type name is there
export named_type(program: link.Program, document: Module, offset: ulong): Found? {
    var written = type_at(document, offset);
    if (written.is_empty()) {
        return Optional<Found>.Empty;
    }
    var t = written.value();
    var base = base_type_name(t.name);
    var dot = base.find(".");
    if (dot >= 0) {
        var q = base.substr_bytes(0, dot as ulong);
        var name = base.substr_bytes(dot as ulong + 1, base.size - dot as ulong - 1);
        if (offset < t.span.start + q.size) {
            return _found(q, _qualifier_import(program, document, q));
        }
        var linked = _linked(program, t.span);
        return _found(name, linked.is_value() ? linked : declaration_named(program, name));
    }
    var linked = _linked(program, t.span);
    return _found(base, linked.is_value() ? linked : declaration_named(program, base));
}

## A type's name without the pointer stars and array brackets after it.
##
## @param name the type's name
## @returns the base name
export base_type_name(name: String): String {
    var end = name.size;
    while (end > 0) {
        var b = name.byte_at(end - 1);
        if (b != '*' and b != '[' and b != ']') {
            break;
        }
        end -= 1;
    }
    return name.substr_bytes(0, end);
}
