import async;

# A Mutex of values that are not thread-safe: a list of Strings that
# several threads add to.
const names = async.Mutex<Array<String>>(Array<String>());

add_names(prefix: String) {
    var i = 0;
    while (i < 3) {
        with (var list = names.lock()) {
            list.append("worker");            # a new String: fine
            list.append(prefix + "!");        # `+` returns a new String: fine
            list.append(copy(prefix));        # a copy of an outside value: fine
            var n = list.count();             # a number leaves freely
            if (list.contains(prefix)) {      # comparing keeps nothing
                n = n + 1;
            }
        }
        i = i + 1;
    }
}

# Part of the locked value leaves the block only as a copy.
first_name(): String {
    with (var list = names.lock()) {
        if (list.count() > 0) {
            return list[0].copy();
        }
    }
    return "";
}

main(): int {
    var a = async.Thread.spawn(() => { add_names("a"); });
    var b = async.Thread.spawn(() => { add_names("b"); });
    a.join();
    b.join();

    var first = first_name();
    first.append(" (mine)");   # changing the copy leaves the list alone
    with (var list = names.lock()) {
        assert(list.count() == 18, "every name was added");
        assert(list[0] == "worker", "the locked String is unchanged");
    }

    # replace swaps in a new value and hands back the old one, which the
    # caller then owns outright.
    var old = names.replace(Array<String>());
    assert(old.count() == 18, "the old list");

    # A thread's own value that is not thread-safe is reached through `with`.
    var scratch = async.ThreadLocal<String>();
    scratch.set("draft");
    with (var text = scratch.enter()) {
        text.append(" 2");
    }
    with (var text = scratch.enter()) {
        assert(text == "draft 2", "this thread's value");
    }
    return 0;
}
