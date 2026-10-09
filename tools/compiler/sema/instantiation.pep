## The specializations an error came from: `gather_generics`'
## `with_instantiation` and `with_requests` in Pepper.

import [demangle, Diagnostic, Location] from compiler.diagnostic;
import [location_of] from "common";
import [NO_FILE] from "loc";
import [Expression, FunctionDef, Module] from "model";
import "static_blocks";
import [parse_type_string] from "type_name";
import [Rewriter, rewrite_block] from "walk";

## `error` with a note for each specialization that led to `symbol`'s, back
## to the code that is not generic.
##
## @param module the model
## @param symbol the specialization (`Box<int>`, `pick<long>`)
## @param error the error
## @returns the error with its notes
export with_requests(module: Module, symbol: String, error: Diagnostic): Diagnostic {
    var out = error;
    var name = parse_type_string(symbol).to_string();
    var shown = Array<String>();
    while (true) {
        var request = module.spec_requests.try_get(name);
        if (!request.is_value()) {
            break;
        }
        var by = request.value().by;
        if (shown.contains(by) or shown.count >= _MAX_SPECIALIZATION_DEPTH) {
            break;
        }
        shown.append(by);
        out = out.with_note(
            $"'{demangle(name)}' is used by '{demangle(by)}' here",
            Optional<Location>.Value(location_of(request.value().loc))
        );
        name = by;
    }
    return out;
}

## `error`, found by a pass, with `with_requests`' notes when it lies in
## the body of a specialization. The specializations of one generic share
## its locations, so when several contain the error, those whose type
## arguments the message names are kept; the error is left as it is unless
## that leaves exactly one.
##
## @param module the model
## @param error the error
## @returns the error, perhaps with notes
export with_instantiation(module: Module, error: Diagnostic): Diagnostic {
    if (!error.location.is_value()) {
        return error;
    }
    var at = error.location.value();
    if (at.file == NO_FILE as ulong) {
        return error;
    }
    var candidates = Array<String>();
    for (var f in module.functions) {
        if (!f.is_generic_func
            and f.name.contains("<")
            and module.spec_requests.contains(parse_type_string(f.name).to_string())
            and _contains(f, at)) {
            candidates.append(f.name);
        }
    }
    for (var st in module.structs) {
        if (st.generic_params.count > 0 or !st.ty.is_generic() or !module.spec_requests.contains(st.ty.to_string())) {
            continue;
        }
        var found = false;
        for (var m in st.method_members) {
            found = found or _contains(m, at);
        }
        for (var c in st.constructors) {
            found = found or _contains(c, at);
        }
        if (found) {
            candidates.append(st.name);
        }
    }
    if (candidates.count > 1) {
        var named = Array<String>();
        var pieces = error.message.split("'");
        ulong i = 1;
        while (i < pieces.count) {
            named.append(pieces[i]);
            i += 2;
        }
        var kept = Array<String>();
        for (var c in candidates) {
            if (_names_argument(demangle(c), named)) {
                kept.append(c);
            }
        }
        candidates = kept;
    }
    if (candidates.count != 1) {
        return error;
    }
    var symbol = candidates[0];
    # A pass that knows its specialization (a `static` block) noted the
    # chain itself.
    var first = module.spec_requests.try_get(parse_type_string(symbol).to_string());
    for (var note in error.notes) {
        if (first.is_value()) {
            if (note.location.is_value() and _same(note.location.value(), location_of(first.value().loc))) {
                return error;
            }
        } else if (!note.location.is_value()) {
            return error;
        }
    }
    return with_requests(module, symbol, error);
}

_same(a: Location, b: Location): bool {
    return a.file == b.file and a.span.start == b.span.start and a.span.end == b.span.end;
}

## Whether `function`'s body has an expression at `at`, or a parameter is
## there.
_contains(function: FunctionDef, at: Location): bool {
    for (var p in function.parameters) {
        if (_same(location_of(p.loc), at)) {
            return true;
        }
    }
    if (!function.body.is_value()) {
        return false;
    }
    var finder = _LocFinder(at);
    rewrite_block(function.body.value(), finder);
    return finder.found;
}

struct _LocFinder {
    var at: Location;
    var found: bool = false;

    construct(at: Location) {
        this.at = at;
    }

    rewrite(e: Expression): Expression {
        if (!found and _same(location_of(_expression_loc(e)), at)) {
            found = true;
        }
        return e;
    }
}

extend _LocFinder with Rewriter;

## Whether a word of the type arguments in `shown` (`Box<Mode>`) is one of
## `named`.
_names_argument(shown: String, named: String[]): bool {
    var at = shown.find("<");
    if (at < 0) {
        return false;
    }
    var arguments = shown.substr_bytes(at as ulong + 1, shown.size - at as ulong - 1);
    var word = "";
    ulong i = 0;
    while (i <= arguments.size) {
        var ends = i == arguments.size;
        if (!ends) {
            var ch = arguments.byte_at(i);
            if (ch.is_alphanumeric() or ch == '_' or ch == '.') {
                word = word + arguments.substr_bytes(i, 1);
                i += 1;
                continue;
            }
        }
        if (named.contains(word)) {
            return true;
        }
        word = "";
        i += 1;
    }
    return false;
}
