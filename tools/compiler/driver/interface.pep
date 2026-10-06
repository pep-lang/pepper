## A file's interface hash: the part of the file that code in other
## compilation units can depend on, as `pepper_sema::interface` computes it.
## A unit's key names the files it reads from other units by their
## interface hashes rather than their text, so an edit that leaves a file's
## interface alone (a body, a comment, a moved declaration) rebuilds only
## that file's unit: early cutoff.
##
## The interface is the file's tokens, without comments, whitespace or
## positions, with each body the build cache may skip (`sema.strip_bodies`:
## non-generic, an explicit return type, its link summary recorded)
## replaced by that summary without the blame's position, and by how many
## closures it may create, since a file's closure structs are numbered in
## order. A body without a recorded summary is never skipped, so its tokens
## are part of the interface.

import compiler.ast;
import digest;
import compiler.link;
import compiler.sema;
import syntax;

## The interface hash of a program file, in hexadecimal.
##
## @param file the file
## @param index its index in the program's files
## @param summaries the link summaries recorded for the program's functions
## @returns the hash
export interface_hash(file: link.ProgramFile, index: uint, summaries: HashMap<sema.Loc, String>): String {
    var skipped = Array<(ast.Span, String)>();
    var skip = (function: ast.FunctionDecl) => {
        if (!function.body.is_value() or function.generic_params.count > 0 or _is_auto(function.return_type)) {
            return;
        }
        var summary = summaries.try_get(sema.Loc.at(index, function.name_span));
        if (summary.is_value()) {
            skipped.append((function.body.value().span, $"summary {summary_without_position(summary.value())}"));
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

## Whether `ty`, a declared return type, is none: the type is inferred.
_is_auto(ty: ast.TypeName): bool {
    return ty.name == "" or ty.name == "auto" or ty.name == "__auto";
}

## A recorded link summary without the position of what it blames, which
## moves with every edit above it: `summary_without_position` in
## `check_confinement.rs`.
##
## @param text the summary
## @returns the summary without the position
export summary_without_position(text: String): String {
    # Facts other passes append after `|` (`static_strings`) stay.
    var bar = text.find("|");
    var head = bar < 0 ? text : text.substr_bytes(0, bar as ulong);
    var facts = bar < 0 ? "" : text.substr_bytes(bar as ulong, text.size - bar as ulong);
    var semi = head.rfind(";");
    if (semi < 0) {
        return head + facts;
    }
    var rest = head.substr_bytes(0, semi as ulong);
    var blamed = head.substr_bytes(semi as ulong + 1, head.size - semi as ulong - 1);
    return blamed == "-" ? $"{rest};-{facts}" : $"{rest};blamed{facts}";
}
