# Releases reference chains deep enough to overflow the stack if each
# link's release recursed into the next (#65): a linked list, a binary
# tree, a list through a trait-typed field, a reference enum list, a tree
# whose nodes hold an `Array` of children, closures that capture closures;
# and one released by a task while another task waits inside a destructor.
# Then prints the order shallow destructors run in: unchanged for types no
# cycle runs through, and for a recursive one as `memory.md` describes.

import async;
import process;

const counted = async.Atomic<int>(0);

struct Link {
    var next: Link;
}

trait Node {
    depth(): int;
}

struct TraitLink {
    var next: Node;
}

extend TraitLink with Node {
    depth(): int {
        return 1;
    }
}

enum List {
    Empty,
    Cons(head: int, tail: List),
}

struct Tree {
    var children: Array<Tree> = Array<Tree>();
}

struct Branch {
    var left: Branch;
    var right: Branch;
}

# A trait-linked chain that counts its destructions.
struct Counted {
    var next: Node;

    destruct {
        counted.fetch_add(1);
    }
}

extend Counted with Node {
    depth(): int {
        return 1;
    }
}

# Its destructor lets other tasks run: a release that suspends its task,
# of a type whose last release bounds its nesting (a cycle through `Node`).
struct Waits {
    var next: Node;

    destruct {
        async.yield_now();
    }
}

extend Waits with Node {
    depth(): int {
        return 1;
    }
}

struct Named {
    var name: String;
    var first: Named;
    var second: Named;

    construct(name: String) {
        this.name = name;
    }

    destruct {
        print($"destroy {name}");
    }
}

# Destroys `name` and then its `piece`: no cycle runs through either type.
struct Part {
    var name: String;
    var piece: Piece;

    construct(name: String) {
        this.name = name;
        this.piece = Piece(name + ".piece");
    }

    destruct {
        print($"destroy {name}");
    }
}

struct Piece {
    var name: String;

    construct(name: String) {
        this.name = name;
    }

    destruct {
        print($"destroy {name}");
    }
}

struct Holder {
    var first: Part;
    var second: Part;

    destruct {
        print("destroy holder");
    }
}

link_chain(depth: int) {
    var root = Link();
    var node = root;
    for (var i in 0..depth) {
        var child = Link();
        node.next = child;
        node = child;
    }
}

# A tree `depth` levels deep along `left`, with a leaf on each `right`.
branch_tree(depth: int) {
    var root = Branch();
    var node = root;
    for (var i in 0..depth) {
        var child = Branch();
        node.left = child;
        node.right = Branch();
        node = child;
    }
}

trait_chain(depth: int) {
    Node root = TraitLink();
    var node = TraitLink();
    root = node;
    for (var i in 0..depth) {
        var child = TraitLink();
        node.next = child;
        node = child;
    }
}

enum_chain(depth: int) {
    var list = List.Empty;
    for (var i in 0..depth) {
        list = List.Cons(i, list);
    }
}

# A tree `depth` levels deep with a second, leaf child at each level.
tree(depth: int) {
    var root = Tree();
    var node = root;
    for (var i in 0..depth) {
        var child = Tree();
        node.children.append(child);
        node.children.append(Tree());
        node = child;
    }
}

# Each closure captures the one before it.
closure_chain(depth: int) {
    var f: () => int = () => 0;
    for (var i in 0..depth) {
        var g = f;
        f = () => g() + 1;
    }
}

# A task waits inside a destructor while another releases a deep chain,
# which must be destroyed at once, without overflowing the task's stack.
suspended_destructor(depth: int) {
    async.run(() => {
        var waiting = async.Task<void>.spawn_local(() => {
            var waits = Waits();
        });
        var releasing = async.Task<void>.spawn_local(() => {
            {
                var root = Counted();
                var node = root;
                for (var i in 0..depth) {
                    var child = Counted();
                    node.next = child;
                    node = child;
                }
            }
            if (counted.load() == depth + 1) {
                print("chain released while a task waits in a destructor");
            }
        });
        waiting.join();
        releasing.join();
    });
}

plain_order() {
    var holder = Holder();
    holder.first = Part("first");
    holder.second = Part("second");
}

recursive_order() {
    var root = Named("root");
    root.first = Named("first");
    root.second = Named("second");
    root.first.first = Named("first.first");
    root.first.second = Named("first.second");
}

main(): int {
    var depth = int.parse(process.arguments()[1]).value();
    link_chain(depth);
    print("link chain released");
    branch_tree(depth);
    print("branch tree released");
    trait_chain(depth);
    print("trait chain released");
    enum_chain(depth);
    print("enum chain released");
    tree(depth);
    print("tree released");
    closure_chain(depth);
    print("closure chain released");
    suspended_destructor(depth);
    plain_order();
    recursive_order();
    return 0;
}
