# Leveled, structured logging: levels, fields, a target, and a JSON file.
import io;
import log;

main(): int {
    log.info("started");
    log.warning("disk almost full", [log.field("free_mb", 120)], target = "storage");
    log.debug("hidden: the default level is info");

    log.set_level(log.Level.Debug, "storage");
    if (log.enabled(log.Level.Debug, "storage")) {
        log.debug("scanning", [log.field("path", "/var/data")], target = "storage");
    }

    # From here on, lines go to a file as JSON Lines.
    var path = io.Directory.temp().join("logging-basics.log");
    var file = io.File.create(copy(path)).value();
    log.set_output(move(file), log.Format.Json);
    log.error("cannot connect", [log.field("attempt", 3)], target = "db");
    log.set_output(io.File.stderr());

    var text = io.File.read_to_string(path).value();
    assert(text.starts_with("{\"time\":"), "one JSON object per line");
    assert(text.contains("\"level\":\"error\",\"target\":\"db\",\"message\":\"cannot connect\""), "the line's keys");
    assert(text.contains("\"attempt\":3}"), "the field, as JSON");
    io.File.remove(path);
    return 0;
}
