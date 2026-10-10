## `--emit-static`: the program's source with each `static` block replaced
## by the code it emits, Pepper's `cc -E`: `crates/pepper-driver/src/emit_static.rs`
## in Pepper.
##
## Sema records each expansion as source (`sema.StaticRecording`); this
## writes a copy of every file of the program under the entry file's
## folder (the runtime and other libraries are left where they are) into
## the output folder, mirroring the paths, so the copy builds as a whole
## program:
##
## - A block in concrete code becomes its expansion, a `{ ... }` block
##   between `# static (...) expanded from file:line:col` and
##   `# end static`.
## - A block in a generic free function expands differently for each
##   specialization, so the function stays as written and is followed by a
##   concrete override per specialization the program uses
##   (`describe<Point>(value: Point)`), with its blocks expanded.
## - A block in any other generic code (a method of a generic struct, a
##   generic method) stays, with each specialization's expansion above it
##   as `#` comments.
##
## Every other byte of a file is copied as it is. Then `pep-fmt`, when it is
## beside the compiler or on `PATH`, formats the copies.
##
## `--debug-static=expanded` writes the same copies, unformatted, beside
## the output (`write_debug_sources`), for the debug info to point at.

import compiler.ast;
import [Diagnostic, SourceText, render_all] from compiler.diagnostic;
import io;
import [Directory, File, Path] from io;
import compiler.link;
import compiler.parse;
import process;
import compiler.sema;
import [StaticExpansion, StaticRecording, substitute_names] from compiler.sema;
import "build";

## Checks `program`, recording its `static` blocks' expansions, and writes
## the expanded copies into `out_dir` (see the module documentation). With
## `keep`, each block is also kept as a `#` comment above its expansion.
##
## @param program the loaded program
## @param entry the program's entry file
## @param out_dir the folder to write the copies into
## @param keep whether to keep each block as comments
## @returns nothing, or the error, rendered
export emit_static(program: link.Program, entry: Path, out_dir: Path, keep: bool): Result<void, String> {
    var sources = program.sources();
    var expansions = check_recording(program, sources);
    if (expansions.is_err()) {
        return Result<void, String>.err(expansions.error());
    }
    var root = _root(entry);
    var by_file = _by_file(expansions.value());
    var written = Array<Path>();
    for (var index in 0..program.files.count) {
        var file = program.files[index];
        if (file.prelude or file.prelude_part) {
            continue;
        }
        var path = _absolute(Path(file.name));
        var relative = _relative(path, root);
        if (!relative.is_value()) {
            # A library outside the program's folder builds from where it is.
            continue;
        }
        var text = file.source;
        var found = by_file.try_get(index);
        if (found.is_value()) {
            var expanded = _expand_file(file.source, relative.value(), found.value(), keep);
            if (expanded.is_err()) {
                return Result<void, String>.err(expanded.error());
            }
            var (out, _) = expanded.value();
            text = out;
        }
        var target = out_dir.join(Path(relative.value()));
        if (_absolute(target).to_string() == path.to_string()) {
            return Result<void, String>.err(
                $"--emit-static would overwrite {file.name}; choose another folder with -o"
            );
        }
        var made = _write(target, text);
        if (made.is_err()) {
            return made;
        }
        written.append(target);
    }
    var formatter = process.find_companion("pep-fmt");
    if (formatter.is_value() and written.count > 0) {
        # The expansion is indented to fit; pep-fmt also wraps long lines.
        var command = process.Command(formatter.value().to_string());
        command.argument("-w");
        for (var path in written) {
            command.argument(path.to_string());
        }
        command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
        var ran = command.run();
        if (ran.is_err() or !ran.value().status.success()) {
            File.stderr().write_all(
                $"warning: {formatter.value()} could not format the expanded files; they are written unformatted\n"
            );
        }
    }
    return Result<void, String>.ok();
}

## Checks `program` with the sema passes recording its `static` blocks'
## expansions, printing the warnings.
##
## @param program the loaded program, its bodies linked
## @param sources its files' text
## @returns the expansions, or the error, rendered
export check_recording(program: link.Program, sources: SourceText[]): Result<StaticExpansion[], String> {
    var errors = program.check();
    var warnings = program.warnings();
    if (errors.is_value()) {
        report_warnings(warnings, sources);
        return Result<StaticExpansion[], String>.err(errors.value());
    }
    var built = sema.merge(program);
    if (built.is_err()) {
        report_warnings(warnings, sources);
        return Result<StaticExpansion[], String>.err(built.error());
    }
    var state = sema.PassState(program.target);
    state.sources = sources;
    state.lazy_methods = true;
    state.static_recording = Optional<StaticRecording>.Value(StaticRecording());
    var ran = sema.run_steps_with(built.value(), state, 0xffffffffffffffff);
    warnings.append_all(state.notes);
    report_warnings(warnings, sources);
    if (ran.is_err()) {
        return Result<StaticExpansion[], String>.err(render_all([ran.error()], sources));
    }
    return Result<StaticExpansion[], String>.ok(state.static_recording.value().expansions);
}

## A file `write_debug_sources` wrote: its name and text, and where each id
## of its expansions is in it, as a byte offset.
export struct DebugSource {
    var source: SourceText;
    var placed: Array<(uint, ulong)>;

    construct(source: SourceText, placed: Array<(uint, ulong)>) {
        this.source = source;
        this.placed = placed;
    }
}

## `-g --debug-static=expanded`: writes each file of `program` under the
## entry file's folder that has an expansion as `<name>.static.pep`, beside
## `output` (mirroring the folders below the entry's), as `--emit-static`
## would write it but unformatted, for the debug info to point at.
##
## @param program the program
## @param expansions the expansions sema recorded
## @param entry the program's entry file
## @param output the executable the build writes
## @returns each file written, or why one could not be
export write_debug_sources(
    program: link.Program, expansions: StaticExpansion[], entry: Path, output: Path
): Result<DebugSource[], String> {
    var root = _root(entry);
    var out = _absolute(output);
    var parent = out.parent();
    var out_dir = parent.is_value() ? parent.value() : Path(".");
    var by_file = _by_file(expansions);
    var files = Array<ulong>();
    for (var (index, _) in by_file) {
        files.append(index);
    }
    files.sort((a, b) => a < b ? -1 : (a > b ? 1 : 0));
    var written = Array<DebugSource>();
    for (var index in files) {
        if (index >= program.files.count) {
            continue;
        }
        var file = program.files[index];
        if (file.prelude or file.prelude_part) {
            continue;
        }
        var relative = _relative(_absolute(Path(file.name)), root);
        if (!relative.is_value()) {
            continue;
        }
        var expanded = _expand_file(file.source, relative.value(), by_file[index], false);
        if (expanded.is_err()) {
            return Result<DebugSource[], String>.err(expanded.error());
        }
        var (text, placed) = expanded.value();
        var name = relative.value();
        var stem = name.ends_with(".pep") ? name.substr_bytes(0, name.size - 4) : name;
        var target = out_dir.join(Path($"{stem}.static.pep"));
        var made = _write(target, text);
        if (made.is_err()) {
            return Result<DebugSource[], String>.err(made.error());
        }
        written.append(DebugSource(SourceText(target.to_string(), text), placed));
    }
    return Result<DebugSource[], String>.ok(written);
}

# The expansions of each file, by file index.
_by_file(expansions: StaticExpansion[]): HashMap<ulong, StaticExpansion[]> {
    var out = HashMap<ulong, StaticExpansion[]>();
    for (var expansion in expansions) {
        var file = expansion.loc.file as ulong;
        if (!out.contains(file)) {
            out[file] = Array<StaticExpansion>();
        }
        out[file].append(expansion);
    }
    return out;
}

# The folder the program's copied files are under: the entry file's.
_root(entry: Path): Path {
    var parent = entry.parent();
    if (parent.is_value() and !parent.value().to_string().is_empty) {
        return _absolute(parent.value());
    }
    return _absolute(Path("."));
}

# `path`, absolute and with its links resolved when it exists.
_absolute(path: Path): Path {
    var resolved = path.canonicalize();
    if (resolved.is_ok()) {
        return resolved.value();
    }
    if (path.is_relative()) {
        var cwd = process.working_directory();
        if (cwd.is_ok()) {
            return cwd.value().join(path).normalize();
        }
    }
    return path;
}

# `path` relative to `root`, with `/` between folders; none when it is not
# below `root`, or is in a `.pep` folder (a fetched dependency).
_relative(path: Path, root: Path): String? {
    var text = path.to_string().replace("\\", "/");
    var prefix = root.to_string().replace("\\", "/");
    if (!prefix.ends_with("/")) {
        prefix = prefix + "/";
    }
    if (!text.starts_with(prefix)) {
        return Optional<String>.Empty;
    }
    var relative = text.substr_bytes(prefix.size, text.size - prefix.size);
    for (var part in relative.split("/")) {
        if (part == ".pep") {
            return Optional<String>.Empty;
        }
    }
    return Optional<String>.Value(relative);
}

# Writes `text` to `target`, making its folder.
_write(target: Path, text: String): Result<void, String> {
    var parent = target.parent();
    if (parent.is_value()) {
        var created = Directory.create_all(parent.value());
        if (created.is_err()) {
            return Result<void, String>.err($"cannot create {parent.value()}: {created.error().message}");
        }
    }
    var written = File.write_text(target, text);
    if (written.is_err()) {
        return Result<void, String>.err($"cannot write {target}: {written.error().message}");
    }
    return Result<void, String>.ok();
}

# One block's expansions: a concrete block has one, with no type
# arguments; a block in generic code one per specialization.
struct _Block {
    var span: ast.Span;
    var expansions: StaticExpansion[] = Array<StaticExpansion>();

    construct(span: ast.Span) {
        this.span = span;
    }

    # Whether it is in generic code: an expansion has type arguments.
    is_generic(): bool {
        for (var expansion in expansions) {
            if (expansion.type_arguments.count > 0) {
                return true;
            }
        }
        return false;
    }
}

# A generic free function with a block, where its body ends, and its
# blocks.
struct _Override {
    var function: ast.FunctionDecl;
    var end: ulong;
    var blocks: _Block[];

    construct(function: ast.FunctionDecl, end: ulong, blocks: _Block[]) {
        this.function = function;
        this.end = end;
        this.blocks = blocks;
    }
}

# Orders type argument lists as Rust orders vectors of pairs.
_compare_arguments(a: Array<(String, String)>, b: Array<(String, String)>): int {
    var count = a.count < b.count ? a.count : b.count;
    for (var i in 0..count) {
        var (p, q) = a[i];
        var (r, s) = b[i];
        if (p != r) {
            return p < r ? -1 : 1;
        }
        if (q != s) {
            return q < s ? -1 : 1;
        }
    }
    return a.count < b.count ? -1 : (a.count > b.count ? 1 : 0);
}

# `source` with its recorded blocks expanded (see the module comment), and
# where each id of the expansions is in it. `name` is the file's path as
# the output shows it.
_expand_file(
    source: String, name: String, expansions: StaticExpansion[], keep: bool
): Result<(String, Array<(uint, ulong)>), String> {
    var blocks = Array<_Block>();
    for (var expansion in expansions) {
        var block = Optional<_Block>.Empty;
        for (var b in blocks) {
            if (b.span.start == expansion.span.start) {
                block = Optional<_Block>.Value(b);
            }
        }
        if (!block.is_value()) {
            block = Optional<_Block>.Value(_Block(expansion.span));
            blocks.append(block.value());
        }
        bool seen = false;
        for (var e in block.value().expansions) {
            seen = seen or e.same_arguments(expansion.type_arguments);
        }
        if (!seen) {
            block.value().expansions.append(expansion);
        }
    }
    blocks.sort((a, b) => a.span.start < b.span.start ? -1 : (a.span.start > b.span.start ? 1 : 0));
    for (var block in blocks) {
        block.expansions.sort((a, b) => _compare_arguments(a.type_arguments, b.type_arguments));
    }
    var parsed = parse.parse(source);
    if (parsed.is_err()) {
        return Result<(String, Array<(uint, ulong)>), String>.err($"{name}: {parsed.error().message}");
    }
    # The generic free functions with a block, and where each ends.
    var overrides = Array<_Override>();
    for (var declaration in parsed.value().declarations) {
        if (declaration is Function(function)) {
            if (function.generic_params.count == 0 or !function.body.is_value()) {
                continue;
            }
            var inside = Array<_Block>();
            for (var b in blocks) {
                if (b.span.start >= function.span.start and b.span.end <= function.span.end and b.is_generic()) {
                    inside.append(b);
                }
            }
            # A declaration's span runs on to the next one; its body ends at
            # its `}`.
            if (inside.count > 0) {
                overrides.append(_Override(function, function.body.value().span.end, inside));
            }
        }
    }
    var out = StringBuilder();
    ulong size = 0;
    var placed = Array<(uint, ulong)>();
    ulong at = 0;
    ulong pending = 0;
    for (var block in blocks) {
        # Overrides go after their generic function, before any later block.
        while (pending < overrides.count and overrides[pending].end <= block.span.start) {
            var o = overrides[pending];
            size = _append_text(out, size, source.substr_bytes(at, o.end - at));
            size = _append(out, size, placed, _specializations(source, name, o));
            at = o.end;
            pending += 1;
        }
        size = _append_text(out, size, source.substr_bytes(at, block.span.start - at));
        var indent = _line_indent(source, block.span.start);
        if (!block.is_generic()) {
            size = _append(
                out,
                size,
                placed,
                _expanded(source, name, block.span, block.expansions[0], indent, keep, Array<(String, String)>())
            );
            at = block.span.end;
        } else if (_in_overrides(overrides, block)) {
            # Expanded in the overrides; the generic function stays as
            # written.
            size = _append_text(out, size, source.substr_bytes(block.span.start, block.span.end - block.span.start));
            at = block.span.end;
        } else {
            size = _append_text(out, size, _commented(source, name, block, indent));
            at = block.span.start;
        }
    }
    while (pending < overrides.count) {
        var o = overrides[pending];
        size = _append_text(out, size, source.substr_bytes(at, o.end - at));
        size = _append(out, size, placed, _specializations(source, name, o));
        at = o.end;
        pending += 1;
    }
    out.append(source.substr_bytes(at, source.size - at));
    return Result<(String, Array<(uint, ulong)>), String>.ok((out.to_string(), placed));
}

# Whether `block` is expanded in one of `overrides`.
_in_overrides(overrides: _Override[], block: _Block): bool {
    for (var o in overrides) {
        for (var b in o.blocks) {
            if (b.span.start == block.span.start) {
                return true;
            }
        }
    }
    return false;
}

# Appends `text` to `out`, which holds `size` bytes; returns its new size.
_append_text(out: StringBuilder, size: ulong, text: String): ulong {
    out.append(text);
    return size + text.size;
}

# Appends `part`'s text to `out`, which holds `size` bytes, and the places
# in it to `placed`; returns the new size.
_append(out: StringBuilder, size: ulong, placed: Array<(uint, ulong)>, part: (String, Array<(uint, ulong)>)): ulong {
    var (text, places) = part;
    for (var (id, offset) in places) {
        placed.append((id, size + offset));
    }
    out.append(text);
    return size + text.size;
}

# The whitespace before the first non-blank character of the line `at` is
# on.
_line_indent(source: String, at: ulong): String {
    var start = (source.substr_bytes(0, at).rfind("\n") + 1) as ulong;
    var end = start;
    while (end < source.size and (source.byte_at(end) == ' ' or source.byte_at(end) == '\t')) {
        end += 1;
    }
    return source.substr_bytes(start, end - start);
}

# `file:line:col` of `at`.
_position(source: String, name: String, at: ulong): String {
    var before = source.substr_bytes(0, at);
    ulong line = 1;
    for (var i in 0..before.size) {
        if (before.byte_at(i) == '\n') {
            line += 1;
        }
    }
    var start = (before.rfind("\n") + 1) as ulong;
    var column = before.substr_bytes(start, before.size - start).length + 1;
    return $"{name}:{line}:{column}";
}

# `static (out, value)`: the block's head, as written.
_head(source: String, span: ast.Span): String {
    var text = source.substr_bytes(span.start, span.end - span.start);
    var brace = text.find("{");
    if (brace >= 0) {
        text = text.substr_bytes(0, brace as ulong);
    }
    var words = Array<String>();
    for (var word in text.replace("\t", " ").replace("\r", " ").replace("\n", " ").split(" ")) {
        if (!word.is_empty) {
            words.append(word);
        }
    }
    return " ".join(words).replace("( ", "(").replace(" )", ")");
}

# The block at `span` replaced by `expansion`'s lines, bracketed by
# comments, with lines after the first at `indent`, and where its ids are;
# with `keep`, the block as written first, as `#` comments. `label` names
# a specialization's type arguments.
_expanded(
    source: String,
    name: String,
    span: ast.Span,
    expansion: StaticExpansion,
    indent: String,
    keep: bool,
    label: Array<(String, String)>
): (String, Array<(uint, ulong)>) {
    var out = Array<String>();
    if (keep) {
        var written = source.substr_bytes(span.start, span.end - span.start).split("\n");
        for (var i in 0..written.count) {
            var line = i == 0 ? written[i] : _strip_indent(written[i], indent);
            out.append(line.trim().is_empty ? "#" : $"# {line.trim_end()}");
        }
    }
    var first = $"# {_head(source, span)} expanded from {_position(source, name, span.start)}";
    if (label.count > 0) {
        first = $"{first} for {_arguments(label)}";
    }
    out.append(first);
    var first_line = out.count;
    out.append_all(expansion.lines);
    out.append("# end static");
    var text = StringBuilder();
    ulong size = 0;
    var starts = Array<ulong>();
    for (var i in 0..out.count) {
        if (i > 0) {
            text.append("\n");
            size += 1;
        }
        starts.append(size);
        if (i > 0 and !out[i].is_empty) {
            text.append(indent);
            size += indent.size;
        }
        text.append(out[i]);
        size += out[i].size;
    }
    var placed = Array<(uint, ulong)>();
    for (var (id, line, column) in expansion.positions) {
        if (first_line + line < starts.count) {
            placed.append((id, starts[first_line + line] + indent.size + column));
        }
    }
    return (text.to_string(), placed);
}

_strip_indent(line: String, indent: String): String {
    if (line.starts_with(indent)) {
        return line.substr_bytes(indent.size, line.size - indent.size);
    }
    return line.trim_start();
}

# `T = Point, U = int`.
_arguments(type_arguments: Array<(String, String)>): String {
    var parts = Array<String>();
    for (var (param, ty) in type_arguments) {
        parts.append($"{param} = {ty}");
    }
    return ", ".join(parts);
}

# A block in generic code other than a free function: each
# specialization's expansion as `#` comments, above the block, which stays.
_commented(source: String, name: String, block: _Block, indent: String): String {
    var out = [
        $"# {_head(source, block.span)} at {_position(source, name, block.span.start)} expands in each specialization:"
    ];
    for (var expansion in block.expansions) {
        out.append($"# for {_arguments(expansion.type_arguments)}");
        for (var line in expansion.lines) {
            out.append($"# {line}");
        }
    }
    out.append("# end static");
    var text = StringBuilder();
    for (var i in 0..out.count) {
        if (i > 0) {
            text.append("\n");
            text.append(indent);
        }
        text.append(out[i]);
    }
    text.append("\n");
    text.append(indent);
    return text.to_string();
}

# After the generic function of `o`, a concrete override per
# specialization whose blocks expanded, each with its type arguments in
# place of the type parameters and its blocks expanded.
_specializations(source: String, name: String, o: _Override): (String, Array<(uint, ulong)>) {
    var function = o.function;
    # Each specialization's blocks and expansions, ordered by its type
    # arguments.
    var keys = Array<Array<(String, String)>>();
    var groups = Array<Array<(_Block, StaticExpansion)>>();
    for (var block in o.blocks) {
        for (var expansion in block.expansions) {
            long found = -1;
            for (var i in 0..keys.count) {
                if (expansion.same_arguments(keys[i])) {
                    found = i as long;
                }
            }
            if (found < 0) {
                keys.append(expansion.type_arguments);
                groups.append(Array<(_Block, StaticExpansion)>());
                found = (keys.count - 1) as long;
            }
            groups[found as ulong].append((block, expansion));
        }
    }
    var order = Array<ulong>();
    for (var i in 0..keys.count) {
        order.append(i);
    }
    order.sort((a, b) => _compare_arguments(keys[a], keys[b]));
    var params = Array<String>();
    for (var p in function.generic_params) {
        params.append(p.name);
    }
    var indent = _line_indent(source, function.name_span.start);
    var out = StringBuilder();
    ulong size = 0;
    var placed = Array<(uint, ulong)>();
    for (var k in order) {
        # Only the function's own parameters name a specialization.
        var names = Array<(String, String)>();
        for (var (param, ty) in keys[k]) {
            if (params.contains(param)) {
                names.append((param, ty));
            }
        }
        var spelled = Array<String>();
        for (var p in params) {
            for (var (param, ty) in names) {
                if (param == p) {
                    spelled.append(ty);
                }
            }
        }
        if (spelled.count != params.count) {
            continue;
        }
        # The text from the name, with `<T>` spelled `<Point>`.
        var list_start = function.name_span.end;
        var list_end = _generic_list_end(source, list_start);
        if (!list_end.is_value()) {
            continue;
        }
        var text = StringBuilder();
        ulong text_size = 0;
        text_size = _append_text(
            text,
            text_size,
            $"\n\n{indent}# '{function.name}' specialized for {_arguments(names)}, with its static blocks expanded\n{indent}"
        );
        if (function.is_exported) {
            text_size = _append_text(text, text_size, "export ");
        }
        if (function.is_private) {
            text_size = _append_text(text, text_size, "private ");
        }
        text_size = _append_text(
            text, text_size, source.substr_bytes(function.name_span.start, list_start - function.name_span.start)
        );
        text_size = _append_text(text, text_size, $"<{", ".join(spelled)}>");
        var at = list_end.value();
        var inside = groups[k].copy();
        inside.sort((a, b) => {
            var (x, _) = a;
            var (y, _) = b;
            return x.span.start < y.span.start ? -1 : (x.span.start > y.span.start ? 1 : 0);
        });
        for (var (block, expansion) in inside) {
            text_size = _append_text(text, text_size, substitute_names(source, ast.Span(at, block.span.start), names));
            var block_indent = _line_indent(source, block.span.start);
            var (block_text, places) = _expanded(source, name, block.span, expansion, block_indent, false, names);
            for (var (id, offset) in places) {
                placed.append((id, size + text_size + offset));
            }
            text_size = _append_text(text, text_size, block_text);
            at = block.span.end;
        }
        text_size = _append_text(text, text_size, substitute_names(source, ast.Span(at, o.end), names));
        size = _append_text(out, size, text.to_string());
    }
    return (out.to_string(), placed);
}

# The end of the generic parameter list `<...>` starting at `at` (after
# spaces), past its `>`.
_generic_list_end(source: String, at: ulong): ulong? {
    var start = at;
    while (start < source.size and (source.byte_at(start) == ' ' or source.byte_at(start) == '\t')) {
        start += 1;
    }
    if (start >= source.size or source.byte_at(start) != '<') {
        return Optional<ulong>.Empty;
    }
    long depth = 0;
    for (var i in start..source.size) {
        var c = source.byte_at(i);
        if (c == '<') {
            depth += 1;
        } else if (c == '>') {
            depth -= 1;
            if (depth == 0) {
                return Optional<ulong>.Value(i + 1);
            }
        }
    }
    return Optional<ulong>.Empty;
}
