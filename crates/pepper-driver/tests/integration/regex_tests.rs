//! The `regex` module: pattern syntax, leftmost-first matching, flags,
//! iteration over matches, replacement, splitting, UTF-8 text, invalid
//! patterns, and linear time on patterns that make backtracking engines
//! explode. Each test returns 0 on success or a distinct negative code per
//! check, and must leave no allocation behind.

use crate::io_tests::assert_runs;
use crate::support::jit_census;

fn run(source: &str) -> i32 {
    let (result, leaked) = jit_census(source);
    assert_eq!(leaked, 0, "allocations leaked or double-released");
    result
}

#[test]
fn matches_the_syntax() {
    assert_eq!(
        run(r##"
import regex;

# The text of the first match of `pattern` in `text`, or "<none>".
first(pattern: String, text: String): String {
    var found = regex.Regex(pattern).find(text);
    if (found.is_none()) {
        return "<none>";
    }
    return found.value().text();
}

test(): int {
    if (first("b+", "abbbc") != "bbb") { return -1; }
    if (first("a.c", "xabcx") != "abc") { return -2; }
    if (first("a.c", "a\nc") != "<none>") { return -3; }
    if (first("[a-c]+", "xxcabz") != "cab") { return -4; }
    if (first("[^a-c]+", "abxyc") != "xy") { return -5; }
    if (first("[]a]+", "x]a]y") != "]a]") { return -6; }
    if (first("[a-]+", "x-a-y") != "-a-") { return -7; }
    if (first("\\d+", "ab123c") != "123") { return -8; }
    if (first("\\D+", "12ab3") != "ab") { return -9; }
    if (first("\\w+", "  hi_9!") != "hi_9") { return -10; }
    if (first("\\s+", "a \t\nb") != " \t\n") { return -11; }
    if (first("[\\d.]+", "v1.25!") != "1.25") { return -12; }
    if (first("[[:alpha:]]+", "12abc3") != "abc") { return -13; }
    if (first("[[:^digit:]]+", "12abc3") != "abc") { return -14; }
    if (first("\\x41\\x{42}", "zABz") != "AB") { return -15; }
    if (first("\\.\\*", "a.*b") != ".*") { return -16; }
    if (first("a{2}", "aaaa") != "aa") { return -17; }
    if (first("a{2,}", "aaaa") != "aaaa") { return -18; }
    if (first("a{1,3}", "aaaa") != "aaa") { return -19; }
    if (first("a{,2}", "a{,2}") != "a{,2}") { return -20; }
    if (first("x{0}y", "xy") != "y") { return -21; }
    if (first("a+?", "aaa") != "a") { return -22; }
    if (first("a*?b", "aab") != "aab") { return -23; }
    if (first("a{2,3}?", "aaaa") != "aa") { return -24; }
    if (first("<.+>", "<a><b>") != "<a><b>") { return -25; }
    if (first("<.+?>", "<a><b>") != "<a>") { return -26; }
    # Leftmost first: the earliest start wins, then the earlier branch.
    if (first("b|ab", "ab") != "ab") { return -27; }
    if (first("a|ab", "ab") != "a") { return -28; }
    if (first("ab|a", "ab") != "ab") { return -29; }
    if (first("", "abc") != "") { return -30; }
    if (first("colou?r", "my color") != "color") { return -31; }
    if (first("(?:ab)+", "ababa") != "abab") { return -32; }
    # Anchors and word boundaries.
    if (first("^a", "ba") != "<none>") { return -40; }
    if (first("a$", "ab") != "<none>") { return -41; }
    if (first("^a$", "a") != "a") { return -42; }
    if (first("\\bcat\\b", "concat cat") != "cat") { return -43; }
    if (regex.Regex("\\bcat\\b").find("concat cat").value().start() != 7) { return -44; }
    if (first("\\Bat", "at cat") != "at") { return -45; }
    if (regex.Regex("\\Bat").find("at cat").value().start() != 4) { return -46; }
    if (first("\\Aa\\z", "a") != "a") { return -47; }
    if (first("\\Aa", "ba") != "<none>") { return -48; }
    if (!regex.Regex("^\\d+$").is_match("2026")) { return -49; }
    if (regex.Regex("^\\d+$").is_match("2026a")) { return -50; }
    if (regex.Regex("x").is_match("")) { return -51; }
    if (!regex.Regex("x*").is_match("")) { return -52; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn reports_groups() {
    assert_eq!(
        run(r##"
import regex;

test(): int {
    var date = regex.Regex("(\\d{4})-(\\d{2})-(\\d{2})");
    if (date.group_count() != 3) { return -1; }
    var found = date.find("due 2026-10-01!").value();
    if (found.text() != "2026-10-01" || found.start() != 4 || found.end() != 14) { return -2; }
    if (found.group(0).value() != "2026-10-01") { return -3; }
    if (found.group(1).value() != "2026" || found.group(3).value() != "01") { return -4; }
    if (found.group_count() != 3) { return -5; }
    var (start, end) = found.group_range(2).value();
    if (start != 9 || end != 11) { return -6; }

    var named = regex.Regex("(?<key>\\w+)=(?P<value>\\w*)");
    var pair = named.find("x  name=pepper").value();
    if (pair.group("key").value() != "name" || pair.group("value").value() != "pepper") { return -10; }
    if (pair.group(2).value() != "pepper") { return -11; }

    # A group that does not take part is none; an empty one is "".
    var either = regex.Regex("(a)|(b)").find("b").value();
    if (either.group(1).is_some() || either.group(2).value() != "b") { return -20; }
    if (either.group_range(1).is_some()) { return -21; }
    var empty = regex.Regex("x(y*)z").find("xz").value();
    if (empty.group(1).value() != "") { return -22; }

    # A repeated group keeps its last iteration.
    var last = regex.Regex("(\\w)+").find("abc").value();
    if (last.group(1).value() != "c") { return -30; }
    # Nested groups are numbered by their opening '('.
    var nested = regex.Regex("((a)(b))").find("ab").value();
    if (nested.group(1).value() != "ab" || nested.group(2).value() != "a" || nested.group(3).value() != "b") {
        return -31;
    }
    if ($"{nested}" != "ab" || $"{named}" != named.pattern()) { return -32; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn applies_flags() {
    assert_eq!(
        run(r##"
import regex;

first(pattern: String, text: String): String {
    var found = regex.Regex(pattern).find(text);
    if (found.is_none()) {
        return "<none>";
    }
    return found.value().text();
}

test(): int {
    if (first("(?i)hello", "say HeLLo") != "HeLLo") { return -1; }
    if (first("(?i)[a-c]+", "xAbCd") != "AbC") { return -2; }
    if (first("(?i)[^a]+", "AAbB") != "bB") { return -3; }
    if (first("a(?i:b)c", "aBc aBC") != "aBc") { return -4; }
    if (first("(?i)a(?-i)b", "AB Ab") != "Ab") { return -5; }
    # A flag set inside a group ends with the group.
    if (first("((?i)a)a", "AA Aa") != "Aa") { return -6; }
    if (first("(?m)^b$", "a\nb\nc") != "b") { return -10; }
    if (first("^b$", "a\nb\nc") != "<none>") { return -11; }
    if (first("(?m)a$", "a\nb") != "a") { return -12; }
    if (first("(?s)a.b", "a\nb") != "a\nb") { return -20; }
    if (first("(?U)a+", "aaa") != "a") { return -30; }
    if (first("(?U)a+?", "aaa") != "aaa") { return -31; }
    if (first("(?is)A.B", "a\nb") != "a\nb") { return -32; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn iterates_replaces_and_splits() {
    assert_eq!(
        run(r##"
import regex;

joined(pieces: String[]): String {
    return "|".join(pieces);
}

all(pattern: String, text: String): String {
    var found = Array<String>();
    for (var found_match in regex.Regex(pattern).find_all(text)) {
        found.append(found_match.text());
    }
    return joined(found);
}

test(): int {
    if (all("\\d+", "1 22 333") != "1|22|333") { return -1; }
    if (all("\\d+", "none") != "") { return -2; }
    # Empty matches: one at each position, but none right after a match.
    if (all("x*", "ab") != "||") { return -3; }
    if (all("a*", "aba") != "a|a") { return -4; }
    if (all("", "é") != "|") { return -5; }

    var offsets = Array<String>();
    for (var found_match in regex.Regex("o").find_all("foo boo")) {
        offsets.append(to_string(found_match.start()));
    }
    if (joined(offsets) != "1|2|5|6") { return -6; }

    var space = regex.Regex("\\s+");
    if (space.replace_all("a  b\t\nc", " ") != "a b c") { return -10; }
    if (space.replace("a  b  c", "_") != "a_b  c") { return -11; }
    if (space.replace("abc", "_") != "abc") { return -12; }
    if (regex.Regex("a*").replace_all("baaac", "-") != "-b-c-") { return -13; }

    var pair = regex.Regex("(\\w+) (?<second>\\w+)");
    if (pair.replace("hello world", "$2 $1") != "world hello") { return -20; }
    if (pair.replace("hello world", "${second}-${1}") != "world-hello") { return -21; }
    if (pair.replace("hello world", "[$0] $$1 $x $") != "[hello world] $1 $x $") { return -22; }
    if (pair.replace("hello world", "${1}0") != "hello0") { return -23; }
    if (regex.Regex("(a)|(b)").replace_all("ab", "<$1>") != "<a><>") { return -24; }

    var comma = regex.Regex(",\\s*");
    if (joined(comma.split("a, b,c")) != "a|b|c") { return -30; }
    if (joined(comma.split(",a,")) != "|a|") { return -31; }
    if (comma.split("abc").count != 1) { return -32; }
    if (comma.split("").count != 1) { return -33; }

    var after = regex.Regex("\\d").find_at("1a2b3", 1).value();
    if (after.text() != "2" || after.start() != 2) { return -40; }
    if (regex.Regex("\\d").find_at("1a2", 3).is_some()) { return -41; }
    # Assertions see the text before the start.
    if (regex.Regex("^a").find_at("aa", 1).is_some()) { return -42; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn matches_code_points_and_reports_byte_offsets() {
    assert_eq!(
        run(r##"
import regex;

test(): int {
    var found = regex.Regex("é.").find("café!").value();
    if (found.text() != "é!" || found.start() != 3 || found.end() != 6) { return -1; }
    if (regex.Regex("^.$").find("🙂").value().text() != "🙂") { return -2; }
    if (regex.Regex("[^a]+").find("a日本a").value().text() != "日本") { return -3; }
    if (regex.Regex("[à-ÿ]+").find("voilà!").value().text() != "à") { return -4; }
    if (regex.Regex("\\x{1F642}").find("hi 🙂").value().start() != 3) { return -5; }
    if (regex.Regex("\\w+").find("été").value().text() != "t") { return -6; }
    if (regex.Regex(".").replace_all("ñü", "x") != "xx") { return -7; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn rejects_invalid_patterns() {
    assert_eq!(
        run(r##"
import regex;

error_of(pattern: String): String {
    var result = regex.Regex.parse(pattern);
    if (result.is_ok()) {
        return "<valid>";
    }
    return result.error().message;
}

test(): int {
    if (error_of("(a") != "invalid regex '(a': missing ')' at offset 0") { return -1; }
    if (error_of("a)") != "invalid regex 'a)': unmatched ')' at offset 1") { return -2; }
    if (error_of("[a") != "invalid regex '[a': missing ']' at offset 0") { return -3; }
    if (error_of("*a") != "invalid regex '*a': missing argument to repetition operator '*' at offset 0") { return -4; }
    if (error_of("a**") != "invalid regex 'a**': invalid nested repetition operator at offset 2") { return -5; }
    if (error_of("a{3,2}") != "invalid regex 'a{3,2}': invalid repeat count: minimum is larger than maximum at offset 1") {
        return -6;
    }
    if (error_of("a{1001}") != "invalid regex 'a{1001}': repeat count exceeds 1000 at offset 1") { return -7; }
    if (error_of("[z-a]") != "invalid regex '[z-a]': invalid character class range at offset 2") { return -8; }
    if (error_of("(\\w)\\1") != "invalid regex '(\\w)\\1': backreferences are not supported at offset 4") { return -9; }
    if (error_of("a(?=b)") != "invalid regex 'a(?=b)': lookaround is not supported at offset 1") { return -10; }
    if (error_of("(?<!a)b") != "invalid regex '(?<!a)b': lookaround is not supported at offset 0") { return -11; }
    if (error_of("\\q") != "invalid regex '\\q': unknown escape '\\q' at offset 0") { return -12; }
    if (error_of("a\\") != "invalid regex 'a\\': trailing backslash at offset 1") { return -13; }
    if (error_of("(?x)a") != "invalid regex '(?x)a': unknown flag 'x' at offset 2") { return -14; }
    if (error_of("(?<a>x)(?<a>y)") != "invalid regex '(?<a>x)(?<a>y)': duplicate group name 'a' at offset 7") { return -15; }
    if (error_of("(?<>x)") != "invalid regex '(?<>x)': empty group name at offset 0") { return -16; }
    if (error_of("[[:nope:]]") != "invalid regex '[[:nope:]]': unknown character class '[:nope:]' at offset 1") {
        return -17;
    }
    if (error_of("\\xZZ") != "invalid regex '\\xZZ': invalid hexadecimal escape at offset 0") { return -18; }
    if (error_of("[\\d-z]") != "<valid>") { return -19; }
    if (error_of("[a-\\d]") != "invalid regex '[a-\\d]': a class such as '\\d' cannot bound a range at offset 3") {
        return -20;
    }
    if (error_of("(a{1000}){1000}").find("exceeds 100000 instructions") < 0) { return -21; }
    if (error_of("(?i)") != "<valid>" || error_of("x{") != "<valid>") { return -22; }

    var deep = "(".repeat(300) + ")".repeat(300);
    if (error_of(deep).find("groups nest more than 250 deep") < 0) { return -23; }
    var fine = "(".repeat(200) + "a" + ")".repeat(200);
    if (!regex.Regex(fine).is_match("a")) { return -24; }

    if (regex.Regex.escape("1+1=2? [x]") != "1\\+1=2\\? \\[x\\]") { return -30; }
    var literal = "a.b*c(d)|e$^{f}\\";
    if (regex.Regex(regex.Regex.escape(literal)).find("xx" + literal).value().start() != 2) { return -31; }
    return 0;
}
"##),
        0
    );
}

/// Patterns that take exponential time in a backtracking engine stay
/// linear: each finishes at once on input sizes that would never finish
/// there.
#[test]
fn runs_in_linear_time() {
    assert_eq!(
        run(r##"
import regex;

test(): int {
    var a_run = "a".repeat(5000);
    if (regex.Regex("(a*)*b").is_match(a_run)) { return -1; }
    if (regex.Regex("(a|aa)+$").find(a_run).value().end() != 5000) { return -2; }
    if (regex.Regex("(x+x+)+y").is_match("x".repeat(5000))) { return -3; }
    if (regex.Regex("(a?){30}a{30}").find("a".repeat(30)).value().end() != 30) { return -4; }
    var count = 0;
    for (var found_match in regex.Regex("a").find_all(a_run)) {
        count += 1;
    }
    if (count != 5000) { return -5; }
    return 0;
}
"##),
        0
    );
}

/// A `Regex` is `[Shared]`: one compiled at module scope serves every
/// thread at once. Threads run in a built program, not the JIT.
#[test]
fn shares_one_regex_between_threads() {
    assert_runs(
        "regex_threads",
        r##"
import async;
import regex;

const word = regex.Regex("(?<word>[a-z]+)");
const found = async.Atomic<long>(0);

count_words() {
    var i = 0;
    while (i < 200) {
        for (var each in word.find_all("one two three")) {
            if (each.group("word").value().size > 0) {
                found.fetch_add(1);
            }
        }
        i += 1;
    }
}

main(): int {
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        workers.append(async.Thread.spawn(count_words));
        i += 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    assert(found.load() == 4 * 200 * 3, "every thread found every word");
    return 0;
}
"##,
    );
}
