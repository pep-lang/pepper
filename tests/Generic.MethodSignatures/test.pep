# A generic method's signature may name another module's types as any
# other method's does: a type alias it returns (`io.IoResult<void>`) and an
# enum case as a parameter's default (`json.UnknownKeys.Ignore`).

import io;
import json;

struct Box {
    var stored: int = 0;

    construct() {}

    keys<T>(value: T, keys: json.UnknownKeys = json.UnknownKeys.Ignore): int {
        return keys == json.UnknownKeys.Ignore ? 1 : 2;
    }

    put<T>(value: T): io.IoResult<void> {
        stored += 1;
        return io.IoResult<void>.ok();
    }
}

main(): int {
    var b = Box();
    if (b.keys<int>(3) != 1) {
        return 1;
    }
    if (b.keys<int>(3, json.UnknownKeys.Reject) != 2) {
        return 2;
    }
    if (b.put<String>("x").is_err() or b.stored != 1) {
        return 3;
    }
    return 0;
}
