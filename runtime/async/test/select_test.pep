# Select<E> across threads: channels of different types matched on an enum,
# fairness, try_wait, timeouts, every channel closed, and a stress run where
# every value must arrive.

import async;
import "../atomic";

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

# What a select that both receives and sends returns.
private enum Flow {
    Got(value: long),
    Sent(value: long),
}

[Test]
select_sends_only_when_its_arm_fires() {
    # A full bounded channel: the send arm waits, so the receive arm fires.
    var out = async.Channel<String>(1);
    expect_true(out.try_send("first"));
    var input = async.Channel<long>();
    input.send(7);
    var select = async.Select<Flow>();
    select.receive(input, (n: long): Flow => Flow.Got(n));
    select.send(out, "second", (): Flow => Flow.Sent(2));
    match (select.try_wait().value()) {
        Got(n) => {
            expect_equal(n, 7);
        }
        Sent(n) => {
            panic("the channel is full");
        }
    }
    # Nothing is ready now: the value was not sent.
    expect_equal(select.try_wait().error().message, "no value is waiting");
    expect_equal(out.count, 1);
    # Once there is room, the send arm fires and leaves the select.
    expect_equal(out.try_receive().value(), "first");
    match (select.try_wait().value()) {
        Got(n) => {
            panic("input is empty");
        }
        Sent(n) => {
            expect_equal(n, 2);
        }
    }
    expect_equal(out.try_receive().value(), "second");
    expect_equal(select.try_wait().error().message, "no value is waiting");
    # Only the receive arm is left: closing its channel ends the select.
    input.close();
    expect_equal(select.wait().error().message, "every channel is closed");
}

[Test]
select_send_to_a_closed_channel_never_fires() {
    var out = async.Channel<long>();
    out.close();
    var select = async.Select<long>();
    select.send(out, 1, (): long => 1);
    expect_equal(select.wait().error().message, "every channel is closed");
    expect_equal(out.count, 0);
}

# A worker drains `results` slowly while the select sends to it and also
# receives every number from `inputs`: a send arm waits for room on another
# thread, and a lost wakeup would fail the wait's timeout.
[Test]
select_waits_to_send_across_threads() {
    var inputs = async.Channel<long>();
    var results = async.Channel<long>(2);
    var feeder = async.Thread.spawn(() => {
        stream(inputs);
    });
    var drained = Atomic<long>(0);
    var drainer = async.Thread.spawn(() => {
        for (var n in results) {
            drained.fetch_add(n);
        }
    });
    var select = async.Select<Flow>();
    select.receive(inputs, (n: long): Flow => Flow.Got(n));
    long pending = 0;
    long received = 0;
    long sent = 0;
    var running = true;
    while (running) {
        match (select.wait_for(10000)) {
            Ok(flow) => {
                match (flow) {
                    Got(n) => {
                        received = received + 1;
                        # Each number goes on as soon as `results` has room.
                        select.send(results, n, (): Flow => Flow.Sent(1));
                        pending = pending + 1;
                    }
                    Sent(one) => {
                        sent = sent + one;
                        pending = pending - 1;
                    }
                }
            }
            Err(error) => {
                expect_equal(error.message, "every channel is closed");
                running = false;
            }
        }
        if (received == PER_STREAM && pending == 0) {
            running = false;
        }
    }
    results.close();
    feeder.join();
    drainer.join();
    expect_equal(received, PER_STREAM);
    expect_equal(sent, PER_STREAM);
    expect_equal(drained.load(), PER_STREAM * (PER_STREAM - 1) / 2);
}
