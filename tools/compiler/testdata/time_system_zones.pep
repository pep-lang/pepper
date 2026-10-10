# Prints offsets in zones of the system's database, or that it has none
# (programs_test.pep).

import time;

main(): int {
    var paris = time.TimeZone.named("Europe/Paris");
    if (paris.is_err()) {
        print("no database");
        return 0;
    }
    var zone = paris.value();
    var summer = time.OffsetDateTime.parse("2024-07-14T10:00:00Z").value().to_system_time();
    var winter = time.OffsetDateTime.parse("2024-01-14T10:00:00Z").value().to_system_time();
    var future = time.OffsetDateTime.parse("2100-07-14T10:00:00Z").value().to_system_time();
    print($"paris {zone.at(summer)} {zone.at(winter)} {zone.at(future)}");
    print($"local {zone.at_local(time.DateTime(2024, 12, 25, 18, 0))}");
    print($"kolkata {time.TimeZone.named("Asia/Kolkata").value().offset_at(summer)}");
    print($"unknown {time.TimeZone.named("Nowhere/Atlantis").is_err()}");
    return 0;
}
