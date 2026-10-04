//! The `time` module (runtime/time/) in linked programs: time zones from
//! TZif files, POSIX TZ rules, the local zone and the system's database,
//! which depend on the program's environment (`TZDIR`, `TZ`). The calendar,
//! offsets and formatting are tested by `runtime/time/test/`.

use crate::support;
use crate::support::stdout_of;

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
