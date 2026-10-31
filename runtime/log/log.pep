## Levels, fields, the output, and the functions that write a line.

import async;
import io;
import json;
import os;
import time;
import "terminal";

extern ulong strlen(char* s);

## How much a line matters, most important first.
##
## As the level a target shows (`set_level`, `PEPPER_LOG`), each level also
## shows the ones above it: `Info` shows errors, warnings and info lines.
export enum Level {
    ## Nothing: as the level a target shows, turns its lines off.
    Off,
    ## Something failed (`error`).
    Error,
    ## Something looks wrong but the program carries on (`warning`).
    Warning,
    ## What the program is doing, at the level of whole operations (`info`).
    Info,
    ## Detail for finding a bug (`debug`).
    Debug,
    ## Step-by-step detail (`trace`).
    Trace,
}

## How each line is written.
export enum Format {
    ## One readable line: the UTC time, the level, the target in brackets,
    ## the message, `key=value` fields, and the call's location in
    ## parentheses.
    Text,
    ## One JSON object per line (JSON Lines), with the keys `time`,
    ## `level`, `target` (when there is one), `message` and `location`, then
    ## each field.
    Json,
}

## A key and value attached to a line. Make one with `field`.
export struct Field {
    ## The key.
    var key: String = "";

    ## The value as JSON text: `200`, `"ann"`, `true`.
    var value: String = "";

    ## Creates a field from a key and the JSON text of its value; `field`
    ## makes the text from any value.
    ##
    ## @param key the key
    ## @param value the value's JSON text
    construct(key: String, value: String) {
        this.key = key;
        this.value = value;
    }
}

## Makes a field for a line: `log.info("done", [log.field("ms", 12)])`.
##
## The value is turned into JSON (see `json.encode`) when the field is
## made, whether or not the line is written; guard costly fields with
## `enabled`.
##
## @typeParam T the type of `value`
## @param key the key
## @param value the value
## @returns the field
## @example
##     import log;
##
##     main(): int {
##         log.info("request done", [log.field("status", 200), log.field("path", "/")]);
##         return 0;
##     }
export field<T>(key: String, value: T): Field {
    return Field(key, json.encode(value));
}

# What the Mutex guards: where lines go and which levels each target shows.
struct _LogState {
    var writer: io.Writer = io.File.stderr();
    var level: Level = Level.Info;
    var targets: HashMap<String, Level> = HashMap<String, Level>();

    # The level `target` shows: its own, else the global one.
    shown(target: String): Level {
        if (target.is_empty) {
            return level;
        }
        return targets.try_get(target).value_or(level);
    }

    # The most verbose level any target shows.
    loosest(): Level {
        var most = level;
        for (var (target, shown) in targets) {
            if ((shown as int) > (most as int)) {
                most = shown;
            }
        }
        return most;
    }
}

[Shared]
struct _LogConfig {
    # `_LogState.loosest()`, so a line no target shows is dropped without
    # taking the lock.
    const loosest: async.Atomic<Level>;

    # How lines are written, read without the lock to build a line before
    # taking it.
    const format: async.Atomic<Format>;
    # 1 for ANSI colors (`async.Atomic<bool>` does not compile yet).
    const color: async.Atomic<int>;

    const state: async.Mutex<_LogState>;

    construct([Move] state: _LogState, color: bool) {
        loosest = async.Atomic<Level>(state.loosest());
        format = async.Atomic<Format>(Format.Text);
        this.color = async.Atomic<int>(color ? 1 : 0);
        this.state = async.Mutex<_LogState>(move(state));
    }
}

# Built on the first line or setting, so a program that never logs never
# reads PEPPER_LOG.
const _log_config = async.Lazy<_LogConfig>(_log_load);

_log_load(): _LogConfig {
    var state = _LogState();
    var color = _log_stderr_shows_color() && os.environment("NO_COLOR").is_empty();
    var spec = os.environment("PEPPER_LOG");
    if (spec.is_value()) {
        _log_apply(state, spec.value());
    }
    return _LogConfig(move(state), color);
}

# Applies `PEPPER_LOG`: comma-separated items, each a level for every
# target (`info`) or for one (`http=debug`). An item that names no level
# is reported on standard error and skipped.
_log_apply(state: _LogState, spec: String) {
    for (var item in spec.split(",")) {
        var text = item.trim();
        if (text.is_empty) {
            continue;
        }
        var target = "";
        var name = text;
        var pair = text.split_once("=");
        if (pair.is_value()) {
            target = pair.value().0.trim();
            name = pair.value().1.trim();
        }
        var level = _log_parse_level(name);
        if (level.is_empty()) {
            var report = $"PEPPER_LOG: unknown level '{name}'\n";
            _pep_write_error(report.c_str());
            continue;
        }
        if (target.is_empty) {
            state.level = level.value();
        } else {
            state.targets.insert(target, level.value());
        }
    }
}

_log_parse_level(name: String): Level? {
    var lower = name.lower();
    if (lower == "off") {
        return Optional<Level>.Value(Level.Off);
    }
    if (lower == "error") {
        return Optional<Level>.Value(Level.Error);
    }
    if (lower == "warning" || lower == "warn") {
        return Optional<Level>.Value(Level.Warning);
    }
    if (lower == "info") {
        return Optional<Level>.Value(Level.Info);
    }
    if (lower == "debug") {
        return Optional<Level>.Value(Level.Debug);
    }
    if (lower == "trace") {
        return Optional<Level>.Value(Level.Trace);
    }
    return Optional<Level>.Empty;
}

## Sets the level a target shows, or with no target the level every target
## without its own shows. The default is `Level.Info`, unless the
## `PEPPER_LOG` environment variable says otherwise.
##
## @param level the least important level to show; `Level.Off` shows nothing
## @param target the target, as the logging functions' `target`; empty for
##   the global level
## @example
##     import log;
##
##     main(): int {
##         log.set_level(log.Level.Debug);
##         log.set_level(log.Level.Warning, "http");
##         log.debug("shown");
##         log.info("not shown", target = "http");
##         return 0;
##     }
export set_level(level: Level, target: String = "") {
    var config = _log_config.get();
    with (var state = config.state.lock()) {
        if (target.is_empty) {
            state.level = level;
        } else {
            state.targets.insert(copy(target), level);
        }
        config.loosest.store(state.loosest());
    }
}

## Sends every line from now on to `writer` in `format`, instead of to
## standard error. Lines are written whole, one `write_all` each, under a
## lock, so lines from many threads and tasks never interleave. A failed
## write is ignored. Colors are off.
##
## @param writer where lines go: a new value, or one handed over with
##   `move(x)`, since the log keeps it
## @param format how each line is written
## @example
##     import io;
##     import log;
##
##     main(): int {
##         var file = io.File.create(io.Directory.temp().join("app.log")).value();
##         log.set_output(move(file), log.Format.Json);
##         log.info("started");
##         return 0;
##     }
export set_output([Move] writer: io.Writer, format: Format = Format.Text) {
    var config = _log_config.get();
    with (var state = config.state.lock()) {
        state.writer = move(writer);
        config.format.store(format);
        config.color.store(0);
    }
}

## Reports whether a line at `level` for `target` would be written, so a
## caller can skip building a costly message or field.
##
## Cheap when no target shows `level`: two atomic loads, with no lock.
##
## @param level the line's level
## @param target the line's target; empty for none
## @returns true when `target` shows `level`; false for `Level.Off`
## @example
##     import log;
##
##     main(): int {
##         if (log.enabled(log.Level.Debug)) {
##             var queue = [1, 2, 3];
##             log.debug($"queue: {queue.count} jobs");
##         }
##         return 0;
##     }
export enabled(level: Level, target: String = ""): bool {
    if (level == Level.Off) {
        return false;
    }
    var config = _log_config.get();
    if ((level as int) > (config.loosest.load() as int)) {
        return false;
    }
    var shown = Level.Off;
    with (var state = config.state.lock()) {
        shown = state.shown(target);
    }
    return (level as int) <= (shown as int);
}

## Writes an error line: something failed.
##
## @param message the message
## @param fields keys and values to add to the line (see `field`)
## @param target the part of the program the line is about, which
##   `set_level` and `PEPPER_LOG` can show or hide on its own; empty for none
## @example
##     log.error("cannot open the database", [log.field("path", path)]);
export error(
    message: String,
    fields: Array<Field> = Array<Field>(),
    target: String = "",
    location: __ptr<char> = __caller_location()
) {
    _log_write(Level.Error, message, fields, target, location);
}

## Writes a warning line: something looks wrong but the program carries on.
##
## @param message the message
## @param fields keys and values to add to the line (see `field`)
## @param target the part of the program the line is about; empty for none
## @example
##     log.warning("retrying", [log.field("attempt", 2)], target = "http");
export warning(
    message: String,
    fields: Array<Field> = Array<Field>(),
    target: String = "",
    location: __ptr<char> = __caller_location()
) {
    _log_write(Level.Warning, message, fields, target, location);
}

## Writes an info line: what the program is doing.
##
## @param message the message
## @param fields keys and values to add to the line (see `field`)
## @param target the part of the program the line is about; empty for none
## @example
##     log.info("listening", [log.field("port", 8080)]);
export info(
    message: String,
    fields: Array<Field> = Array<Field>(),
    target: String = "",
    location: __ptr<char> = __caller_location()
) {
    _log_write(Level.Info, message, fields, target, location);
}

## Writes a debug line: detail for finding a bug. Not shown by default.
##
## @param message the message
## @param fields keys and values to add to the line (see `field`)
## @param target the part of the program the line is about; empty for none
## @example
##     log.debug("cache miss", [log.field("key", key)], target = "cache");
export debug(
    message: String,
    fields: Array<Field> = Array<Field>(),
    target: String = "",
    location: __ptr<char> = __caller_location()
) {
    _log_write(Level.Debug, message, fields, target, location);
}

## Writes a trace line: step-by-step detail. Not shown by default.
##
## @param message the message
## @param fields keys and values to add to the line (see `field`)
## @param target the part of the program the line is about; empty for none
## @example
##     log.trace("read a frame", [log.field("bytes", 512)], target = "http");
export trace(
    message: String,
    fields: Array<Field> = Array<Field>(),
    target: String = "",
    location: __ptr<char> = __caller_location()
) {
    _log_write(Level.Trace, message, fields, target, location);
}

_log_write(level: Level, message: String, fields: Array<Field>, target: String, location: __ptr<char>) {
    if (!enabled(level, target)) {
        return;
    }
    var stamp = time.now_utc().format("%FT%T.%3NZ");
    # Without the mark of an `[Unsafe("bounds")]` caller (see `_pep_panic`).
    var place = location[0] == 1 ? location + 1 : location;
    var where = _pep_string_from_c(place, strlen(place));
    var config = _log_config.get();
    var line = "";
    if (config.format.load() == Format.Json) {
        line = _log_json(stamp, level, message, fields, target, where);
    } else {
        line = _log_text(stamp, level, message, fields, target, where, config.color.load() == 1);
    }
    var bytes = line.bytes();
    with (var state = config.state.lock()) {
        state.writer.write_all(bytes);
    }
}

_log_text(
    stamp: String, level: Level, message: String, fields: Array<Field>, target: String, where: String, color: bool
): String {
    var line = $"{stamp} {_log_level_word(level, color)} ";
    if (!target.is_empty) {
        line = line + $"[{target}] ";
    }
    line = line + message;
    for (var field in fields) {
        line = line + $" {field.key}={field.value}";
    }
    return line + $" ({where})\n";
}

_log_json(stamp: String, level: Level, message: String, fields: Array<Field>, target: String, where: String): String {
    var line = $"{{\"time\":\"{stamp}\",\"level\":{json.encode(_log_level_name(level))}";
    if (!target.is_empty) {
        line = line + $",\"target\":{json.encode(target)}";
    }
    line = line + $",\"message\":{json.encode(message)},\"location\":{json.encode(where)}";
    for (var field in fields) {
        line = line + $",{json.encode(field.key)}:{field.value}";
    }
    return line + "}\n";
}

_log_level_name(level: Level): String {
    if (level == Level.Error) {
        return "error";
    }
    if (level == Level.Warning) {
        return "warning";
    }
    if (level == Level.Info) {
        return "info";
    }
    if (level == Level.Debug) {
        return "debug";
    }
    if (level == Level.Trace) {
        return "trace";
    }
    return "off";
}

# The level as the text format shows it: five columns, in color on a
# terminal.
_log_level_word(level: Level, color: bool): String {
    var word = _log_level_name(level).upper();
    if (word.size < 5) {
        word = word + " ".repeat(5 - word.size);
    }
    if (word == "WARNING") {
        word = "WARN ";
    }
    if (!color) {
        return word;
    }
    var code = "90";
    if (level == Level.Error) {
        code = "31";
    } else if (level == Level.Warning) {
        code = "33";
    } else if (level == Level.Info) {
        code = "32";
    } else if (level == Level.Debug) {
        code = "34";
    }
    return $"\x1B[{code}m{word}\x1B[0m";
}
