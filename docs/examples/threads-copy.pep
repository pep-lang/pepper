import async;

# A plain struct: no destructor and no raw pointer, so `copy` copies it field
# by field. Its Strings and Array are not thread-safe, but a Channel copies
# every value it is sent.
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

    # send() copies, so the order can change after it is sent.
    var worker = async.Thread.spawn(count_letters);
    var order = Order("grace");
    order.items.append("coffee");
    orders.send(order);
    order.items.append("biscuits");
    orders.close();
    worker.join();
    assert(letters.load() == 6, "the worker saw only what was sent");
    return 0;
}
