import async;

main(): int {
    # Build the list here, then hand it to the Mutex: `move` gives up
    # `lines`' reference, so nothing is copied and `lines` is empty after.
    var lines = Array<String>();
    lines.append("first");
    var log = async.Mutex<Array<String>>(move(lines));

    var line = "second";
    with (var list = log.lock()) {
        # `line` holds the only reference to its String, so it can move in.
        list.append(move(line));
    }

    # Swap in a new list; the old one comes back without a copy either.
    var next = Array<String>();
    next.append("third");
    var old = log.replace(move(next));
    print($"{old.count()}");     # 2
    print(old[1]);               # second
    return 0;
}
