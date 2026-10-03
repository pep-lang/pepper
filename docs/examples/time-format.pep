import time;

main(): int {
    # An OffsetDateTime is an RFC 3339 timestamp: a date and time at an
    # offset from UTC, which together name one instant.
    var meeting = time.OffsetDateTime.parse("2024-03-01T09:00:00+01:00").value();
    print(meeting.to_utc());  # 2024-03-01T08:00:00Z
    assert(meeting.offset == time.Offset.from_hours(1), "the offset it was written at");

    # The same instant at two offsets is not ==, but compares as equal.
    var utc = meeting.to_utc();
    assert(utc != meeting && !(utc < meeting) && !(utc > meeting), "one instant");
    assert(utc.to_system_time() == meeting.to_system_time(), "one SystemTime");

    # strftime codes lay a date out any way.
    assert(meeting.format("%A %e %B %Y, %H:%M %:z") == "Friday  1 March 2024, 09:00 +01:00", "strftime");
    assert(meeting.format("%G-W%V-%u") == "2024-W09-5", "the ISO week date");

    # HTTP's Date and Last-Modified headers, both ways.
    var header = meeting.to_http_date();
    assert(header == "Fri, 01 Mar 2024 08:00:00 GMT", "an IMF-fixdate, in GMT");
    assert(time.OffsetDateTime.parse_http_date(header).value() == utc, "and back");
    return 0;
}
