struct range {
    int current;
    int end;
    int step;

    new(int start, int end, int step=1) {
        this.current = start;
        this.end = end;
        this.step = step;
    }
}

extend range with {
    bool next() {
        this.current += step;
        return this.current < end;
    }
}
