struct range_test<T> {
    T start;
    T current;
    T end;
    T step;

    new(this.start, this.end = -1, this.step=1) {
        if (end == -1) {
            end = start + 1;
            step = 0;
        }
        current = start - step;
    }
}

extend range_test<T> {
    bool next() {
        if ((current + step) == start) {
            current = start;
        } else {
            current += step;
        }
        return current < end;
    }

    T value() {
        return current;
    }
}

int main() {
    range_test<int> r = range_test<int>(0, 10);
    int x = 0;
    while (r.next()) {
        x += 1;
    }
    return x - 10;
}