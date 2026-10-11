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
