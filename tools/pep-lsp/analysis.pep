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
import [Path] from io;
import os;

import [demangle, Diagnostic, DEPRECATED_CODE, Severity] from compiler.diagnostic;
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
        var analysis = analyze(copy(uri), copy(text.value()), build_options);
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

## Analyzes `text`, the text of document `uri`: its syntax error or
## deprecated syntax, then, when `uri` names a file, the errors of the
## program rooted at it (unresolved imports, linking and visibility errors,
## then the first error type checking finds) and its warnings, all as they
## apply to the document.
##
## @param uri the document
## @param text its current text, which may differ from the file on disk
## @param build_options the build options (`-D`) to analyze with, by name
## @returns the diagnostics and how the analysis went
export analyze(
    uri: String, text: String, build_options: HashMap<String, String> = HashMap<String, String>()
): Analysis {
    var out = Analysis(uri, text);
    var document = lsp.TextDocument(uri, text);
    var parsed = parse.parse(text);
    if (parsed.is_err()) {
        var error = parsed.error();
        out.diagnostics.append(lsp.Diagnostic(document.range_of(error.span.start, error.span.end), error.message));
        out.outcome = "did not parse";
        out.actions = syntax_actions(document);
        return out;
    }
    var path = lsp.uri_to_path(uri);
    if (path.is_empty()) {
        return out;
    }
    var host = link.Target();
    for (var (name, value) in build_options) {
        host.build_options[name] = value;
    }
    out.os = analysis_os(text, parsed.value(), host);
    var setup = link.Setup();
    setup.target = target_for(host, out.os);
    setup.sources[link.path_key(Path(path.value()))] = text;
    var loaded = link.load_program(Path(path.value()), setup);
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
    reporter.out.append_all(inactive_hints(document, parsed.value(), host));
    for (var warning in program.warnings()) {
        reporter.add_if_in_document(warning);
    }
    # Unresolved imports are warnings: the editor does not know the `-I`
    # folders a build passes, so the compiler may still find them.
    for (var error in program.errors) {
        if (error.file != 0) {
            continue;
        }
        var diagnostic = reporter.convert(error.to_diagnostic());
        if (error.unresolved) {
            diagnostic.severity = Optional<int>.Value(lsp.SEVERITY_WARNING);
        }
        reporter.out.append(diagnostic);
    }
    if (program.errors.count > 0) {
        out.diagnostics = reporter.out;
        out.outcome = "found an error";
        return out;
    }
    var checked = program.check_diagnostics();
    if (checked.count > 0) {
        for (var error in checked) {
            reporter.add_if_in_document(error);
        }
        out.diagnostics = reporter.out;
        out.outcome = "found an error";
        return out;
    }
    var built = sema.build(program);
    if (built.is_err()) {
        reporter.add(built.error());
        out.diagnostics = reporter.out;
        out.outcome = "found an error";
        return out;
    }
    var model = built.value();
    var ran = sema.run_passes(model, program.target, program.sources());
    if (ran.is_err()) {
        var shown = reporter.add(ran.error());
        var arms = missing_arms(document, program, ran.error(), shown);
        if (arms is Value(action)) {
            out.actions.append(action);
        }
        out.outcome = "found an error";
    } else {
        for (var note in ran.value().notes) {
            reporter.add_if_in_document(note);
        }
        out.model = Optional<sema.Module>.Value(model);
        out.state = Optional<sema.PassState>.Value(ran.value());
        out.outcome = "passed";
    }
    out.diagnostics = reporter.out;
    return out;
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
