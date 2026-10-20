export enum Value {
    Null,
    Integer(value: long),
}

export struct Statement {
    var bound: int = 0;
    var last: long = 0;

    bind(index: int, value: long): Result<void> {
        bound = index;
        last = value;
        return Result<void>.ok();
    }

    bind(index: int, value: Value): Result<void> {
        if (value is Integer(n)) {
            return bind(index, n);
        }
        bound = index;
        return Result<void>.ok();
    }

    bind_all(values: Value[]): Result<void> {
        for (var i in 0..values.count) {
            var value = values[i];
            var index = (i + 1) as int;
            bind(index, value)?;
        }
        return Result<void>.ok();
    }
}
