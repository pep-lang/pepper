# Inlay hints: the call an `[Implicit]` conversion inserts (`Path(` and `)`
# around a `String` passed as a `Path`), and the parameter name before a
# literal argument passed by position (`width: 800`). Both come from the
# newest analysis whose sema passed, moved by the edits since; none is
# shown on a line the edits touched.

import lsp;
import compiler.sema;
import "analysis";
import "edits";

## The inlay hints of `document` in `range`.
##
## @param document the document as the editor holds it
## @param ready its newest analysis that passed sema, if any
## @param range the part of the document shown
## @param conversions whether to show implicit conversions
## @param parameters whether to name literal arguments
## @returns the hints, in no particular order
export inlay_hints(
    document: lsp.TextDocument, ready: Analysis?, range: lsp.Range, conversions: bool, parameters: bool
): lsp.InlayHint[] {
    var out = Array<lsp.InlayHint>();
    if (ready.is_empty() or ready.value().model.is_empty()) {
        return out;
    }
    var r = ready.value();
    var model = r.model.value();
    var edits = Optional<EditMap>.Empty;
    if (r.text != document.text) {
        edits = Optional<EditMap>.Value(EditMap(r.text, document.text));
    }
    var hints = Array<lsp.InlayHint>();
    if (conversions) {
        var pairs = conversion_hints(r.text, model);
        ulong i = 0;
        # Each conversion's `To(` and `)` move as one range, so an edit
        # inside it drops both.
        while (i + 1 < pairs.count) {
            var open = pairs[i];
            var close = pairs[i + 1];
            i += 2;
            if (edits is Value(e)) {
                var moved = e.line_range_to_current(r.text, document.text, lsp.Range(open.position, close.position));
                if (moved.is_empty()) {
                    continue;
                }
                open.position = moved.value().start;
                close.position = moved.value().end;
            }
            hints.append(open);
            hints.append(close);
        }
    }
    if (parameters) {
        for (var hint in parameter_hints(r.text, model)) {
            if (edits is Value(e)) {
                var moved = e.line_range_to_current(r.text, document.text, lsp.Range(hint.position, hint.position));
                if (moved.is_empty()) {
                    continue;
                }
                hint.position = moved.value().start;
            }
            hints.append(hint);
        }
    }
    for (var hint in hints) {
        if (!_before(hint.position, range.start) and !_before(range.end, hint.position)) {
            out.append(hint);
        }
    }
    return out;
}

## The inlay hints around each value of the document (`program.files[0]`)
## an `[Implicit]` constructor converts: `Path(` before and `)` after, so
## the call the compiler inserts is visible. They come in pairs, each
## conversion's two in a row, in source order.
##
## @param text the text the model was checked from
## @param model the checked model
## @returns the hints
export conversion_hints(text: String, model: sema.Module): lsp.InlayHint[] {
    var document = lsp.TextDocument("", text);
    var out = Array<lsp.InlayHint>();
    for (var c in _document_conversions(model)) {
        if (c.at.span.end > text.size) {
            continue;
        }
        var open = lsp.InlayHint(document.position_at(c.at.span.start), c.to.display() + "(");
        open.tooltip = Optional<lsp.MarkupContent>.Value(lsp.MarkupContent(lsp.MARKDOWN, conversion_note(c)));
        out.append(open);
        out.append(lsp.InlayHint(document.position_at(c.at.span.end), ")"));
    }
    return out;
}

## The inlay hints naming the parameter before each literal argument of
## the document passed by position (`width: 800`), as sema recorded them.
##
## @param text the text the model was checked from
## @param model the checked model
## @returns the hints
export parameter_hints(text: String, model: sema.Module): lsp.InlayHint[] {
    var document = lsp.TextDocument("", text);
    var out = Array<lsp.InlayHint>();
    for (var (at, name) in model.argument_names) {
        if (at.file != 0 or at.span.start > text.size) {
            continue;
        }
        var hint = lsp.InlayHint(document.position_at(at.span.start), name + ":");
        hint.kind = Optional<int>.Value(lsp.INLAY_PARAMETER);
        hint.padding_right = Optional<bool>.Value(true);
        out.append(hint);
    }
    return out;
}

## The innermost implicit conversion of the document covering `offset`.
##
## @param model the checked model
## @param offset the byte offset
## @returns the conversion; empty when none covers it
export conversion_at(model: sema.Module, offset: ulong): sema.Conversion? {
    var found = Optional<sema.Conversion>.Empty;
    for (var c in _document_conversions(model)) {
        var span = c.at.span;
        if (span.start > offset or offset >= span.end) {
            continue;
        }
        if (found is Value(f)) {
            if (f.at.span.end - f.at.span.start <= span.end - span.start) {
                continue;
            }
        }
        found = Optional<sema.Conversion>.Value(c);
    }
    return found;
}

## What hover says about a conversion.
##
## @param c the conversion
## @returns the note
export conversion_note(c: sema.Conversion): String {
    return $"Converted to `{c.to.display()}` by its `[Implicit]` constructor from `{c.from.display()}`.";
}

# The implicit conversions of the document, in source order.
_document_conversions(model: sema.Module): sema.Conversion[] {
    var out = Array<sema.Conversion>();
    for (var c in model.conversions) {
        if (c.at.file == 0) {
            out.append(c);
        }
    }
    out.sort((a: sema.Conversion, b: sema.Conversion) => {
        if (a.at.span.start != b.at.span.start) {
            return a.at.span.start < b.at.span.start ? -1 : 1;
        }
        if (a.at.span.end != b.at.span.end) {
            return a.at.span.end < b.at.span.end ? -1 : 1;
        }
        return 0;
    });
    return out;
}

# Whether `a` comes before `b`.
_before(a: lsp.Position, b: lsp.Position): bool {
    return a.line < b.line or (a.line == b.line and a.character < b.character);
}
