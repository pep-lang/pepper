main(): int {
    # ok: is_ok true, value() returns the value.
    var a = Result<int>.ok(42);
    if (!a.is_ok()) { return 1; }
    if (a.value() != 42) { return 2; }

    # err: is_err true, error message preserved.
    var b = Result<int>.err(Error("boom"));
    if (b.is_ok()) { return 3; }
    if (!b.is_err()) { return 4; }
    if (b.error().message.length != 4) { return 5; }

    # ok_or: value on Ok, fallback on Err.
    if (a.ok_or(-1) != 42) { return 6; }
    if (b.ok_or(-1) != -1) { return 7; }

    # default TError: Result<int> fills TError from the parameter default.
    var c = Result<int>.ok(1);
    var d = Result<int>.err(Error("e"));
    if (!c.is_ok() || d.is_ok()) { return 8; }
    if (d.error().message.length != 1) { return 9; }

    # The cases build results too, and a match reads them.
    var e = Result<int>.Err(Error("e"));
    if (match (e) { Ok(v) => true, Err(x) => false }) { return 10; }

    # void: the value type of a result with nothing to return.
    var n = Result<void>.ok();
    if (!n.is_ok()) { return 11; }
    var m = Result<void>.err(Error("no"));
    if (!m.is_err() || m.error().message.length != 2) { return 12; }

    return 0;
}
