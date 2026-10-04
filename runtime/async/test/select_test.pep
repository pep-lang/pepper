# Select<E> across threads: channels of different types matched on an enum,
# fairness, try_wait, timeouts, every channel closed, and a stress run where
# every value must arrive.

import async;

private enum Event {
    Word(text: String),
    Number(value: long),
    Stop,
}

private const words = async.Channel<String>();
private const numbers = async.Channel<long>();
const quit = async.Channel<bool>();
const STREAMS = 4;
const PER_STREAM = 2000;

private produce() {
    words.send("ab");
    numbers.send(2);
    words.send("cde");
    numbers.send(3);
    words.close();
    numbers.close();
}

stream(channel: async.Channel<long>) {
    long i = 0;
    while (i < PER_STREAM) {
        channel.send(i);
        if (i % 97 == 0) {
            async.Thread.sleep(0);
        }
        i = i + 1;
    }
    channel.close();
}

[Test]
select_matches_channels_of_different_types() {
    var select = async.Select<Event>();
    select.receive(words, (text: String): Event => Event.Word(text));
    select.receive(numbers, (value: long): Event => Event.Number(value));
    select.receive(quit, (stop: bool): Event => Event.Stop);
    var thread = async.Thread.spawn(produce);
    var letters = 0;
    long total = 0;
    var events = 0;
    quit.close();
    var running = true;
    while (running) {
        match (select.wait_for(5000)) {
            Ok(event) => {
                events = events + 1;
                match (event) {
                    Word(text) => {
                        letters = letters + text.length as int;
                    }
                    Number(value) => {
                        total = total + value;
                    }
                    Stop => {
                        panic("quit only closes");
                    }
                }
            }
            Err(error) => {
                expect_equal(error.message, "every channel is closed");
                running = false;
            }
        }
    }
    thread.join();
    # Every value arrived once.
    expect_equal(events, 4);
    expect_equal(letters, 5);
    expect_equal(total, 5);
}

[Test]
select_takes_turns() {
    var a = async.Channel<long>();
    var b = async.Channel<long>();
    long i = 0;
    while (i < 3) {
        a.send(i);
        b.send(10 + i);
        i = i + 1;
    }
    var select = async.Select<long>();
    select.receive(a, (n: long): long => n);
    select.receive(b, (n: long): long => n);
    var order = Array<long>();
    var k = 0;
    while (k < 6) {
        order.append(select.try_wait().value());
        k = k + 1;
    }
    # Turns alternate, and keep alternating.
    expect_equal(order[0], 0);
    expect_equal(order[1], 10);
    expect_equal(order[2], 1);
    expect_equal(order[3], 11);
    expect_equal(order[4], 2);
    expect_equal(order[5], 12);
    expect_equal(select.try_wait().error().message, "no value is waiting");
}

[Test]
select_timeouts_and_closed_channels() {
    var quiet = async.Channel<long>();
    var select = async.Select<long>();
    select.receive(quiet, (n: long): long => n);
    var result = select.wait_for(30);
    expect_true(result.is_err());
    expect_equal(result.error().message, "the time ran out");
    quiet.close();
    expect_equal(select.wait().error().message, "every channel is closed");
    var none = async.Select<long>();
    expect_equal(none.wait().error().message, "the select has no channels");
}

# A lost wakeup would hang it, so every wait has a generous timeout that
# fails the test instead.
[Test]
select_stress_loses_no_value() {
    var select = async.Select<long>();
    var threads = Array<async.Thread>();
    var i = 0;
    while (i < STREAMS) {
        var channel = async.Channel<long>();
        select.receive(channel, (n: long): long => n);
        threads.append(async.Thread.spawn(() => {
            stream(channel);
        }));
        i = i + 1;
    }
    long received = 0;
    long sum = 0;
    var running = true;
    while (running) {
        match (select.wait_for(10000)) {
            Ok(n) => {
                received = received + 1;
                sum = sum + n;
            }
            Err(error) => {
                expect_equal(error.message, "every channel is closed");
                running = false;
            }
        }
    }
    for (var thread in threads) {
        thread.join();
    }
    # No value was lost, and each arrived once.
    expect_equal(received, STREAMS * PER_STREAM);
    expect_equal(sum, STREAMS * (PER_STREAM * (PER_STREAM - 1) / 2));
}
