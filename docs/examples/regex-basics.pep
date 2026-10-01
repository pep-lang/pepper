# Regular expressions: match, capture, iterate, replace and split.
import regex;

main(): int {
    # Compile once, reuse. Backslashes are doubled inside a string literal.
    var date = regex.Regex("(?<year>\\d{4})-(\\d{2})-(\\d{2})");
    assert(date.is_match("due 2026-10-01"), "a date somewhere");

    # The first match, with its groups. Positions are byte offsets.
    var found = date.find("due 2026-10-01").value();
    assert(found.text() == "2026-10-01" && found.start() == 4, "where");
    assert(found.group(2).value() == "10", "a numbered group");
    assert(found.group("year").value() == "2026", "a named group");

    # Every match, left to right.
    var total = 0;
    for (var number in regex.Regex("\\d+").find_all("1 22 333")) {
        total += int.parse(number.text()).value();
    }
    assert(total == 356, "1 + 22 + 333");

    # Replace with group references, and split.
    var swapped = regex.Regex("(\\w+)@(\\w+)").replace_all("ann@home bob@work", "$2:$1");
    assert(swapped == "home:ann work:bob", "groups swapped");
    var parts = regex.Regex("\\s*,\\s*").split("a , b,c");
    assert(parts.count() == 3 && parts[1] == "b", "three pieces");

    # Flags go inside the pattern: (?i) ignores case.
    assert(regex.Regex("(?i)^hello").is_match("HeLLo there"), "any case");

    # An invalid pattern from outside the program: parse reports it.
    var bad = regex.Regex.parse("(unclosed");
    assert(bad.is_err(), "missing ')'");
    return 0;
}
