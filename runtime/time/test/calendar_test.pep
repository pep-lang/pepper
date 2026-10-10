# The time module's calendar: days from the epoch, weekdays, leap years,
# month and year arithmetic, dates and times as text, offsets and RFC 3339,
# strftime-style formatting, and HTTP dates. Time zones, which depend on
# the process's environment, are tested in whole programs by
# tools/compiler/programs_test.pep.

import os;
import time;

[Test]
dates_count_days_from_the_epoch() {
    expect_equal(time.Date().days(), 0);
    expect_equal(time.Date(1969, 12, 31).days(), -1);
    expect_equal(time.Date(2000, 3, 1).days(), 11017);
    expect_equal(time.Date(0, 1, 1).days(), -719528);
    # Every day from 1600 to 2400 survives the round trip and follows the last.
    var previous = time.Date(1599, 12, 31);
    for (var days in time.Date(1600, 1, 1).days()..time.Date(2400, 1, 1).days()) {
        var date = time.Date.from_days(days);
        if (date.days() != days || !(previous < date) || previous.add_days(1) != date) {
            panic($"day {days} does not round-trip");
        }
        previous = date;
    }
    expect_equal(time.Date.from_days(-1000000), time.Date(-768, 2, 4));
    expect_equal(time.Date(2024, 3, 1).days_since(time.Date(2024, 2, 1)), 29);
}

[Test]
weekdays_years_and_months() {
    expect_true(time.Date().weekday() == time.Weekday.Thursday);
    expect_true(time.Date(2024, 2, 29).weekday() == time.Weekday.Thursday);
    expect_true(time.Date(1, 1, 1).weekday() == time.Weekday.Monday);
    expect_true(time.Date(-1, 12, 31).weekday() == time.Weekday.Friday);
    expect_equal(time.Weekday.Sunday as int, 7);
    expect_equal(time.Weekday.Monday.name(), "Monday");
    expect_true(time.is_leap_year(2000));
    expect_false(time.is_leap_year(1900));
    expect_true(time.is_leap_year(0));
    expect_true(time.is_leap_year(-4));
    expect_equal(time.days_in_month(2023, 2), 28);
    expect_equal(time.days_in_month(2024, 2), 29);
    expect_equal(time.days_in_month(2024, 4), 30);
    expect_equal(time.Date(2024, 12, 31).day_of_year(), 366);
    expect_equal(time.Date(2023, 3, 1).day_of_year(), 60);
    expect_false(time.Date.checked(2023, 2, 29).is_value());
    expect_false(time.Date.checked(2024, 13, 1).is_value());
    expect_equal(time.Date.checked(2024, 2, 29).value(), time.Date(2024, 2, 29));
}

[Test]
months_and_years_clamp_the_day() {
    expect_equal(time.Date(2024, 1, 31).add_months(1), time.Date(2024, 2, 29));
    expect_equal(time.Date(2023, 1, 31).add_months(1), time.Date(2023, 2, 28));
    expect_equal(time.Date(2024, 3, 15).add_months(-15), time.Date(2022, 12, 15));
    expect_equal(time.Date(2024, 2, 29).add_years(1), time.Date(2025, 2, 28));
    expect_equal(time.Date(2024, 2, 29).add_years(-4), time.Date(2020, 2, 29));
    expect_equal(time.Date(1, 1, 1).add_months(-1), time.Date(0, 12, 1));
}

[Test]
dates_and_times_as_text() {
    expect_equal(time.Date(2024, 2, 9).to_string(), "2024-02-09");
    expect_equal($"{time.Date(-1, 12, 31)}", "-0001-12-31");
    expect_equal(time.Date(12345, 6, 7).to_string(), "+12345-06-07");
    expect_equal(time.Date(5, 1, 1).to_string(), "0005-01-01");
    expect_equal(time.Date.parse("2024-02-29").value(), time.Date(2024, 2, 29));
    expect_equal(time.Date.parse("+12345-06-07").value(), time.Date(12345, 6, 7));
    expect_equal(time.Date.parse("-0001-12-31").value(), time.Date(-1, 12, 31));
    expect_false(time.Date.parse("2023-02-29").is_ok());
    expect_false(time.Date.parse("2024-2-9").is_ok());
    expect_false(time.Date.parse("2024-02-09x").is_ok());
    expect_equal(time.Time(8, 30).to_string(), "08:30:00");
    expect_equal(time.Time(23, 59, 59, 250000000).to_string(), "23:59:59.25");
    expect_equal(time.Time(0, 0, 0, 1).to_string(), "00:00:00.000000001");
    expect_equal(time.Time.parse("08:30").value(), time.Time(8, 30));
    expect_equal(time.Time.parse("08:30:05.1234567891").value(), time.Time(8, 30, 5, 123456789));
    expect_false(time.Time.parse("24:00:00").is_ok());
    expect_false(time.Time.parse("08:30:").is_ok());
    expect_false(time.Time.parse("08:30:00.").is_ok());
    var date_time = time.DateTime(2024, 3, 1, 9, 5, 7);
    expect_equal(date_time.to_string(), "2024-03-01T09:05:07");
    expect_equal(time.DateTime.parse("2024-03-01 09:05:07").value(), date_time);
    expect_equal(time.DateTime.parse("2024-03-01t09:05:07").value(), date_time);
    expect_false(time.DateTime.parse("2024-03-01").is_ok());
    expect_false(time.DateTime.parse("2024-03-01T09:05:07Z").is_ok());
}

[Test]
date_times_move_and_compare() {
    var date_time = time.DateTime(2024, 12, 31, 23, 59, 59, 900000000);
    var later = date_time + os.Duration.from_milliseconds(200);
    expect_equal(later, time.DateTime(2025, 1, 1, 0, 0, 0, 100000000));
    expect_equal(later - os.Duration.from_milliseconds(200), date_time);
    expect_true(date_time < later);
    expect_true(later >= date_time);
    expect_false(date_time > later);
    expect_true(date_time <= date_time);
    var before = time.DateTime() - os.Duration.from_nanoseconds(1);
    expect_equal(before, time.DateTime(1969, 12, 31, 23, 59, 59, 999999999));
    expect_equal(before.unix_seconds(), -1);
    expect_equal(time.DateTime.from_unix_seconds(1709283600), time.DateTime(2024, 3, 1, 9, 0));
    expect_equal(time.DateTime.from_unix_seconds(-86401), time.DateTime(1969, 12, 30, 23, 59, 59));
    var instant = os.SystemTime.from_unix_nanoseconds(-1);
    expect_equal(time.DateTime.from_system_time(instant), before);
    expect_true(before.to_system_time() == instant);
    expect_equal(time.Date(2024, 3, 1).at(time.Time(9)), time.DateTime(2024, 3, 1, 9));
    expect_equal(date_time.year, 2024);
    expect_equal(date_time.month, 12);
    expect_equal(date_time.day, 31);
    expect_equal(date_time.hour, 23);
    expect_equal(date_time.minute, 59);
    expect_equal(date_time.second, 59);
    expect_equal(time.Time.from_nanoseconds(time.Time(13, 14, 15, 16).nanoseconds()), time.Time(13, 14, 15, 16));
}

[Test]
offsets_and_rfc_3339() {
    expect_equal(time.Offset.from_hours(5, 30).seconds, 19800);
    expect_equal(time.Offset.from_hours(-3, -30).to_string(), "-03:30");
    expect_equal(time.Offset().to_string(), "+00:00");
    expect_equal(time.Offset(1172).to_string(), "+00:19:32");
    expect_equal(time.Offset.parse("Z").value(), time.Offset());
    expect_equal(time.Offset.parse("-0530").value(), time.Offset.from_hours(-5, -30));
    expect_equal(time.Offset.parse("+02").value(), time.Offset.from_hours(2));
    expect_false(time.Offset.parse("+24:00").is_ok());
    var meeting = time.OffsetDateTime.parse("2024-03-01T09:00:00+01:00").value();
    expect_equal(meeting.date_time, time.DateTime(2024, 3, 1, 9));
    expect_equal(meeting.offset, time.Offset.from_hours(1));
    expect_equal(meeting.to_utc().to_string(), "2024-03-01T08:00:00Z");
    expect_equal(meeting.to_string(), "2024-03-01T09:00:00+01:00");
    expect_equal(meeting.unix_seconds(), 1709280000);
    expect_equal(meeting.to_system_time().unix_seconds(), 1709280000);
    var same = time.OffsetDateTime.parse("2024-03-01 08:00:00z").value();
    expect_false(same == meeting);
    expect_false(same < meeting);
    expect_false(same > meeting);
    expect_true(same <= meeting);
    expect_equal(same.to_offset(time.Offset.from_hours(1)), meeting);
    expect_equal(
        time.OffsetDateTime.parse("2024-03-01t08:00:00.5-00:30").value().to_string(), "2024-03-01T08:00:00.5-00:30"
    );
    expect_false(time.OffsetDateTime.parse("2024-03-01T08:00:00").is_ok());
    expect_false(time.OffsetDateTime.parse("2024-03-01T08:00:00+0100").is_ok());
    var early = time.OffsetDateTime.from_system_time(
        os.SystemTime.from_unix_nanoseconds(-1500000000), time.Offset.from_hours(-1)
    );
    expect_equal(early.to_string(), "1969-12-31T22:59:58.5-01:00");
    var expected = time.OffsetDateTime(time.DateTime(1969, 12, 31, 23, 59, 58, 500000000), time.Offset.from_hours(-1));
    expect_equal(early + os.Duration.from_seconds(3600), expected);
}

[Test]
formats_with_strftime_codes() {
    var at = time.OffsetDateTime(time.DateTime(2024, 3, 1, 9, 5, 7, 123456789), time.Offset.from_hours(-5, -30));
    expect_equal(at.format("%Y-%m-%d %H:%M:%S.%N %z %:z"), "2024-03-01 09:05:07.123456789 -0530 -05:30");
    expect_equal(at.format("%a %A %b %h %B %e %j %u %w"), "Fri Friday Mar Mar March  1 061 5 5");
    expect_equal(at.format("%F %T %R %I %p %C %y %3N %s %%"), "2024-03-01 09:05:07 09:05 09 AM 20 24 123 1709303707 %");
    expect_equal(time.DateTime(2024, 3, 3, 0, 1).format("%I%p %u %w"), "12AM 7 0");
    expect_equal(time.Time(13).format("%I %p|%n|%t"), "01 PM|\n|\t");
    expect_equal(time.Date(2021, 1, 3).format("%G-W%V-%u"), "2020-W53-7");
    expect_equal(time.Date(2024, 12, 30).format("%G-W%V"), "2025-W01");
    expect_equal(time.Date(2026, 6, 15).format("%G-W%V"), "2026-W25");
    expect_equal(time.Date(-50, 1, 1).format("%Y %C %y"), "-0050 -1 50");
}

[Test]
reads_and_writes_http_dates() {
    var expected = time.OffsetDateTime(time.DateTime(1994, 11, 6, 8, 49, 37));
    expect_equal(time.OffsetDateTime.parse_http_date("Sun, 06 Nov 1994 08:49:37 GMT").value(), expected);
    expect_equal(time.OffsetDateTime.parse_http_date("Sunday, 06-Nov-94 08:49:37 GMT").value(), expected);
    expect_equal(time.OffsetDateTime.parse_http_date("Sun Nov  6 08:49:37 1994").value(), expected);
    expect_equal(
        time.OffsetDateTime.parse_http_date("Thursday, 01-Jan-04 00:00:00 GMT").value().date, time.Date(2004, 1, 1)
    );
    expect_false(time.OffsetDateTime.parse_http_date("Mon, 06 Nov 1994 08:49:37 GMT").is_ok());
    expect_false(time.OffsetDateTime.parse_http_date("Sun, 06 Nov 1994 08:49:37 UTC").is_ok());
    expect_false(time.OffsetDateTime.parse_http_date("Sun, 6 Nov 1994 08:49:37 GMT").is_ok());
    var at = time.OffsetDateTime.parse("2024-03-01T09:00:00.75+01:00").value();
    expect_equal(at.to_http_date(), "Fri, 01 Mar 2024 08:00:00 GMT");
}
