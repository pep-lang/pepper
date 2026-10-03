//! The `time` module (runtime/time/) in linked programs: calendar
//! arithmetic, offsets, formatting and parsing, and time zones from TZif
//! files, POSIX TZ rules, the local zone and the system's database.

use crate::support;
use crate::support::stdout_of;

const CALENDAR_PROGRAM: &str = r#"
import os;
import time;

dates_count_days_from_the_epoch(): int {
    if (time.Date().days() != 0 || time.Date(1969, 12, 31).days() != -1) { return 1; }
    if (time.Date(2000, 3, 1).days() != 11017 || time.Date(0, 1, 1).days() != -719528) { return 2; }
    # Every day from 1600 to 2400 survives the round trip and follows the last.
    var previous = time.Date(1599, 12, 31);
    for (var days in time.Date(1600, 1, 1).days()..time.Date(2400, 1, 1).days()) {
        var date = time.Date.from_days(days);
        if (date.days() != days || !(previous < date) || previous.add_days(1) != date) { return 3; }
        previous = date;
    }
    if (time.Date.from_days(-1000000) != time.Date(-768, 2, 4)) { return 4; }
    if (time.Date(2024, 3, 1).days_since(time.Date(2024, 2, 1)) != 29) { return 5; }
    return 0;
}

weekdays_years_and_months(): int {
    if (time.Date().weekday() != time.Weekday.Thursday || time.Date(2024, 2, 29).weekday() != time.Weekday.Thursday) { return 1; }
    if (time.Date(1, 1, 1).weekday() != time.Weekday.Monday || time.Date(-1, 12, 31).weekday() != time.Weekday.Friday) { return 2; }
    if (time.Weekday.Sunday as int != 7 || time.Weekday.Monday.name() != "Monday") { return 3; }
    if (!time.is_leap_year(2000) || time.is_leap_year(1900) || !time.is_leap_year(0) || !time.is_leap_year(-4)) { return 4; }
    if (time.days_in_month(2023, 2) != 28 || time.days_in_month(2024, 2) != 29 || time.days_in_month(2024, 4) != 30) { return 5; }
    if (time.Date(2024, 12, 31).day_of_year() != 366 || time.Date(2023, 3, 1).day_of_year() != 60) { return 6; }
    if (time.Date.checked(2023, 2, 29).is_value() || time.Date.checked(2024, 13, 1).is_value()) { return 7; }
    if (time.Date.checked(2024, 2, 29).value() != time.Date(2024, 2, 29)) { return 8; }
    return 0;
}

months_and_years_clamp_the_day(): int {
    if (time.Date(2024, 1, 31).add_months(1) != time.Date(2024, 2, 29)) { return 1; }
    if (time.Date(2023, 1, 31).add_months(1) != time.Date(2023, 2, 28)) { return 2; }
    if (time.Date(2024, 3, 15).add_months(-15) != time.Date(2022, 12, 15)) { return 3; }
    if (time.Date(2024, 2, 29).add_years(1) != time.Date(2025, 2, 28)) { return 4; }
    if (time.Date(2024, 2, 29).add_years(-4) != time.Date(2020, 2, 29)) { return 5; }
    if (time.Date(1, 1, 1).add_months(-1) != time.Date(0, 12, 1)) { return 6; }
    return 0;
}

dates_and_times_as_text(): int {
    if (time.Date(2024, 2, 9).to_string() != "2024-02-09" || $"{time.Date(-1, 12, 31)}" != "-0001-12-31") { return 1; }
    if (time.Date(12345, 6, 7).to_string() != "+12345-06-07" || time.Date(5, 1, 1).to_string() != "0005-01-01") { return 2; }
    if (time.Date.parse("2024-02-29").value() != time.Date(2024, 2, 29)) { return 3; }
    if (time.Date.parse("+12345-06-07").value() != time.Date(12345, 6, 7)) { return 4; }
    if (time.Date.parse("-0001-12-31").value() != time.Date(-1, 12, 31)) { return 5; }
    if (time.Date.parse("2023-02-29").is_ok() || time.Date.parse("2024-2-9").is_ok() || time.Date.parse("2024-02-09x").is_ok()) { return 6; }
    if (time.Time(8, 30).to_string() != "08:30:00" || time.Time(23, 59, 59, 250000000).to_string() != "23:59:59.25") { return 7; }
    if (time.Time(0, 0, 0, 1).to_string() != "00:00:00.000000001") { return 8; }
    if (time.Time.parse("08:30").value() != time.Time(8, 30)) { return 9; }
    if (time.Time.parse("08:30:05.1234567891").value() != time.Time(8, 30, 5, 123456789)) { return 10; }
    if (time.Time.parse("24:00:00").is_ok() || time.Time.parse("08:30:").is_ok() || time.Time.parse("08:30:00.").is_ok()) { return 11; }
    var dt = time.DateTime(2024, 3, 1, 9, 5, 7);
    if (dt.to_string() != "2024-03-01T09:05:07") { return 12; }
    if (time.DateTime.parse("2024-03-01 09:05:07").value() != dt || time.DateTime.parse("2024-03-01t09:05:07").value() != dt) { return 13; }
    if (time.DateTime.parse("2024-03-01").is_ok() || time.DateTime.parse("2024-03-01T09:05:07Z").is_ok()) { return 14; }
    return 0;
}

date_times_move_and_compare(): int {
    var dt = time.DateTime(2024, 12, 31, 23, 59, 59, 900000000);
    var later = dt + os.Duration.from_milliseconds(200);
    if (later != time.DateTime(2025, 1, 1, 0, 0, 0, 100000000)) { return 1; }
    if (later - os.Duration.from_milliseconds(200) != dt) { return 2; }
    if (!(dt < later) || !(later >= dt) || dt > later || !(dt <= dt)) { return 3; }
    var before = time.DateTime() - os.Duration.from_nanoseconds(1);
    if (before != time.DateTime(1969, 12, 31, 23, 59, 59, 999999999) || before.unix_seconds() != -1) { return 4; }
    if (time.DateTime.from_unix_seconds(1709283600) != time.DateTime(2024, 3, 1, 9, 0)) { return 5; }
    if (time.DateTime.from_unix_seconds(-86401) != time.DateTime(1969, 12, 30, 23, 59, 59)) { return 6; }
    var instant = os.SystemTime.from_unix_nanoseconds(-1);
    if (time.DateTime.from_system_time(instant) != before || before.to_system_time() != instant) { return 7; }
    if (time.Date(2024, 3, 1).at(time.Time(9)) != time.DateTime(2024, 3, 1, 9)) { return 8; }
    if (dt.year != 2024 || dt.month != 12 || dt.day != 31 || dt.hour != 23 || dt.minute != 59 || dt.second != 59) { return 9; }
    if (time.Time.from_nanoseconds(time.Time(13, 14, 15, 16).nanoseconds()) != time.Time(13, 14, 15, 16)) { return 10; }
    return 0;
}

offsets_and_rfc_3339(): int {
    if (time.Offset.from_hours(5, 30).seconds != 19800 || time.Offset.from_hours(-3, -30).to_string() != "-03:30") { return 1; }
    if (time.Offset().to_string() != "+00:00" || time.Offset(1172).to_string() != "+00:19:32") { return 2; }
    if (time.Offset.parse("Z").value() != time.Offset() || time.Offset.parse("-0530").value() != time.Offset.from_hours(-5, -30)) { return 3; }
    if (time.Offset.parse("+02").value() != time.Offset.from_hours(2) || time.Offset.parse("+24:00").is_ok()) { return 4; }
    var meeting = time.OffsetDateTime.parse("2024-03-01T09:00:00+01:00").value();
    if (meeting.date_time != time.DateTime(2024, 3, 1, 9) || meeting.offset != time.Offset.from_hours(1)) { return 5; }
    if (meeting.to_utc().to_string() != "2024-03-01T08:00:00Z" || meeting.to_string() != "2024-03-01T09:00:00+01:00") { return 6; }
    if (meeting.unix_seconds() != 1709280000 || meeting.to_system_time().unix_seconds() != 1709280000) { return 7; }
    var same = time.OffsetDateTime.parse("2024-03-01 08:00:00z").value();
    if (same == meeting || same < meeting || same > meeting || !(same <= meeting)) { return 8; }
    if (same.to_offset(time.Offset.from_hours(1)) != meeting) { return 9; }
    if (time.OffsetDateTime.parse("2024-03-01t08:00:00.5-00:30").value().to_string() != "2024-03-01T08:00:00.5-00:30") { return 10; }
    if (time.OffsetDateTime.parse("2024-03-01T08:00:00").is_ok() || time.OffsetDateTime.parse("2024-03-01T08:00:00+0100").is_ok()) { return 11; }
    var early = time.OffsetDateTime.from_system_time(os.SystemTime.from_unix_nanoseconds(-1500000000), time.Offset.from_hours(-1));
    if (early.to_string() != "1969-12-31T22:59:58.5-01:00") { return 12; }
    if (early + os.Duration.from_seconds(3600) != time.OffsetDateTime(time.DateTime(1969, 12, 31, 23, 59, 58, 500000000), time.Offset.from_hours(-1))) { return 13; }
    return 0;
}

formats_with_strftime_codes(): int {
    var at = time.OffsetDateTime(time.DateTime(2024, 3, 1, 9, 5, 7, 123456789), time.Offset.from_hours(-5, -30));
    if (at.format("%Y-%m-%d %H:%M:%S.%N %z %:z") != "2024-03-01 09:05:07.123456789 -0530 -05:30") { return 1; }
    if (at.format("%a %A %b %h %B %e %j %u %w") != "Fri Friday Mar Mar March  1 061 5 5") { return 2; }
    if (at.format("%F %T %R %I %p %C %y %3N %s %%") != "2024-03-01 09:05:07 09:05 09 AM 20 24 123 1709303707 %") { return 3; }
    if (time.DateTime(2024, 3, 3, 0, 1).format("%I%p %u %w") != "12AM 7 0") { return 4; }
    if (time.Time(13).format("%I %p|%n|%t") != "01 PM|\n|\t") { return 5; }
    if (time.Date(2021, 1, 3).format("%G-W%V-%u") != "2020-W53-7" || time.Date(2024, 12, 30).format("%G-W%V") != "2025-W01") { return 6; }
    if (time.Date(2026, 6, 15).format("%G-W%V") != "2026-W25" || time.Date(-50, 1, 1).format("%Y %C %y") != "-0050 -1 50") { return 7; }
    return 0;
}

reads_and_writes_http_dates(): int {
    var expected = time.OffsetDateTime(time.DateTime(1994, 11, 6, 8, 49, 37));
    if (time.OffsetDateTime.parse_http_date("Sun, 06 Nov 1994 08:49:37 GMT").value() != expected) { return 1; }
    if (time.OffsetDateTime.parse_http_date("Sunday, 06-Nov-94 08:49:37 GMT").value() != expected) { return 2; }
    if (time.OffsetDateTime.parse_http_date("Sun Nov  6 08:49:37 1994").value() != expected) { return 3; }
    if (time.OffsetDateTime.parse_http_date("Thursday, 01-Jan-04 00:00:00 GMT").value().date != time.Date(2004, 1, 1)) { return 4; }
    if (time.OffsetDateTime.parse_http_date("Mon, 06 Nov 1994 08:49:37 GMT").is_ok()) { return 5; }
    if (time.OffsetDateTime.parse_http_date("Sun, 06 Nov 1994 08:49:37 UTC").is_ok()) { return 6; }
    if (time.OffsetDateTime.parse_http_date("Sun, 6 Nov 1994 08:49:37 GMT").is_ok()) { return 7; }
    var at = time.OffsetDateTime.parse("2024-03-01T09:00:00.75+01:00").value();
    if (at.to_http_date() != "Fri, 01 Mar 2024 08:00:00 GMT") { return 8; }
    return 0;
}
"#;

#[test]
fn calendar_offsets_and_formatting() {
    support::linked_cases(
        "time_calendar",
        CALENDAR_PROGRAM,
        &[
            "dates_count_days_from_the_epoch",
            "weekdays_years_and_months",
            "months_and_years_clamp_the_day",
            "dates_and_times_as_text",
            "date_times_move_and_compare",
            "offsets_and_rfc_3339",
            "formats_with_strftime_codes",
            "reads_and_writes_http_dates",
        ],
        &[],
    );
}

/// A version 2 TZif file (RFC 8536): `transitions` as (UTC seconds, type
/// index), `types` as UTC offsets in seconds, and the POSIX TZ `footer`.
fn tzif(transitions: &[(i64, u8)], types: &[i32], footer: &str) -> Vec<u8> {
    fn header(out: &mut Vec<u8>, time_count: usize, type_count: usize) {
        out.extend_from_slice(b"TZif2");
        out.extend_from_slice(&[0; 15]);
        // isutcnt, isstdcnt, leapcnt, timecnt, typecnt, charcnt
        for count in [0, 0, 0, time_count, type_count, 4] {
            out.extend_from_slice(&(count as u32).to_be_bytes());
        }
    }
    let mut out = Vec::new();
    // The version 1 block, which readers of version 2 skip: one type.
    header(&mut out, 0, 1);
    out.extend_from_slice(&types[0].to_be_bytes());
    out.extend_from_slice(&[0, 0]);
    out.extend_from_slice(b"ZZZ\0");
    header(&mut out, transitions.len(), types.len());
    for (start, _) in transitions {
        out.extend_from_slice(&start.to_be_bytes());
    }
    for (_, index) in transitions {
        out.push(*index);
    }
    for offset in types {
        out.extend_from_slice(&offset.to_be_bytes());
        out.extend_from_slice(&[0, 0]);
    }
    out.extend_from_slice(b"ZZZ\0");
    out.push(b'\n');
    out.extend_from_slice(footer.as_bytes());
    out.push(b'\n');
    out
}

const ZONES_PROGRAM: &str = r#"
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
    print($"history {offset_at(history, "1969-12-31T23:59:59Z")} {offset_at(history, "1970-01-01T00:00:00Z")} {offset_at(history, "1970-01-12T13:46:40Z")} {offset_at(history, "2100-01-01T00:00:00Z")}");
    var julian = time.TimeZone.named("Test/Julian").value();
    print($"julian {offset_at(julian, "2024-02-29T12:00:00Z")} {offset_at(julian, "2024-03-01T12:00:00Z")} {offset_at(julian, "2024-03-02T12:00:00Z")}");
    print($"missing {time.TimeZone.named("Test/Missing").is_err()} {time.TimeZone.named("../Test/Rule").is_err()} {time.TimeZone.named("/etc/passwd").is_err()}");
    print($"garbage {time.TimeZone.named("Test/Garbage").is_err()}");
    print($"utc {time.TimeZone.named("UTC").value().name} {time.TimeZone.utc().offset_at(os.SystemTime.now())}");
    var fixed = time.TimeZone.fixed(time.Offset.from_hours(5, 30));
    print($"fixed {fixed.name} {offset_at(fixed, "2024-01-01T00:00:00Z")}");
    print($"local {offset_at(time.TimeZone.local(), "2024-01-15T12:00:00Z")} {offset_at(time.TimeZone.local(), "2024-07-15T12:00:00Z")}");
    print($"now {time.now().offset == time.TimeZone.local().offset_at(os.SystemTime.now())} {time.now_utc().offset.is_utc()}");
    return 0;
}
"#;

#[test]
fn zones_from_tzif_files_rules_and_the_local_zone() {
    let dir = std::env::temp_dir().join(format!("pepper_time_zones_{}", std::process::id()));
    let test = dir.join("Test");
    std::fs::create_dir_all(&test).unwrap();
    std::fs::write(test.join("Rule"), tzif(&[], &[3600], "CET-1CEST,M3.5.0,M10.5.0/3")).unwrap();
    std::fs::write(test.join("South"), tzif(&[], &[36000], "AEST-10AEDT,M10.1.0,M4.1.0/3")).unwrap();
    std::fs::write(test.join("History"), tzif(&[(0, 1), (1_000_000, 2)], &[1800, 3600, 7200], "")).unwrap();
    std::fs::write(test.join("Julian"), tzif(&[], &[0], "<+00>0<+01>-1,J60/0,J61/0")).unwrap();
    std::fs::write(test.join("Garbage"), b"not a zone").unwrap();
    let output = support::run_linked("time_zones", ZONES_PROGRAM, |command| {
        // A POSIX TZ string needs no database; every system honors TZDIR.
        command.env("TZDIR", &dir).env("TZ", "<+03>-3");
    });
    let _ = std::fs::remove_dir_all(&dir);
    let stdout = stdout_of(&output);
    assert!(output.status.success(), "{}", support::output_text(&output));
    // Windows reads the zone in its settings, not TZ.
    if !cfg!(windows) {
        let line = "local 2024-01-15T15:00:00+03:00 2024-07-15T15:00:00+03:00";
        assert!(stdout.contains(&format!("{line}\n")), "missing {line:?} in:\n{stdout}");
    }
    for line in [
        "rule Test/Rule 2024-01-15T13:00:00+01:00 2024-07-15T14:00:00+02:00",
        "rule edge 2024-03-31T01:59:59+01:00 2024-03-31T03:00:00+02:00",
        "rule back 2024-10-27T02:59:59+02:00 2024-10-27T02:00:00+01:00",
        "gap 2024-03-31T03:30:00+02:00",
        "overlap 2024-10-27T02:30:00+02:00",
        "plain 2024-06-01T12:00:00+02:00",
        "south 2024-01-15T23:00:00+11:00 2024-07-15T22:00:00+10:00",
        "history 1970-01-01T00:29:59+00:30 1970-01-01T01:00:00+01:00 1970-01-12T15:46:40+02:00 2100-01-01T02:00:00+02:00",
        "julian 2024-02-29T12:00:00Z 2024-03-01T13:00:00+01:00 2024-03-02T12:00:00Z",
        "garbage true",
        "missing true true true",
        "utc UTC +00:00",
        "fixed +05:30 2024-01-01T05:30:00+05:30",
        "now true true",
    ] {
        assert!(stdout.contains(&format!("{line}\n")), "missing {line:?} in:\n{stdout}");
    }
}

const SYSTEM_DATABASE_PROGRAM: &str = r#"
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
"#;

#[test]
fn named_zones_from_the_system_database() {
    let output = support::run_linked("time_system_zones", SYSTEM_DATABASE_PROGRAM, |command| {
        command.env_remove("TZDIR");
    });
    let stdout = stdout_of(&output);
    assert!(output.status.success(), "{}", support::output_text(&output));
    if stdout.contains("no database") {
        // Linux without tzdata installed; macOS and Windows always have one.
        assert!(cfg!(target_os = "linux"), "{stdout}");
        return;
    }
    for line in [
        "paris 2024-07-14T12:00:00+02:00 2024-01-14T11:00:00+01:00 2100-07-14T12:00:00+02:00",
        "local 2024-12-25T18:00:00+01:00",
        "kolkata +05:30",
        "unknown true",
    ] {
        assert!(stdout.contains(&format!("{line}\n")), "missing {line:?} in:\n{stdout}");
    }
}
