//! Generic calls without type arguments (`larger(3, 9)`), methods with
//! type parameters of their own (`map<U>`), and the iterator adapters built
//! on them (`Iterator.map`, `filter`, `enumerate`, `zip`, `to_array`), with
//! the leak census.

use crate::support::jit_census as run;
use crate::support::compile_error;

#[test]
fn type_arguments_from_arguments() {
    let src = r#"
larger<T>(a: T, b: T): T { return a > b ? a : b; }
first<U>(items: Array<U>): U { return items[0]; }

test(): int {
    var words = Array<String>();
    words.append("hello");
    var word = first(words);
    return larger(3, 9) + (word.size as int);
}
"#;
    assert_eq!(run(src), (14, 0));
}

#[test]
fn closure_arguments_take_and_give_type_arguments() {
    let src = r#"
apply<T>(f: (T) => T, x: T): T { return f(x); }

transform<T, U>(items: Array<T>, f: (T) => U): Array<U> {
    var out = Array<U>();
    for (var item in items) {
        out.append(f(item));
    }
    return out;
}

test(): int {
    var words = Array<String>();
    words.append("hi");
    words.append("there");
    var sizes = transform(words, (w) => w.size);
    return apply((x) => x + 1, 2) * 100 + (sizes[1] as int);
}
"#;
    assert_eq!(run(src), (305, 0));
}

#[test]
fn generic_methods() {
    let src = r#"
struct Box<T> {
    T value;
    construct(T v) { value = v; }
    map<U>(f: (T) => U): Box<U> { return Box<U>(f(value)); }
}

test(): int {
    var b = Box<int>(4);
    var explicit = b.map<long>((x: int): long => x + 1);
    var tens = b.map((x) => x * 10);
    var text = tens.map((x) => "abc");
    return (explicit.value as int) * 100 + (tens.value as int) + (text.value.size as int);
}
"#;
    assert_eq!(run(src), (543, 0));
}

#[test]
fn iterator_adapters() {
    let src = r#"
struct Person {
    String name;
    int age;
    construct(this.name = "", this.age = 0) {}
}

test(): int {
    var people = Array<Person>();
    people.append(Person("Ada", 36));
    people.append(Person("Bo", 12));
    people.append(Person("Cyd", 40));
    var letters = 0;
    for (var name in people.iterate().filter((p) => p.age >= 18).map((p) => p.name)) {
        letters = letters + (name.size as int);
    }
    var kept = 0;
    for (var c in "hello".iterate().filter((c) => c != "l")) {
        kept = kept + 1;
    }
    return letters * 10 + kept;
}
"#;
    assert_eq!(run(src), (63, 0));
}

#[test]
fn adapters_on_your_own_iterator() {
    let src = r#"
struct Countdown {
    int remaining;
    int now;
    construct(this.remaining = 0) {}
    bool next() {
        if (remaining == 0) { return false; }
        now = remaining;
        remaining = remaining - 1;
        return true;
    }
    int current() { return now; }
}

extend Countdown with Iterator<int> {}

test(): int {
    var total = 0;
    for (var n in Countdown(5).map((n) => n * n).filter((n) => n > 4)) {
        total = total + n;
    }
    return total;
}
"#;
    assert_eq!(run(src), (50, 0));
}

#[test]
fn enumerate_zip_and_to_array() {
    let src = r#"
struct Item {
    int v;
    construct(this.v = 0) {}
}

test(): int {
    var items = [Item(1), Item(2), Item(3)];
    ulong weighted = 0;
    for (var (i, item) in items.iterate().enumerate()) {
        weighted += i * (item.v as ulong);          # 0 + 2 + 6
    }
    var signed = 0;
    for (var (i, item) in items.iterate().enumerate<int>()) {
        signed += i - item.v;                        # -1 - 1 - 1
    }
    var names = ["Ada", "Grace"];
    var zipped = 0;
    for (var (item, name) in items.iterate().zip(names.iterate())) {
        zipped += item.v * (name.size as int);     # 3 + 10, stops at the shorter
    }
    var big = items.iterate().filter((x) => x.v > 1).to_array();
    var it = items.iterate();
    var all = it.to_array();
    if (!it.next() || it.current().v != 1) {         # to_array left it in place
        return -1;
    }
    var pairs = (0..2).zip(names.iterate()).to_array();
    return (weighted as int) * 1000 + (signed + 3) * 100 + zipped + (big.count as int) * 10000
        + (all.count as int) * 100000 + (pairs[1].1.size as int) * 1000000;
}
"#;
    assert_eq!(run(src), (5_328_013, 0));
}

#[test]
fn trait_parameter_infers_through_a_declared_conformance() {
    let src = r#"
struct Countdown {
    int remaining;
    int now;
    construct(this.remaining = 0) {}
    next(): bool {
        if (remaining == 0) { return false; }
        now = remaining;
        remaining -= 1;
        return true;
    }
    current(): int { return now; }
}

extend Countdown with Iterator<int> {}

total<T>(items: Iterator<T>): T {
    T sum = 0;
    while (items.next()) {
        sum += items.current();
    }
    return sum;
}

test(): int {
    return total(Countdown(4));   # T = int, from 'extend Countdown with Iterator<int>'
}
"#;
    assert_eq!(run(src), (10, 0));
}

#[test]
fn uninferable_type_arguments_are_an_error() {
    let err = compile_error(
        r#"
make<T>(): T { return __default<T>(); }

test(): int {
    var x = make();
    return 0;
}
"#,
    );
    assert!(err.contains("cannot infer the type arguments of 'make' from its arguments; write them: make<T>(...)"), "{}", err);
    assert!(err.contains("test.pep:5:13"), "{}", err);
}

#[test]
fn inferred_calls_in_a_generic_structs_generic_method() {
    // `describe(this.v)` in `Box<T>` names `T` until `Box` is specialized:
    // it is inferred in `Box<int>.show<U>` (as `describe<int>`), not in the
    // generic base, where it would have become `describe<T>`.
    let src = r#"
describe<T>(v: T): int { return 7; }
wrap<X>(x: X): int { return describe(x) + 1; }
struct Box<T> {
    var v: T;
    construct(T v) { this.v = v; }
    show<U>(U u): int { return describe(this.v) + wrap(u); }
    plain(): int { return describe(this.v); }
}
test(): int { var b = Box<int>(1); return b.show(true) * 100 + b.plain(); }
"#;
    let (result, leaked) = run(src);
    assert_eq!(result, 1507);
    assert_eq!(leaked, 0);
}

#[test]
fn bound_naming_another_type_parameter() {
    // #331: `I: Iterator<T>` binds `T` from `I`'s argument, written type
    // arguments may stop early (`count_all<int>(...)`), and a trait default
    // method's bound takes the trait's argument.
    let src = r#"
count_all<T, I: Iterator<T>>(source: I): int {
    var n = 0;
    while (source.next()) {
        n += 1;
    }
    return n;
}

first<T, I: Iterator<T>>(source: I): T {
    source.next();
    return source.current();
}

pick<T, U>(a: T, b: U): T { return a; }

struct Counter<T, I: Iterator<T>> {
    var source: I;
    construct(s: I) { source = s; }
    total(): int { return count_all<T, I>(source); }
}

struct Tally {
    count_all<T, I: Iterator<T>>(source: I): int {
        var n = 0;
        while (source.next()) {
            n += 1;
        }
        return n;
    }
}

trait Sink<T> {
    put(x: T);
    put_all<I: Iterator<T>>(source: I) {
        while (source.next()) {
            put(source.current());
        }
    }
}

struct Sum {
    var total = 0;
    put(x: int) { total += x; }
}

extend Sum with Sink<int> {}

test(): int {
    var numbers = Array<int>();
    numbers.append(3);
    numbers.append(4);
    var words = Array<String>();
    words.append("hello");
    var counter = Counter<int, ArrayIterator<int>>(numbers.iterate());
    var tally = Tally();
    var sum = Sum();
    sum.put_all(numbers.iterate());
    return count_all(numbers.iterate())
        + count_all<int>(numbers.iterate()) * 10
        + (first(words.iterate()).size as int) * 100
        + pick<int>(1, "x") * 1000
        + counter.total() * 10000
        + (tally.count_all(numbers.iterate()) + tally.count_all<int>(numbers.iterate())) * 100000
        + sum.total * 1000000;
}
"#;
    assert_eq!(run(src), (7_421_522, 0));
}

/// Inside a generic struct, `var` infers types that mention the struct's
/// type parameters, specialized per instantiation (#377).
#[test]
fn var_infers_type_parameter_types_in_generic_struct() {
    let src = r#"
struct Stack<T> {
    var items: Array<T>;
    construct() { items = Array<T>(); }
    push(item: T) { items.append(item); }
    peek(): T {
        var top = items.last();
        return top;
    }
    copy(): Array<T> {
        var all = items.clone();
        return all;
    }
    paired(): (T, ulong) {
        var pair = (items.last(), items.count);
        return pair;
    }
}

test(): int {
    var numbers = Stack<int>();
    numbers.push(1);
    numbers.push(2);
    var words = Stack<String>();
    words.push("pepper");
    var (word, count) = words.paired();
    return numbers.peek() + (words.peek().size as int) + numbers.copy().count as int + (word.size as int) + count as int;
}
"#;
    assert_eq!(run(src), (2 + 6 + 2 + 6 + 1, 0));
}

#[test]
fn generic_methods_as_values() {
    let src = r#"
struct Box<T> {
    T value;
    construct(v: T) { value = v; }
    map<U>(f: (T) => U): Box<U> { return Box<U>(f(value)); }
    static wrap<U>(u: U): Box<U> { return Box<U>(u); }
}

test(): int {
    var b = Box<int>(3);
    # Type arguments written.
    var doubled = b.map<long>;
    var wrap = Box<int>.wrap<int>;
    var unbound: (Box<int>, (int) => long) => Box<long> = Box<int>.map<long>;
    var all = Array<((int) => long) => Box<long>>();
    all.append(b.map<long>);
    # Or picked by the function type.
    var named: ((int) => String) => Box<String> = b.map;
    var unbound2: (Box<int>, (int) => long) => Box<long> = Box<int>.map;
    var wrap2: (String) => Box<String> = Box<int>.wrap;
    var total = doubled((x: int): long => x * 2).value + unbound(b, (x: int): long => x).value + all[0]((x: int): long => x).value;
    total = total + unbound2(Box<int>(4), (x: int): long => x).value;
    return (total as int) * 100 + wrap(5).value * 10 + named((x: int) => "ab").value.length + wrap2("c").value.length;
}
"#;
    // 6 + 3 + 3 + 4 = 16; 5; 2 + 1.
    assert_eq!(run(src), (1653, 0));
}

#[test]
fn generic_method_value_without_a_type_is_an_error() {
    let err = compile_error(
        r#"
struct Box<T> {
    T value;
    construct(v: T) { value = v; }
    map<U>(f: (T) => U): Box<U> { return Box<U>(f(value)); }
}

test(): int {
    var m = Box<int>(1).map;
    return 0;
}
"#,
    );
    assert!(
        err.contains("9:25: error: cannot infer the type arguments of method 'map' of 'Box<int>' used as a value; write them (map<U>) or give the value a function type"),
        "{}",
        err
    );
}
