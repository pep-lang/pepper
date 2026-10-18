# The log module: levels, targets, fields, both formats, and PEPPER_LOG.
# Each test runs in a process of its own, so each sets the output afresh.

import async;
import io;
import json;
import log;
import os;

# Sends lines to a new file and returns its path. The log keeps its
# settings and output for the program, so the leak check leaves out what
# changing them allocates.
private capture(name: String, format: log.Format = log.Format.Text): io.Path {
    var path = io.Directory.temp().join("pepper-log-" + name + ".log");
    keep_for_the_program(() => {
        var file = io.File.create(copy(path)).value();
        log.set_output(move(file), format);
    });
    return path;
}

# Closes the file `capture` made (back to standard error) and returns what
# it holds.
private captured(path: io.Path): String {
    keep_for_the_program(() => {
        log.set_output(io.File.stderr());
    });
    var text = io.File.read_to_string(path).value();
    io.File.remove(path);
    return text;
}

private set_level(level: log.Level, target: String = "") {
    keep_for_the_program(() => {
        log.set_level(level, target);
    });
}

[Test]
info_is_shown_and_debug_is_not_by_default() {
    var path = capture("default");
    log.info("hello");
    log.debug("hidden");
    var text = captured(path);
    expect_true(text.contains(" INFO  hello ("));
    expect_true(text.contains("log_test.pep:"));
    expect_false(text.contains("hidden"));
    expect_equal(text.split("\n").count, 2);
}

[Test]
text_lines_carry_target_and_fields() {
    var path = capture("text");
    log.warning("slow", [log.field("ms", 250), log.field("path", "/a b")], target = "http");
    var text = captured(path);
    expect_true(text.ends_with("\n"));
    expect_true(text.contains(" WARN  [http] slow ms=250 path=\"/a b\" ("));
    expect_true(text.starts_with("20"));
    expect_true(text.contains("Z WARN"));
}

[Test]
json_lines_are_objects() {
    var path = capture("json", log.Format.Json);
    log.error("failed \"x\"", [log.field("code", 7), log.field("ok", false)], target = "db");
    var line = captured(path).trim();
    var value = json.parse(line).value();
    expect_equal(value["level"].as_string().value(), "error");
    expect_equal(value["target"].as_string().value(), "db");
    expect_equal(value["message"].as_string().value(), "failed \"x\"");
    expect_equal(value["code"].as_int().value(), 7);
    expect_true(value["location"].as_string().value().contains("log_test.pep:"));
}

[Test]
set_level_per_target() {
    var path = capture("targets");
    set_level(log.Level.Warning);
    set_level(log.Level.Trace, "net");
    expect_true(log.enabled(log.Level.Trace, "net"));
    expect_false(log.enabled(log.Level.Info));
    expect_false(log.enabled(log.Level.Off, "net"));
    log.info("quiet");
    log.trace("loud", target = "net");
    set_level(log.Level.Off, "net");
    log.error("off", target = "net");
    var text = captured(path);
    expect_false(text.contains("quiet"));
    expect_true(text.contains("[net] loud"));
    expect_false(text.contains("off"));
}

[Test]
pepper_log_sets_the_levels() {
    os.set_environment("PEPPER_LOG", "error, cache=debug,bogus=loud");
    keep_for_the_program(() => {
        expect_false(log.enabled(log.Level.Warning));
    });
    expect_true(log.enabled(log.Level.Debug, "cache"));
    expect_false(log.enabled(log.Level.Trace, "cache"));
    expect_true(log.enabled(log.Level.Error, "bogus"));
}

private log_lines() {
    var index = 0;
    while (index < 200) {
        log.info("from a thread", [log.field("index", index)]);
        index = index + 1;
    }
}

# Lines from many threads arrive whole, one per line.
[Test]
threads_never_interleave_lines() {
    var path = capture("threads");
    var threads = Array<async.Thread>();
    var count = 0;
    while (count < 4) {
        threads.append(async.Thread.spawn(log_lines));
        count = count + 1;
    }
    for (var thread in threads) {
        thread.join();
    }
    var lines = captured(path).trim().split("\n");
    expect_equal(lines.count, 800);
    for (var line in lines) {
        expect_true(line.contains(" INFO  from a thread index="));
        expect_true(line.ends_with(")"));
    }
}
