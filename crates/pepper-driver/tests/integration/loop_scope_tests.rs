//! A while body's struct locals are released where each iteration leaves the
//! body: its fall-through end, a `continue`, or a `break`, each releasing only
//! the locals declared before it. They used to be released at the loop's
//! condition block, which a `continue` placed before a declaration reaches
//! without passing that declaration: invalid IR ("Instruction does not
//! dominate all uses").

use crate::support::jit_census as compile_jit_census;

#[test]
fn continue_before_a_declaration() {
    let (result, leaked) = compile_jit_census(
        r#"
struct Item {
    int v;
    construct(this.v = 0) {}
}
test(): int {
    var kept = Array<Item>();
    var i = 0;
    while (i < 10) {
        var early = Item(i);
        i = i + 1;
        if (i % 2 == 0) {
            continue;                    # `late` is not declared yet
        }
        var late = Item(i * 10);
        kept.append(late);
        if (i == 9) {
            break;                       # both locals are live here
        }
    }
    return kept.count() - 5;
}
"#,
    );
    assert_eq!(result, 0);
    assert_eq!(leaked, 0, "loop locals leaked or double-released");
}

#[test]
fn locals_released_every_iteration() {
    // Each iteration's String is released on every exit path; a shared one
    // survives the loop with its count intact.
    let (result, leaked) = compile_jit_census(
        r#"
test(): int {
    var shared = "s";
    var n = 0;
    while (n < 100) {
        var a = shared;
        var b = "x" + shared;
        n = n + 1;
        if (n > 50) {
            continue;
        }
        var c = b + a;
    }
    return shared.size() - 1;
}
"#,
    );
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}
