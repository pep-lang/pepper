# The supervisor: `pep-lsp` as the editor starts it. A panic in Pepper ends
# the process (`_pep_panic` aborts), so the server itself runs in a child,
# `pep-lsp --serve`, and this process relays the protocol between the editor
# and it. When the child ends without being asked to, the requests it had
# not answered get an empty answer, as the Rust server's `catch_unwind`
# gave, and a new child gets the editor's `initialize` again and every open
# document, so the editor keeps its server. The relay keeps what that
# takes: the `initialize` request, each open document's newest text, and
# the requests not answered yet.
#
# A child that ends again before the editor changes anything most likely
# ended on the text of the document changed last; that document is left
# out of the next child until its next change, so one bad text cannot keep
# the server down.

import async;
import [Channel, Thread] from async;
import [File, FileTransfer] from io;
import json;
import [JsonValue] from json;
import lsp;
import process;

# The most children that may end in a row, with no change from the editor
# in between, before the supervisor gives up.
const _RESTARTS: ulong = 5;
# The id of the `initialize` a new child is sent; its answer goes nowhere.
const _REPLAY_ID = "pep-lsp-restart";

# What the relay's loop handles, from its reader threads.
enum _Event {
    # A message from the editor.
    FromEditor(message: JsonValue),
    # The editor's input ended.
    EditorEnded,
    # A message from child number `generation`.
    FromChild(generation: ulong, message: JsonValue),
    # Child number `generation`'s output ended: it ended.
    ChildEnded(generation: ulong),
}

# The running child and its pipes.
struct _Child {
    var process: process.Child;
    var input: File;
    var generation: ulong;

    construct(child: process.Child, generation: ulong) {
        this.process = child;
        this.input = child.stdin();
        this.generation = generation;
    }
}

## Runs `pep-lsp --serve` in a child and relays the editor's standard input
## and output to it, starting a new child whenever one ends before the
## editor asked it to (`shutdown`, then `exit`).
##
## @returns the exit code: the child's after `exit`, 1 when the editor's
##   input ends first or a child cannot be started
export supervise(): int {
    var executable = process.executable_path();
    if (executable.is_err()) {
        File.stderr().write_all($"pep-lsp: cannot find this program: {executable.error().message}\n");
        return 1;
    }
    var events = Channel<_Event>();
    Thread.spawn(() => {
        var reader = lsp.MessageReader(File.stdin());
        while (true) {
            var read = reader.read();
            if (read.is_err() or read.value().is_empty()) {
                events.send(_Event.EditorEnded);
                return;
            }
            events.send(copy(_Event.FromEditor(read.value().value())));
        }
    }, "editor-reader");
    var relay = _Relay(executable.value().to_string(), events);
    return relay.run();
}

# The relay's state, on the supervisor's one thread.
struct _Relay {
    var executable: String;
    var events: Channel<_Event>;
    var child: _Child?;
    var generations: ulong;
    # The editor's `initialize` request, and whether it sent `initialized`.
    var initialize: JsonValue?;
    var initialized: bool;
    # Each open document's `TextDocumentItem`, its newest text, by URI.
    var documents: HashMap<String, JsonValue>;
    # The document changed last, and those left out of the child.
    var changed_last: String;
    var left_out: HashSet<String>;
    # The editor's requests the child has not answered, by id as JSON text.
    var pending: HashMap<String, JsonValue>;
    # Children that ended since the editor last changed a document.
    var restarts: ulong;
    var shutting_down: bool;

    construct(executable: String, events: Channel<_Event>) {
        this.executable = executable;
        this.events = events;
        this.child = Optional<_Child>.Empty;
        this.generations = 0;
        this.initialize = Optional<JsonValue>.Empty;
        this.initialized = false;
        this.documents = HashMap<String, JsonValue>();
        this.changed_last = "";
        this.left_out = HashSet<String>();
        this.pending = HashMap<String, JsonValue>();
        this.restarts = 0;
        this.shutting_down = false;
    }

    # Relays until the editor sends `exit` or its input ends.
    run(): int {
        if (!_start()) {
            return 1;
        }
        while (true) {
            var next = events.receive();
            if (next.is_err()) {
                return 1;
            }
            match (next.value()) {
                FromEditor(message) => {
                    var done = _from_editor(message);
                    if (done is Value(code)) {
                        return code;
                    }
                }
                EditorEnded => {
                    _stop();
                    return 1;
                }
                FromChild(generation, message) => {
                    if (_is_current(generation)) {
                        _from_child(message);
                    }
                }
                ChildEnded(generation) => {
                    if (_is_current(generation)) {
                        var done = _child_ended();
                        if (done is Value(code)) {
                            return code;
                        }
                    }
                }
            }
        }
        return 1;
    }

    _is_current(generation: ulong): bool {
        if (child is Value(current)) {
            return current.generation == generation;
        }
        return false;
    }

    # Starts a child and its output's reader thread; false when it cannot.
    _start(): bool {
        var command = process.Command(executable);
        command.argument("--serve");
        command.stdin(process.Stream.Pipe);
        command.stdout(process.Stream.Pipe);
        var spawned = command.spawn();
        if (spawned.is_err()) {
            File.stderr().write_all($"pep-lsp: cannot start the server: {spawned.error().message}\n");
            return false;
        }
        generations += 1;
        var started = _Child(spawned.value(), generations);
        # The output's reader owns the pipe on its own thread.
        FileTransfer output = started.process.stdout().into_transfer();
        ulong generation = generations;
        var sink = events;
        Thread.spawn(() => {
            var pipe = File.adopt(output);
            if (pipe.is_ok()) {
                var reader = lsp.MessageReader(pipe.value());
                while (true) {
                    var read = reader.read();
                    if (read.is_err() or read.value().is_empty()) {
                        break;
                    }
                    sink.send(copy(_Event.FromChild(generation, read.value().value())));
                }
            }
            sink.send(_Event.ChildEnded(generation));
        }, "server-reader");
        child = Optional<_Child>.Value(started);
        return true;
    }

    # Closes the child's input, so it ends, and waits for it: its exit code.
    _stop(): int {
        if (child is Value(current)) {
            current.input.close();
            var status = current.process.wait();
            child = Optional<_Child>.Empty;
            if (status.is_ok()) {
                if (status.value().code() is Value(code)) {
                    return code;
                }
            }
        }
        return 1;
    }

    _to_child(message: JsonValue) {
        if (child is Value(current)) {
            # A child that ended reads nothing: `_child_ended` answers for it.
            lsp.write_message(current.input, message);
        }
    }

    _to_editor(message: JsonValue) {
        lsp.write_message(File.stdout(), message);
    }

    # Relays `message` from the editor, noting what a new child would need;
    # the exit code once the editor sends `exit`.
    _from_editor(message: JsonValue): int? {
        var method = message["method"].as_string();
        var id = message["id"];
        var name = method.is_value() ? method.value() : "";
        if (method.is_value() and !id.is_null()) {
            pending[id.to_string()] = id;
        }
        if (name == "initialize") {
            initialize = Optional<JsonValue>.Value(message);
        } else if (name == "initialized") {
            initialized = true;
        } else if (name == "shutdown") {
            shutting_down = true;
        } else if (name == "exit") {
            _to_child(message);
            var code = _stop();
            return Optional<int>.Value(shutting_down ? code : 1);
        } else if (name == "textDocument/didOpen") {
            var item = message["params"]["textDocument"];
            var uri = item["uri"].as_string();
            if (uri.is_value()) {
                documents[uri.value()] = item;
                _changed(uri.value());
            }
        } else if (name == "textDocument/didChange") {
            var uri = message["params"]["textDocument"]["uri"].as_string();
            var changes = message["params"]["contentChanges"].as_array();
            if (uri.is_value()
                and documents.contains(uri.value())
                and changes.is_value()
                and changes.value().count > 0) {
                # Full sync: the last change is the whole text.
                var item = documents[uri.value()];
                item["text"] = changes.value()[changes.value().count - 1]["text"];
                item["version"] = message["params"]["textDocument"]["version"];
                _changed(uri.value());
                if (left_out.contains(uri.value())) {
                    # The child never saw it: it opens with the new text.
                    left_out.remove(uri.value());
                    _to_child(_did_open(item));
                    return Optional<int>.Empty;
                }
            }
        } else if (name == "textDocument/didClose") {
            var uri = message["params"]["textDocument"]["uri"].as_string();
            if (uri.is_value()) {
                documents.remove(uri.value());
                if (left_out.contains(uri.value())) {
                    left_out.remove(uri.value());
                    return Optional<int>.Empty;
                }
            }
        }
        _to_child(message);
        return Optional<int>.Empty;
    }

    _changed(uri: String) {
        changed_last = uri;
        restarts = 0;
    }

    # Relays `message` from the child, but not the answer to a replayed
    # `initialize`.
    _from_child(message: JsonValue) {
        var id = message["id"];
        if (message["method"].is_null() and !id.is_null()) {
            if (id.as_string() == Optional<String>.Value(_REPLAY_ID)) {
                return;
            }
            pending.remove(id.to_string());
        }
        _to_editor(message);
    }

    # The child ended. After `shutdown`, its exit code; otherwise answers
    # what it left unanswered, starts another and gives it the editor's
    # state again.
    _child_ended(): int? {
        var code = _stop();
        if (shutting_down) {
            return Optional<int>.Value(code);
        }
        for (var (_, id) in pending) {
            var answer = JsonValue.object();
            answer["jsonrpc"] = JsonValue.String("2.0");
            answer["id"] = id;
            answer["result"] = JsonValue.Null;
            _to_editor(answer);
        }
        pending.clear();
        restarts += 1;
        var note = "";
        if (restarts > 1
            and !changed_last.is_empty
            and documents.contains(changed_last)
            and !left_out.contains(changed_last)) {
            left_out.insert(changed_last);
            note = $"; {changed_last} is left out until it changes";
        }
        if (restarts > _RESTARTS) {
            _log($"pep-lsp: the server ended {restarts} times in a row; giving up");
            return Optional<int>.Value(1);
        }
        _log($"pep-lsp: the server ended (exit code {code}); restarting it{note}");
        if (!_start()) {
            return Optional<int>.Value(1);
        }
        if (initialize is Value(request)) {
            var again = json.parse(request.to_string()).value();
            again["id"] = JsonValue.String(_REPLAY_ID);
            _to_child(again);
        }
        if (initialized) {
            var note_initialized = JsonValue.object();
            note_initialized["jsonrpc"] = JsonValue.String("2.0");
            note_initialized["method"] = JsonValue.String("initialized");
            note_initialized["params"] = JsonValue.object();
            _to_child(note_initialized);
        }
        for (var (uri, item) in documents) {
            if (!left_out.contains(uri)) {
                _to_child(_did_open(item));
            }
        }
        return Optional<int>.Empty;
    }

    _log(message: String) {
        var params = JsonValue.object();
        params["type"] = JsonValue.Integer(lsp.MESSAGE_ERROR);
        params["message"] = JsonValue.String(message);
        var log = JsonValue.object();
        log["jsonrpc"] = JsonValue.String("2.0");
        log["method"] = JsonValue.String("window/logMessage");
        log["params"] = params;
        _to_editor(log);
    }
}

# A `didOpen` notification for `item`.
_did_open(item: JsonValue): JsonValue {
    var params = JsonValue.object();
    params["textDocument"] = item;
    var open = JsonValue.object();
    open["jsonrpc"] = JsonValue.String("2.0");
    open["method"] = JsonValue.String("textDocument/didOpen");
    open["params"] = params;
    return open;
}
