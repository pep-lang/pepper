# Releases chains whose links a recursive struct's last release steers
# (#133) at the depth given, shallow and deep enough to overflow the stack
# if each release recursed into the next: through a trait value with two
# conformers, an `Array` of trait values, an `Array` whose nodes have a
# destructor, closures capturing two closures each, and, still bounded by
# the runtime's stack floor, a tuple, released while another task waits
# inside a destructor. Then prints the order shallow destructors run in.

import async;
import process;

const destroyed = async.Atomic<int>(0);

trait Shape {
    area(): int;
}

struct Square {
    var next: Shape;
}

extend Square with Shape {
    area(): int {
        return 1;
    }
}

struct Circle {
    var first: Shape;
    var second: Shape;
}

extend Circle with Shape {
    area(): int {
        return 2;
    }
}

trait Item {
    weight(): int;
}

struct Bag {
    var items: Array<Item> = Array<Item>();
}

extend Bag with Item {
    weight(): int {
        return 0;
    }
}

struct Counted {
    var children: Array<Counted> = Array<Counted>();

    destruct {
        destroyed.fetch_add(1);
    }
}

# A cycle through a tuple, which the last release does not steer.
struct Pairs {
    var next: (Pairs, int);

    destruct {
        destroyed.fetch_add(1);
    }
}

struct Waits {
    var next: (Waits, int);

    destruct {
        async.yield_now();
    }
}

struct Named {
    var name: String;
    var children: Array<Named> = Array<Named>();
    var shape: Shape;

    construct(name: String) {
        this.name = name;
    }

    destruct {
        print($"destroy {name}");
    }
}

extend Named with Shape {
    area(): int {
        return 0;
    }
}

# Squares and circles in turn, each circle's second shape a leaf square.
shape_chain(depth: int) {
    Shape root = Square();
    var square = Square();
    root = square;
    for (var i in 0..depth) {
        var circle = Circle();
        circle.second = Square();
        square.next = circle;
        square = Square();
        circle.first = square;
    }
}

bag_chain(depth: int) {
    var root = Bag();
    var bag = root;
    for (var i in 0..depth) {
        var inner = Bag();
        bag.items.append(Bag());
        bag.items.append(inner);
        bag = inner;
    }
}

# Each node holds a deeper node and a leaf; a leaf held elsewhere too
# outlives the chain.
counted_chain(depth: int): int {
    destroyed.store(0);
    var kept = Counted();
    {
        var root = Counted();
        var node = root;
        for (var i in 0..depth) {
            var child = Counted();
            node.children.append(child);
            node.children.append(i == 0 ? kept : Counted());
            node = child;
        }
    }
    return destroyed.load();
}

closure_chain(depth: int): int {
    var f: () => int = () => 1;
    for (var i in 0..depth) {
        var a = f;
        var b: () => int = () => 1;
        f = () => a() + b();
    }
    return 0;
}

pairs_chain(depth: int): int {
    destroyed.store(0);
    {
        var root = Pairs();
        var node = root;
        for (var i in 0..depth) {
            var child = Pairs();
            node.next = (child, i);
            node = child;
        }
    }
    return destroyed.load();
}

# A task waits inside a destructor while another releases a deep chain
# through a tuple, which the runtime bounds on the task's own stack.
suspended_destructor(depth: int) {
    async.run(() => {
        var waiting = async.Task<void>.spawn_local(() => {
            var waits = Waits();
        });
        var releasing = async.Task<void>.spawn_local(() => {
            if (pairs_chain(depth) == depth + 1) {
                print("tuple chain released while a task waits in a destructor");
            }
        });
        waiting.join();
        releasing.join();
    });
}

order() {
    var root = Named("root");
    root.children.append(Named("first"));
    root.children.append(Named("second"));
    root.children[0].children.append(Named("first.first"));
    root.shape = Named("shape");
}

main(): int {
    var depth = int.parse(process.arguments()[1]).value();
    shape_chain(depth);
    print("shape chain released");
    bag_chain(depth);
    print("bag chain released");
    print($"counted chain released {counted_chain(depth) == 2 * depth}");
    closure_chain(depth);
    print("closure chain released");
    suspended_destructor(depth);
    order();
    return 0;
}
