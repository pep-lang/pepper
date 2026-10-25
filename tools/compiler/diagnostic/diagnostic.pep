## Compiler diagnostics, rendered in clang's format:
##
##     main.pep:2:13: error: expected expression
##         2 |     var x = ;
##           |             ^
##     main.pep:1:1: note: in this function
##         1 | main(): int {
##           | ^~~~
##
## A diagnostic may carry suggested fixes. The renderer shows a fix's edit
## under the caret when it is on the diagnostic's own line, as clang shows
## fix-it hints. Rendering spells private names as the user wrote them (see
## `demangle`).

import [Span] from compiler.ast;

## How serious a diagnostic is.
export enum Severity {
    ## The program cannot be compiled.
    Error,
    ## The program compiles, but something in it is likely wrong.
    Warning,
    ## More about the diagnostic before it.
    Note,
}

## A place in one of the program's files.
export struct Location {
    ## The file's index among the program's files.
    var file: ulong;
    ## The bytes it covers.
    var span: Span;

    ## Creates a location.
    ##
    ## @param file the file's index
    ## @param span the bytes
    construct(file: ulong, span: Span) {
        this.file = file;
        this.span = span;
    }

    ## Returns whether `other` is the same place.
    ##
    ## @param other the other location
    ## @returns true when the file and span match
    same(other: Location): bool {
        return file == other.file and span.start == other.span.start and span.end == other.span.end;
    }
}

## Replaces the text at a location (an empty span inserts).
export struct Edit {
    ## What is replaced.
    var location: Location;
    ## The text that replaces it.
    var replacement: String;

    ## Creates an edit.
    ##
    ## @param location what is replaced
    ## @param replacement the new text
    construct(location: Location, replacement: String) {
        this.location = location;
        this.replacement = replacement;
    }
}

## A suggested fix: what it does, in the imperative, and its edits.
export struct Fix {
    ## What it does.
    var message: String;
    ## The edits that do it.
    var edits: Edit[] = Array<Edit>();

    ## Creates a fix that replaces the text at `location`.
    ##
    ## @param message what it does
    ## @param location the text to replace
    ## @param replacement the new text
    construct(message: String, location: Location, replacement: String) {
        this.message = message;
        edits.append(Edit(location, replacement));
    }
}

## The code of every deprecation warning.
export const DEPRECATED_CODE = "deprecated";

## One diagnostic: a message at an optional location, then notes (each a
## diagnostic of its own, usually pointing somewhere else) and any
## suggested fixes.
export struct Diagnostic {
    ## How serious it is.
    var severity: Severity;
    ## What it says.
    var message: String;
    ## Where it points, if anywhere.
    var location: Location?;
    ## The notes that follow it.
    var notes: Diagnostic[] = Array<Diagnostic>();
    ## Its class (`deprecated`), shown after the message as `[code]`, or
    ## empty.
    var code: String = "";
    ## The fixes it suggests.
    var fixes: Fix[] = Array<Fix>();

    ## Creates a diagnostic with no location.
    ##
    ## @param severity how serious it is
    ## @param message what it says
    construct(severity: Severity, message: String) {
        this.severity = severity;
        this.message = message;
    }

    ## Returns an error.
    ##
    ## @param message what it says
    ## @returns the error
    static error(message: String): Diagnostic {
        return Diagnostic(Severity.Error, message);
    }

    ## Returns a warning.
    ##
    ## @param message what it says
    ## @returns the warning
    static warning(message: String): Diagnostic {
        return Diagnostic(Severity.Warning, message);
    }

    ## Returns a warning that `what` (as the source spells it, "`new`") at
    ## `location` is deprecated, with the fix that migrates the code.
    ##
    ## @param what the deprecated syntax
    ## @param instead what replaces it
    ## @param location where it is
    ## @param fix the fix
    ## @returns the warning
    static deprecated(what: String, instead: String, location: Location, fix: Fix): Diagnostic {
        var out = Diagnostic.warning($"{what} is deprecated; {instead}").at(location).with_fix(fix);
        out.code = DEPRECATED_CODE;
        return out;
    }

    ## Returns a warning that the declaration `name`, used at `location`, is
    ## marked `[Deprecated(message)]`.
    ##
    ## @param name the declaration
    ## @param message the attribute's message, possibly empty
    ## @param location the use
    ## @returns the warning
    static deprecated_declaration(name: String, message: String, location: Location): Diagnostic {
        var text = message.is_empty ? $"'{name}' is deprecated" : $"'{name}' is deprecated: {message}";
        var out = Diagnostic.warning(text).at(location);
        out.code = DEPRECATED_CODE;
        return out;
    }

    ## Places the diagnostic at `location`.
    ##
    ## @param location where it points
    ## @returns the diagnostic
    at(location: Location): Diagnostic {
        this.location = Optional<Location>.Value(location);
        return this;
    }

    ## Appends a note, at `location` if it has one.
    ##
    ## @param message what the note says
    ## @param location where it points
    ## @returns the diagnostic
    with_note(message: String, location: Location?): Diagnostic {
        var note = Diagnostic(Severity.Note, message);
        note.location = location;
        notes.append(note);
        return this;
    }

    ## Appends a suggested fix.
    ##
    ## @param fix the fix
    ## @returns the diagnostic
    with_fix(fix: Fix): Diagnostic {
        fixes.append(fix);
        return this;
    }

    ## Returns the diagnostic rendered against `sources`: a header line, the
    ## source line with a caret and underline under the span, then each note
    ## the same way.
    ##
    ## @param sources each file's name and text, by index
    ## @returns the text, without a final newline
    render(sources: SourceText[]): String {
        var out = StringBuilder();
        _render_into(sources, out);
        var text = out.to_string();
        ulong size = text.size;
        while (size > 0 and text.byte_at(size - 1) == '\n') {
            size -= 1;
        }
        return text.substr_bytes(0, size);
    }

    _render_into(sources: SourceText[], out: StringBuilder) {
        var suffix = code.is_empty ? "" : $" [{code}]";
        var label = _label(severity);
        if (location.is_value() and location.value().file < sources.count) {
            var at = location.value();
            var source = sources[at.file];
            var (line, column) = _position(source.text, at.span.start);
            out.append($"{source.name}:{line}:{column}: {label}: {demangle(message)}{suffix}\n");
            _snippet(source.text, at.span, _fix_on_line(at, source.text), out);
        } else {
            out.append($"{label}: {demangle(message)}{suffix}\n");
        }
        for (var note in notes) {
            note._render_into(sources, out);
        }
    }

    # The first fix's edit, when the fix is a single edit on the same line
    # as `at` (the one line the snippet shows).
    _fix_on_line(at: Location, text: String): Edit? {
        if (fixes.count == 0 or fixes[0].edits.count != 1) {
            return Optional<Edit>.Empty;
        }
        var edit = fixes[0].edits[0];
        var line = _line_of(text, at.span.start);
        if (edit.location.file == at.file
            and _line_of(text, edit.location.span.start) == line
            and _line_of(text, edit.location.span.end) == line
            and !edit.replacement.contains("\n")) {
            return Optional<Edit>.Value(edit);
        }
        return Optional<Edit>.Empty;
    }
}

## A file a diagnostic may point into: its name as diagnostics show it, and
## its text.
export struct SourceText {
    ## The name.
    var name: String;
    ## The text.
    var text: String;

    ## Creates a file.
    ##
    ## @param name the name
    ## @param text the text
    construct(name: String, text: String) {
        this.name = name;
        this.text = text;
    }
}

## Returns `diagnostics` rendered against `sources`, one after another.
##
## @param diagnostics the diagnostics
## @param sources each file's name and text, by index
## @returns the text, without a final newline
export render_all(diagnostics: Diagnostic[], sources: SourceText[]): String {
    var parts = Array<String>();
    for (var d in diagnostics) {
        parts.append(d.render(sources));
    }
    return "\n".join(parts);
}

_label(severity: Severity): String {
    match (severity) {
        Error => {
            return "error";
        }
        Warning => {
            return "warning";
        }
        Note => {
            return "note";
        }
    }
}

# The 1-based line and column (in characters) of byte `offset`.
_position(text: String, offset: ulong): (ulong, ulong) {
    var end = offset < text.size ? offset : text.size;
    ulong i = 0;
    ulong line = 1;
    ulong column = 1;
    while (i < end) {
        var b = text.byte_at(i);
        if (b == '\n') {
            line += 1;
            column = 1;
        } else if (!_is_continuation(b)) {
            column += 1;
        }
        i += 1;
    }
    return (line, column);
}

# The 0-based line of byte `offset`.
_line_of(text: String, offset: ulong): ulong {
    var end = offset < text.size ? offset : text.size;
    ulong line = 0;
    ulong i = 0;
    while (i < end) {
        if (text.byte_at(i) == '\n') {
            line += 1;
        }
        i += 1;
    }
    return line;
}

_is_continuation(b: byte): bool {
    return (b as u8 & 0xC0) == 0x80;
}

# Width tabs expand to in snippets, so the caret lines up with the text.
const _TAB_WIDTH = 4;

# The source line holding `span.start`, then a caret under the start and
# `~` under the rest of the span (clipped to that line), then `fix`'s
# replacement under the text it replaces.
_snippet(text: String, span: Span, fix: Edit?, out: StringBuilder) {
    var start = span.start < text.size ? span.start : text.size;
    ulong line_start = start;
    while (line_start > 0 and text.byte_at(line_start - 1) != '\n') {
        line_start -= 1;
    }
    ulong line_end = start;
    while (line_end < text.size and text.byte_at(line_end) != '\n') {
        line_end += 1;
    }
    ulong line_size = line_end - line_start;
    while (line_size > 0 and text.byte_at(line_start + line_size - 1) == '\r') {
        line_size -= 1;
    }
    ulong line_number = _line_of(text, line_start) + 1;
    # A span starting on a CRLF's '\n' lies past the line once its '\r' is
    # trimmed; the caret then goes at the line's end.
    ulong limit = line_start + line_size > start ? line_start + line_size : start;
    ulong end = span.end < start ? start : (span.end > limit ? limit : span.end);

    # Expand tabs, tracking the display columns of the span's ends.
    var shown = StringBuilder();
    ulong width = 0;
    long caret_column = -1;
    long end_column = -1;
    long fix_column = -1;
    ulong i = 0;
    while (i < line_size) {
        var at = line_start + i;
        var b = text.byte_at(at);
        if (_is_continuation(b)) {
            shown.append(text.substr_bytes(at, 1));
            i += 1;
            continue;
        }
        if (at == start) {
            caret_column = width as long;
        }
        if (fix.is_value() and fix.value().location.span.start == at) {
            fix_column = width as long;
        }
        if (at == end) {
            end_column = width as long;
        }
        if (b == '\t') {
            var spaces = _TAB_WIDTH - width % _TAB_WIDTH;
            shown.append(" ".repeat(spaces));
            width += spaces;
        } else {
            # A character's bytes: this one and its continuations.
            ulong size = 1;
            while (i + size < line_size and _is_continuation(text.byte_at(at + size))) {
                size += 1;
            }
            shown.append(text.substr_bytes(at, size));
            width += 1;
            i += size;
            continue;
        }
        i += 1;
    }
    var caret = caret_column < 0 ? width : caret_column as ulong;
    var last = end_column < 0 ? width : end_column as ulong;
    if (last < caret + 1) {
        last = caret + 1;
    }
    var number = $"{line_number}";
    var gutter = number.size > 5 ? number.size : 5;
    out.append($"{" ".repeat(gutter - number.size)}{number} | {shown.to_string()}\n");
    var blank = " ".repeat(gutter);
    out.append($"{blank} | {" ".repeat(caret)}^{"~".repeat(last - caret - 1)}\n");
    if (fix.is_value() and !fix.value().replacement.is_empty) {
        var column = fix_column < 0 ? width : fix_column as ulong;
        out.append($"{blank} | {" ".repeat(column)}{fix.value().replacement}\n");
    }
}

## Separates a name from the namespace of the file that declares it.
const _NAMESPACE_SEPARATOR = '@';

## Separates an overload set's name from a member's number.
const _OVERLOAD_SEPARATOR = '$';

## Returns `text` (a message) with every mangled name inside single quotes
## spelled as the user wrote it: `no member named 'x' in
## 'Box<Point@geo/shapes>'` becomes `no member named 'x' in 'Box<Point>'`.
## An apostrophe inside a word (`runtime's`) opens no quote. A name the
## message holds from two namespaces, such as a struct of two majors of one
## package, is spelled with its module (`_qualifier`), so the two differ:
## `'numbers_v1.Num'` and `'numbers_v2.Num'`.
##
## @param text the message
## @returns the message as the user reads it
export demangle(text: String): String {
    if (!text.contains("@") and !text.contains("$")) {
        return text;
    }
    var namespaces = HashMap<String, HashSet<String>>();
    _demangle(text, namespaces, false);
    return _demangle(text, namespaces, true);
}

# `demangle`'s walk over `text`. Without `write`, it records the namespaces
# each name has in `namespaces`; with it, it returns the text demangled,
# each name of several namespaces qualified.
_demangle(text: String, namespaces: HashMap<String, HashSet<String>>, write: bool): String {
    var out = StringBuilder();
    bool quoted = false;
    # The last byte written, as a name character or not.
    bool after_name = false;
    ulong i = 0;
    ulong copied = 0;
    while (i < text.size) {
        var b = text.byte_at(i);
        if (b == '\'' and (quoted or !after_name)) {
            quoted = !quoted;
        } else if (quoted and after_name and (b == _NAMESPACE_SEPARATOR or b == _OVERLOAD_SEPARATOR)) {
            ulong size = 0;
            while (i + 1 + size < text.size
                and (b == _NAMESPACE_SEPARATOR ?
                    _is_namespace_byte(text.byte_at(i + 1 + size)) :
                    _is_digit(text.byte_at(i + 1 + size)))) {
                size += 1;
            }
            if (size > 0 and b == _NAMESPACE_SEPARATOR) {
                var start = i;
                while (start > copied and _is_name_byte(text.byte_at(start - 1))) {
                    start -= 1;
                }
                var name = text.substr_bytes(start, i - start);
                var namespace = text.substr_bytes(i + 1, size);
                if (!write) {
                    if (!namespaces.contains(name)) {
                        namespaces[name] = HashSet<String>();
                    }
                    namespaces[name].insert(namespace);
                } else if (namespaces[name].count > 1) {
                    out.append(text.substr_bytes(copied, start - copied));
                    out.append(_qualifier(namespace, namespaces[name]) + ".");
                    copied = start;
                }
            }
            if (size > 0) {
                out.append(text.substr_bytes(copied, i - copied));
                i += 1 + size;
                copied = i;
                # The name before the separator is still the last thing
                # written.
                continue;
            }
        }
        after_name = _is_name_byte(b);
        i += 1;
    }
    out.append(text.substr_bytes(copied, text.size - copied));
    return out.to_string();
}

# How `demangle` qualifies a name declared in `namespace`, one of `all`:
# by its module, the namespace's first part (`numbers_v1` for
# `numbers_v1/module`), or the whole namespace, `/` spelled `.`, when
# another of `all` is in the same module.
_qualifier(namespace: String, all: HashSet<String>): String {
    var module = namespace.split("/")[0];
    for (var other in all) {
        if (other != namespace and other.split("/")[0] == module) {
            return namespace.replace("/", ".");
        }
    }
    return module;
}

_is_digit(b: byte): bool {
    return b >= '0' and b <= '9';
}

_is_name_byte(b: byte): bool {
    return _is_digit(b) or (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or b == '_';
}

_is_namespace_byte(b: byte): bool {
    return _is_name_byte(b) or b == '/' or b == '#';
}
