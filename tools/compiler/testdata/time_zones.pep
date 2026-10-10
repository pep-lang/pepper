# Prints offsets in the zones of the TZif files under `TZDIR`, and in the
# local zone `TZ` names (programs_test.pep).

import os;
import time;

offset_at(zone: time.TimeZone, utc: String): String {
    var instant = time.OffsetDateTime.parse(utc).value().to_system_time();
    return zone.at(instant).to_string();
}

main(): int {
    var rule = time.TimeZone.named("Test/Rule").value();
    print($"rule {rule.name} {offset_at(rule, "2024-01-15T12:00:00Z")} {offset_at(rule, "2024-07-15T12:00:00Z")}");
    print($"rule edge {offset_at(rule, "2024-03-31T00:59:59Z")} {offset_at(rule, "2024-03-31T01:00:00Z")}");
    print($"rule back {offset_at(rule, "2024-10-27T00:59:59Z")} {offset_at(rule, "2024-10-27T01:00:00Z")}");
    print($"gap {rule.at_local(time.DateTime(2024, 3, 31, 2, 30))}");
    print($"overlap {rule.at_local(time.DateTime(2024, 10, 27, 2, 30))}");
    print($"plain {rule.at_local(time.DateTime(2024, 6, 1, 12))}");
    var south = time.TimeZone.named("Test/South").value();
    print($"south {offset_at(south, "2024-01-15T12:00:00Z")} {offset_at(south, "2024-07-15T12:00:00Z")}");
    var history = time.TimeZone.named("Test/History").value();
    print(
        $"history {offset_at(history, "1969-12-31T23:59:59Z")} {offset_at(history, "1970-01-01T00:00:00Z")} {offset_at(history, "1970-01-12T13:46:40Z")} {offset_at(history, "2100-01-01T00:00:00Z")}"
    );
    var julian = time.TimeZone.named("Test/Julian").value();
    print(
        $"julian {offset_at(julian, "2024-02-29T12:00:00Z")} {offset_at(julian, "2024-03-01T12:00:00Z")} {offset_at(julian, "2024-03-02T12:00:00Z")}"
    );
    print(
        $"missing {time.TimeZone.named("Test/Missing").is_err()} {time.TimeZone.named("../Test/Rule").is_err()} {time.TimeZone.named("/etc/passwd").is_err()}"
    );
    print($"garbage {time.TimeZone.named("Test/Garbage").is_err()}");
    print($"utc {time.TimeZone.named("UTC").value().name} {time.TimeZone.utc().offset_at(os.SystemTime.now())}");
    var fixed = time.TimeZone.fixed(time.Offset.from_hours(5, 30));
    print($"fixed {fixed.name} {offset_at(fixed, "2024-01-01T00:00:00Z")}");
    print(
        $"local {offset_at(time.TimeZone.local(), "2024-01-15T12:00:00Z")} {offset_at(time.TimeZone.local(), "2024-07-15T12:00:00Z")}"
    );
    print(
        $"now {time.now().offset == time.TimeZone.local().offset_at(os.SystemTime.now())} {time.now_utc().offset.is_utc()}"
    );
    return 0;
}
