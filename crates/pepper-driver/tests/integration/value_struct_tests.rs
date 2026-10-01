//! Value structs (`[Value]`): stored inline and copied like a tuple, with
//! their reference fields counted (see `pepper_sema::value_structs`). Each
//! program returns 0, or a distinct negative code for the check that
//! failed, and must leave no allocation behind.

use crate::support::jit_census;

/// Runs `source`'s `test`, expecting 0 and no leak.
fn assert_runs_clean(source: &str) {
    let (result, leaked) = jit_census(source);
    assert_eq!(result, 0, "test() returned {}", result);
    assert_eq!(leaked, 0, "{} allocations leaked", leaked);
}

const SPAN: &str = r#"
[Value]
struct Span {
    var start: int;
    var end: int;

    construct(this.start = 0, this.end = 0) {}

    length(): int {
        return end - start;
    }

    grow(by: int) {
        end = end + by;
    }

    grown(by: int): Span {
        var copy = this;
        copy.grow(by);
        return copy;
    }
}
"#;

#[test]
fn a_copy_is_independent() {
    assert_runs_clean(&format!(
        "{}{}",
        SPAN,
        r#"
test(): int {
    var a = Span(0, 4);
    var b = a;
    b.grow(2);
    if (a.length() != 4) { return -1; }
    if (b.length() != 6) { return -2; }
    b = a;
    if (b.length() != 4) { return -3; }
    a.end = 10;
    if (b.end != 4) { return -4; }
    return 0;
}
"#
    ));
}

#[test]
fn values_pass_return_and_change_through_this() {
    assert_runs_clean(&format!(
        "{}{}",
        SPAN,
        r#"
measure(s: Span): int {
    s.grow(100);
    return s.length();
}

make(n: int): Span {
    return Span(0, n);
}

test(): int {
    var a = Span(1, 3);
    if (measure(a) != 102) { return -1; }
    if (a.length() != 2) { return -2; }
    if (make(5).length() != 5) { return -3; }
    var g = a.grown(3);
    if (g.length() != 5 || a.length() != 2) { return -4; }
    if (make(2).grown(1).length() != 3) { return -5; }
    return 0;
}
"#
    ));
}

#[test]
fn a_value_field_is_its_holders_storage() {
    assert_runs_clean(&format!(
        "{}{}",
        SPAN,
        r#"
struct Holder {
    var span: Span;
}

[Value]
struct Pair {
    var first: Span;
    var second: Span;
}

test(): int {
    var h = Holder();
    h.span.grow(3);
    var other = h;
    if (other.span.length() != 3) { return -1; }
    h.span.end = 7;
    if (other.span.end != 7) { return -2; }
    var p = Pair();
    p.first.grow(2);
    p.second = p.first;
    p.second.grow(1);
    if (p.first.length() != 2 || p.second.length() != 3) { return -3; }
    var q = p;
    q.first.end = 9;
    if (p.first.end != 2) { return -4; }
    return 0;
}
"#
    ));
}

#[test]
fn reference_fields_are_counted() {
    assert_runs_clean(
        r#"
[Value]
struct Named {
    var name: String;
    var count: int;

    construct(this.name = "", this.count = 0) {}

    renamed(to: String) {
        name = to;
    }
}

struct Box {
    var named: Named;
}

pass(n: Named): Named {
    return n;
}

test(): int {
    var a = Named("first", 1);
    var b = a;
    b.renamed("second");
    if (a.name != "first" || b.name != "second") { return -1; }
    a = b;
    a = a;
    if (a.name != "second") { return -2; }
    var box = Box();
    box.named = pass(a);
    box.named.renamed("third");
    if (box.named.name != "third" || a.name != "second") { return -3; }
    pass(Named("temporary", 2));
    if (Named("x", 3).name != "x") { return -4; }
    return 0;
}
"#,
    );
}

#[test]
fn values_go_in_arrays_and_generics() {
    assert_runs_clean(&format!(
        "{}{}",
        SPAN,
        r#"
[Value]
struct Wrapper<T> {
    var item: T;

    construct(this.item = __default<T>()) {}

    get(): T {
        return item;
    }
}

test(): int {
    var spans = Array<Span>();
    spans.append(Span(0, 1));
    spans.append(Span(0, 2));
    var total = 0;
    for (var s in spans) {
        total = total + s.length();
    }
    if (total != 3) { return -1; }
    var first = spans[0];
    first.grow(5);
    if (spans[0].length() != 1) { return -2; }
    spans[1] = first;
    if (spans[1].length() != 6) { return -3; }
    var w = Wrapper<String>("held");
    var v = w;
    if (v.get() != "held") { return -4; }
    var n = Wrapper<Span>(Span(2, 5));
    if (n.get().length() != 3) { return -5; }
    return 0;
}
"#
    ));
}

/// A value larger than a pointer: `sizeof` gives its layout, not a slot's,
/// so an Array's buffer has room for every element as it grows.
#[test]
fn arrays_of_values_larger_than_a_pointer_grow() {
    assert_runs_clean(
        r#"
[Value]
struct Labeled {
    var label: String;
    var index: long;
    var weight: long;

    construct(this.label = "", this.index = 0, this.weight = 0) {}
}

test(): int {
    var items = Array<Labeled>();
    var index = 0;
    while (index < 40) {
        items.append(Labeled($"item {index}", index, index * 2));
        index = index + 1;
    }
    var optionals = Array<String?>();
    optionals.append(Optional<String>.some("a"));
    optionals.append(Optional<String>.none());
    optionals.append(Optional<String>.some("c"));
    if (items[39].label != "item 39" || items[39].weight != 78) { return -1; }
    if (optionals[2].value() != "c" || optionals[1].is_some()) { return -2; }
    return 0;
}
"#,
    );
}

/// A value in a trait slot is a copy in a box: a mutating method through the
/// trait value changes the box, and copies of the trait value share it.
#[test]
fn a_value_converted_to_a_trait_is_boxed() {
    assert_runs_clean(
        r#"
trait Sized {
    length(): int;
    grow(by: int);
}

[Value]
struct Named {
    var name: String;
    var count: int;

    construct(this.name = "", this.count = 0) {}

    length(): int {
        return count;
    }

    grow(by: int) {
        count = count + by;
    }
}

extend Named with Sized {}

measure(s: Sized): int {
    return s.length();
}

make(): Named {
    return Named("made", 7);
}

test(): int {
    var a = Named("first", 3);
    if (measure(a) != 3) { return -1; }
    var s: Sized = a;
    s.grow(10);
    if (s.length() != 13 || a.count != 3) { return -2; }
    if (measure(make()) != 7) { return -3; }
    var all = Array<Sized>();
    all.append(a);
    all.append(make());
    all[0].grow(1);
    if (all[0].length() != 4) { return -4; }
    var t = s;
    t.grow(1);
    if (s.length() != 14) { return -5; }
    return 0;
}
"#,
    );
}

/// The runtime's iterators are values: a copy is independent, and `for`,
/// `map`, maps and strings still iterate.
#[test]
fn runtime_iterators_are_values() {
    assert_runs_clean(
        r#"
test(): int {
    var a = Array<int>();
    a.append(1);
    a.append(2);
    a.append(3);
    var total = 0;
    for (var x in a) {
        total = total + x;
    }
    if (total != 6) { return -1; }
    var doubled = 0;
    for (var y in a.iterate().map<int>((v: int) => v * 2)) {
        doubled = doubled + y;
    }
    if (doubled != 12) { return -2; }
    var names = Array<String>();
    names.append("a");
    names.append("b");
    var joined = "";
    for (var n in names) {
        joined = joined + n;
    }
    if (joined != "ab") { return -3; }
    var it = names.iterate();
    var copy = it;
    it.next();
    copy.next();
    copy.next();
    if (it.current() != "a" || copy.current() != "b") { return -4; }
    var m = HashMap<String, int>();
    m["x"] = 1;
    m["y"] = 2;
    var sum = 0;
    for (var e in m) {
        sum = sum + e.1;
    }
    if (sum != 3) { return -5; }
    var chars = 0;
    for (var c in "héllo") {
        chars = chars + 1;
    }
    if (chars != 5) { return -6; }
    return 0;
}
"#,
    );
}

/// `for` drives a stored value iterator in place, so a second loop resumes
/// after a `break`.
#[test]
fn for_over_a_stored_iterator_resumes_it() {
    assert_runs_clean(
        r#"
test(): int {
    var a = Array<int>();
    var i = 0;
    while (i < 5) {
        a.append(i);
        i = i + 1;
    }
    var it = a.iterate();
    for (var x in it) {
        if (x == 1) {
            break;
        }
    }
    var rest = 0;
    for (var y in it) {
        rest = rest + y;
    }
    if (rest != 9) { return -1; }
    return 0;
}
"#,
    );
}
