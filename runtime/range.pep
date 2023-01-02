struct range {
    int start;
    int current = 0xffffffff;
    int end;
    int step;

    new(this.start, this.end = -1, this.step=1) {
        if (end == -1) {
            end = start + 1;
            step = 0;
        }
    }
}

extend range {
    bool next() {
        if (current == 0xffffffff) {
            current = start;
        } else {
            current += step;
        }
        return current < end;
    }

    int value() {
        return current;
    }
}