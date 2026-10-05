# The standard library reference: one Markdown page per runtime file,
# generated from its `##` doc comments (see `doc.pep`).
#
# A page lists the file's public declarations (exported, not
# `_`-prefixed) in source order, each with its signature as written and
# its doc comment; a struct or trait lists its public fields, constructor,
# and methods below it. A `##` block at the very top of a file, followed by
# a blank line, introduces the page.

import compiler.ast;
import [Declaration, FunctionDecl, Import, Module, PropertyDecl, VariableDecl] from compiler.ast;
import [Diagnostic, Location, SourceText] from compiler.diagnostic;
import [
    DocComment,
    built_in_name,
    doc_comment_before,
    doc_comment_of,
    file_doc,
    first_attribute,
    is_caller_location,
    is_public,
    is_public_member,
    member_name
] from compiler.doc;
import [Directory, File, Path] from io;
import compiler.parse;
import "strings";

# Page titles for the runtime files, in the order the reference lists
# them. Every runtime file that gets a page must be named here: `generate`
# fails on one that is not, so a new file cannot land at the end of the
# list under whatever module happens to come last. A module's files follow
# its `module.pep`, which the summary nests them under.
export pages(): Array<(String, String)> {
    return [
        ("internals.pep", "Built-in functions"),
        ("attributes.pep", "Built-in attributes"),
        ("reflect.pep", "The reflect module (compile time)"),
        ("builtins.pep", "Compiler built-ins"),
        ("process.pep", "Arguments and exit (deprecated)"),
        ("string.pep", "String"),
        ("number.pep", "Numbers"),
        ("range.pep", "Ranges"),
        ("array.pep", "Array"),
        ("hash.pep", "HashMap and HashSet"),
        ("map.pep", "Map and Set"),
        ("ordered_map.pep", "OrderedMap"),
        ("iterator.pep", "Iterators"),
        ("scoped.pep", "Scoped"),
        ("weak.pep", "Weak"),
        ("handle.pep", "Handle"),
        ("result.pep", "Result"),
        ("optional.pep", "Optional"),
        ("copy.pep", "Copying"),
        ("uri.pep", "URI"),
        ("expect.pep", "Test checks"),
        ("io/module.pep", "The io module"),
        ("io/types.pep", "Errors and platform types"),
        ("io/stream.pep", "Reader and Writer"),
        ("io/path.pep", "Path"),
        ("io/file.pep", "File"),
        ("io/directory.pep", "Directory"),
        ("io/address.pep", "Network addresses"),
        ("io/socket.pep", "Sockets"),
        ("io/unix.pep", "Unix domain sockets"),
        ("io/memory.pep", "Streams in memory"),
        ("io/print.pep", "Print"),
        ("async/module.pep", "The async module"),
        ("async/atomic.pep", "Atomic"),
        ("async/thread.pep", "Thread"),
        ("async/thread_local.pep", "ThreadLocal"),
        ("async/mutex.pep", "Mutex and Condition"),
        ("async/coordination.pep", "Semaphore, Barrier and Latch"),
        ("async/rwlock.pep", "RwLock"),
        ("async/once.pep", "Once and Lazy"),
        ("async/channel.pep", "Channel"),
        ("async/select.pep", "Select"),
        ("async/cpus.pep", "Processor counts"),
        ("async/task.pep", "Tasks"),
        ("async/task_local.pep", "TaskLocal"),
        ("async/driver.pep", "I/O backends"),
        ("process/module.pep", "The process module"),
        ("process/command.pep", "Command"),
        ("process/child.pep", "Child"),
        ("process/current.pep", "The running process"),
        ("process/find.pep", "Finding programs"),
        ("os/module.pep", "The os module"),
        ("os/environment.pep", "Environment"),
        ("os/time.pep", "Time"),
        ("os/machine.pep", "Machine"),
        ("os/user.pep", "User"),
        ("time/module.pep", "The time module"),
        ("time/civil.pep", "Dates and times"),
        ("time/offset.pep", "Offsets"),
        ("time/zone.pep", "Time zones"),
        ("math/module.pep", "The math module"),
        ("math/parse.pep", "Parsing integers"),
        ("hint/module.pep", "The hint module"),
        ("simd/module.pep", "The simd module"),
        ("debug/module.pep", "The debug module"),
        ("debug/backtrace.pep", "Backtraces"),
        ("debug/debugger.pep", "The debugger"),
        ("text/module.pep", "The text module"),
        ("text/utf8.pep", "UTF-8"),
        ("text/utf16.pep", "UTF-16"),
        ("text/ascii.pep", "ASCII"),
        ("text/code_page_437.pep", "Code page 437"),
        ("regex/module.pep", "The regex module"),
        ("regex/regex.pep", "Regex and Match"),
        ("json/module.pep", "The json module"),
        ("json/value.pep", "JsonValue"),
        ("json/parse.pep", "Parsing"),
        ("json/document.pep", "Documents with comments"),
        ("json/convert.pep", "Struct conversion"),
        ("serialize/module.pep", "The serialize module"),
        ("toml/module.pep", "The toml module"),
        ("toml/value.pep", "TomlValue"),
        ("toml/parse.pep", "Parsing"),
        ("toml/write.pep", "Writing"),
        ("toml/document.pep", "Documents with comments"),
        ("toml/convert.pep", "Struct conversion"),
        ("compress/module.pep", "The compress module"),
        ("compress/format.pep", "Formats and streams"),
        ("compress/checksum.pep", "Checksums"),
        ("archive/module.pep", "The archive module"),
        ("archive/tar.pep", "Tar archives"),
        ("archive/path.pep", "Entry paths"),
        ("digest/module.pep", "The digest module"),
        ("digest/sha256.pep", "SHA-256"),
        ("digest/sha1.pep", "SHA-1"),
        ("digest/blake3.pep", "BLAKE3"),
        ("digest/hex.pep", "Hexadecimal"),
        ("cli/module.pep", "The cli module"),
        ("cli/parser.pep", "Parser"),
        ("cli/options.pep", "Options"),
        ("cli/completions.pep", "Completions"),
        ("http/module.pep", "The http module"),
        ("http/message.pep", "Requests and responses"),
        ("http/client.pep", "Client"),
        ("http/server.pep", "Server"),
        ("tls/module.pep", "The tls module"),
        ("tls/stream.pep", "Connectors and streams"),
        ("testing/module.pep", "The testing module"),
        ("testing/runner.pep", "TestRunner"),
        ("testing/temp_folder.pep", "TempFolder")
    ];
}

# The command that regenerates the reference, named in each page's header.
export const REGENERATE = "pep-doc reference";

# A generated page: its path under `reference/`, its title and its
# Markdown.
export struct Page {
    var file: String = "";
    var title: String = "";
    var markdown: String = "";

    construct(file: String, title: String, markdown: String) {
        this.file = file;
        this.title = title;
        this.markdown = markdown;
    }
}

# Every `.pep` file under `dir`, as paths relative to it with `/`
# separators. Tests (`test/` folders, which are not part of any module)
# and hidden folders such as `.pep/` are left out.
export pep_files(dir: Path, prefix: String, out: String[]): Result<void> {
    var listing = Directory.open(dir);
    if (listing.is_err()) {
        return Result<void>.Err($"cannot read {dir.to_string()}: {listing.error().message}");
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return Result<void>.Err($"cannot read {dir.to_string()}: {entries.error().message}");
    }
    for (var entry in entries.value()) {
        if (entry.is_directory) {
            if (entry.name == "test" or entry.name.starts_with(".")) {
                continue;
            }
            pep_files(entry.path, $"{prefix}{entry.name}/", out)?;
        } else if (entry.name.ends_with(".pep")) {
            out.append(prefix + entry.name);
        }
    }
    return Result<void>.ok();
}

# The position of `file` in `pages()`, or past the end for a file not
# named there.
_rank(titles: Array<(String, String)>, file: String): ulong {
    ulong i = 0;
    for (var (name, _) in titles) {
        if (name == file) {
            return i;
        }
        i += 1;
    }
    return titles.count;
}

# The title `pages()` gives `file`.
_title_of(titles: Array<(String, String)>, file: String): String? {
    for (var (name, title) in titles) {
        if (name == file) {
            return Optional<String>.Value(title);
        }
    }
    return Optional<String>.Empty;
}

# Parses the source file `name`, reporting an error as `name:line:col:
# error: message`.
export parse_file(name: String, source: String): Result<Module> {
    var parsed = parse.parse(source);
    if (parsed.is_err()) {
        var error = parsed.error();
        var diagnostic = Diagnostic.error(error.message).at(Location(0, error.span));
        return Result<Module>.Err(diagnostic.render([SourceText(name, source)]));
    }
    return Result<Module>.ok(parsed.value());
}

# The reference pages for the runtime in `runtime_dir`, in reading order.
# Files with nothing public and no introduction get no page.
export generate(runtime_dir: Path): Result<Page[]> {
    var files = Array<String>();
    pep_files(runtime_dir, "", files)?;
    var titles = pages();
    files.sort((a, b) => {
        var rank_a = _rank(titles, a);
        var rank_b = _rank(titles, b);
        if (rank_a != rank_b) {
            return rank_a < rank_b ? -1 : 1;
        }
        return a.compare(b);
    });
    var out = Array<Page>();
    for (var file in files) {
        var path = runtime_dir.join(file);
        var read = File.read_to_string(path);
        if (read.is_err()) {
            return Result<Page[]>.Err($"cannot read {path.to_string()}: {read.error().message}");
        }
        var source = read.value();
        var module = parse_file($"runtime/{file}", source)?;
        var body = "".join([reexports(module, file), page_body(module, source)]);
        var intro = file_doc(source);
        if (body.is_empty and intro.is_empty()) {
            continue;
        }
        var title = _title_of(titles, file);
        if (title.is_empty()) {
            return Result<Page[]>.Err(
                $"runtime/{file} has public declarations but no reference page; give it a title and a place in pages() in tools/pep-doc/reference.pep"
            );
        }
        var markdown = StringBuilder();
        markdown.append(
            $"<!-- Generated from runtime/{file} by `{REGENERATE}`. Do not edit. -->\n\n# {title.value()}\n\n"
        );
        if (intro.is_value()) {
            markdown.append(intro.value().to_markdown());
            markdown.append("\n\n");
        }
        markdown.append($"Source: `runtime/{file}`\n");
        markdown.append(body);
        var page_file = file.substr_bytes(0, file.size - 4).replace("/", "-") + ".md";
        out.append(Page(page_file, title.value(), markdown.to_string()));
    }
    out.insert(0, _prelude_page(out));
    return Result<Page[]>.ok(out);
}

# The page every prelude page nests under: the runtime files outside any
# module, which every program gets without an import.
const PRELUDE_PAGE = "prelude.md";

# The first sentence of a page's prose: its introduction, else the
# description of its first declaration.
export first_sentence(markdown: String): String {
    bool in_code = false;
    var paragraph = Array<String>();
    for (var line in markdown.lines()) {
        if (line.starts_with("```")) {
            in_code = !in_code;
            continue;
        }
        bool skip = in_code or line.starts_with("#") or line.starts_with("<!--") or line.starts_with("Source:");
        if (skip or line.trim().is_empty) {
            if (!paragraph.is_empty) {
                break;
            }
            continue;
        }
        paragraph.append(line.trim());
    }
    var text = " ".join(paragraph);
    # The first ". " outside a code span ends the sentence.
    in_code = false;
    for (var i in 0..text.size) {
        var b = text.byte_at(i);
        if (b == '`') {
            in_code = !in_code;
        } else if (b == '.' and !in_code and i + 1 < text.size and text.byte_at(i + 1) == ' ') {
            return slice(text, 0, i + 1);
        }
    }
    return text;
}

# The prelude's page: what it is, and a line per page in it.
_prelude_page(found: Page[]): Page {
    var markdown = StringBuilder();
    markdown.append($"<!-- Generated by `{REGENERATE}`. Do not edit. -->\n\n# The prelude\n\n");
    markdown.append(
        "The prelude is the part of the standard library every program gets without an import: the files at the top of "
    );
    markdown.append("`runtime/`. Each module after it (`io`, `async`, `json`, ...) is brought in with an import.\n\n");
    for (var page in found) {
        if (!page.file.contains("-")) {
            markdown.append($"- [{page.title}]({page.file}): {first_sentence(page.markdown)}\n");
        }
    }
    return Page(PRELUDE_PAGE, "The prelude", markdown.to_string());
}

# The source of a declaration from `start` up to `end`, as one line,
# without `export`.
export signature(source: String, start: ulong, end: ulong): String {
    var text = one_line(slice(source, start, end));
    var size = text.size;
    while (size > 0
        and (text.byte_at(size - 1) == '{' or text.byte_at(size - 1) == ';' or text.byte_at(size - 1) == ' ')) {
        size -= 1;
    }
    # `[Attr] export x` and `export x` read as `[Attr] x`.
    return replace_first(text.substr_bytes(0, size), "export ", "");
}

# The signature of function `f`, leaving out the parameters the compiler
# fills in (`location: __ptr<char> = __caller_location()`): callers never
# pass them. Each goes with the `, ` before it, or the one after it when
# it comes first.
export function_signature(source: String, f: FunctionDecl): String {
    var start = first_attribute(f.attributes, f.span.start);
    var end = _function_end(source, f);
    if (end < start) {
        end = start;
    }
    var text = StringBuilder();
    var from = start;
    ulong index = 0;
    for (var p in f.parameters) {
        var first = index == 0;
        index += 1;
        if (!is_caller_location(p)) {
            continue;
        }
        var (cut_start, cut_end) = first ? _cut_first(source, p, end) : _cut_later(source, p);
        if (cut_start < from or cut_end > end) {
            continue;
        }
        text.append(slice(source, from, cut_start));
        from = cut_end;
    }
    text.append(slice(source, from, end));
    var written = text.to_string();
    return signature(written, 0, written.size);
}

# Where the signature of `f` ends: at its body, or at the `;` of a
# declaration without one (a trait method, an extern), whose span may run
# on over trivia.
_function_end(source: String, f: FunctionDecl): ulong {
    if (f.body.is_value()) {
        return f.body.value().span.start;
    }
    var semicolon = find_byte(source, ';', f.name_span.end, f.span.end);
    return semicolon < f.span.end ? semicolon : f.span.end;
}

# The text a later caller-location parameter `p` takes with it: from the
# `,` before it.
_cut_later(source: String, p: VariableDecl): (ulong, ulong) {
    var comma = slice(source, 0, p.span.start).rfind(",");
    return (comma < 0 ? p.span.start : comma as ulong, p.span.end);
}

# The text a first caller-location parameter `p` takes with it: the `, `
# after it, when one follows before `end`.
_cut_first(source: String, p: VariableDecl, end: ulong): (ulong, ulong) {
    var after = p.span.end;
    while (after < end and (source.byte_at(after) == ',' or is_ascii_space(source.byte_at(after)))) {
        after += 1;
    }
    if (after == end) {
        after = p.span.end;
    }
    if (!slice(source, p.span.end, after).contains(",")) {
        after = p.span.end;
    }
    return (p.span.start, after);
}

# The heading and anchor text for a member: operators and indexers read
# as `operator ==`, `indexer []`.
export member_title(name: String): String {
    if (!name.is_empty) {
        var b = name.byte_at(0);
        if ((b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or b == '_' or b >= 128) {
            return name;
        }
    }
    return $"operator {name}";
}

_entry(out: StringBuilder, level: ulong, title: String, signature: String, doc: DocComment?) {
    out.append($"\n{"#".repeat(level)} {title}\n\n```pepper\n{signature}\n```\n");
    if (doc.is_empty()) {
        return;
    }
    var markdown = doc.value().to_markdown();
    if (!markdown.is_empty) {
        out.append("\n");
        out.append(markdown);
        out.append("\n");
    }
}

_field(out: StringBuilder, source: String, v: VariableDecl) {
    _entry(out, 4, v.name, signature(source, v.span.start, v.span.end), doc_comment_before(source, v.span.start));
}

_method(out: StringBuilder, source: String, owner: String, f: FunctionDecl) {
    var doc = doc_comment_before(source, first_attribute(f.attributes, f.span.start));
    var title = f.name == "new" or f.name == "construct" ? $"{owner}()" : member_title(member_name(f));
    _entry(out, 4, title, function_signature(source, f), doc);
}

# A property's entry: its declaration with the accessors' bodies left out
# (`var count: ulong { get; }`).
_property(out: StringBuilder, source: String, p: PropertyDecl) {
    var doc = doc_comment_before(source, p.span.start);
    var accessors = Array<String>();
    if (p.getter.is_value()) {
        accessors.append("get;");
    }
    if (p.setter.is_value()) {
        accessors.append("set;");
    }
    var span = p.type_name.span;
    var type_text = span.start <= span.end and span.end <= source.size ?
        slice(source, span.start, span.end) :
        p.type_name.to_string();
    _entry(out, 4, p.name, $"var {p.name}: {type_text} {{ {" ".join(accessors)} }}", doc);
}

_members(
    out: StringBuilder,
    source: String,
    owner: String,
    fields: VariableDecl[],
    properties: PropertyDecl[],
    constructors: FunctionDecl[],
    methods: FunctionDecl[]
) {
    var public_fields = Array<VariableDecl>();
    for (var f in fields) {
        if (is_public(f.name)) {
            public_fields.append(f);
        }
    }
    if (!public_fields.is_empty) {
        out.append("\n### Fields\n");
        for (var f in public_fields) {
            _field(out, source, f);
        }
    }
    var public_properties = Array<PropertyDecl>();
    for (var p in properties) {
        if (is_public(p.name)) {
            public_properties.append(p);
        }
    }
    if (!public_properties.is_empty) {
        out.append("\n### Properties\n");
        for (var p in public_properties) {
            _property(out, source, p);
        }
    }
    if (!constructors.is_empty) {
        out.append(constructors.count == 1 ? "\n### Constructor\n" : "\n### Constructors\n");
        for (var c in constructors) {
            _method(out, source, owner, c);
        }
    }
    var statics = Array<FunctionDecl>();
    var instance = Array<FunctionDecl>();
    for (var m in methods) {
        if (!is_public_member(m)) {
            continue;
        }
        if (m.is_static) {
            statics.append(m);
        } else {
            instance.append(m);
        }
    }
    if (!statics.is_empty) {
        out.append("\n### Static methods\n");
        for (var m in statics) {
            _method(out, source, owner, m);
        }
    }
    if (!instance.is_empty) {
        out.append("\n### Methods\n");
        for (var m in instance) {
            _method(out, source, owner, m);
        }
    }
}

# The page of the file or module an `export ... from` names, relative to
# the runtime file `file`: `io-types.md` for `"types"` in `io/module.pep`,
# `async-module.md` for the module `async`.
export source_page(file: String, imported: Import): String {
    if (!imported.is_local) {
        return $"{imported.name}-module.md";
    }
    var slash = file.rfind("/");
    var dir = slash < 0 ? "" : slice(file, 0, slash as ulong + 1);
    return $"{dir}{imported.stem()}.md".replace("/", "-");
}

# A "Re-exports" section listing the file's `export * from` and `export
# [...] from` lines, each linking to the page of the file or module that
# declares the names. Empty without any.
export reexports(module: Module, file: String): String {
    var out = StringBuilder();
    bool any = false;
    for (var imported in module.imports) {
        if (!imported.reexport) {
            continue;
        }
        any = true;
        var source = imported.is_local ? $"`{imported.stem()}.pep`" : $"the `{imported.name}` module";
        var link = $"[{source}]({source_page(file, imported)})";
        if (imported.symbols.is_empty()) {
            out.append($"- Everything {link} exports.\n");
            continue;
        }
        for (var symbol in imported.symbols.value()) {
            var named = symbol.alias.is_value() ? $"`{symbol.name}` (as `{symbol.alias.value()}`)" : $"`{symbol.name}`";
            out.append($"- {named} from {link}.\n");
        }
    }
    if (!any) {
        return "";
    }
    return "\n## Re-exports\n\n" + out.to_string();
}

# `signature` of a `[__BuiltIn]` declaration named `name`, which declares
# the built-in `built_in`: without the attribute, and with the built-in's
# name in place of its own (`reflect.name<T>(): String`).
export built_in_signature(signature: String, name: String, built_in: String): String {
    var text = signature;
    var start = text.find($"[{ast.BUILT_IN_ATTRIBUTE}");
    if (start >= 0) {
        var from = start as ulong;
        var close = find_byte(text, ']', from, text.size);
        var end = skip_spaces(text, close < text.size ? close + 1 : text.size, text.size);
        text = "".join([slice(text, 0, from), slice_from(text, end)]);
    }
    ulong at = 0;
    while (true) {
        var found = text.find(name, at);
        if (found < 0) {
            break;
        }
        var i = found as ulong;
        var after = i + name.size;
        bool word_before = i > 0 and _is_word_char(text.byte_at(i - 1));
        bool word_after = after < text.size and _is_word_char(text.byte_at(after));
        if (!word_before and !word_after) {
            return "".join([slice(text, 0, i), built_in, slice_from(text, after)]);
        }
        at = after;
    }
    return text;
}

# A byte of a word: a letter, a digit, `_`, or part of a non-ASCII
# character.
_is_word_char(b: byte): bool {
    return is_word_byte(b) or b >= 128;
}

# The entries of every public declaration of `module`.
export page_body(module: Module, source: String): String {
    var out = StringBuilder();
    for (var decl in module.declarations) {
        if (!decl.is_exported()) {
            continue;
        }
        var doc = doc_comment_of(source, decl);
        var start = first_attribute(decl.attributes(), decl.span().start);
        # A `[__BuiltIn]` declaration is public whatever its name (`__ptr`),
        # and reads as the built-in it declares.
        var built_in = built_in_name(decl.attributes(), decl.declared_name());
        var title = built_in.is_value() ? built_in.value() : decl.declared_name();
        if (!built_in.is_value() and !is_public(decl.declared_name()) and !_is_extension(decl)) {
            continue;
        }
        match (decl) {
            Function(f) => {
                _entry(out, 2, title, _shown(built_in, function_signature(source, f), f.name), doc);
            }
            Struct(s) => {
                var end = _brace_after(source, s.name_span.end, s.span.end);
                _entry(out, 2, title, _shown(built_in, signature(source, start, end), s.name), doc);
                if (s.enumeration.is_value() and !s.enumeration.value().cases.is_empty) {
                    out.append("\n### Cases\n");
                    for (var c in s.enumeration.value().cases) {
                        var case_start = first_attribute(c.attributes, c.span.start);
                        _entry(
                            out,
                            4,
                            c.name,
                            signature(source, case_start, c.span.end),
                            doc_comment_before(source, case_start)
                        );
                    }
                }
                _members(out, source, s.name, s.fields, s.properties, s.constructors, s.methods);
            }
            Trait(t) => {
                var end = _brace_after(source, t.name_span.end, t.span.end);
                _entry(out, 2, title, _shown(built_in, signature(source, start, end), t.name), doc);
                _members(out, source, t.name, Array<VariableDecl>(), t.properties, Array<FunctionDecl>(), t.methods);
            }
            Extend(e) => {
                var end = _brace_after(source, e.target.span.end, e.span.end);
                _entry(out, 2, $"extend {e.target.to_string()}", signature(source, start, end), doc);
                _members(
                    out, source, e.target.name, Array<VariableDecl>(), e.properties, Array<FunctionDecl>(), e.methods
                );
            }
            TypeAlias(t) => {
                _entry(out, 2, title, _shown(built_in, signature(source, start, t.span.end), t.name), doc);
            }
            Variable(v) => {
                _entry(out, 2, title, _shown(built_in, signature(source, start, v.span.end), v.name), doc);
            }
            else => {}
        }
    }
    return out.to_string();
}

_is_extension(decl: Declaration): bool {
    if (decl is Extend(_)) {
        return true;
    }
    return false;
}

# The signature as the reference shows it: a built-in's with its own name.
_shown(built_in: String?, signature: String, name: String): String {
    return built_in.is_value() ? built_in_signature(signature, name, built_in.value()) : signature;
}

# The offset of the first `{` from `from`, or `fallback` when there is
# none.
_brace_after(source: String, from: ulong, fallback: ulong): ulong {
    var brace = find_byte(source, '{', from, source.size);
    return brace < source.size ? brace : fallback;
}

# The reference's part of `SUMMARY.md`: a line per page, nested under
# `reference/README.md`.
export summary_lines(found: Page[]): String {
    var out = StringBuilder();
    for (var p in found) {
        # A module's other files (`io-path.md`) nest under its `module.pep`
        # page (`io-module.md`); the prelude's files (`string.md`) nest
        # under its page.
        var dash = p.file.find("-");
        bool nested = p.file != PRELUDE_PAGE;
        if (dash >= 0) {
            var module_page = slice(p.file, 0, dash as ulong) + "-module.md";
            nested = p.file != module_page and _has_page(found, module_page);
        }
        out.append($"{nested ? "    " : "  "}- [{p.title}](reference/{p.file})\n");
    }
    return out.to_string();
}

_has_page(found: Page[], file: String): bool {
    for (var p in found) {
        if (p.file == file) {
            return true;
        }
    }
    return false;
}

const SUMMARY_START = "<!-- reference:start -->";
const SUMMARY_END = "<!-- reference:end -->";

# `summary` with the text between the reference markers replaced by the
# page list.
export update_summary(summary: String, found: Page[]): Result<String> {
    var start = summary.find(SUMMARY_START);
    if (start < 0) {
        return Result<String>.Err("SUMMARY.md has no reference:start marker");
    }
    var end = summary.find(SUMMARY_END);
    if (end < 0) {
        return Result<String>.Err("SUMMARY.md has no reference:end marker");
    }
    var head = slice(summary, 0, start as ulong + SUMMARY_START.size);
    return Result<String>.ok($"{head}\n{summary_lines(found)}{slice_from(summary, end as ulong)}");
}

# Writes `text` to `path` unless it holds that already, adding the path to
# `changed` when it writes.
_put(path: Path, text: String, changed: Path[]): Result<void> {
    var current = File.read_to_string(path);
    if (current.is_ok() and current.value() == text) {
        return Result<void>.ok();
    }
    var written = File.write_text(path, text);
    if (written.is_err()) {
        return Result<void>.Err($"cannot write {path.to_string()}: {written.error().message}");
    }
    changed.append(path);
    return Result<void>.ok();
}

# Writes the pages into `docs/src/reference/` (removing stale generated
# pages) and their list into `SUMMARY.md`. Returns the files that changed.
export write(docs_dir: Path, found: Page[]): Result<Path[]> {
    var dir = docs_dir.join("src").join("reference");
    var created = Directory.create_all(dir);
    if (created.is_err()) {
        return Result<Path[]>.Err($"cannot create {dir.to_string()}: {created.error().message}");
    }
    var changed = Array<Path>();
    for (var page in found) {
        _put(dir.join(page.file), page.markdown, changed)?;
    }
    # A page whose runtime file is gone.
    var listing = Directory.open(dir);
    if (listing.is_err()) {
        return Result<Path[]>.Err($"cannot read {dir.to_string()}: {listing.error().message}");
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return Result<Path[]>.Err($"cannot read {dir.to_string()}: {entries.error().message}");
    }
    for (var entry in entries.value()) {
        if (entry.name == "README.md" or !entry.name.ends_with(".md") or _has_page(found, entry.name)) {
            continue;
        }
        var text = File.read_to_string(entry.path);
        if (text.is_err() or !text.value().starts_with("<!-- Generated from runtime/")) {
            continue;
        }
        var removed = File.remove(entry.path);
        if (removed.is_err()) {
            return Result<Path[]>.Err($"cannot remove {entry.path.to_string()}: {removed.error().message}");
        }
        changed.append(entry.path);
    }
    var summary_path = docs_dir.join("src").join("SUMMARY.md");
    var summary = File.read_to_string(summary_path);
    if (summary.is_err()) {
        return Result<Path[]>.Err($"cannot read {summary_path.to_string()}: {summary.error().message}");
    }
    _put(summary_path, update_summary(summary.value(), found)?, changed)?;
    return Result<Path[]>.ok(changed);
}
