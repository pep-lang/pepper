export struct Failure {
    var code: int;
}

export type Outcome<T> = Result<T, Failure>;

export struct Db {
    step(): Outcome<void> {
        return Outcome<void>.ok();
    }

    run<T>(body: () => Outcome<T>): Outcome<T> {
        var result = body();
        var checked = step();
        if (checked is Err(e)) {
            return Outcome<T>.err(e);
        }
        return result;
    }
}
