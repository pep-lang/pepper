# Carrying offsets between two texts of a document: the text the last
# passing analysis checked and the text the editor holds now. Sema takes
# seconds, so requests never wait for it: a name outside what changed
# since is answered from the old analysis at once, and one inside it from
# the current text alone.

import lsp;
import compiler.parse;
import "analysis";
import "navigate";

## The one region where a later text of a document differs from an earlier
## one, found as their common prefix (whole lines) and suffix:
## `earlier[prefix..earlier_end]` became `current[prefix..current_end]`. Several edits in
## different places make one region spanning them all, which only maps
## fewer offsets.
export struct EditMap {
    ## Where the region starts in both texts: the start of a line.
    var prefix: ulong;
    ## Where it ends in the earlier text.
    var earlier_end: ulong;
    ## Where it ends in the current text.
    var current_end: ulong;
    ## The region ends at the end of a line in both texts, so the text
    ## after it starts a line.
    var ends_line: bool;

    ## The region where `current` differs from `earlier`.
    ##
    ## @param earlier the earlier text
    ## @param current the later text
    construct(earlier: String, current: String) {
        var shorter = earlier.size < current.size ? earlier.size : current.size;
        ulong common = 0;
        while (common < shorter and earlier.byte_at(common) == current.byte_at(common)) {
            common += 1;
        }
        # From the start of the line the edit is on: a line inserted after
        # `var a;` into `var b;` would otherwise share `var ` with it, and
        # the edit would land inside `b`.
        var start = common;
        while (start > 0 and earlier.byte_at(start - 1) != '\n') {
            start -= 1;
        }
        var limit = shorter - start;
        ulong suffix = 0;
        while (suffix < limit
            and earlier.byte_at(earlier.size - suffix - 1) == current.byte_at(current.size - suffix - 1)) {
            suffix += 1;
        }
        # Never split a character: a UTF-8 continuation byte belongs to the
        # region.
        while (suffix > 0 and (earlier.byte_at(earlier.size - suffix) & 0xC0) == 0x80) {
            suffix -= 1;
        }
        this.prefix = start;
        this.earlier_end = earlier.size - suffix;
        this.current_end = current.size - suffix;
        this.ends_line = _starts_line(earlier, earlier_end) and _starts_line(current, current_end);
    }

    ## `offset` in the current text, carried to the earlier one, when its line is
    ## wholly outside the edit: what a name means depends on the rest of its
    ## expression (`p.x` edited to `q.x` changes what `x` is), which rarely
    ## leaves the line.
    ##
    ## @param current the current text
    ## @param offset the byte offset in it
    ## @returns the offset in the earlier text; empty inside the edit
    to_earlier(current: String, offset: ulong): ulong? {
        var at = offset < current.size ? offset : current.size;
        # `prefix` starts a line, so an offset before it is on an earlier one.
        if (at < prefix) {
            return Optional<ulong>.Value(at);
        }
        if (at < current_end) {
            return Optional<ulong>.Empty;
        }
        if (!ends_line and current.substr_bytes(current_end, at - current_end).find("\n") < 0) {
            return Optional<ulong>.Empty;
        }
        return Optional<ulong>.Value(at - current_end + earlier_end);
    }

    ## The range `range` of the text `earlier` in the text `current`, when
    ## it lies outside the edit.
    ##
    ## @param earlier the earlier text
    ## @param current the current text
    ## @param range the range in the earlier text
    ## @returns the range in the current text; empty when the edit touches it
    range_to_current(earlier: String, current: String, range: lsp.Range): lsp.Range? {
        var before = lsp.TextDocument("", earlier);
        var start = before.offset_at(range.start);
        var end = before.offset_at(range.end);
        var after = lsp.TextDocument("", current);
        # After the edit first: an empty range where text was inserted (at
        # the start of a line a new line went above) moves with it.
        if (start >= earlier_end) {
            return Optional<lsp.Range>.Value(
                after.range_of(start - earlier_end + current_end, end - earlier_end + current_end)
            );
        }
        if (end <= prefix) {
            return Optional<lsp.Range>.Value(after.range_of(start, end));
        }
        return Optional<lsp.Range>.Empty;
    }

    ## `range_to_current` for something that depends on its whole line, as
    ## an answer computed at the earlier text does: only a range on a line
    ## the edit left alone.
    ##
    ## @param earlier the earlier text
    ## @param current the current text
    ## @param range the range in the earlier text
    ## @returns the range in the current text; empty when the edit touches
    ##   its lines
    line_range_to_current(earlier: String, current: String, range: lsp.Range): lsp.Range? {
        var before = lsp.TextDocument("", earlier);
        var start = before.offset_at(range.start);
        var end = before.offset_at(range.end);
        # `prefix` starts a line, so a range ending before it is on earlier
        # lines; one after the edit must start on a later line than its end.
        var after = start >= earlier_end
            and (ends_line or earlier.substr_bytes(earlier_end, start - earlier_end).find("\n") >= 0);
        if (end < prefix or after) {
            return range_to_current(earlier, current, range);
        }
        return Optional<lsp.Range>.Empty;
    }
}

# Whether `at` starts a line of `text`.
_starts_line(text: String, at: ulong): bool {
    return at == 0 or text.byte_at(at - 1) == '\n';
}

## The hover at `offset` of `document`: from `ready`, the newest analysis
## whose sema passed, when the name there is outside what changed since
## (with a note saying it may be out of date), else from the current text
## and `latest`, its last analysis, when that is of the same text.
##
## @param document the document as the editor holds it
## @param latest its last analysis, if any
## @param ready its newest analysis that passed sema, if any
## @param offset the byte offset in its text
## @returns the hover; empty when nothing is named there
export hover_across_edits(document: lsp.TextDocument, latest: Analysis?, ready: Analysis?, offset: ulong): lsp.Hover? {
    if (ready is Value(r)) {
        var earlier = _earlier_offset(document, r, offset);
        if (earlier is Value(at)) {
            var context = context_of(lsp.TextDocument(document.uri, r.text), Optional<Analysis>.Value(r));
            var hover = hover_at(context.value(), at);
            if (r.text == document.text or hover.is_empty()) {
                return hover;
            }
            # A declaration edited since may read differently.
            var note = "_Checking your latest edit; this may be out of date._";
            if (latest is Value(l)) {
                if (l.text == document.text) {
                    note = "_From before your latest edit, which does not check yet._";
                }
            }
            var h = hover.value();
            h.contents.value = h.contents.value + DOC_SEPARATOR + note;
            return Optional<lsp.Hover>.Value(h);
        }
    }
    var context = context_of(document, latest);
    if (context.is_empty()) {
        return Optional<lsp.Hover>.Empty;
    }
    return hover_at(context.value(), offset);
}

## The definition at `offset` of `document`, answered as
## `hover_across_edits` answers: a place in the document found in the older
## text moves with the edits since.
##
## @param document the document as the editor holds it
## @param latest its last analysis, if any
## @param ready its newest analysis that passed sema, if any
## @param offset the byte offset in its text
## @returns where the name there is declared; empty when nowhere
export definition_across_edits(
    document: lsp.TextDocument, latest: Analysis?, ready: Analysis?, offset: ulong
): lsp.Location[] {
    if (ready is Value(r)) {
        var moved = _definition_from(document, r, offset);
        if (moved.is_value()) {
            return moved.value();
        }
    }
    var context = context_of(document, latest);
    if (context.is_empty()) {
        return Array<lsp.Location>();
    }
    return definition_at(context.value(), offset);
}

## What answers about `document` are computed from: its text, parsed, with
## the program and model of `analysis` when that is of the same text.
##
## @param document the document
## @param analysis its last analysis, if any
## @returns the context; empty when the text does not parse
export context_of(document: lsp.TextDocument, analysis: Analysis?): Context? {
    var parsed = parse.parse(document.text);
    if (parsed.is_err()) {
        return Optional<Context>.Empty;
    }
    var context = Context(document, parsed.value());
    if (analysis is Value(a)) {
        if (a.text == document.text) {
            context.program = a.program;
            context.model = a.model;
            context.state = a.state;
        }
    }
    return Optional<Context>.Value(context);
}

# `offset` of the document's text in the text `ready` analyzed.
_earlier_offset(document: lsp.TextDocument, ready: Analysis, offset: ulong): ulong? {
    if (ready.text == document.text) {
        return Optional<ulong>.Value(offset);
    }
    return EditMap(ready.text, document.text).to_earlier(document.text, offset);
}

# The definition at `offset` as `ready` answers it, its places in the
# document moved to the current text; empty when the name is inside the
# edit, or a place it found is.
_definition_from(document: lsp.TextDocument, ready: Analysis, offset: ulong): lsp.Location[]? {
    var none = Optional<Array<lsp.Location>>.Empty;
    var earlier = _earlier_offset(document, ready, offset);
    if (earlier.is_empty()) {
        return none;
    }
    var context = context_of(lsp.TextDocument(document.uri, ready.text), Optional<Analysis>.Value(ready));
    var found = definition_at(context.value(), earlier.value());
    if (found.count == 0 or ready.text == document.text) {
        return Optional<Array<lsp.Location>>.Value(found);
    }
    var edits = EditMap(ready.text, document.text);
    var out = Array<lsp.Location>();
    for (var location in found) {
        if (location.uri != document.uri) {
            out.append(location);
            continue;
        }
        var range = edits.range_to_current(ready.text, document.text, location.range);
        if (range.is_empty()) {
            return none;
        }
        out.append(lsp.Location(location.uri, range.value()));
    }
    return Optional<Array<lsp.Location>>.Value(out);
}
