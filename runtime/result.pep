# Rust-analogous Result type. Pepper has no unions: both `Value` and
# `Error` always exist, and `IsOk` selects the live one (the dead field
# stays at its default/null value).

import "internals";

export struct Error {
    String Message;

    construct(String message = "") {
        this.Message = message;
    }
}

# The value of a result that carries no value on success:
# `Result<None>.ok(None())` (Rust's `Result<(), E>`).
export struct None {
}

export struct Result<TValue, TError=Error> {
    bool IsOk;
    TValue Value;
    TError Error;

    # Default state: an Err holding a default-constructed error.
    construct() {
        this.IsOk = false;
    }

    static Result<TValue, TError> ok(TValue v) {
        var r = Result<TValue, TError>();
        r.IsOk = true;
        r.Value = v;
        return r;
    }

    static Result<TValue, TError> err(TError e) {
        var r = Result<TValue, TError>();
        r.IsOk = false;
        r.Error = e;
        return r;
    }

    bool is_ok() {
        return this.IsOk;
    }

    bool is_err() {
        return !this.IsOk;
    }

    TValue unwrap() {
        assert(this.IsOk, "Result::unwrap on an Err value");
        return this.Value;
    }

    TValue ok_or(TValue fallback) {
        if (this.IsOk) {
            return this.Value;
        }
        return fallback;
    }
}
