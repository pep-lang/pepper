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
import digest;
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
    var filling = Filling();
    _analyze_documents(jobs, results, client, filling);
    # A filler still running is stopped; its workers end with its pipes.
    for (var filler in filling.fillers) {
        filler.kill();
        filler.wait();
    }
}

# `analyze_documents`, keeping in `filling` the `--fill-cache` children the
# analyses start.
_analyze_documents(jobs: Channel<Job>, results: Channel<Analysis>, client: lsp.Client, filling: Filling) {
    # The newest text of each document waiting for analysis, by URI.
    var pending = HashMap<String, String>();
    var order = Array<String>();
    var build_options = HashMap<String, String>();
    # The documents open in the editor, each showing its own analysis.
    var open = HashSet<String>();
    # By document, the other files its last analysis showed warnings in.
    var shown = HashMap<String, HashSet<String>>();
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
                    open.insert(uri);
                }
                Close(uri) => {
                    pending.remove(uri);
                    open.remove(uri);
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
        var analysis = analyze(copy(uri), copy(text.value()), build_options, workers = true, filling = filling);
        var took = (os.Instant.now() - start).nanoseconds() / 1000000;
        # Edited or closed meanwhile: what was found is about old text.
        var newer = _take_jobs(jobs, pending, order, build_options, open);
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
        _publish_others(client, analysis, open, shown);
        results.send(copy(analysis));
        client.wake();
    }
}

# Takes the jobs waiting in `jobs` without waiting: Value(true) when one
# was `Stop`.
_take_jobs(
    jobs: Channel<Job>,
    pending: HashMap<String, String>,
    order: String[],
    build_options: HashMap<String, String>,
    open: HashSet<String>
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
                open.insert(uri);
            }
            Close(uri) => {
                pending.remove(uri);
                open.remove(uri);
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

# Publishes the warnings `analysis` found in its program's other files,
# except in documents `open`, which show their own analysis, and clears
# those of the files its document's last analysis showed, in `shown`, and
# this one no longer does.
_publish_others(
    client: lsp.Client, analysis: Analysis, open: HashSet<String>, shown: HashMap<String, HashSet<String>>
) {
    var now = HashSet<String>();
    for (var (uri, diagnostics) in analysis.others) {
        if (open.contains(uri)) {
            continue;
        }
        client.publish_diagnostics(uri, diagnostics);
        now.insert(uri);
    }
    var before = shown.try_get(analysis.uri);
    if (before.is_value()) {
        for (var uri in before.value()) {
            if (!now.contains(uri) and !open.contains(uri)) {
                client.publish_diagnostics(uri, Array<lsp.Diagnostic>());
            }
        }
    }
    shown[analysis.uri] = now;
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
    ## The warnings in the program's other files, by URI.
    var others: HashMap<String, Array<lsp.Diagnostic>>;
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
        this.others = HashMap<String, Array<lsp.Diagnostic>>();
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
## With `workers`, a cache without the runtime's compilation unit (the first
## analysis of a project, or with a new pep-lsp) is filled by a `pep-lsp
## --fill-cache` child, added to `filling`, while the program is checked whole
## in this process, which gives the diagnostics sooner than compilation units
## checked one after another with nothing to load. Until that child is done,
## the next analyses check their edits again on the record of the program
## checked whole (`incremental.recheck_compilation_unit`), and wait for the
## child only when that cannot be done.
##
## @param uri the document
## @param text its current text, which may differ from the file on disk
## @param build_options the build options (`-D`) to analyze with, by name
## @param workers whether compilation units the cache lacks may be checked in
##   `--compilation-unit-worker` children of this executable: only when it is
##   pep-lsp
## @param filling the `--fill-cache` children the analyses before started,
##   where this one adds one it starts
## @returns the diagnostics and how the analysis went
export analyze(
    uri: String,
    text: String,
    build_options: HashMap<String, String> = HashMap<String, String>(),
    workers: bool = false,
    filling: Filling = Filling()
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
    var warnings = Array<Diagnostic>();
    var result = _check(
        program,
        units,
        own,
        _project_folder(Path(path.value())),
        path.value(),
        text,
        out.os,
        build_options,
        workers,
        filling,
        warnings
    );
    # Warnings of the program's files, and of its own compilation unit's
    # checking.
    for (var warning in warnings) {
        reporter.add_if_in_document(warning);
    }
    out.others = _other_files(program, warnings);
    if (result.is_err()) {
        out.outcome = "found an error";
        match (result.error()) {
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
    out.model = Optional<sema.Module>.Value(result.value().module);
    out.state = Optional<sema.PassState>.Value(result.value().state);
    out.outcome = "passed";
    out.diagnostics = reporter.out;
    return out;
}

# The warnings of `warnings` in `program`'s files other than the document,
# by URI, each on its own file.
_other_files(program: link.Program, warnings: Diagnostic[]): HashMap<String, Array<lsp.Diagnostic>> {
    var reporters = HashMap<ulong, _Reporter>();
    for (var warning in warnings) {
        if (warning.location.is_empty()) {
            continue;
        }
        var file = warning.location.value().file;
        if (file == 0 or file >= program.files.count) {
            continue;
        }
        if (!reporters.contains(file)) {
            var source = program.files[file];
            var document = lsp.TextDocument(lsp.path_to_uri(source.name), source.source);
            reporters[file] = _Reporter(document, program, file);
        }
        var reporter = reporters[file];
        reporter.out.append(reporter.convert(warning));
    }
    var out = HashMap<String, Array<lsp.Diagnostic>>();
    for (var (_, reporter) in reporters) {
        out[reporter.document.uri] = reporter.out;
    }
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
    return incremental.compilation_units(program, keys.base(), root_last = false);
}

# Whether the build cache lacks the runtime's compilation unit, the first: then
# it lacks every compilation unit above it too, whose keys its own interface is
# part of.
_cold(units: incremental.CompilationUnit[], cache: incremental.Cache, program: link.Program): bool {
    var runtime = units[0];
    runtime.key = incremental.compilation_unit_key(units, 0, Array<String>());
    return incremental.find_checked(cache, program, runtime).is_empty();
}

## The `--fill-cache` children that analyses on an empty cache started, for
## the next analyses: while one runs, they check their edits again on the
## record of the program checked whole; after, they load the compilation
## units it checked.
export struct Filling {
    ## The children not yet waited for.
    var fillers: Array<process.Child> = Array<process.Child>();

    construct() {}

    ## Whether a child is still filling the cache. Waits for those done.
    ##
    ## @returns whether one runs
    running(): bool {
        var still = Array<process.Child>();
        for (var filler in fillers) {
            var status = filler.try_wait();
            if (status.is_ok() and status.value().is_empty()) {
                still.append(filler);
                continue;
            }
            filler.wait();
        }
        fillers = still;
        return !fillers.is_empty;
    }

    ## Waits for every child: an analysis that loads compilation units reads
    ## those they are checking.
    wait() {
        for (var filler in fillers) {
            filler.wait();
        }
        fillers.clear();
    }
}

# Checks `program`, whose compilation units are `units`, up to `own`, the
# document's (the last when none), as `analyze` describes. The document is
# `root`, whose text is `text`, in the project `folder`.
_check(
    program: link.Program,
    units: incremental.CompilationUnit[],
    own: ulong?,
    folder: Path,
    root: String,
    text: String,
    os_name: String,
    build_options: HashMap<String, String>,
    workers: bool,
    filling: Filling,
    warnings: Diagnostic[]
): Result<incremental.Checked, incremental.CheckError> {
    # A runtime that cannot be checked alone has no compilation units.
    if (units.is_empty) {
        return check_whole(program, warnings);
    }
    var cache = incremental.default_cache(folder);
    var below = own.is_value() ? own.value() : units.count - 1;
    var prechecked = HashMap<ulong, (u8[], String, String)>();
    if (!workers or below <= 1) {
        return _check_compilation_units(program, units, own, cache, prechecked, warnings);
    }
    var inputs = _whole_inputs(units, root, os_name, build_options);
    if (filling.running()) {
        var again = recheck_whole(program, cache, inputs, warnings);
        if (again.is_value()) {
            return again.value();
        }
        filling.wait();
    }
    # A cache without the runtime's compilation unit lacks the rest too: the
    # program is checked whole here while a `--fill-cache` child fills the
    # cache.
    if (_cold(units, cache, program)) {
        var dir = _workers_folder(folder);
        if (_prepare_workers(dir, root, text, os_name, build_options).is_value()) {
            return check_whole(program, warnings);
        }
        var filler = _start_filler(dir);
        if (filler.is_empty()) {
            return check_whole(program, warnings);
        }
        filling.fillers.append(filler.value());
        return check_whole(program, warnings, Optional<(incremental.Cache, String)>.Value((cache, inputs)));
    }
    # The compilation units below the document's that the cache does not have
    # are checked in parallel, in worker children, as `pepc` checks them.
    var parallel = _check_in_workers(
        program, units, below, cache, prechecked, folder, root, text, os_name, build_options
    );
    if (parallel.is_err()) {
        return Result<incremental.Checked, incremental.CheckError>.err(incremental.CheckError.Failed(parallel.error()));
    }
    return _check_compilation_units(program, units, own, cache, prechecked, warnings);
}

# `incremental.check_compilation_units` up to `own`, with the records
# compilation unit workers made, `prechecked`.
_check_compilation_units(
    program: link.Program,
    units: incremental.CompilationUnit[],
    own: ulong?,
    cache: incremental.Cache,
    prechecked: HashMap<ulong, (u8[], String, String)>,
    warnings: Diagnostic[]
): Result<incremental.Checked, incremental.CheckError> {
    return incremental.check_compilation_units(
        program,
        units,
        cache,
        Optional<incremental.Reused>.Empty,
        program.sources(),
        warnings,
        Array<String>(),
        incremental.Clock(false),
        false,
        false,
        prechecked,
        stop = own
    );
}

## Checks `program` whole, as one compilation unit on nothing: on an empty
## cache, one pass over every file is sooner than the compilation units one
## after another, each on the records of those it reads.
##
## @param program the program, its bodies deferred or not
## @param warnings where its warnings go
## @param keep the build cache to keep the program's record in, and what it
##   is checked with (`_whole_inputs`), for the next analyses to check their
##   edits again on; none to keep nothing
## @returns the module checked and its passes' state, or why not
export check_whole(
    program: link.Program,
    warnings: Diagnostic[],
    keep: (incremental.Cache, String)? = Optional<(incremental.Cache, String)>.Empty
): Result<incremental.Checked, incremental.CheckError> {
    var unread = program.link_bodies(incremental.every_file(program));
    if (unread.is_value()) {
        return Result<incremental.Checked, incremental.CheckError>.err(incremental.CheckError.Unread(unread.value()));
    }
    var errors = program.check_diagnostics();
    if (errors.count > 0) {
        return Result<incremental.Checked, incremental.CheckError>.err(incremental.CheckError.Linking(errors));
    }
    warnings.append_all(program.warnings());
    var inputs = keep.is_value() ? keep.value().1 : "";
    var whole = _whole_unit(program, inputs);
    var empty = incremental.merged_module(program, HashMap<ulong, u8[]>(), Array<ulong>());
    # What its record is a delta on: nothing.
    var base = sema.DeltaBase();
    sema.index_module(empty.value(), base);
    var noted = warnings.count;
    var checked = incremental.check_compilation_unit(
        program, empty.value(), whole, Optional<incremental.Reused>.Empty, program.sources(), warnings
    );
    if (checked.is_err()) {
        return Result<incremental.Checked, incremental.CheckError>.err(
            incremental.CheckError.Checking(checked.error())
        );
    }
    var (module, state, aliases) = checked.value();
    if (keep.is_value()) {
        # Its warnings, which keep a re-check from starting on it.
        var notes = Array<Diagnostic>();
        for (var i in noted..warnings.count) {
            notes.append(warnings[i]);
        }
        var sources = program.sources();
        incremental.store_checked(
            keep.value().0,
            program,
            whole,
            sema.finish_checked(module, state, aliases),
            base,
            incremental.render_warnings(notes, sources),
            incremental.recheck_source(program, whole, inputs),
            Array<String>()
        );
    }
    return Result<incremental.Checked, incremental.CheckError>.ok(incremental.Checked(module, state));
}

## Checks `program` again from the record `check_whole` kept in `cache` with
## `inputs`: the record read back, the bodies and declarations the edits
## since changed or added checked on top
## (`incremental.recheck_compilation_unit`).
##
## @param program the program as edited, its bodies deferred
## @param cache the build cache `check_whole` kept the record in
## @param inputs what the program is checked with (`_whole_inputs`)
## @param warnings where the warnings of the files edited go
## @returns the module checked and its passes' state, or a linking error;
##   nothing when there is no record, or it does not fit the edits (any
##   but those to bodies and additions, or one that gives an error or a
##   warning)
export recheck_whole(
    program: link.Program, cache: incremental.Cache, inputs: String, warnings: Diagnostic[]
): Result<incremental.Checked, incremental.CheckError>? {
    var none = Optional<Result<incremental.Checked, incremental.CheckError>>.Empty;
    var whole = _whole_unit(program, inputs);
    var found = incremental.find_recheck_base(cache, program, whole, inputs);
    if (found.is_empty()) {
        return none;
    }
    var base = found.value();
    # The bodies of the files edited, and of the document, whose warnings
    # show.
    var bodies = Array<bool>();
    for (var _ in 0..program.files.count) {
        bodies.append(false);
    }
    bodies[0] = true;
    for (var (file, _, _) in base.changed) {
        bodies[file as ulong] = true;
    }
    for (var (file, _) in base.added) {
        bodies[file as ulong] = true;
    }
    var unread = program.link_bodies(bodies);
    if (unread.is_value()) {
        return none;
    }
    var errors = program.check_diagnostics();
    if (errors.count > 0) {
        return Optional<Result<incremental.Checked, incremental.CheckError>>.Value(
            Result<incremental.Checked, incremental.CheckError>.err(incremental.CheckError.Linking(errors))
        );
    }
    var empty = incremental.merged_module(program, HashMap<ulong, u8[]>(), Array<ulong>());
    var again = incremental.recheck_compilation_unit(
        program, empty.value(), whole, base, Optional<incremental.Reused>.Empty, program.sources()
    );
    if (again.is_empty()) {
        return none;
    }
    warnings.append_all(program.warnings());
    var (module, state, _) = again.value();
    return Optional<Result<incremental.Checked, incremental.CheckError>>.Value(
        Result<incremental.Checked, incremental.CheckError>.ok(incremental.Checked(module, state))
    );
}

# `program` as one compilation unit, keyed by `inputs`: what `check_whole`
# checks and keeps.
_whole_unit(program: link.Program, inputs: String): incremental.CompilationUnit {
    var out = incremental.CompilationUnit("pep-lsp-whole");
    out.key = inputs;
    for (var i in 0..program.files.count) {
        out.files.append(i);
    }
    return out;
}

# What a program checked whole is checked with, hashed: the runtime's
# compilation unit's key (the compiler and the runtime), the document `root`,
# the OS it is analyzed for and the build options.
_whole_inputs(
    units: incremental.CompilationUnit[], root: String, os_name: String, build_options: HashMap<String, String>
): String {
    var hasher = digest.Blake3();
    hasher.update("pep-lsp whole 1\n");
    hasher.update(incremental.compilation_unit_key(units, 0, Array<String>()) + "\n");
    hasher.update(_job_text(root, os_name, build_options));
    return hasher.finish_hex();
}

# The program `<dir>/program` names for workers (`_load_job`): `root`, the OS
# it is analyzed for and the build options, a line each.
_job_text(root: String, os_name: String, build_options: HashMap<String, String>): String {
    var job = StringBuilder();
    job.append($"{root}\n{os_name}\n");
    for (var (name, value) in build_options) {
        job.append($"{name}={value}\n");
    }
    return job.to_string();
}

# The folder an analysis's compilation unit workers share, in the build folder
# of the project `folder`.
_workers_folder(folder: Path): Path {
    return folder.join(Path(".pep")).join(Path("build")).join(Path($"lsp-compilation-units.{process.id()}"));
}

# Creates `dir` with the program the workers load: `root`, the OS it is
# analyzed for and the build options, a line each, in `<dir>/program`,
# and the root's `text` in `<dir>/root.text`. Returns why it could not, if
# it could not.
_prepare_workers(
    dir: Path, root: String, text: String, os_name: String, build_options: HashMap<String, String>
): String? {
    Directory.remove_all(dir);
    var created = Directory.create_all(dir);
    if (created.is_err()) {
        return Optional<String>.Value($"cannot create {dir}: {created.error().message}");
    }
    if (File.write_text(dir.join(Path("program")), _job_text(root, os_name, build_options)).is_err()
        or File.write_text(dir.join(Path("root.text")), text).is_err()) {
        Directory.remove_all(dir);
        return Optional<String>.Value($"cannot write to {dir}");
    }
    return Optional<String>.Empty;
}

# Starts `pep-lsp --fill-cache <dir>` on the program `dir` holds, if it
# can: its standard output is not the protocol's.
_start_filler(dir: Path): process.Child? {
    var executable = process.executable_path();
    if (executable.is_err()) {
        return Optional<process.Child>.Empty;
    }
    var command = process.Command(executable.value().to_string());
    command.argument("--fill-cache").argument(dir.to_string());
    command.stdin(process.Stream.Null).stdout(process.Stream.Null);
    var spawned = command.spawn();
    return spawned.is_ok() ? Optional<process.Child>.Value(spawned.value()) : Optional<process.Child>.Empty;
}

# Checks compilation units `0..count` of `program` in `pep-lsp
# --compilation-unit-worker` children (`incremental.check_in_workers`), each
# loading the program as `analyze` did: `root`, with the document's `text`, for
# `os_name`, with `build_options`.
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
    var dir = _workers_folder(folder);
    var prepared = _prepare_workers(dir, root, text, os_name, build_options);
    if (prepared.is_value()) {
        return Result<void, String>.err(prepared.value());
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

# The program `<dir>/program` names, loaded as `analyze` loaded it: its
# root, the OS it is analyzed for and the build options, a line each, the
# root's text in `<dir>/root.text`. Returns the program and its root, or
# why it did not load.
_load_job(dir: Path): Result<(link.Program, Path), String> {
    var job = File.read_to_string(dir.join(Path("program")));
    var text = File.read_to_string(dir.join(Path("root.text")));
    if (job.is_err() or text.is_err()) {
        return Result<(link.Program, Path), String>.err($"no program to check in {dir}");
    }
    var lines = job.value().split("\n");
    if (lines.count < 2) {
        return Result<(link.Program, Path), String>.err($"no program to check in {dir}");
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
        return Result<(link.Program, Path), String>.err(loaded.error());
    }
    return Result<(link.Program, Path), String>.ok((loaded.value(), root));
}

## A `pep-lsp --fill-cache <dir>` child of an analysis that checked its program
## whole: checks the compilation units below the document's that the build cache
## lacks, in `--compilation-unit-worker` children through `dir`, as `analyze`
## does, so that the next analysis loads them. Removes `dir` when done.
##
## @param dir the folder holding the program (`_load_job`), which its
##   workers share
## @returns the exit code: 0 once the compilation units are checked
export fill_cache(dir: Path): int {
    var loaded = _load_job(dir);
    if (loaded.is_err()) {
        File.stderr().write_all($"pep-lsp: {loaded.error()}\n");
        Directory.remove_all(dir);
        return 1;
    }
    var (program, root) = loaded.value();
    var units = _compilation_units(program);
    var below = units.count - 1;
    for (var k in 0..units.count) {
        if (units[k].files.contains(0)) {
            below = k;
        }
    }
    var checked = incremental.check_in_workers(
        program,
        units,
        below,
        incremental.default_cache(_project_folder(root)),
        async.logical_cpus(),
        HashMap<ulong, (u8[], String, String)>(),
        dir,
        Array<String>(),
        Optional<process.Child>.Empty,
        false,
        (k) => true
    );
    Directory.remove_all(dir);
    if (checked.is_err()) {
        File.stderr().write_all($"pep-lsp: {checked.error()}\n");
        return 1;
    }
    return 0;
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
    var loaded = _load_job(dir);
    if (loaded.is_err()) {
        File.stderr().write_all($"pep-lsp: {loaded.error()}\n");
        return 1;
    }
    var (program, root) = loaded.value();
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
    # The program file the document is: the root, 0, unless reporting on
    # another file.
    var file: ulong;
    var out: Array<lsp.Diagnostic>;
    # The fixes of the diagnostics added.
    var actions: Array<lsp.CodeAction>;

    construct(document: lsp.TextDocument, program: link.Program, file: ulong = 0) {
        this.document = document;
        this.program = program;
        this.file = file;
        this.out = Array<lsp.Diagnostic>();
        this.actions = Array<lsp.CodeAction>();
    }

    # Adds `diagnostic` when it points into the document.
    add_if_in_document(diagnostic: Diagnostic) {
        if (diagnostic.location is Value(location)) {
            if (location.file == file) {
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
            if (location.file == file) {
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
        if (location.file == file) {
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
