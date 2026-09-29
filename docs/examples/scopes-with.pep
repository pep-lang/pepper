# A module-scope counter: const, and changed through an Atomic.
const open_sessions = Atomic<int>(0);

# A scope object: enter() hands out what the block works with, and the
# destructor calls exit() when the last reference goes away.
struct Session {
    var user: String;

    construct(this.user = "") {
        open_sessions.fetch_add(1);
    }

    destruct {
        this.exit();
    }

    Session enter() {
        return this;
    }

    exit() {
        open_sessions.fetch_sub(1);
    }
}

extend Session with Scoped<Session> {}

# enter() may return a null reference: then the body is skipped and the
# `else` block runs.
struct Lookup {
    var found: Session;

    construct(Session session) {
        found = session;
    }

    Session enter() {
        return found;
    }

    exit() {}
}

extend Lookup with Scoped<Session> {}

first_user(): String {
    with (var session = Session("ada")) {
        # `return` leaves the block too: the session still closes.
        return session.user;
    }
    return "";
}

main(): int {
    with (var session = Session("grace")) {
        assert(open_sessions.load() == 1, "open inside the block");
        assert(session.user == "grace", "bound to what enter() returned");
    }
    assert(open_sessions.load() == 0, "closed at the end of the block");

    assert(first_user() == "ada", "the value was returned");
    assert(open_sessions.load() == 0, "closed on return as well");

    var hits = 0;
    with (var s = Lookup(Session("linus"))) {
        hits += 1;
    } else {
        hits -= 100;
    }
    with (var s = Lookup(__null)) {
        hits -= 100;
    } else {
        hits += 1;
    }
    assert(hits == 2, "the body ran for a session, the else block for null");
    return 0;
}
