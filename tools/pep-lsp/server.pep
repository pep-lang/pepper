# The Pepper language server: the `lsp.LanguageServer` the editor talks to.
# It keeps the open documents' text, hands each new text to the analysis
# thread (`analysis.pep`), keeps the analyses it hands back, and answers
# requests from the text and those analyses (`edits.pep`).

import async;
import [Channel] from async;
import json;
import [JsonValue] from json;
import compiler.link;
import lsp;
import [ResponseError] from lsp;
import compiler.parse;
import os;
import "actions";
import "analysis";
import "completion";
import "edits";
import "hints";
import "symbols";

## The server: the open documents, and the analysis thread's queue.
export struct PepperServer {
    var client: lsp.Client;
    ## The open documents, by URI.
    var documents: HashMap<String, lsp.TextDocument>;
    ## Whether the editor reports changed `.pep` files when asked.
    var watches_files: bool;
    ## Whether the editor asks again for inlay hints when told to.
    var refreshes_hints: bool;
    ## Whether to show implicit conversions as inlay hints
    ## (`inlayHints.implicitConversions`).
    var conversion_hints: bool;
    ## Whether to name literal arguments in inlay hints
    ## (`inlayHints.parameterNames`).
    var parameter_hints: bool;
    # The analysis thread's work.
    var _jobs: Channel<Job>;
    # The analyses the analysis thread finished, not yet taken in.
    var _results: Channel<Analysis>;
    # The last analysis of each open document, by URI.
    var _analyses: HashMap<String, Analysis>;
    # The newest analysis of each open document whose sema passed.
    var _ready: HashMap<String, Analysis>;
    var _version: String;

    ## Creates the server and starts its analysis thread.
    ##
    ## @param client how the server talks to the editor
    ## @param version the version `initialize` reports
    construct(client: lsp.Client, version: String) {
        this.client = client;
        this.documents = HashMap<String, lsp.TextDocument>();
        this.watches_files = false;
        this.refreshes_hints = false;
        this.conversion_hints = true;
        this.parameter_hints = true;
        this._version = version;
        this._analyses = HashMap<String, Analysis>();
        this._ready = HashMap<String, Analysis>();
        var jobs = Channel<Job>();
        var results = Channel<Analysis>();
        this._jobs = jobs;
        this._results = results;
        async.Thread.spawn(() => {
            analyze_documents(jobs, results, client);
        }, "pep-lsp-analysis");
    }

    # Queues the document's current text for analysis.
    _analyze(document: lsp.TextDocument) {
        _jobs.send(copy(Job.Analyze(document.uri, document.text)));
    }

    # Logs a request that took longer than `SLOW_REQUEST_MS` since `start`
    # to the editor's output (the "Pepper Language Server" channel).
    _answered(method: String, start: os.Instant) {
        var took = (os.Instant.now() - start).nanoseconds() / 1000000;
        if (took > SLOW_REQUEST_MS) {
            client.log_message(lsp.MESSAGE_WARNING, $"{method} took {took} ms");
        }
    }
}

# A request that takes longer than this many milliseconds is logged.
const SLOW_REQUEST_MS = 200;

extend PepperServer with lsp.LanguageServer {
    initialize(params: lsp.InitializeParams): Result<lsp.InitializeResult, ResponseError> {
        watches_files = json_flag(
            params.capabilities, ["workspace", "didChangeWatchedFiles", "dynamicRegistration"], false
        );
        refreshes_hints = json_flag(params.capabilities, ["workspace", "inlayHint", "refreshSupport"], false);
        conversion_hints = json_flag(params.initialization_options, ["inlayHints", "implicitConversions"], true);
        parameter_hints = json_flag(params.initialization_options, ["inlayHints", "parameterNames"], true);
        _jobs.send(copy(Job.Configure(build_options(params.initialization_options))));
        var result = lsp.InitializeResult();
        result.capabilities.text_document_sync = Optional<lsp.TextDocumentSyncOptions>.Value(
            lsp.TextDocumentSyncOptions(lsp.SYNC_FULL)
        );
        result.capabilities.document_symbol_provider = Optional<bool>.Value(true);
        result.capabilities.hover_provider = Optional<bool>.Value(true);
        result.capabilities.definition_provider = Optional<bool>.Value(true);
        result.capabilities.inlay_hint_provider = Optional<bool>.Value(true);
        result.capabilities.code_action_provider = Optional<bool>.Value(true);
        var completion = lsp.CompletionOptions();
        completion.trigger_characters = Optional<Array<String>>.Value([".", "("]);
        result.capabilities.completion_provider = Optional<lsp.CompletionOptions>.Value(completion);
        var info = lsp.ClientInfo();
        info.name = "pep-lsp";
        info.version = Optional<String>.Value(_version);
        result.server_info = Optional<lsp.ClientInfo>.Value(info);
        return Result<lsp.InitializeResult, ResponseError>.ok(result);
    }

    initialized() {
        client.log_message(lsp.MESSAGE_INFO, $"pep-lsp {_version} started");
        # Analyses read imports from disk: have the editor report `.pep`
        # files that change.
        if (watches_files) {
            client.watch_files("pep-files", "**/*.pep");
        }
    }

    shutdown(): Result<void, ResponseError> {
        _jobs.send(Job.Stop);
        return Result<void, ResponseError>.ok();
    }

    did_open(params: lsp.DidOpenTextDocumentParams) {
        var document = lsp.TextDocument.opened(params.text_document);
        documents[document.uri] = document;
        _analyze(document);
    }

    did_change(params: lsp.DidChangeTextDocumentParams) {
        var document = documents.try_get(params.text_document.uri);
        if (document.is_empty()) {
            return;
        }
        document.value().apply_changes(params);
        _analyze(document.value());
    }

    did_close(params: lsp.DidCloseTextDocumentParams) {
        var uri = params.text_document.uri;
        documents.remove(uri);
        _analyses.remove(uri);
        _ready.remove(uri);
        _jobs.send(copy(Job.Close(uri)));
        client.publish_diagnostics(uri, Array<lsp.Diagnostic>());
    }

    # A `.pep` file changed on disk: an open document may import it, so
    # each is analyzed again.
    did_change_watched_files(params: lsp.DidChangeWatchedFilesParams) {
        for (var (_, document) in documents) {
            _analyze(document);
        }
    }

    # Takes in the analyses the analysis thread finished, for documents
    # still open.
    woken() {
        while (true) {
            var received = _results.try_receive();
            if (received.is_err()) {
                return;
            }
            var analysis = received.value();
            if (!documents.contains(analysis.uri)) {
                continue;
            }
            _analyses[analysis.uri] = analysis;
            if (analysis.model.is_empty()) {
                continue;
            }
            _ready[analysis.uri] = analysis;
            # The hints come from the passed analysis: ask for them again.
            if (refreshes_hints) {
                client.refresh_inlay_hints();
            }
        }
    }

    hover(params: lsp.TextDocumentPositionParams): Result<lsp.Hover?, ResponseError> {
        var start = os.Instant.now();
        var uri = params.text_document.uri;
        var document = documents.try_get(uri);
        if (document.is_empty()) {
            return Result<lsp.Hover?, ResponseError>.ok(Optional<lsp.Hover>.Empty);
        }
        var offset = document.value().offset_at(params.position);
        var hover = hover_across_edits(document.value(), _analyses.try_get(uri), _ready.try_get(uri), offset);
        _answered("hover", start);
        return Result<lsp.Hover?, ResponseError>.ok(hover);
    }

    definition(params: lsp.TextDocumentPositionParams): Result<Array<lsp.Location>, ResponseError> {
        var start = os.Instant.now();
        var uri = params.text_document.uri;
        var document = documents.try_get(uri);
        if (document.is_empty()) {
            return Result<Array<lsp.Location>, ResponseError>.ok(Array<lsp.Location>());
        }
        var offset = document.value().offset_at(params.position);
        var found = definition_across_edits(document.value(), _analyses.try_get(uri), _ready.try_get(uri), offset);
        _answered("definition", start);
        return Result<Array<lsp.Location>, ResponseError>.ok(found);
    }

    completion(params: lsp.CompletionParams): Result<lsp.CompletionList?, ResponseError> {
        var start = os.Instant.now();
        var uri = params.text_document.uri;
        var document = documents.try_get(uri);
        if (document.is_empty()) {
            return Result<lsp.CompletionList?, ResponseError>.ok(Optional<lsp.CompletionList>.Empty);
        }
        var offset = document.value().offset_at(params.position);
        var items = completion_at(document.value(), _analyses.try_get(uri), _ready.try_get(uri), offset);
        _answered("completion", start);
        return Result<lsp.CompletionList?, ResponseError>.ok(
            Optional<lsp.CompletionList>.Value(lsp.CompletionList(items))
        );
    }

    inlay_hint(params: lsp.InlayHintParams): Result<Array<lsp.InlayHint>, ResponseError> {
        var start = os.Instant.now();
        var uri = params.text_document.uri;
        var document = documents.try_get(uri);
        if (document.is_empty()) {
            return Result<Array<lsp.InlayHint>, ResponseError>.ok(Array<lsp.InlayHint>());
        }
        var hints = inlay_hints(document.value(), _ready.try_get(uri), params.range, conversion_hints, parameter_hints);
        _answered("inlayHint", start);
        return Result<Array<lsp.InlayHint>, ResponseError>.ok(hints);
    }

    code_action(params: lsp.CodeActionParams): Result<Array<lsp.CodeAction>, ResponseError> {
        var start = os.Instant.now();
        var uri = params.text_document.uri;
        var document = documents.try_get(uri);
        if (document.is_empty()) {
            return Result<Array<lsp.CodeAction>, ResponseError>.ok(Array<lsp.CodeAction>());
        }
        var analyzed = Optional<String>.Empty;
        var actions = Array<lsp.CodeAction>();
        var latest = _analyses.try_get(uri);
        if (latest is Value(l)) {
            analyzed = Optional<String>.Value(l.text);
            actions = l.actions;
        }
        var found = code_actions(document.value(), analyzed, actions, params.range);
        _answered("codeAction", start);
        return Result<Array<lsp.CodeAction>, ResponseError>.ok(found);
    }

    document_symbol(params: lsp.DocumentSymbolParams): Result<Array<lsp.DocumentSymbol>, ResponseError> {
        var start = os.Instant.now();
        var document = documents.try_get(params.text_document.uri);
        if (document.is_empty()) {
            return Result<Array<lsp.DocumentSymbol>, ResponseError>.ok(Array<lsp.DocumentSymbol>());
        }
        var module = parse.parse(document.value().text);
        if (module.is_err()) {
            return Result<Array<lsp.DocumentSymbol>, ResponseError>.ok(Array<lsp.DocumentSymbol>());
        }
        var symbols = document_symbols(document.value(), module.value());
        _answered("documentSymbol", start);
        return Result<Array<lsp.DocumentSymbol>, ResponseError>.ok(symbols);
    }
}

## The build options to analyze with, from the `buildOptions` array of
## strings in the initialization options, each as the compiler's `-D`
## takes it: `NAME` or `NAME=VALUE`. One that does not parse is left out.
##
## @param options the initialization options, if any
## @returns the options' values by name
export build_options(options: JsonValue?): HashMap<String, String> {
    var out = HashMap<String, String>();
    if (options.is_empty() or !options.value().contains("buildOptions")) {
        return out;
    }
    var items = Array<JsonValue>();
    if (options.value()["buildOptions"] is Array(listed)) {
        items = listed;
    }
    for (var item in items) {
        var text = item.as_string();
        if (text.is_empty()) {
            continue;
        }
        var option = text.value();
        var equals = option.find("=");
        var name = equals < 0 ? option : option.substr_bytes(0, equals as ulong);
        var value = equals < 0 ? "1" : option.substr_bytes(equals as ulong + 1, option.size - equals as ulong - 1);
        if (link.is_build_option_name(name)) {
            out[name] = value;
        }
    }
    return out;
}

## The boolean at `path` in the JSON object `value`, such as a client
## capability or an initialization option.
##
## @param value the object, if any
## @param path the member names leading to the value
## @param missing what to return when it is not there or not a boolean
## @returns the value
export json_flag(value: JsonValue?, path: String[], missing: bool): bool {
    if (value.is_empty()) {
        return missing;
    }
    var at = value.value();
    for (var name in path) {
        if (!at.contains(name)) {
            return missing;
        }
        at = at[name];
    }
    var flag = at.as_bool();
    return flag.is_value() ? flag.value() : missing;
}
