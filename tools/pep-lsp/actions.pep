# Code actions: the quick fixes the compiler suggests. A diagnostic may
# carry fixes (`Diagnostic.fixes`: replace deprecated syntax or a
# deprecated name, hand a value over with `move`, implement `Copyable`);
# each becomes an action that makes its edits. A missing `;` and a
# `match` missing cases get fixes of their own here.

import [EnumCase, Match, Module, Span] from compiler.ast;
import [demangle, Diagnostic] from compiler.diagnostic;
import compiler.link;
import lsp;
import compiler.parse;
import "scope";

## The quick fixes for the document's current text at `range`: those its
## last analysis found when that is of the same text, else those its
## syntax alone shows.
##
## @param document the document as the editor holds it
## @param analyzed the text of its last analysis, if any
## @param actions that analysis's actions
## @param range the range the editor asks about
## @returns the actions whose diagnostics overlap `range`
export code_actions(
    document: lsp.TextDocument, analyzed: String?, actions: lsp.CodeAction[], range: lsp.Range
): lsp.CodeAction[] {
    var all = actions;
    if (analyzed.is_empty() or analyzed.value() != document.text) {
        all = syntax_actions(document);
    }
    var out = Array<lsp.CodeAction>();
    for (var action in all) {
        if (action.diagnostics is Value(diagnostics)) {
            if (diagnostics.count > 0 and _overlap(diagnostics[0].range, range)) {
                out.append(action);
            }
        }
    }
    return out;
}

## The quick fixes the document's syntax shows: inserting a missing `;`,
## and replacing deprecated syntax (`new` for `construct`).
##
## @param document the document
## @returns the actions
export syntax_actions(document: lsp.TextDocument): lsp.CodeAction[] {
    var out = Array<lsp.CodeAction>();
    var parsed = parse.parse(document.text);
    if (parsed.is_err()) {
        var error = parsed.error();
        if (error.message != "expected ';'") {
            return out;
        }
        var at = error.span.start;
        var diagnostic = lsp.Diagnostic(document.range_of(at, error.span.end), error.message);
        out.append(_action(document, diagnostic, "Insert ';'", Span(at, at), ";"));
        return out;
    }
    for (var w in parsed.value().warnings) {
        var diagnostic = lsp.Diagnostic(
            document.range_of(w.span.start, w.span.end), $"{w.what} is deprecated: {w.instead}", lsp.SEVERITY_WARNING
        );
        diagnostic.code = Optional<String>.Value("deprecated");
        diagnostic.source = Optional<String>.Value("pepper");
        diagnostic.tags = Optional<Array<int>>.Value([lsp.TAG_DEPRECATED]);
        out.append(_action(document, diagnostic, $"Replace {w.what} with `{w.replacement}`", w.span, w.replacement));
    }
    return out;
}

## One action per fix `diagnostic` (the compiler's) suggests, each making
## its edits in the document; a fix that edits another file is left out.
##
## @param document the document
## @param diagnostic the compiler's diagnostic
## @param shown the same diagnostic as the editor shows it
## @returns the actions
export fix_actions(document: lsp.TextDocument, diagnostic: Diagnostic, shown: lsp.Diagnostic): lsp.CodeAction[] {
    var out = Array<lsp.CodeAction>();
    ulong i = 0;
    while (i < diagnostic.fixes.count) {
        var edits = Array<lsp.TextEdit>();
        var elsewhere = false;
        for (var e in diagnostic.fixes[i].edits) {
            if (e.location.file != 0) {
                elsewhere = true;
            }
            var span = e.location.span;
            edits.append(lsp.TextEdit(document.range_of(span.start, span.end), e.replacement));
        }
        if (!elsewhere) {
            out.append(_edit_action(document, shown, diagnostic.fixes[i].message, edits));
        }
        i += 1;
    }
    return out;
}

## The fix for `match on 'E' does not handle ...` in the document: an arm
## with an empty block for each case the `match` leaves out, before its
## closing brace, binding each value a case carries by its declared name.
##
## @param document the document
## @param program the program rooted at it
## @param error sema's error
## @param shown the same error as the editor shows it
## @returns the action; empty for any other error
export missing_arms(
    document: lsp.TextDocument, program: link.Program, error: Diagnostic, shown: lsp.Diagnostic
): lsp.CodeAction? {
    var none = Optional<lsp.CodeAction>.Empty;
    var prefix = "match on '";
    if (error.location.is_empty() or error.location.value().file != 0) {
        return none;
    }
    if (!error.message.starts_with(prefix) or !error.message.contains("does not handle")) {
        return none;
    }
    var rest = error.message.substr_bytes(prefix.size, error.message.size - prefix.size);
    var enum_name = demangle(rest.substr_bytes(0, rest.find("'") as ulong));
    # A generic enum's `match` names its specialization (`Tree<int>`).
    var angle = enum_name.find("<");
    var base = angle < 0 ? enum_name : enum_name.substr_bytes(0, angle as ulong);
    var parsed = parse.parse(document.text);
    if (parsed.is_err()) {
        return none;
    }
    var found = _match_at(parsed.value(), error.location.value().span.start);
    if (found.is_empty()) {
        return none;
    }
    var m = found.value();
    var cases = Optional<Array<EnumCase>>.Empty;
    for (var file in program.files) {
        for (var declaration in file.module.declarations) {
            if (declaration is Struct(s)) {
                if ((s.name == base or link.demangle_name(s.name) == base) and s.enumeration.is_value()) {
                    cases = Optional<Array<EnumCase>>.Value(s.enumeration.value().cases);
                }
            }
        }
        if (cases.is_value()) {
            break;
        }
    }
    if (cases.is_empty()) {
        return none;
    }
    # A guarded arm may not run, so it handles nothing.
    var handled = Array<String>();
    for (var arm in m.arms) {
        if (arm.guard.is_empty()) {
            for (var p in arm.patterns) {
                handled.append(p.case_name);
            }
        }
    }
    var missing = Array<String>();
    for (var c in cases.value()) {
        if (handled.contains(c.name)) {
            continue;
        }
        if (c.payload is Value(values)) {
            var names = Array<String>();
            for (var v in values) {
                names.append(v.name);
            }
            missing.append(c.name + "(" + ", ".join(names) + ")");
        } else {
            missing.append(c.name);
        }
    }
    if (missing.count == 0) {
        return none;
    }
    var text = document.text;
    var indent_start = _line_start(text, m.keyword_span.start);
    var indent_end = indent_start;
    while (indent_end < text.size and (text.byte_at(indent_end) == ' ' or text.byte_at(indent_end) == '\t')) {
        indent_end += 1;
    }
    var indent = text.substr_bytes(indent_start, indent_end - indent_start);
    var close = m.span.end - 1;
    var arms = "";
    for (var c in missing) {
        arms = arms + $"{indent}    {c} => {{}}\n";
    }
    # Insert on the closing brace's own line when it has one.
    var close_line = _line_start(text, close);
    var at = close;
    var replacement = "\n" + arms + indent;
    if (text.substr_bytes(close_line, close - close_line).trim().is_empty) {
        at = close_line;
        replacement = arms;
    }
    var plural = missing.count == 1 ? "" : "s";
    return Optional<lsp.CodeAction>.Value(
        _action(document, shown, $"Add the missing case{plural} of '{enum_name}'", Span(at, at), replacement)
    );
}

# The action titled `title` that fixes `shown` by making `edits`.
_edit_action(document: lsp.TextDocument, shown: lsp.Diagnostic, title: String, edits: lsp.TextEdit[]): lsp.CodeAction {
    var edit = lsp.WorkspaceEdit();
    for (var e in edits) {
        edit.add(document.uri, e);
    }
    # The kind is passed: its default, a constant of the `lsp` package,
    # makes the Rust compiler emit a call LLVM rejects.
    var action = lsp.CodeAction(title, lsp.QUICK_FIX);
    action.diagnostics = Optional<Array<lsp.Diagnostic>>.Value([shown]);
    action.edit = Optional<lsp.WorkspaceEdit>.Value(edit);
    action.is_preferred = Optional<bool>.Value(true);
    return action;
}

# The action titled `title` that fixes `shown` by replacing `span` with
# `replacement`.
_action(
    document: lsp.TextDocument, shown: lsp.Diagnostic, title: String, span: Span, replacement: String
): lsp.CodeAction {
    return _edit_action(document, shown, title, [lsp.TextEdit(document.range_of(span.start, span.end), replacement)]);
}

# The `match` statement of `module` whose keyword starts at `start`.
_match_at(module: Module, start: ulong): Match? {
    var enclosing = body_at(module, start);
    if (enclosing.is_empty()) {
        return Optional<Match>.Empty;
    }
    var blocks = [enclosing.value().body];
    while (blocks.count > 0) {
        var block = blocks.pop();
        if (!contains(block.span, start)) {
            continue;
        }
        for (var statement in block.statements) {
            if (statement is Match(m)) {
                if (m.keyword_span.start == start) {
                    return Optional<Match>.Value(m);
                }
            }
            blocks.append_all(statement_blocks(statement));
        }
    }
    return Optional<Match>.Empty;
}

# Where the line holding `at` starts.
_line_start(text: String, at: ulong): ulong {
    var start = at;
    while (start > 0 and text.byte_at(start - 1) != '\n') {
        start -= 1;
    }
    return start;
}

# Whether ranges `a` and `b` overlap, ends included.
_overlap(a: lsp.Range, b: lsp.Range): bool {
    return !_before(a.end, b.start) and !_before(b.end, a.start);
}

# Whether `a` comes before `b`.
_before(a: lsp.Position, b: lsp.Position): bool {
    return a.line < b.line or (a.line == b.line and a.character < b.character);
}
