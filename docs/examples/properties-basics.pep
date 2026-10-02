# A property is read and written like a field, but its `get` and `set`
# accessors can run code.
struct Account {
    # An auto property: implied storage, read and written by anyone.
    var owner: String { get; set; }

    # Read-only outside the struct: only Account's own code assigns it.
    var balance: long { get; }

    # A custom `set` over implied storage: `field` is the storage and
    # `value` is the new value.
    var name: String {
        get;
        set {
            assert(!value.is_empty, "an account name cannot be empty");
            field = value;
        }
    } = "unnamed";

    # Computed: no accessor is omitted and none uses `field`, so it takes
    # no space.
    var is_empty: bool {
        get {
            return balance == 0;
        }
    }

    # Explicit storage, when you want it.
    var _deposits: ulong;
    var deposits: ulong {
        get {
            return _deposits;
        }
    }

    # An initializer initializes the implied storage.
    var limit: long { get; set; } = 100;

    construct(this.owner = "") {}

    deposit(amount: long) {
        balance += amount;   # Account's own code may set a get-only property
        _deposits += 1;
    }
}

main(): int {
    var account = Account("Ann");
    assert(account.owner == "Ann", "a constructor parameter can set a property");
    assert(account.is_empty, "a computed property runs its get");

    account.owner = "Bob";
    account.name = "Savings";
    assert(account.name == "Savings", "the set stored the name");

    account.deposit(30);
    account.deposit(12);
    assert(account.balance == 42 && account.deposits == 2, "methods update the storage");
    assert(!account.is_empty, "the computed property follows the balance");

    # `account.balance = 0;` would not compile: 'balance' has no 'set'.

    account.limit += 50;   # a get, then a set
    assert(account.limit == 150, "compound assignment reads and writes");
    return 0;
}
