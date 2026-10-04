# Channel<T>: FIFO order, bounded sends, close waking blocked senders and
# receivers, timeouts, many producers and consumers, values released with a
# dropped channel, and values that are not thread-safe sent as copies.

import async;

[Shared]
struct Message {
    const id: long;
    construct(this.id = 0) {}
    destruct {
        released.fetch_add(1);
    }
}

private const released = async.Atomic<long>(0);
const fifo = async.Channel<long>();
const bounded = async.Channel<long>(1);
const second_sent = async.Atomic<long>(0);
const empty = async.Channel<long>();
const full = async.Channel<long>(1);
const woken = async.Atomic<long>(0);
private const work = async.Channel<long>(8);
private const sum = async.Atomic<long>(0);
const received_count = async.Atomic<long>(0);

check_order() {
    long expected = 0;
    for (var n in fifo) {
        # Values arrive in the order they were sent.
        expect_equal(n, expected);
        expected = expected + 1;
    }
    # The loop ended after the last value.
    expect_equal(expected, 1000);
}

send_second() {
    bounded.send(2);
    second_sent.store(1);
}

receive_until_closed() {
    # A receiver woken by close gets an error.
    expect_true(empty.receive().is_err());
    woken.fetch_add(1);
}

send_into_full() {
    # A sender woken by close fails.
    expect_false(full.send(2));
    woken.fetch_add(1);
}

private produce() {
    long i = 1;
    while (i <= 1000) {
        work.send(i);
        i = i + 1;
    }
}

consume() {
    for (var n in work) {
        sum.fetch_add(n);
        received_count.fetch_add(1);
    }
}

drop_with_queued() {
    var c = async.Channel<Message>();
    long i = 0;
    while (i < 40) {
        c.send(Message(i));
        i = i + 1;
    }
    # The oldest message comes first.
    expect_equal(c.receive().value().id, 0);
    expect_equal(c.count, 39);
}

[Test]
channels() {
    # FIFO from one sender, across growth of the unbounded buffer.
    var checker = async.Thread.spawn(check_order);
    long i = 0;
    while (i < 1000) {
        expect_true(fifo.send(i));
        i = i + 1;
    }
    fifo.close();
    checker.join();
    # A closed channel refuses values, and is empty.
    expect_false(fifo.send(1));
    expect_true(fifo.is_closed());
    expect_true(fifo.receive().is_err());

    # A bounded send waits for room.
    expect_true(bounded.send(1));
    expect_false(bounded.try_send(9));
    var sender = async.Thread.spawn(send_second);
    async.Thread.sleep(50);
    expect_equal(second_sent.load(), 0);
    expect_equal(bounded.receive().value(), 1);
    sender.join();
    expect_equal(second_sent.load(), 1);
    expect_equal(bounded.receive().value(), 2);
    expect_true(bounded.try_receive().is_err());
    # Empty is not closed.
    expect_false(bounded.is_closed());

    # close wakes blocked receivers and senders.
    full.send(1);
    var blocked = Array<async.Thread>();
    blocked.append(async.Thread.spawn(receive_until_closed));
    blocked.append(async.Thread.spawn(receive_until_closed));
    blocked.append(async.Thread.spawn(send_into_full));
    async.Thread.sleep(50);
    expect_equal(woken.load(), 0);
    empty.close();
    full.close();
    for (var t in blocked) {
        t.join();
    }
    expect_equal(woken.load(), 3);
    # Values queued before close are still received, then the closed
    # channel is empty.
    expect_equal(full.receive().value(), 1);
    expect_true(full.receive().is_err());

    # receive_for runs out, or returns a waiting value.
    var quiet = async.Channel<long>();
    expect_true(quiet.receive_for(30).is_err());
    quiet.send(5);
    expect_equal(quiet.receive_for(30).value(), 5);

    # Many producers and consumers: every value arrives exactly once,
    # unchanged.
    var producers = Array<async.Thread>();
    var consumers = Array<async.Thread>();
    var k = 0;
    while (k < 4) {
        producers.append(async.Thread.spawn(produce));
        consumers.append(async.Thread.spawn(consume));
        k = k + 1;
    }
    for (var p in producers) {
        p.join();
    }
    work.close();
    for (var c in consumers) {
        c.join();
    }
    expect_equal(received_count.load(), 4000);
    expect_equal(sum.load(), 4 * 500500);

    # Generic and function payloads (a pointer to a pointer to a generic
    # type in the buffer field once crashed the thread-safety check).
    var counters = async.Channel<async.Atomic<long>>();
    var one = async.Atomic<long>(1);
    counters.send(one);
    # An Atomic crosses by reference.
    expect_equal(counters.receive().value().load(), 1);
    var bodies = async.Channel<async.ThreadBody>();
    bodies.send(() => {
        woken.fetch_add(10);
    });
    bodies.receive().value()();
    # A shared function value crosses.
    expect_equal(woken.load(), 13);

    # A channel dropped with values still queued releases them.
    var before = _pep_live_allocs();
    drop_with_queued();
    expect_equal(released.load(), 40);
    expect_equal(_pep_live_allocs(), before);
}

struct Order {
    String customer;
    Array<String> items;
    construct(this.customer = "") {
        items = Array<String>();
    }
}

const orders = async.Channel<Order>(8);
const received_items = async.Atomic<long>(0);
const received_letters = async.Atomic<long>(0);
private const first = async.Channel<String>();

produce_orders() {
    var i = 0;
    while (i < 500) {
        var order = Order("ada");
        order.items.append("tea");
        order.items.append("cake");
        orders.send(copy(order));
        # Changing the original after sending does not reach the receiver.
        order.items.append("extra");
        order.customer.append("!");
        i = i + 1;
    }
}

consume_orders() {
    for (var order in orders) {
        # The copy was taken before the change.
        expect_equal(order.customer, "ada");
        received_items.fetch_add(order.items.count as long);
        for (var item in order.items) {
            received_letters.fetch_add(item.length as long);
        }
    }
}

# `Channel<T>` for a `T` that is not thread-safe: `send` copies, so the
# receiver owns a value the sender cannot change or release; many producers
# and consumers exchange Strings and Arrays.
[Test]
channels_send_new_values_that_are_not_thread_safe() {
    var line = "hello";
    first.send(copy(line));
    line.append(" world");
    # A copy is independent.
    expect_equal(first.receive().value(), "hello");
    var word = "moved";
    first.send(move(word));
    expect_equal(first.receive().value(), "moved");

    var producers = Array<async.Thread>();
    var consumers = Array<async.Thread>();
    var i = 0;
    while (i < 3) {
        producers.append(async.Thread.spawn(produce_orders));
        consumers.append(async.Thread.spawn(consume_orders));
        i = i + 1;
    }
    for (var p in producers) {
        p.join();
    }
    orders.close();
    for (var c in consumers) {
        c.join();
    }
    # Every item arrived once, and unchanged.
    expect_equal(received_items.load(), 3 * 500 * 2);
    expect_equal(received_letters.load(), 3 * 500 * 7);
}
