# `?` anywhere in a statement (#322): it runs in place, in source order,
# and a `?` on a branch that does not run does nothing. Each case logs
# what ran; an early return releases what the statement made before it.

struct Box {
    var value: int;

    construct(value: int) {
        this.value = value;
    }
}

# What ran, in order.
struct Log {
    var steps = Array<String>();

    construct() {}

    note(text: String, value: int): int {
        steps.append(text);
        return value;
    }

    ok(text: String, value: int): Result<int> {
        steps.append(text);
        return Result<int>.ok(value);
    }

    bad(text: String): Result<int> {
        steps.append(text);
        return Result<int>.err(Error(text));
    }

    box(text: String, value: int): Box {
        steps.append(text);
        return Box(value);
    }

    boxed(text: String, value: int): Result<Box> {
        steps.append(text);
        return Result<Box>.ok(Box(value));
    }

    some(text: String, value: int): int? {
        steps.append(text);
        return Optional<int>.Value(value);
    }

    none(text: String): int? {
        steps.append(text);
        return Optional<int>.Empty;
    }

    done(text: String): Result<void> {
        steps.append(text);
        return Result<void>.ok();
    }
}

# A call, then a `?`: the call runs first, and what follows the `?` runs
# only when it does not return.
after_call(l: Log, fail: bool): Result<int> {
    return Result<int>.ok(l.note("f", 1) + (fail ? l.bad("g") : l.ok("g", 2))? + l.note("h", 3));
}

# The right operand of `&&` and `||` runs only when the left does not decide.
both(l: Log, a: bool, fail: bool): Result<bool> {
    return Result<bool>.ok(l.note("a", a ? 1 : 0) == 1 && (fail ? l.bad("b") : l.ok("b", 1))? == 1);
}

either(l: Log, a: bool, fail: bool): Result<bool> {
    return Result<bool>.ok(l.note("a", a ? 1 : 0) == 1 || (fail ? l.bad("b") : l.ok("b", 1))? == 1);
}

# A `?:` branch: the other branch's `?` does nothing.
pick(l: Log, c: bool, fail: bool): Result<int> {
    var x = c ? (fail ? l.bad("x") : l.ok("x", 5))? : l.note("y", 0);
    return Result<int>.ok(x + 1);
}

# Numeric branches take the conditional's common type.
widen(l: Log, c: bool): Result<double> {
    return Result<double>.ok(c ? l.ok("i", 2)? : 0.5);
}

enum Shape {
    Circle(r: int),
    Square(side: int),
    Point,
}

# A `match` arm: only the matching arm's `?` runs.
area(l: Log, s: Shape, fail: bool): Result<int> {
    return Result<int>.ok(match (s) {
        Circle(r) => (fail ? l.bad("circle") : l.ok("circle", r * 3))?,
        Square(side) => l.ok("square", side * side)?,
        Point => 0,
    });
}

# Optionals, in a function that returns one.
first(l: Log, fail: bool): int? {
    return Optional<int>.Value(l.note("n", 1) + (fail ? l.none("o") : l.some("o", 2))? + l.note("p", 3));
}

# A statement whose `?:` value is unused.
run_one(l: Log, c: bool): Result<void> {
    c ? l.done("left")? : l.done("right")?;
    return Result<void>.ok();
}

# An assignment's index runs before its value's `?`.
store(l: Log, fail: bool): Result<int> {
    var values = [0, 0, 0];
    values[l.note("index", 1)] = (fail ? l.bad("value") : l.ok("value", 7))?;
    return Result<int>.ok(values[1]);
}

# A struct made before the `?` is released on the early return.
held(l: Log, fail: bool): Result<int> {
    var total = l.box("box", 10).value + (fail ? l.bad("try") : l.ok("try", 1))?;
    return Result<int>.ok(total);
}

# A struct a `?` yields, the one a branch holds, and the receiver of a
# method called with a `?` argument are each released once.
through(l: Log, c: bool, fail: bool): Result<int> {
    var b = c ? l.boxed("boxed", 4)? : l.box("box", 6);
    var list = Array<Box>();
    list.append((fail ? Result<Box>.err(Error("no")) : l.boxed("more", 8))?);
    return Result<int>.ok(b.value + list[0].value);
}

# A receiver that is a call result, made before its argument's `?`.
made(l: Log, fail: bool): Result<int> {
    return Result<int>.ok(l.box("made", 2).value + Box((fail ? l.bad("arg") : l.ok("arg", 3))?).value);
}

# A `while` condition with a `?` on the right of `&&`.
count_up(l: Log, limit: int): Result<int> {
    var i = 0;
    while (i < 5 && (i < limit ? l.ok("step", 1) : l.bad("stop"))? == 1) {
        i += 1;
    }
    return Result<int>.ok(i);
}

# Runs `f` with a fresh log: what it logged and whether it held.
trace(f: (Log) => bool): String {
    var l = Log();
    var held = f(l);
    var joined = ",".join(l.steps);
    return $"{joined}:{held ? "ok" : "no"}";
}

check(name: String, got: String, expected: String): int {
    if (got != expected) {
        print($"{name}: got '{got}', expected '{expected}'");
        return 1;
    }
    return 0;
}

cases(): int {
    var failures = 0;
    failures += check("after call", trace((l) => after_call(l, false).value() == 6), "f,g,h:ok");
    failures += check("after call, err", trace((l) => after_call(l, true).is_err()), "f,g:ok");
    failures += check("&& skipped", trace((l) => !both(l, false, true).value()), "a:ok");
    failures += check("&& err", trace((l) => both(l, true, true).is_err()), "a,b:ok");
    failures += check("&& ok", trace((l) => both(l, true, false).value()), "a,b:ok");
    failures += check("|| skipped", trace((l) => either(l, true, true).value()), "a:ok");
    failures += check("|| err", trace((l) => either(l, false, true).is_err()), "a,b:ok");
    failures += check("|| ok", trace((l) => either(l, false, false).value()), "a,b:ok");
    failures += check("?: skipped", trace((l) => pick(l, false, true).value() == 1), "y:ok");
    failures += check("?: taken", trace((l) => pick(l, true, false).value() == 6), "x:ok");
    failures += check("?: err", trace((l) => pick(l, true, true).is_err()), "x:ok");
    failures += check(
        "?: widen", trace((l) => widen(l, true).value() == 2.0 and widen(l, false).value() == 0.5), "i:ok"
    );
    failures += check("match, other arm", trace((l) => area(l, Shape.Square(3), true).value() == 9), "square:ok");
    failures += check("match, no ?", trace((l) => area(l, Shape.Point, true).value() == 0), ":ok");
    failures += check("match, err", trace((l) => area(l, Shape.Circle(2), true).is_err()), "circle:ok");
    failures += check("match, ok", trace((l) => area(l, Shape.Circle(2), false).value() == 6), "circle:ok");
    failures += check("optional", trace((l) => first(l, false).value() == 6), "n,o,p:ok");
    failures += check("optional, empty", trace((l) => first(l, true).is_empty()), "n,o:ok");
    failures += check(
        "statement ?:", trace((l) => run_one(l, true).is_ok() and run_one(l, false).is_ok()), "left,right:ok"
    );
    failures += check("assignment", trace((l) => store(l, false).value() == 7), "index,value:ok");
    failures += check("assignment, err", trace((l) => store(l, true).is_err()), "index,value:ok");
    failures += check("held", trace((l) => held(l, false).value() == 11), "box,try:ok");
    failures += check("held, err", trace((l) => held(l, true).is_err()), "box,try:ok");
    failures += check("structs", trace((l) => through(l, true, false).value() == 12), "boxed,more:ok");
    failures += check("structs, other", trace((l) => through(l, false, false).value() == 14), "box,more:ok");
    failures += check("structs, err", trace((l) => through(l, true, true).is_err()), "boxed:ok");
    failures += check("receiver", trace((l) => made(l, false).value() == 5), "made,arg:ok");
    failures += check("receiver, err", trace((l) => made(l, true).is_err()), "made,arg:ok");
    failures += check("while", trace((l) => count_up(l, 9).value() == 5), "step,step,step,step,step:ok");
    failures += check("while, err", trace((l) => count_up(l, 2).is_err()), "step,step,stop:ok");
    return failures;
}

main(): int {
    # Once first, so that what the runtime keeps does not count.
    cases();
    var before = _pep_live_allocs();
    var failures = cases();
    var leaked = _pep_live_allocs() - before;
    if (leaked != 0) {
        print($"leaked {leaked}");
        failures += 1;
    }
    print($"{failures} failed");
    return failures;
}
