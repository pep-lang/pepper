# Analyzing a document: parsing it, loading the program it is the root of
# (the runtime and every file its imports reach), and checking that
# program with the compiler's front end, into the diagnostics the editor
# shows.
#
# Analysis takes from a fraction of a second to seconds, so it runs on a
# thread of its own (`analyze_documents`): edits keep arriving, and requests
# keep being answered, while it runs. Each finished analysis goes back to
# the server's thread, which answers hover and go-to-definition from the
# program and model it holds.

import compiler.ast;
import async;
import [Channel] from async;
import io;
import [Directory, File, Path] from io;
import os;
import process;

import [demangle, Diagnostic, DEPRECATED_CODE, Severity] from compiler.diagnostic;
import compiler.incremental;
import compiler.link;
import lsp;
import compiler.parse;
import compiler.sema;
import "actions";
import "platforms";

## How long a document's text must stay unchanged before it is analyzed,
## so typing does not start an analysis per keystroke.
export const SETTLE_MILLISECONDS: ulong = 250;

## Work for the analysis thread.
export enum Job {
    ## Analyze `text`, the text of document `uri`, after it settles.
    Analyze(uri: String, text: String),
    ## The document closed: drop its pending analysis.
    Close(uri: String),
    ## Analyze with these build options (`-D`), by name, from now on.
    Configure(build_options: HashMap<String, String>),
    ## Stop the thread.
    Stop,
}

## Runs on the analysis thread: takes jobs from `jobs` until `Stop` or the
## channel closes, publishes each analyzed document's diagnostics through
## `client`, and hands the analysis to the server's thread through
## `results`, waking it. A document edited again before its turn, or while
## it was analyzed, is analyzed once more instead of publishing stale
## diagnostics.
##
## @param jobs the documents to analyze, newest text last
## @param results where finished analyses go
## @param client where the diagnostics go
export analyze_documents(jobs: Channel<Job>, results: Channel<Analysis>, client: lsp.Client) {
    # The newest text of each document waiting for analysis, by URI.
    var pending = HashMap<String, String>();
    var order = Array<String>();
    var build_options = HashMap<String, String>();
    while (true) {
        # Wait for work, then for the edits to settle.
        var job = order.count == 0 ? jobs.receive() : jobs.receive_for(SETTLE_MILLISECONDS);
        if (job.is_ok()) {
            match (job.value()) {
                Analyze(uri, text) => {
                    if (!pending.contains(uri)) {
                        order.append(uri);
                    }
                    pending[uri] = text;
                }
                Close(uri) => {
                    pending.remove(uri);
                }
                Configure(options) => {
                    build_options.clear();
                    for (var (name, value) in options) {
                        build_options[name] = value;
                    }
                }
                Stop => {
                    return;
                }
            }
            continue;
        }
        if (order.count == 0) {
            # The channel closed with nothing left to do.
            return;
        }
        var uri = order[0];
        order.remove_at(0);
        var text = pending.try_get(uri);
        if (text.is_empty()) {
            continue;
        }
        pending.remove(uri);
        var start = os.Instant.now();
        # Copies, so the analysis shares nothing with `pending` and can move
        # to the server's thread.
        var analysis = analyze(copy(uri), copy(text.value()), build_options, workers = true);
        var took = (os.Instant.now() - start).nanoseconds() / 1000000;
        # Edited or closed meanwhile: what was found is about old text.
        var newer = _take_jobs(jobs, pending, order, build_options);
        if (newer.is_value()) {
            return;
        }
        if (pending.contains(uri)) {
            continue;
        }
        # A file analyzed for another OS than the build target's says so.
        var as_os = analysis.os == link.Target().os ? "" : " as " + analysis.os;
        client.log_message(
            lsp.MESSAGE_LOG,
            $"analyzed {_file_name(uri)}{as_os} ({analysis.files} files): {analysis.outcome} in {took} ms"
        );
        client.publish_diagnostics(analysis.uri, analysis.diagnostics);
        results.send(copy(analysis));
        client.wake();
    }
}

# Takes the jobs waiting in `jobs` without waiting: Value(true) when one
# was `Stop`.
_take_jobs(
    jobs: Channel<Job>, pending: HashMap<String, String>, order: String[], build_options: HashMap<String, String>
): bool? {
    while (true) {
        var job = jobs.try_receive();
        if (job.is_err()) {
            return Optional<bool>.Empty;
        }
        match (job.value()) {
            Analyze(uri, text) => {
                if (!pending.contains(uri)) {
                    order.append(uri);
                }
                pending[uri] = text;
            }
            Close(uri) => {
                pending.remove(uri);
            }
            Configure(options) => {
                build_options.clear();
                for (var (name, value) in options) {
                    build_options[name] = value;
                }
            }
            Stop => {
                return Optional<bool>.Value(true);
            }
        }
    }
    return Optional<bool>.Empty;
}

# The last segment of a URI, for the log.
_file_name(uri: String): String {
    var slash = uri.rfind("/");
    return slash < 0 ? uri : uri.substr_bytes(slash as ulong + 1, uri.size - slash as ulong - 1);
}

## What analyzing a document found.
export struct Analysis {
    ## The document.
    var uri: String;
    ## The text analyzed.
    var text: String;
    ## The program rooted at the document, when it loaded.
    var program: link.Program?;
    ## The checked model, when the program passed sema.
    var model: sema.Module?;
    ## What sema's passes recorded, with `model`.
    var state: sema.PassState?;
    ## The document's diagnostics, for `publishDiagnostics`.
    var diagnostics: Array<lsp.Diagnostic>;
    ## The quick fixes those diagnostics suggest.
    var actions: Array<lsp.CodeAction>;
    ## The OS it was analyzed for: the build target's, or the one whose
    ## code the document mostly is (`analysis_os`).
    var os: String;
    ## How many files its program has; 0 when it did not load.
    var files: ulong;
    ## How it went, for the log: "passed", "found an error", "did not
    ## load" or "did not parse".
    var outcome: String;

    construct(uri: String, text: String) {
        this.uri = uri;
        this.text = text;
        this.program = Optional<link.Program>.Empty;
        this.model = Optional<sema.Module>.Empty;
        this.state = Optional<sema.PassState>.Empty;
        this.diagnostics = Array<lsp.Diagnostic>();
        this.actions = Array<lsp.CodeAction>();
        this.os = "";
        this.files = 0;
        this.outcome = "did not load";
    }
}

# The diagnostic of a parse error, with the `{` a missing `}` should
# close as related information.
_parse_diagnostic(document: lsp.TextDocument, error: parse.ParseError): lsp.Diagnostic {
    var out = lsp.Diagnostic(document.range_of(error.span.start, error.span.end), error.message);
    if (error.related is Value(span)) {
        var info = lsp.DiagnosticRelatedInformation();
        info.location = lsp.Location(document.uri, document.range_of(span.start, span.end));
        info.message = error.related_message;
        out.related_information = Optional<Array<lsp.DiagnosticRelatedInformation>>.Value([info]);
    }
    return out;
}

## Analyzes `text`, the text of document `uri`: its syntax errors (all of
## them, `parse.parse_recovering`) or deprecated syntax, then, when `uri`
## names a file, the errors of the program rooted at it (unresolved
## imports, linking and visibility errors, then the first error type
## checking finds) and its warnings, all as they apply to the document.
##
## The program is checked one compilation unit at a time, as `pepc` builds it
## (`incremental.check_compilation_units`): the build cache in the project's
## `.pep` folder keeps each compilation unit's checked record, so only the
## document's own compilation unit, and any compilation unit whose files or
## interfaces below changed, is checked again; the rest load, and their bodies
## are not even read.
##
## @param uri the document
## @param text its current text, which may differ from the file on disk
## @param build_options the build options (`-D`) to analyze with, by name
## @param workers whether compilation units the cache lacks may be checked in
##   `--compilation-unit-worker` children of this executable: only when it is
##   pep-lsp
## @returns the diagnostics and how the analysis went
export analyze(
    uri: String, text: String, build_options: HashMap<String, String> = HashMap<String, String>(), workers: bool = false
): Analysis {
    var out = Analysis(uri, text);
    var document = lsp.TextDocument(uri, text);
    # Every error, read past each one, so that all show at once.
    var recovered = parse.parse_recovering(text);
    if (!recovered.errors.is_empty) {
        for (var error in recovered.errors) {
            out.diagnostics.append(_parse_diagnostic(document, error));
        }
        out.outcome = "did not parse";
        out.actions = syntax_actions(document);
        return out;
    }
    var parsed = recovered.module;
    var path = lsp.uri_to_path(uri);
    if (path.is_empty()) {
        return out;
    }
    var host = link.Target();
    for (var (name, value) in build_options) {
        host.build_options[name] = value;
    }
    out.os = analysis_os(text, parsed, host);
    var loaded = _load(Path(path.value()), text, target_for(host, out.os));
    if (loaded.is_err()) {
        out.diagnostics.append(lsp.Diagnostic(lsp.Range(), loaded.error()));
        return out;
    }
    var program = loaded.value();
    out.program = Optional<link.Program>.Value(program);
    out.files = program.files.count;
    var reporter = _Reporter(document, program);
    out.actions = reporter.actions;
    # Code the build target leaves out, dimmed.
    reporter.out.append_all(inactive_hints(document, parsed, host));
    if (program.errors.count > 0) {
        _add_program_errors(reporter, program);
        out.diagnostics = reporter.out;
        out.outcome = "found an error";
        return out;
    }
    var units = _compilation_units(program);
    # The document's own compilation unit is checked last: the compilation units
    # after it (its importers, in a cycle with a module file) do not change what
    # it shows.
    var own = Optional<ulong>.Empty;
    for (var k in 0..units.count) {
        if (units[k].files.contains(0)) {
            own = Optional<ulong>.Value(k);
        }
    }
    var folder = _project_folder(Path(path.value()));
    var cache = incremental.default_cache(folder);
    # The compilation units below the document's that the cache does not have
    # are checked in parallel, in worker children, as `pepc` checks them.
    var below = own.is_value() ? own.value() : units.count - 1;
    var prechecked = HashMap<ulong, (u8[], String, String)>();
    if (workers and below > 1) {
        var parallel = _check_in_workers(
            program, units, below, cache, prechecked, folder, path.value(), text, out.os, build_options
        );
        if (parallel.is_err()) {
            reporter.out.append(lsp.Diagnostic(lsp.Range(), parallel.error()));
            out.diagnostics = reporter.out;
            out.outcome = "found an error";
            return out;
        }
    }
    var warnings = Array<Diagnostic>();
    var replayed = Array<String>();
    var checked = incremental.check_compilation_units(
        program,
        units,
        cache,
        Optional<incremental.Reused>.Empty,
        program.sources(),
        warnings,
        replayed,
        incremental.Clock(false),
        false,
        false,
        prechecked,
        stop = own
    );
    # Warnings of the program's files, and of its own compilation unit's
    # checking.
    for (var warning in warnings) {
        reporter.add_if_in_document(warning);
    }
    if (checked.is_err()) {
        out.outcome = "found an error";
        match (checked.error()) {
            Unread(message) => {
                reporter.out.append(lsp.Diagnostic(lsp.Range(), message));
            }
            Linking(errors) => {
                if (program.errors.count > 0) {
                    _add_program_errors(reporter, program);
                } else {
                    for (var error in errors) {
                        reporter.add_if_in_document(error);
                    }
                }
            }
            Checking(error) => {
                var shown = reporter.add(error);
                var arms = missing_arms(document, program, error, shown);
                if (arms is Value(action)) {
                    out.actions.append(action);
                }
            }
            Failed(message) => {
                reporter.out.append(lsp.Diagnostic(lsp.Range(), message));
            }
        }
        out.diagnostics = reporter.out;
        return out;
    }
    out.model = Optional<sema.Module>.Value(checked.value().module);
    out.state = Optional<sema.PassState>.Value(checked.value().state);
    out.outcome = "passed";
    out.diagnostics = reporter.out;
    return out;
}

# Adds `program`'s linking errors. Unresolved imports are warnings: the
# editor does not know the `-I` folders a build passes, so the compiler may
# still find them. An error in another file shows at the document's start,
# since it stops the analysis before sema.
_add_program_errors(reporter: _Reporter, program: link.Program) {
    for (var error in program.errors) {
        var diagnostic = reporter.convert(error.to_diagnostic());
        if (error.unresolved) {
            diagnostic.severity = Optional<int>.Value(lsp.SEVERITY_WARNING);
        }
        reporter.out.append(diagnostic);
    }
}

# Loads the program rooted at `root`, whose text is `text`, for `target`, its
# bodies deferred: `incremental.check_compilation_units` links those of the
# compilation units it checks.
_load(root: Path, text: String, target: link.Target): Result<link.Program, String> {
    var setup = link.Setup();
    setup.target = target;
    setup.sources[link.path_key(root)] = text;
    setup.defer_bodies = true;
    return link.load_program(root, setup);
}

# `program`'s compilation units, keyed for the language server: its own compiler
# identity, no code generation.
_compilation_units(program: link.Program): incremental.CompilationUnit[] {
    var keys = incremental.Keys(program, link.translation_units(program), "pep-lsp");
    return incremental.compilation_units(program, keys.base());
}

# Checks compilation units `0..count` of `program` in `pep-lsp
# --compilation-unit-worker` children (`incremental.check_in_workers`), each
# loading the program as `analyze` did: `root`, with the document's `text`, for
# `os_name`, with `build_options`, as `<dir>/program` and `<dir>/root.text` give
# them.
_check_in_workers(
    program: link.Program,
    units: incremental.CompilationUnit[],
    count: ulong,
    cache: incremental.Cache,
    prechecked: HashMap<ulong, (u8[], String, String)>,
    folder: Path,
    root: String,
    text: String,
    os_name: String,
    build_options: HashMap<String, String>
): Result<void, String> {
    var dir = folder.join(Path(".pep")).join(Path("build")).join(Path($"lsp-compilation-units.{process.id()}"));
    Directory.remove_all(dir);
    var created = Directory.create_all(dir);
    if (created.is_err()) {
        return Result<void, String>.err($"cannot create {dir}: {created.error().message}");
    }
    var job = StringBuilder();
    job.append($"{root}\n{os_name}\n");
    for (var (name, value) in build_options) {
        job.append($"{name}={value}\n");
    }
    if (File.write_text(dir.join(Path("program")), job.to_string()).is_err()
        or File.write_text(dir.join(Path("root.text")), text).is_err()) {
        Directory.remove_all(dir);
        return Result<void, String>.err($"cannot write to {dir}");
    }
    var checked = incremental.check_in_workers(
        program,
        units,
        count,
        cache,
        async.logical_cpus(),
        prechecked,
        dir,
        Array<String>(),
        Optional<process.Child>.Empty,
        false,
        (k) => true
    );
    Directory.remove_all(dir);
    return checked;
}

## A `pep-lsp --compilation-unit-worker <dir>` child of an analysis
## (`incremental.serve_compilation_units`): loads the program `<dir>/program`
## names (its root, the OS it is analyzed for and the build options, a line
## each, the root's text in `<dir>/root.text`), and checks each compilation unit
## it is given, storing its record in the build cache.
##
## @param dir the folder the analysis and its workers share
## @returns the exit code: 0 once standard input ends
export compilation_unit_worker(dir: Path): int {
    var job = File.read_to_string(dir.join(Path("program")));
    var text = File.read_to_string(dir.join(Path("root.text")));
    if (job.is_err() or text.is_err()) {
        File.stderr().write_all($"pep-lsp: no program to check in {dir}\n");
        return 1;
    }
    var lines = job.value().split("\n");
    if (lines.count < 2) {
        File.stderr().write_all($"pep-lsp: no program to check in {dir}\n");
        return 1;
    }
    var root = Path(lines[0]);
    var host = link.Target();
    for (var i in 2..lines.count) {
        var equals = lines[i].find("=");
        if (equals >= 0) {
            var at = equals as ulong;
            host.build_options[lines[i].substr_bytes(0, at)] = lines[i].substr_bytes(at + 1, lines[i].size - at - 1);
        }
    }
    var loaded = _load(root, text.value(), target_for(host, lines[1]));
    if (loaded.is_err()) {
        File.stderr().write_all($"pep-lsp: {loaded.error()}\n");
        return 1;
    }
    var program = loaded.value();
    var units = _compilation_units(program);
    var cache = incremental.default_cache(_project_folder(root));
    var sources = program.sources();
    return incremental.serve_compilation_units(
        program,
        units,
        dir,
        incremental.Clock(false),
        (k, records) => {
            var checked = incremental.check_for_worker(
                program, units[k], records, cache, Optional<incremental.Reused>.Empty, sources, dir, k, StringBuilder()
            );
            return checked.is_err() ? Optional<String>.Value(checked.error()) : Optional<String>.Empty;
        }
    );
}

# The folder whose `.pep` holds the build cache for `file`: its project's
# (`link.find_project`), else its own.
_project_folder(file: Path): Path {
    var project = link.find_project(file);
    if (project.is_value()) {
        return project.value();
    }
    var parent = file.parent();
    return parent.is_value() ? parent.value() : Path(".");
}

# Converts the compiler's diagnostics to the protocol's, on the document.
struct _Reporter {
    var document: lsp.TextDocument;
    var program: link.Program;
    var out: Array<lsp.Diagnostic>;
    # The fixes of the diagnostics added.
    var actions: Array<lsp.CodeAction>;

    construct(document: lsp.TextDocument, program: link.Program) {
        this.document = document;
        this.program = program;
        this.out = Array<lsp.Diagnostic>();
        this.actions = Array<lsp.CodeAction>();
    }

    # Adds `diagnostic` when it points into the document.
    add_if_in_document(diagnostic: Diagnostic) {
        if (diagnostic.location is Value(location)) {
            if (location.file == 0) {
                add(diagnostic);
            }
        }
    }

    # Adds `diagnostic`, wherever it points, with its fixes; returns it as
    # shown.
    add(diagnostic: Diagnostic): lsp.Diagnostic {
        var shown = convert(diagnostic);
        out.append(shown);
        actions.append_all(fix_actions(document, diagnostic, shown));
        return shown;
    }

    # `diagnostic` on the document, with its notes as related information.
    # One in another file, or nowhere, lands at the document's start with
    # that file's name before its message.
    convert(diagnostic: Diagnostic): lsp.Diagnostic {
        var range = lsp.Range();
        var message = demangle(diagnostic.message);
        if (diagnostic.location is Value(location)) {
            if (location.file == 0) {
                range = document.range_of(location.span.start, location.span.end);
            } else if (location.file < program.files.count) {
                message = $"{program.files[location.file].name}: {message}";
            }
        }
        var out = lsp.Diagnostic(range, message, _severity(diagnostic.severity));
        if (!diagnostic.code.is_empty) {
            out.code = Optional<String>.Value(diagnostic.code);
            out.source = Optional<String>.Value("pepper");
            if (diagnostic.code == DEPRECATED_CODE) {
                out.tags = Optional<Array<int>>.Value([lsp.TAG_DEPRECATED]);
            }
        }
        var related = Array<lsp.DiagnosticRelatedInformation>();
        for (var note in diagnostic.notes) {
            var at = _location(note);
            if (at is Value(location)) {
                var info = lsp.DiagnosticRelatedInformation();
                info.location = location;
                info.message = demangle(note.message);
                related.append(info);
            }
        }
        if (related.count > 0) {
            out.related_information = Optional<Array<lsp.DiagnosticRelatedInformation>>.Value(related);
        }
        return out;
    }

    # Where a note points, as a protocol location.
    _location(note: Diagnostic): lsp.Location? {
        if (note.location.is_empty()) {
            return Optional<lsp.Location>.Empty;
        }
        var location = note.location.value();
        if (location.file == 0) {
            return Optional<lsp.Location>.Value(
                lsp.Location(document.uri, document.range_of(location.span.start, location.span.end))
            );
        }
        if (location.file >= program.files.count) {
            return Optional<lsp.Location>.Empty;
        }
        var file = program.files[location.file];
        var other = lsp.TextDocument(lsp.path_to_uri(file.name), file.source);
        return Optional<lsp.Location>.Value(
            lsp.Location(other.uri, other.range_of(location.span.start, location.span.end))
        );
    }
}

# The protocol's severity for the compiler's.
_severity(severity: Severity): int {
    match (severity) {
        Error => {
            return lsp.SEVERITY_ERROR;
        }
        Warning => {
            return lsp.SEVERITY_WARNING;
        }
        else => {
            return lsp.SEVERITY_INFORMATION;
        }
    }
}
