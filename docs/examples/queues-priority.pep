# A scheduler: the job with the earliest deadline runs first.
struct Job {
    var name: String;
    var deadline: int;

    construct(name: String, deadline: int) {
        this.name = name;
        this.deadline = deadline;
    }
}

main(): int {
    # The comparer is reversed, so the smallest deadline is the greatest.
    var jobs = PriorityQueue<Job>((a, b) => b.deadline.compare(a.deadline));
    jobs.push(Job("backup", 30));
    jobs.push(Job("email", 5));
    jobs.push(Job("report", 12));
    assert(jobs.peek().name == "email", "the earliest deadline");

    var order = "";
    while (!jobs.is_empty) {
        order = $"{order}{jobs.pop().name} ";
    }
    assert(order == "email report backup ", "by deadline");

    # Comparable elements need no comparer: the greatest comes out first.
    PriorityQueue<int> scores = [72, 95, 88, 61];
    assert(scores.pop() == 95, "the top score");
    var rest = scores.into_sorted_array();
    assert(rest == [61, 72, 88], "the rest, ascending");
    return 0;
}
