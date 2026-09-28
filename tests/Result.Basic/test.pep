main(): int {
    # ok: is_ok true, unwrap returns the value.
    var a = Result<int>.ok(42);
    if (!a.is_ok()) { return 1; }
    if (a.unwrap() != 42) { return 2; }

    # err: is_err true, error message preserved.
    var b = Result<int>.err(Error("boom"));
    if (b.is_ok()) { return 3; }
    if (!b.is_err()) { return 4; }
    if (b.Error.Message.length() != 4) { return 5; }

    # ok_or: value on Ok, fallback on Err.
    if (a.ok_or(-1) != 42) { return 6; }
    if (b.ok_or(-1) != -1) { return 7; }

    # default TError: Result<int> fills TError from the parameter default.
    var c = Result<int>.ok(1);
    var d = Result<int>.err(Error("e"));
    if (!c.is_ok() || d.is_ok()) { return 8; }
    if (d.Error.Message.length() != 1) { return 9; }

    # default ctor is an Err.
    var e = Result<int>();
    if (e.is_ok()) { return 10; }

    return 0;
}
