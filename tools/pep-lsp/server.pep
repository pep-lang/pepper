# The Pepper language server: the `lsp.LanguageServer` the editor talks to.
# It keeps the open documents' text, hands each new text to the analysis
# thread (`analysis.pep`), and answers requests from the text it holds.

import async;
import [Channel] from async;
import json;
import [JsonValue] from json;
import lsp;
import [ResponseError] from lsp;
import compiler.parse;
import "analysis";
import "symbols";

## The server: the open documents, and the analysis thread's queue.
export struct PepperServer {
    var client: lsp.Client;
    ## The open documents, by URI.
    var documents: HashMap<String, lsp.TextDocument>;
    ## Whether the editor reports changed `.pep` files when asked.
    var watches_files: bool;
    # The analysis thread's work.
    var _jobs: Channel<Job>;
    var _version: String;

    ## Creates the server and starts its analysis thread.
    ##
    ## @param client how the server talks to the editor
    ## @param version the version `initialize` reports
    construct(client: lsp.Client, version: String) {
        this.client = client;
        this.documents = HashMap<String, lsp.TextDocument>();
        this.watches_files = false;
        this._version = version;
        var jobs = Channel<Job>();
        this._jobs = jobs;
        async.Thread.spawn(() => {
            analyze_documents(jobs, client);
        }, "pep-lsp-analysis");
    }

    # Queues the document's current text for analysis.
    _analyze(document: lsp.TextDocument) {
        _jobs.send(copy(Job.Analyze(document.uri, document.text)));
    }
}

extend PepperServer with lsp.LanguageServer {
    initialize(params: lsp.InitializeParams): Result<lsp.InitializeResult, ResponseError> {
        watches_files = _dynamic_watching(params.capabilities);
        var result = lsp.InitializeResult();
        result.capabilities.text_document_sync = Optional<lsp.TextDocumentSyncOptions>.Value(
            lsp.TextDocumentSyncOptions(lsp.SYNC_FULL)
        );
        result.capabilities.document_symbol_provider = Optional<bool>.Value(true);
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

    document_symbol(params: lsp.DocumentSymbolParams): Result<Array<lsp.DocumentSymbol>, ResponseError> {
        var document = documents.try_get(params.text_document.uri);
        if (document.is_empty()) {
            return Result<Array<lsp.DocumentSymbol>, ResponseError>.ok(Array<lsp.DocumentSymbol>());
        }
        var module = parse.parse(document.value().text);
        if (module.is_err()) {
            return Result<Array<lsp.DocumentSymbol>, ResponseError>.ok(Array<lsp.DocumentSymbol>());
        }
        return Result<Array<lsp.DocumentSymbol>, ResponseError>.ok(document_symbols(document.value(), module.value()));
    }
}

# Whether the client registers file watchers when asked:
# `workspace.didChangeWatchedFiles.dynamicRegistration` in its
# capabilities.
_dynamic_watching(capabilities: JsonValue?): bool {
    if (capabilities.is_empty()) {
        return false;
    }
    var workspace = capabilities.value()["workspace"];
    if (!workspace.contains("didChangeWatchedFiles")) {
        return false;
    }
    var watched = workspace["didChangeWatchedFiles"];
    if (!watched.contains("dynamicRegistration")) {
        return false;
    }
    var dynamic = watched["dynamicRegistration"].as_bool();
    return dynamic.is_value() and dynamic.value();
}
