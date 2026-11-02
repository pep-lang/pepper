import async;

const _created = async.Atomic<int>(0);

struct Ticket {
    var number: int;

    construct() {
        number = _created.fetch_add(1) + 1;
    }

    # A property of the type, read as `Ticket.issued`.
    static var issued: int {
        get { return _created.load(); }
        set {
            _created.store(value);
        }
    }

    # In the struct's own code, a bare name.
    static var next: int {
        get { return issued + 1; }
    }
}

main(): int {
    Ticket();
    Ticket();
    assert(Ticket.issued == 2 && Ticket.next == 3, "two issued");
    Ticket.issued = 10;
    Ticket.issued += 5;
    assert(Ticket().number == 16, "numbering goes on from 15");
    return 0;
}
