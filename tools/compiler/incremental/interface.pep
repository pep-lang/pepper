## A file's interface hash: the part of the file that code in other
## compilation units can depend on. A unit's key names the files it reads
## from other units by their interface hashes rather than their text, so an
## edit that leaves a file's interface alone (a body, a comment, a moved
## declaration) rebuilds only that file's unit: early cutoff.
##
## The interface is the file's tokens, without comments, whitespace or
## positions, with each non-generic body sema settled a link summary for
## replaced by what other units see of it (`sema.function_facts`): its
## return type as sema resolved it, inferred or not, and that summary
## without the blame's position; and by how many closures it may create,
## since a file's closure structs are numbered in order. A body without a
## summary keeps its tokens in the interface.

import compiler.ast;
import digest;
import compiler.link;
import compiler.sema;
import syntax;

## The interface hash of a program file, in hexadecimal.
##
## @param file the file
## @param index its index in the program's files
## @param facts each function's return type and link summary, by its
##     location (`sema.function_facts`)
## @returns the hash
export interface_hash(file: link.ProgramFile, index: uint, facts: HashMap<sema.Loc, String>): String {
    var skipped = Array<(ast.Span, String)>();
    var skip = (function: ast.FunctionDecl) => {
        if (!function.body.is_value() or function.generic_params.count > 0) {
            return;
        }
        var fact = facts.try_get(sema.Loc.at(index, function.name_span));
        if (fact.is_value()) {
            skipped.append((function.body.value().span, fact.value()));
        }
    };
    for (var declaration in file.module.declarations) {
        match (declaration) {
            Function(decl) => {
                skip(decl);
            }
            Struct(decl) => {
                if (decl.generic_params.count == 0) {
                    for (var method in decl.methods) {
                        skip(method);
                    }
                }
            }
            Extend(decl) => {
                if (decl.target.generic_types.count == 0) {
                    for (var method in decl.methods) {
                        skip(method);
                    }
                }
            }
            else => {}
        }
    }
    skipped.sort((a, b) => {
        var (x, _) = a;
        var (y, _) = b;
        return x.start < y.start ? -1 : (x.start > y.start ? 1 : 0);
    });
    var hasher = digest.Blake3();
    hasher.update("pepper interface 1\n");
    var tokens = syntax.lex(file.source);
    if (tokens.is_err()) {
        # A file the lexer rejects never builds: its text stands in.
        hasher.update(file.source);
        return hasher.finish_hex();
    }
    ulong next = 0;
    ulong closures = 0;
    var inside = Optional<(ast.Span, String)>.Empty;
    for (var token in tokens.value()) {
        if (inside.is_value()) {
            var (span, summary) = inside.value();
            if (token.offset < span.end) {
                if (token.is(file.source, "=>")) {
                    closures += 1;
                }
                continue;
            }
            hasher.update($"{summary}\nclosures {closures}\n");
            inside = Optional<(ast.Span, String)>.Empty;
        }
        while (next < skipped.count) {
            var (span, _) = skipped[next];
            if (span.end > token.offset) {
                break;
            }
            next += 1;
        }
        if (next < skipped.count) {
            var (span, _) = skipped[next];
            if (token.offset >= span.start) {
                inside = Optional<(ast.Span, String)>.Value(skipped[next]);
                closures = token.is(file.source, "=>") ? 1 : 0;
                next += 1;
                continue;
            }
        }
        hasher.update(token.text(file.source));
        hasher.update("\n");
    }
    if (inside.is_value()) {
        var (_, summary) = inside.value();
        hasher.update($"{summary}\nclosures {closures}\n");
    }
    return hasher.finish_hex();
}

## The names in a program file's code: every identifier in it, and those
## other units' code can reach through it. A top-level function or struct
## (an enum is one) shows the identifiers in it outside the bodies of
## functions that are not generic, and outside the names of its own and
## its methods, but only to code that names it; everything else in the
## file shows its identifiers to all code that reads it.
## `compilation_unit_key` takes the entries of a function, struct or enum
## that is not generic in another unit's own interface only when the
## unit's code can name it: in its own files, or in what the declarations
## it reaches show.
##
## @param file the file
## @returns every name, the names shown to every reader, and the names
##   each declaration shows, by its name
export file_names(file: link.ProgramFile): (HashSet<String>, HashSet<String>, HashMap<String, HashSet<String>>) {
    var all = HashSet<String>();
    var shown = HashSet<String>();
    var shown_by = HashMap<String, HashSet<String>>();
    var tokens = syntax.lex(file.source);
    if (tokens.is_err()) {
        return (all, shown, shown_by);
    }
    # Spans whose tokens other units' code does not see, by start.
    var hidden = Array<ast.Span>();
    # The top-level functions and structs, in order, and their names.
    var declared = Array<ast.Span>();
    var declared_names = Array<String>();
    var hide = (function: ast.FunctionDecl, generic: bool) => {
        hidden.append(function.name_span);
        if (function.body.is_value() and !generic and function.generic_params.count == 0) {
            hidden.append(function.body.value().span);
        }
    };
    for (var declaration in file.module.declarations) {
        match (declaration) {
            Function(decl) => {
                hide(decl, false);
                declared.append(decl.span);
                declared_names.append(sema.function_name(decl.name));
            }
            Struct(decl) => {
                for (var methods in [decl.methods, decl.constructors]) {
                    for (var method in methods) {
                        hide(method, decl.generic_params.count > 0);
                    }
                }
                declared.append(decl.span);
                declared_names.append(sema.function_name(decl.name));
            }
            Extend(decl) => {
                for (var method in decl.methods) {
                    hide(method, decl.target.generic_types.count > 0);
                }
            }
            else => {}
        }
    }
    hidden.sort((a, b) => a.start < b.start ? -1 : (a.start > b.start ? 1 : 0));
    ulong next = 0;
    ulong in_declared = 0;
    for (var token in tokens.value()) {
        if (token.kind != syntax.TokenKind.Identifier) {
            continue;
        }
        var text = token.text(file.source);
        all.insert(text);
        # The spans do not overlap: names and bodies of different functions.
        while (next < hidden.count and hidden[next].end <= token.offset) {
            next += 1;
        }
        if (next < hidden.count and token.offset >= hidden[next].start) {
            continue;
        }
        # A declaration out of order only shows its names to every reader.
        while (in_declared < declared.count and declared[in_declared].end <= token.offset) {
            in_declared += 1;
        }
        if (in_declared == declared.count or token.offset < declared[in_declared].start) {
            shown.insert(text);
            continue;
        }
        # Its own name, as written.
        var name = declared_names[in_declared];
        if (text == name) {
            continue;
        }
        if (!shown_by.contains(name)) {
            shown_by[name] = HashSet<String>();
        }
        shown_by[name].insert(text);
    }
    return (all, shown, shown_by);
}
