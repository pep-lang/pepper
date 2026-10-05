import async;

# What one wait did: a job arrived, or a result went out.
enum Step {
    Job(value: long),
    Sent,
}

const jobs = async.Channel<long>();
# Holds one result at a time, so sending can wait.
const results = async.Channel<long>(1);

feed() {
    var i: long = 1;
    while (i <= 5) {
        jobs.send(i);
        i = i + 1;
    }
    jobs.close();
}

main(): int {
    var select = async.Select<Step>();
    select.receive(jobs, (value: long): Step => Step.Job(value));
    var feeder = async.Thread.spawn(feed);
    var received = 0;
    var waiting = 0;
    var total: long = 0;
    while (received < 5 || waiting > 0) {
        match (select.wait()) {
            Ok(step) => {
                match (step) {
                    Job(value) => {
                        received = received + 1;
                        # Goes into `results` once it has room; until then
                        # the select keeps receiving jobs.
                        select.send(results, value * value, (): Step => Step.Sent);
                        waiting = waiting + 1;
                    }
                    Sent => {
                        waiting = waiting - 1;
                        # Take the result back out, so the next send has room.
                        total = total + results.receive().value();
                    }
                }
            }
            Err(error) => {
                panic(error.message);
            }
        }
    }
    feeder.join();
    assert(total == 55, "every square was sent once");
    return 0;
}
