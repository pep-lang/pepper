import "impl";

export struct Counter {
    var count: int;

    increment(): int {
        count += step();
        return count;
    }
}

export step as increment_size;
