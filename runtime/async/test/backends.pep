# Helpers for the tests that run on each I/O backend: which backends this
# system has.

import async;

# The name of the backend `Backend.Automatic` picks on this system.
[Target(OS(Linux))]
export best_backend(): String {
    return "Epoll";
}

[Target(OS(Mac))]
export best_backend(): String {
    return "Kqueue";
}

[Target(OS(Windows))]
export best_backend(): String {
    return "Iocp";
}

[Target(OS(Wasi))]
export best_backend(): String {
    return "Poll";
}

# Whether this system has io_uring (Linux only); a test of it has nothing to
# check elsewhere.
[Target(OS(Linux))]
export has_io_uring(): bool {
    return true;
}

[Target(!OS(Linux))]
export has_io_uring(): bool {
    return false;
}
