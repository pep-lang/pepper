import os;
import time;

main(): int {
    # The local zone and UTC are always there.
    var now = os.SystemTime.now();
    print($"here: {time.TimeZone.local().at(now)}");
    print($"UTC:  {time.now_utc()}");

    # Named zones come from the system's time zone database.
    var found = time.TimeZone.named("Europe/Paris");
    if (found is Ok(paris)) {
        var bastille = time.OffsetDateTime.parse("2024-07-14T10:00:00Z").value();
        assert(paris.at(bastille.to_system_time()).to_string() == "2024-07-14T12:00:00+02:00", "summer time");

        # A local time in the zone gets the offset in effect then.
        var christmas = paris.at_local(time.DateTime(2024, 12, 25, 18, 0));
        assert(christmas.offset == time.Offset.from_hours(1), "winter time");

        # 02:30 never happens on the night the clocks go forward: it moves
        # on by the hour that was skipped.
        var skipped = paris.at_local(time.DateTime(2024, 3, 31, 2, 30));
        assert(skipped.to_string() == "2024-03-31T03:30:00+02:00", "the gap");
    }
    assert(time.TimeZone.named("Nowhere/Atlantis").is_err(), "an unknown zone");
    return 0;
}
