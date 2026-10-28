import async;

struct Connection {
    var id: int;

    construct(id: int) {
        this.id = id;
    }
}

connect(id: int): Result<Connection, String> {
    return Result<Connection, String>.ok(Connection(id));
}

open_both(pool: async.Channel<Connection>): Result<void, String> {
    # The `Result` is a temporary: once `?` has read it, `first` holds
    # the only reference to the connection.
    var first = connect(1)?;
    pool.send(move(first));
    if (connect(2) is Ok(second)) {
        pool.send(move(second));
    }

    # var kept = connect(3);
    # var third = kept?;
    # pool.send(move(third));   # error: 'kept' also references its value
    return Result<void, String>.ok();
}

main(): int {
    var pool = async.Channel<Connection>();
    open_both(pool);
    print($"{pool.receive().value().id}");  # 1
    print($"{pool.receive().value().id}");  # 2
    return 0;
}
