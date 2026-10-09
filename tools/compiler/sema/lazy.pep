## The `[__Reads]` methods of a `[__Lazy]` struct: `passes::check_lazy` in
## Pepper. Such a method runs on a null `this` when the object is empty and
## not yet allocated (`Array<T>`), reading its fields as zero. So it must not
## write a field of `this`, nor call a method on `this` that is not
## `[__Reads]` itself: either would write through null. Each is an error at
## the write or the call.

import [Location] from compiler.diagnostic;
import "builder";
import "closures";
import [error_at, location_of] from "common";
import [Loc] from "loc";
import [Expression, FunctionDef, Module] from "model";
import [PassState] from "state";
import [Rewriter, rewrite_block] from "walk";

## The attribute that makes an empty object of a runtime struct null until
## something writes to or shares it.
export const LAZY_ATTRIBUTE = "__Lazy";

## The attribute that marks a method of a `[__Lazy]` struct (or a parameter)
## as reading only.
export const READS_ATTRIBUTE = "__Reads";

## Reports a write to `this`, or a call on `this` of a method that is not
## `[__Reads]`, in a `[__Reads]` method of a `[__Lazy]` struct.
##
## @param module the model
## @param state the passes' state, which takes the errors
export check_lazy(module: Module, state: PassState) {
    var reported = HashSet<String>();
    for (var st in module.structs) {
        if (!has_bare_attribute(st.attributes, LAZY_ATTRIBUTE)) {
            continue;
        }
        var reads = HashSet<String>();
        for (var m in st.method_members) {
            if (has_bare_attribute(m.attributes, READS_ATTRIBUTE)) {
                reads.insert(m.name);
            }
        }
        for (var m in st.method_members) {
            if (!reads.contains(m.name) or !m.body.is_value()) {
                continue;
            }
            var checker = _ReadsChecker(reads, m, state, reported);
            rewrite_block(m.body.value(), checker);
        }
    }
}

struct _ReadsChecker {
    var reads: HashSet<String>;
    var method: FunctionDef;
    var state: PassState;
    var reported: HashSet<String>;

    construct(reads: HashSet<String>, method: FunctionDef, state: PassState, reported: HashSet<String>) {
        this.reads = reads;
        this.method = method;
        this.state = state;
        this.reported = reported;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            Binary(node) => {
                if (_is_assignment(node.op) and _writes_this(node.lhs)) {
                    report("a '[__Reads]' method cannot write a field of 'this'", node.loc);
                }
            }
            MethodCall(node) => {
                if (node.this_value is ThisRef and !node.method.starts_with("__") and !reads.contains(node.method)) {
                    report($"a '[__Reads]' method cannot call '{node.method}', which is not '[__Reads]'", node.loc);
                }
            }
            else => {}
        }
        return e;
    }

    report(message: String, at: Loc) {
        var key = $"{at.file}:{at.span.start}:{at.span.end}";
        if (reported.contains(key)) {
            return;
        }
        reported.insert(key);
        state.report(
            error_at(
                message, at
            ).with_note($"'{method.name}' is '[__Reads]'", Optional<Location>.Value(location_of(method.loc)))
        );
    }
}

extend _ReadsChecker with Rewriter;

## Whether the assignment target `lhs` is a field of `this`, or a slot of a
## buffer one holds (`_data[i]`).
_writes_this(lhs: Expression): bool {
    match (lhs) {
        MemberRef(node) => {
            return node.lhs is ThisRef or _writes_this(node.lhs);
        }
        Index(node) => {
            return _writes_this(node.lhs);
        }
        ArrayIndex(node) => {
            return _writes_this(node.lhs);
        }
        else => {
            return false;
        }
    }
}
