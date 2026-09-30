import async;

# A plain struct: no destructor and no raw pointer, so `copy` copies it field
# by field. Its Strings and Array are not thread-safe, but a Channel takes
# only new values, and a copy is one.
struct Order {
    String customer;
    Array<String> items;
    Order next;

    construct(this.customer = "") {
        items = Array<String>();
    }
}

const orders = async.Channel<Order>();
const letters = Atomic<long>(0);

count_letters() {
    for (var order in orders) {
        for (var item in order.items) {
            letters.fetch_add(item.length() as long);
        }
    }
}

main(): int {
    # copy() makes a new object for everything that is not thread-safe.
    var tea = Order("ada");
    tea.items.append("tea");
    var copied = copy(tea);
    copied.items[0].append(" and cake");
    assert(tea.items[0] == "tea", "the original is unchanged");

    # Objects referenced twice stay shared in the copy, and cycles are kept.
    var a = Order("a");
    var b = Order("b");
    a.next = b;
    b.next = a;
    var pair = copy(a);
    assert(pair.next.next === pair, "the copy has the same cycle");
    a.next = __null;
    pair.next = __null;

    # send() takes a new value: send a copy to keep changing the order.
    var worker = async.Thread.spawn(count_letters);
    var order = Order("grace");
    order.items.append("coffee");
    orders.send(copy(order));
    order.items.append("biscuits");
    # Or hand the value itself over with `move`; `last` is null afterwards.
    var last = Order("hopper");
    last.items.append("tea");
    orders.send(move(last));
    orders.close();
    worker.join();
    assert(letters.load() == 9, "the worker saw only what was sent");
    return 0;
}
