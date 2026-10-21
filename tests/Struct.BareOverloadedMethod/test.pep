# A bare call of an overloaded method, whose result `?` unwraps, calls the
# method, in a module the program imports beside `io` (#51): `io`'s
# private `extern int bind(...)` took the call, so `?` saw an `int`.

import io;
import "statement" as s;

main(): int {
    var statement = s.Statement();
    if (statement.bind_all([s.Value.Null, s.Value.Integer(7)]).is_err()) {
        return 1;
    }
    return statement.bound == 2 and statement.last == 7 ? 0 : 2;
}
