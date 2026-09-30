# Types are PascalCase; acronyms are written as words (`HttpClient`, not `HTTPClient`).
struct TemperatureLog {
    # Public data members are snake_case.
    var unit_name: String = "celsius";
    # Private data members start with `_`.
    var _readings: Array<int> = Array<int>();
    var _total: int = 0;

    # Methods and their parameters are snake_case.
    add_reading(degrees: int) {
        _readings.append(degrees);
        _total = _total + degrees;
    }

    average(): int {
        return _is_empty() ? 0 : _total / (_readings.count() as int);
    }

    # A private method starts with `_` too.
    _is_empty(): bool {
        return _readings.count() == 0;
    }
}

# Generic parameters are a single capital letter or PascalCase.
struct Pair<TFirst, TSecond> {
    var first: TFirst;
    var second: TSecond;

    construct(TFirst first, TSecond second) {
        this.first = first;
        this.second = second;
    }
}

# Free functions and local variables are snake_case.
largest_of<T>(values: Array<T>): T {
    var best_so_far = values[0];
    for (var value in values) {
        if (value > best_so_far) {
            best_so_far = value;
        }
    }
    return best_so_far;
}

main(): int {
    var log = TemperatureLog();
    log.add_reading(20);
    log.add_reading(24);
    assert(log.average() == 22, "average of the readings");
    assert(log.unit_name == "celsius", "public member");

    var pair = Pair<String, int>("answer", 42);
    assert(pair.second == 42, "generic struct");

    var numbers = Array<int>();
    numbers.append(3);
    numbers.append(9);
    numbers.append(4);
    assert(largest_of<int>(numbers) == 9, "generic function");
    return 0;
}
