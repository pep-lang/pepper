## Re-checking a compilation unit from an earlier record of it. When an
## edit changed only the bodies of some of a unit's functions (and comments
## or spacing), on the same records below, the unit's newest record of
## before the edit holds everything else as checking it again would make
## it: the build reads it, its locations moved to the edited files
## (`sema.LocShift`), and checks only the changed bodies on top. Each
## record keeps its files' text beside it (`<key>.rec.src`) to tell.

import compiler.ast;
import digest;
import [Directory, File, Path] from io;
import compiler.link;
import compiler.parse;
import compiler.sema;
import syntax;
import "cache";
import [CompilationUnit, record_path] from "compilation_units";

## What a check can start from: an earlier record of the compilation unit,
## where its locations are now, and the bodies the edit changed.
export struct RecheckBase {
    ## The record.
    var bytes: u8[];
    ## Where its locations are in the edited files.
    var shift: sema.LocShift;
    ## The changed bodies: the file, the function's name span and its
    ## body's span, in the edited file.
    var changed: Array<(uint, ast.Span, ast.Span)> = Array<(uint, ast.Span, ast.Span)>();

    construct(bytes: u8[], shift: sema.LocShift) {
        this.bytes = bytes;
        this.shift = shift;
    }
}

## The hash of what compilation unit `unit` is checked on: the records of the
## compilation units it reads, as they are. A record is a delta on them.
##
## @param records each compilation unit's record, by index: those `unit` reads set
## @param unit the compilation unit
## @returns the hash, as hex
export inputs_digest(records: HashMap<ulong, u8[]>, unit: CompilationUnit): String {
    var hasher = digest.Blake3();
    hasher.update("pepper recheck inputs 1\n");
    for (var d in unit.reads) {
        var bytes = records.try_get(d);
        if (!bytes.is_value()) {
            return "";
        }
        hasher.update($"{d} {bytes.value().count}\n");
        hasher.update(bytes.value());
    }
    return hasher.finish_hex();
}

## What a record of `unit` keeps beside it for a later re-check: what it is
## checked on, and its files' text.
##
## @param program the program
## @param unit the compilation unit
## @param inputs `inputs_digest` of the records it reads
## @returns the text
export recheck_source(program: link.Program, unit: CompilationUnit, inputs: String): String {
    var out = StringBuilder();
    out.append($"pepper recheck 1\n{inputs}\n{unit.files.count}\n");
    for (var file in unit.files) {
        var f = program.files[file];
        out.append($"{f.namespace}\n{f.source.size}\n");
        out.append(f.source);
    }
    return out.to_string();
}

## Where the text `recheck_source` made for the record at `path` is.
##
## @param path the record's path
## @returns the path of its text
export recheck_path(path: Path): Path {
    return Path($"{path}.src");
}

## Returns an earlier record of `unit` that a re-check can start from: the
## newest whose text differs from its files' only in bodies (`_align`), on
## the same records below, and whose check warned of nothing.
##
## @param cache the build cache
## @param program the program
## @param unit the compilation unit
## @param inputs `inputs_digest` of the records it reads
## @returns the record, where its locations are now, and the changed bodies
export find_recheck_base(cache: Cache, program: link.Program, unit: CompilationUnit, inputs: String): RecheckBase? {
    if (inputs.is_empty) {
        return Optional<RecheckBase>.Empty;
    }
    var folder = record_path(cache, unit).parent().value();
    var listing = Directory.open(folder);
    if (listing.is_err()) {
        return Optional<RecheckBase>.Empty;
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return Optional<RecheckBase>.Empty;
    }
    var found = Array<(String, long)>();
    for (var entry in entries.value()) {
        if (!entry.name.ends_with(".rec")) {
            continue;
        }
        var metadata = folder.join(Path(entry.name)).metadata();
        if (metadata.is_ok()) {
            found.append((entry.name, metadata.value().modified));
        }
    }
    found.sort((a, b) => {
        var (_, x) = a;
        var (_, y) = b;
        return x > y ? -1 : (x < y ? 1 : 0);
    });
    for (var (name, _) in found) {
        var base = _base_from(folder.join(Path(name)), program, unit, inputs);
        if (base.is_value()) {
            return base;
        }
    }
    return Optional<RecheckBase>.Empty;
}

# The re-check base the record at `path` gives, if it gives one.
_base_from(path: Path, program: link.Program, unit: CompilationUnit, inputs: String): RecheckBase? {
    var none = Optional<RecheckBase>.Empty;
    var warned = File.read_to_string(Path($"{path}.warn"));
    if (warned.is_err() or !warned.value().is_empty) {
        return none;
    }
    var text = File.read_to_string(recheck_path(path));
    if (text.is_err()) {
        return none;
    }
    var reader = _TextReader(text.value());
    if (reader.line() != "pepper recheck 1" or reader.line() != inputs) {
        return none;
    }
    var count = reader.number();
    if (!count.is_value() or count.value() != unit.files.count) {
        return none;
    }
    var shift = sema.LocShift();
    var changed = Array<(uint, ast.Span, ast.Span)>();
    for (var file in unit.files) {
        var f = program.files[file];
        var namespace = reader.line();
        var size = reader.number();
        if (namespace != f.namespace or !size.is_value()) {
            return none;
        }
        var old = reader.bytes(size.value());
        if (!old.is_value() or !_align(old.value(), f, file as uint, shift, changed)) {
            return none;
        }
    }
    var bytes = File.read_bytes(path);
    if (bytes.is_err()) {
        return none;
    }
    var out = RecheckBase(bytes.value(), shift);
    out.changed = changed;
    return Optional<RecheckBase>.Value(out);
}

# Reads what `recheck_source` wrote.
struct _TextReader {
    var text: String;
    var at: ulong = 0;

    construct(text: String) {
        this.text = text;
    }

    line(): String {
        var rest = text.substr_bytes(at, text.size - at);
        var end = rest.find("\n");
        if (end < 0) {
            at = text.size;
            return rest;
        }
        at += end as ulong + 1;
        return rest.substr_bytes(0, end as ulong);
    }

    number(): ulong? {
        var digits = line();
        if (digits.is_empty) {
            return Optional<ulong>.Empty;
        }
        ulong value = 0;
        for (var b in digits.bytes()) {
            if (b < '0' as u8 or b > '9' as u8) {
                return Optional<ulong>.Empty;
            }
            value = value * 10 + (b - '0' as u8) as ulong;
        }
        return Optional<ulong>.Value(value);
    }

    bytes(size: ulong): String? {
        if (at + size > text.size) {
            return Optional<String>.Empty;
        }
        var out = text.substr_bytes(at, size);
        at += size;
        return Optional<String>.Value(out);
    }
}

## The bodies an edit may change and a re-check checks again: those of the
## top-level functions that are not generic, and of the methods and
## constructors that are not generic of the structs that are not.
##
## @param module a file's syntax tree
## @returns each one's name span and body span, in order
_bodies(module: ast.Module): Array<(ast.Span, ast.Span)> {
    var out = Array<(ast.Span, ast.Span)>();
    var add = (decl: ast.FunctionDecl) => {
        if (decl.body.is_value() and decl.generic_params.count == 0) {
            out.append((decl.name_span, decl.body.value().span));
        }
    };
    for (var declaration in module.declarations) {
        if (declaration is Function(decl)) {
            add(decl);
        } else if (declaration is Struct(decl)) {
            if (decl.generic_params.count == 0) {
                for (var m in decl.methods) {
                    add(m);
                }
                for (var c in decl.constructors) {
                    add(c);
                }
            }
        }
    }
    out.sort((a, b) => {
        var (_, x) = a;
        var (_, y) = b;
        return x.start < y.start ? -1 : (x.start > y.start ? 1 : 0);
    });
    return out;
}

# Whether the old text `old` of file `file` (program file `index`) differs
# from its text now only inside the bodies `_bodies` finds; adds where its
# kept tokens are now to `shift`, and the changed bodies to `changed`.
_align(
    old: String, file: link.ProgramFile, index: uint, shift: sema.LocShift, changed: Array<(uint, ast.Span, ast.Span)>
): bool {
    var parsed = parse.parse_declarations(old);
    var old_tokens = syntax.lex(old, false);
    var new_tokens = syntax.lex(file.source, false);
    if (parsed.is_err() or old_tokens.is_err() or new_tokens.is_err()) {
        return false;
    }
    var old_bodies = _bodies(parsed.value());
    var new_bodies = _bodies(file.module);
    if (old_bodies.count != new_bodies.count) {
        return false;
    }
    var tokens = _Tokens(old, old_tokens.value(), file.source, new_tokens.value());
    var moved = Array<(ast.Span, ulong)>();
    for (var n in 0..old_bodies.count) {
        var (_, old_body) = old_bodies[n];
        var (new_name, new_body) = new_bodies[n];
        if (!tokens.same(old_body.start, new_body.start)) {
            return false;
        }
        if (!tokens.same(old_body.end, new_body.end)) {
            moved.append((old_body, new_body.start));
            changed.append((index, new_name, new_body));
        }
        # Where the body ended is where it ends.
        tokens.old_offsets.append(old_body.end);
        tokens.new_offsets.append(new_body.end);
    }
    if (!tokens.same(old.size + 1, file.source.size + 1)) {
        return false;
    }
    shift.add_file(index, tokens.old_offsets, tokens.new_offsets, moved);
    return true;
}

# Two texts' tokens, walked in step.
struct _Tokens {
    var old_text: String;
    var a: syntax.Token[];
    var new_text: String;
    var b: syntax.Token[];
    var i: ulong = 0;
    var j: ulong = 0;
    ## The kept tokens' offsets, in each text.
    var old_offsets: ulong[] = Array<ulong>();
    var new_offsets: ulong[] = Array<ulong>();

    construct(old_text: String, a: syntax.Token[], new_text: String, b: syntax.Token[]) {
        this.old_text = old_text;
        this.a = a;
        this.new_text = new_text;
        this.b = b;
    }

    # Whether the tokens up to `old_end` and `new_end` are the same; keeps
    # their offsets when they are.
    same(old_end: ulong, new_end: ulong): bool {
        var i0 = i;
        var j0 = j;
        while (i < a.count and a[i].offset < old_end) {
            i += 1;
        }
        while (j < b.count and b[j].offset < new_end) {
            j += 1;
        }
        if (i - i0 != j - j0) {
            return false;
        }
        for (var k in 0..(i - i0)) {
            if (a[i0 + k].text(old_text) != b[j0 + k].text(new_text)) {
                return false;
            }
        }
        for (var k in 0..(i - i0)) {
            old_offsets.append(a[i0 + k].offset);
            new_offsets.append(b[j0 + k].offset);
        }
        return true;
    }
}
