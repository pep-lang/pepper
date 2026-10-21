## Releasing reference chains without recursion (#65): which structs can
## reach a value of their own type through their fields (`find_chains`),
## and the last release of such a struct, which destroys a chain of its
## own kind in a loop instead of one nested call per link.
##
## A struct no cycle runs through keeps the plain last release, a call to
## `T.__last_release`. In a cycle, each field that holds a struct of the
## same cycle directly is a chain field: before the destructor runs, the
## last release takes an extra reference to each chain field's object that
## nothing else holds, and pushes it on a list local to the outermost
## `T.__last_release` frame (eight entries on the stack, then the heap).
## The destructor's own release of the field then leaves it alive, and the
## loop releases it once the parent is freed. A cycle that also runs
## through a trait value, a container's buffer or a closure cannot be
## steered from the destructor; its last release goes through the
## runtime's `_pep_release_last`, which bounds the nesting on the stack.

import llvm;
import compiler.sema;
import [CountField, StructDef, TypeName, VariableDef] from compiler.sema;
import "address";
import "calls";
import "checks";
import "expressions";
import "functions";
import [Generator, StructDesc] from "generator";
import "generator";
import "globals";
import "lazy";
import "operators";
import "ops";
import "refs";
import "simd";
import "traits";
import "types";

## Entries of a chain list held on the stack before it moves to the heap.
const _CHAIN_INLINE_ENTRIES: ulong = 8;

## One field edge of the struct graph: the struct it reaches, and whether
## that is a chain field (its owner and target both have the standard
## counts, and it holds the target directly).
struct _Edge {
    var target: ulong;
    var direct: bool;

    construct(target: ulong, direct: bool) {
        this.target = target;
        this.direct = direct;
    }
}

extend Generator {
    ## Fills `recursive`, `deep_recursive` and `chain_fields` from the
    ## program's structs: the strongly connected components of the graph
    ## whose nodes are the structs and whose edges are what their fields can
    ## hold (Tarjan's algorithm, with an explicit stack).
    find_chains(all: StructDef[]) {
        var index = HashMap<String, ulong>();
        var nodes = Array<StructDef>();
        for (var st in all) {
            if (is_abstract(st) or !structs.contains(st.name)) {
                continue;
            }
            index[st.name] = nodes.count;
            nodes.append(st);
        }
        var conformers = HashMap<String, Array<ulong>>();
        var closures = HashMap<String, Array<ulong>>();
        for (var at in 0..nodes.count) {
            var st = nodes[at];
            for (var t in st.traits) {
                var name = t.to_string();
                if (!conformers.contains(name)) {
                    conformers[name] = Array<ulong>();
                }
                conformers[name].append(at);
            }
            if (sema.is_closure_struct(st.name)) {
                for (var m in st.method_members) {
                    if (m.name == sema.CALL_METHOD) {
                        var key = _signature_key(m.ty, _parameter_types(m.parameters));
                        if (!closures.contains(key)) {
                            closures[key] = Array<ulong>();
                        }
                        closures[key].append(at);
                    }
                }
            }
        }
        var edges = Array<Array<_Edge>>();
        for (var st in nodes) {
            var out = Array<_Edge>();
            bool owner = _chain_owner(st.name);
            for (var field in st.field_members) {
                _type_edges(field.ty, owner, index, conformers, out);
            }
            if (st.ty.is_function_type()) {
                var ret = st.ty.function_return();
                var key = _signature_key(ret.is_value() ? ret.value() : TypeName.void(), st.ty.function_params());
                var found = closures.try_get(key);
                if (found.is_value()) {
                    for (var c in found.value()) {
                        out.append(_Edge(c, false));
                    }
                }
            }
            edges.append(out);
        }
        var component = _components(edges);
        # A component is recursive when it has an edge inside it; deep when
        # one of those is not a chain field.
        var cyclic = HashSet<ulong>();
        var deep = HashSet<ulong>();
        for (var from in 0..nodes.count) {
            for (var edge in edges[from]) {
                if (component[edge.target] == component[from]) {
                    cyclic.insert(component[from]);
                    if (!edge.direct) {
                        deep.insert(component[from]);
                    }
                }
            }
        }
        for (var at in 0..nodes.count) {
            var c = component[at];
            if (!cyclic.contains(c)) {
                continue;
            }
            var name = nodes[at].name;
            recursive.insert(name);
            if (deep.contains(c)) {
                deep_recursive.insert(name);
            }
            var fields = Array<(uint, String)>();
            uint position = 0;
            for (var field in nodes[at].field_members) {
                var ty = field.ty.to_string();
                var target = index.try_get(ty);
                if (_chain_owner(name) and target.is_value() and component[target.value()] == c and _chain_owner(ty)) {
                    fields.append((position, ty));
                }
                position += 1;
            }
            if (fields.count > 0) {
                chain_fields[name] = fields;
            }
        }
    }

    ## Whether struct `name` has the standard `__release`, so its last
    ## release may take its chain fields out (see `standard_release`).
    _chain_owner(name: String): bool {
        var desc = structs.try_get(name);
        return desc.is_value() and desc.value().standard;
    }

    ## Appends to `out` the structs a slot of type `ty` can hold: the
    ## struct it names (a chain edge when `owner` and the struct has the
    ## standard counts), a trait's conformers, a pointer's or tuple's
    ## elements. A weak reference owns nothing.
    _type_edges(
        ty: TypeName,
        owner: bool,
        index: HashMap<String, ulong>,
        conformers: HashMap<String, Array<ulong>>,
        out: Array<_Edge>
    ) {
        if (ty.is_weak() or ty.is_extern_function_type()) {
            return;
        }
        if (ty.is_pointer() or ty.is_tuple()) {
            for (var element in ty.sub_types) {
                _type_edges(element, false, index, conformers, out);
            }
            return;
        }
        var name = ty.to_string();
        var found = conformers.try_get(name);
        if (found.is_value()) {
            for (var c in found.value()) {
                out.append(_Edge(c, false));
            }
            return;
        }
        var target = index.try_get(name);
        if (target.is_value()) {
            out.append(_Edge(target.value(), owner and _chain_owner(name)));
        }
    }

    # Last releases of chain structs

    ## `T.__last_release(object)` for a struct with chain fields: a chain
    ## list on the stack, `T.__chain_destroy(object, list)`, then each
    ## listed object's `__chain_release` until the list is empty, and the
    ## list's heap buffer freed if it grew.
    emit_chain_last_release(ty_name: String, object: llvm.Value): Result<void> {
        var fields = chain_fields[ty_name];
        if (fields.count == 1 and fields[0].1 == ty_name) {
            return emit_list_last_release(ty_name, object, fields[0].0);
        }
        var function = builder.insert_block().parent();
        var pointer = context.pointer_type();
        var i64_type = context.int64_type();
        var header_type = _chain_header_type();
        var header = entry_alloca(header_type, "chain");
        var inline_data = entry_alloca(pointer.array_type(_CHAIN_INLINE_ENTRIES * 2), "chain_entries");
        builder.store(inline_data, builder.field_pointer(header_type, header, 0, "data_slot"));
        builder.store(i64_type.zero(), builder.field_pointer(header_type, header, 1, "count_slot"));
        builder.store(
            i64_type.const_uint(_CHAIN_INLINE_ENTRIES), builder.field_pointer(header_type, header, 2, "capacity_slot")
        );
        builder.store(inline_data, builder.field_pointer(header_type, header, 3, "inline_slot"));
        var destroy = chain_destroy(ty_name)?;
        builder.call(destroy.global_type(), destroy, [object, header], "");
        var loop = context.append_block(function, "chain_loop");
        var next = context.append_block(function, "chain_next");
        var done = context.append_block(function, "chain_done");
        builder.branch(loop);
        builder.position_at_end(loop);
        var count_slot = builder.field_pointer(header_type, header, 1, "count_slot");
        var count = builder.load(i64_type, count_slot, "count");
        builder.conditional_branch(
            builder.compare(llvm.IntPredicate.Equal, count, i64_type.zero(), "empty"), done, next
        );
        builder.position_at_end(next);
        var last = builder.sub(count, i64_type.const_uint(1), "last");
        builder.store(last, count_slot);
        var data = builder.load(pointer, builder.field_pointer(header_type, header, 0, "data_slot"), "data");
        var slot = builder.element_pointer(
            pointer, data, [builder.shift_left(last, i64_type.const_uint(1), "at")], true, "entry"
        );
        var item = builder.load(pointer, slot, "object");
        var release = builder.load(
            pointer, builder.element_pointer(pointer, slot, [i64_type.const_uint(1)], true, "release_slot"), "release"
        );
        var release_type = llvm.Type.function(context.void_type(), [pointer, pointer]);
        builder.call(release_type, release, [item, header], "");
        builder.branch(loop);
        builder.position_at_end(done);
        var final_data = builder.load(pointer, builder.field_pointer(header_type, header, 0, "data_slot"), "data");
        var grown = builder.compare(llvm.IntPredicate.NotEqual, final_data, inline_data, "grown");
        var free_block = context.append_block(function, "chain_free");
        var end = context.append_block(function, "chain_end");
        builder.conditional_branch(grown, free_block, end);
        builder.position_at_end(free_block);
        call_function("_pep_free", [final_data])?;
        builder.branch(end);
        builder.position_at_end(end);
        return Result<void>.ok();
    }

    ## `T.__last_release(object)` for a struct whose one chain field, at
    ## `position`, holds its own type (a linked list): no list, a loop that
    ## takes the next link, destroys the current one, and moves on while
    ## the taken link's count reaches 0.
    emit_list_last_release(ty_name: String, object: llvm.Value, position: uint): Result<void> {
        var function = builder.insert_block().parent();
        var desc = structs[ty_name];
        bool atomic = desc.release_counts.value();
        var pointer = context.pointer_type();
        var i32_type = context.int32_type();
        var entry = builder.insert_block();
        var loop = context.append_block(function, "link_loop");
        var check = context.append_block(function, "link_check");
        var take = context.append_block(function, "link_take");
        var destroy = context.append_block(function, "link_destroy");
        var release = context.append_block(function, "link_release");
        var done = context.append_block(function, "link_done");
        builder.branch(loop);
        builder.position_at_end(loop);
        var current = builder.phi(pointer, "current");
        var link = builder.load(
            pointer, builder.field_pointer(desc.llvm_type, current, position, "chain_field"), "link"
        );
        builder.conditional_branch(builder.is_null(link, "no_link"), destroy, check);
        builder.position_at_end(check);
        # Only a link the field alone holds is taken (see `chain_destroy`).
        var count = builder.load(i32_type, head_count_ptr(link, CountField.Strong)?, "link_count");
        if (atomic) {
            count.set_ordering(_MONOTONIC);
        }
        builder.conditional_branch(
            builder.compare(llvm.IntPredicate.Equal, count, i32_type.const_uint(1), "alone"), take, destroy
        );
        builder.position_at_end(take);
        count_step(link, CountField.Strong, true, atomic, true)?;
        builder.branch(destroy);
        builder.position_at_end(destroy);
        var taken = builder.phi(pointer, "taken");
        taken.add_incoming([pointer.zero(), pointer.zero(), link], [loop, check, take]);
        destroy_object(ty_name, current, atomic)?;
        builder.conditional_branch(builder.is_null(taken, "none_taken"), done, release);
        builder.position_at_end(release);
        var left = count_step(taken, CountField.Strong, false, atomic, false)?;
        builder.conditional_branch(
            builder.compare(llvm.IntPredicate.Equal, left, i32_type.zero(), "is_last"), loop, done
        );
        current.add_incoming([object, taken], [entry, release]);
        builder.position_at_end(done);
        return Result<void>.ok();
    }

    ## `{ data, count, capacity, inline data }`: a chain list, whose
    ## entries are pairs of an object and its `__chain_release`.
    _chain_header_type(): llvm.Type {
        var pointer = context.pointer_type();
        var i64_type = context.int64_type();
        return context.struct_type([pointer, i64_type, i64_type, pointer]);
    }

    ## `T.__chain_destroy(object, list)`: what the last release of `T` does
    ## once the count is 0. Pushes each chain field's object that only the
    ## field holds on `list`, with a reference of the list's own, then runs
    ## the destructor and frees the memory (`destroy_object`).
    chain_destroy(ty_name: String): Result<llvm.Value> {
        var name = $"{ty_name}.__chain_destroy";
        var existing = ir.function(name);
        if (existing.is_value()) {
            return Result<llvm.Value>.ok(existing.value());
        }
        var desc = structs[ty_name];
        var pointer = context.pointer_type();
        var function = ir.add_function(name, llvm.Type.function(context.void_type(), [pointer, pointer]));
        var resume = builder.insert_block();
        builder.position_at_end(context.append_block(function, "entry"));
        var object = function.param(0);
        var list = function.param(1);
        var i32_type = context.int32_type();
        for (var (position, field_type) in chain_fields[ty_name]) {
            var target = structs[field_type];
            bool atomic = target.release_counts.value();
            var value = builder.load(
                pointer, builder.field_pointer(desc.llvm_type, object, position, "chain_field"), "link"
            );
            var check = context.append_block(function, "chain_check");
            var take = context.append_block(function, "chain_take");
            var after = context.append_block(function, "chain_after");
            builder.conditional_branch(builder.is_null(value, "no_link"), after, check);
            builder.position_at_end(check);
            # Only an object the field alone holds is taken: one another
            # slot holds is not this chain's to destroy, and an immortal
            # one's count is far above 1.
            var count = builder.load(i32_type, head_count_ptr(value, CountField.Strong)?, "link_count");
            if (atomic) {
                count.set_ordering(_MONOTONIC);
            }
            var alone = builder.compare(llvm.IntPredicate.Equal, count, i32_type.const_uint(1), "alone");
            builder.conditional_branch(alone, take, after);
            builder.position_at_end(take);
            count_step(value, CountField.Strong, true, atomic, true)?;
            _chain_push(list, value, chain_release(field_type)?)?;
            builder.branch(after);
            builder.position_at_end(after);
        }
        destroy_object(ty_name, object, desc.release_counts.value())?;
        builder.return_void();
        if (!resume.is_null()) {
            builder.position_at_end(resume);
        }
        return Result<llvm.Value>.ok(function);
    }

    ## `T.__chain_release(object, list)`: drops the list's reference to a
    ## taken object, and destroys it into `list` if that was the last.
    chain_release(ty_name: String): Result<llvm.Value> {
        var name = $"{ty_name}.__chain_release";
        var existing = ir.function(name);
        if (existing.is_value()) {
            return Result<llvm.Value>.ok(existing.value());
        }
        var pointer = context.pointer_type();
        var function = ir.add_function(name, llvm.Type.function(context.void_type(), [pointer, pointer]));
        var resume = builder.insert_block();
        builder.position_at_end(context.append_block(function, "entry"));
        var object = function.param(0);
        var after = count_step(object, CountField.Strong, false, structs[ty_name].release_counts.value(), false)?;
        var last = context.append_block(function, "last_release");
        var done = context.append_block(function, "done");
        builder.conditional_branch(
            builder.compare(llvm.IntPredicate.Equal, after, context.int32_type().zero(), "is_last"), last, done
        );
        builder.position_at_end(last);
        var destroy = chain_destroy(ty_name)?;
        builder.call(destroy.global_type(), destroy, [object, function.param(1)], "");
        builder.branch(done);
        builder.position_at_end(done);
        builder.return_void();
        if (!resume.is_null()) {
            builder.position_at_end(resume);
        }
        return Result<llvm.Value>.ok(function);
    }

    ## Appends `(value, release)` to the chain list at `list`, moving it to
    ## a bigger heap buffer when full (`_pep_release_list_grow`).
    _chain_push(list: llvm.Value, value: llvm.Value, release: llvm.Value): Result<void> {
        var function = builder.insert_block().parent();
        var pointer = context.pointer_type();
        var i64_type = context.int64_type();
        var header_type = _chain_header_type();
        var count_slot = builder.field_pointer(header_type, list, 1, "count_slot");
        var capacity_slot = builder.field_pointer(header_type, list, 2, "capacity_slot");
        var data_slot = builder.field_pointer(header_type, list, 0, "data_slot");
        var count = builder.load(i64_type, count_slot, "count");
        var full = builder.compare(
            llvm.IntPredicate.Equal, count, builder.load(i64_type, capacity_slot, "capacity"), "full"
        );
        var grow = context.append_block(function, "chain_grow");
        var store = context.append_block(function, "chain_store");
        builder.conditional_branch(full, grow, store);
        builder.position_at_end(grow);
        var inline_data = builder.load(pointer, builder.field_pointer(header_type, list, 3, "inline_slot"), "inline");
        var old = builder.load(pointer, data_slot, "data");
        var moved = call_function("_pep_release_list_grow", [old, count, inline_data])?;
        builder.store(moved, data_slot);
        builder.store(builder.shift_left(count, i64_type.const_uint(1), "doubled"), capacity_slot);
        builder.branch(store);
        builder.position_at_end(store);
        var data = builder.load(pointer, data_slot, "data");
        var slot = builder.element_pointer(
            pointer, data, [builder.shift_left(count, i64_type.const_uint(1), "at")], true, "entry"
        );
        builder.store(value, slot);
        builder.store(release, builder.element_pointer(pointer, slot, [i64_type.const_uint(1)], true, "release_slot"));
        builder.store(builder.add(count, i64_type.const_uint(1), "count"), count_slot);
        return Result<void>.ok();
    }
}

## The key a function type and a closure's `__call` share: its return and
## parameter types.
_signature_key(ret: TypeName, parameters: TypeName[]): String {
    var parts = Array<String>();
    for (var p in parameters) {
        parts.append(p.to_string());
    }
    var joined = ", ".join(parts);
    return $"{ret.to_string()}({joined})";
}

_parameter_types(parameters: VariableDef[]): TypeName[] {
    var out = Array<TypeName>();
    for (var p in parameters) {
        if (p.name != "this") {
            out.append(p.ty);
        }
    }
    return out;
}

## The strongly connected component of each node of `edges` (Tarjan's
## algorithm, iterative so a long chain of structs cannot overflow it).
_components(edges: Array<Array<_Edge>>): ulong[] {
    # Every order and component number is below the node count.
    ulong unset = edges.count;
    var order = Array<ulong>();
    var low = Array<ulong>();
    var component = Array<ulong>();
    var on_stack = Array<bool>();
    for (var i in 0..edges.count) {
        order.append(unset);
        low.append(0);
        component.append(unset);
        on_stack.append(false);
    }
    var stack = Array<ulong>();
    ulong counter = 0;
    ulong components = 0;
    for (var root in 0..edges.count) {
        if (order[root] != unset) {
            continue;
        }
        # Each frame: a node and the next of its edges to visit.
        var frames = Array<(ulong, ulong)>();
        frames.append((root, 0));
        order[root] = counter;
        low[root] = counter;
        counter += 1;
        stack.append(root);
        on_stack[root] = true;
        while (frames.count > 0) {
            var (node, next) = frames[frames.count - 1];
            if (next < edges[node].count) {
                frames[frames.count - 1] = (node, next + 1);
                var target = edges[node][next].target;
                if (order[target] == unset) {
                    order[target] = counter;
                    low[target] = counter;
                    counter += 1;
                    stack.append(target);
                    on_stack[target] = true;
                    frames.append((target, 0));
                } else if (on_stack[target] and order[target] < low[node]) {
                    low[node] = order[target];
                }
                continue;
            }
            frames.pop();
            if (frames.count > 0) {
                var (parent, _) = frames[frames.count - 1];
                if (low[node] < low[parent]) {
                    low[parent] = low[node];
                }
            }
            if (low[node] == order[node]) {
                while (true) {
                    var member = stack.pop();
                    on_stack[member] = false;
                    component[member] = components;
                    if (member == node) {
                        break;
                    }
                }
                components += 1;
            }
        }
    }
    return component;
}
