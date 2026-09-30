import async;

sum(from: long, to: long): long {
    var total: long = 0;
    var i = from;
    while (i < to) {
        total = total + i;
        i = i + 1;
    }
    return total;
}

main(): int {
    async.run_with(async.RuntimeOptions().workers(4), () => {
        # Two halves of the work, on two workers at the same time.
        var low = async.spawn<long>(() => { return sum(0, 500000); });
        var high = async.spawn<long>(() => { return sum(500000, 1000000); });
        var total = low.join().value() + high.join().value();
        assert(total == 499999500000, "both halves were added");
    });
    return 0;
}
