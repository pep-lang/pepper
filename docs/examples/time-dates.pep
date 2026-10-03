import os;
import time;

main(): int {
    # A Date is a day on the calendar, with no time of day or zone.
    var leap_day = time.Date(2024, 2, 29);
    assert(leap_day.weekday() == time.Weekday.Thursday, "2024-02-29 was a Thursday");
    assert(leap_day.day_of_year() == 60, "the 60th day of the year");
    assert(leap_day.add_years(1) == time.Date(2025, 2, 28), "no February 29 in 2025");
    assert(time.Date(2024, 1, 31).add_months(1) == leap_day, "the last day of February");
    assert(time.Date(2024, 12, 25).days_since(leap_day) == 300, "days between dates");

    # Parts from outside the program are checked, not trusted.
    assert(time.Date.checked(2023, 2, 29).is_empty(), "2023 is not a leap year");
    assert(time.Date.parse("2024-02-29").value() == leap_day, "ISO 8601 text");

    # A DateTime adds a time of day; durations move it.
    var start = time.DateTime(2024, 3, 1, 23, 30);
    var end = start + os.Duration.from_seconds(90 * 60);
    print(end);  # 2024-03-02T01:00:00
    assert(end.date == time.Date(2024, 3, 2) && end.time == time.Time(1, 0), "past midnight");
    assert(start < end, "date times compare");
    return 0;
}
