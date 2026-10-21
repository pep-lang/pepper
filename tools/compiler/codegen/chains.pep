## Releasing reference chains without recursion (#65): which structs can
## reach a value of their own type through their fields (`find_chains`),
## and the last release of such a struct, which destroys a chain of its
## own kind in a loop instead of one nested call per link.
##
## A struct no cycle runs through keeps the plain last release, a call to
## `T.__last_release`. In a cycle, each field that holds a struct of the
## same cycle is a chain field: before the destructor runs, the last
## release takes each chain field's object (its reference moved out of the
## field when no destructor body can see the field, else an extra one,
## when nothing else holds it), and pushes it on a list local to the outermost
## `T.__last_release` frame (32 entries on the stack, then the heap).
## The destructor's own release of the field then leaves it alive, and the
## loop releases it once the parent is freed. A chain field holds its
## objects directly, through a trait value (told apart by the vtable's
## type id), as an `Array`'s elements, or as a function type's closure
## (told apart by its `__destroy`), whose captures are taken. A cycle that
## also runs through anything else (a tuple, another container's buffer)
## cannot be steered from the destructor; its last release goes through
## the runtime's `_pep_release_last`, which bounds the nesting on the stack.

import llvm;
import compiler.sema;
import [CountField, Statement, StructDef, TypeName, VariableDef] from compiler.sema;
import "address";
import "calls";
import "checks";
import "expressions";
import "functions";
import [ChainField, ChainKind, Generator, StructDesc] from "generator";
import "generator";
import "globals";
import "lazy";
import "operators";
import "ops";
import "refs";
import "simd";
import "traits";
import "types";

## Entries of a chain list held on the stack before it moves to the heap:
## enough for an `Array` tree of 8 children per node, 3 levels deep (the
## entries waiting are a node's siblings at each level).
const _CHAIN_INLINE_ENTRIES: ulong = 32;

## One edge of the struct graph: the struct a field can hold, and whether
## the field steers it (its owner and target both have counts codegen
## generates, and the field holds the target in a way `ChainKind` names).
struct _Edge {
    var target: ulong;
    var direct: bool;
    var kind: ChainKind;
    ## The field's position in its struct.
    var position: uint;
    ## The sema type of the slot holding the target.
    var ty: String;

    construct(target: ulong, direct: bool, kind: ChainKind, position: uint, ty: String) {
        this.target = target;
        this.direct = direct;
        this.kind = kind;
        this.position = position;
        this.ty = ty;
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
            # `Array`'s destructor releases `_size` elements of `_data`, so
            # its last release can take them out first.
            bool array = st.ty.name == "Array" and _field_position(structs[st.name], "_size").is_value();
            uint position = 0;
            for (var field in st.field_members) {
                bool buffer = array and field.name == "_data" and field.ty.is_pointer();
                var kind = buffer ? ChainKind.Buffer : ChainKind.Struct;
                _type_edges(field.ty, owner, kind, position, nodes, index, conformers, out);
                position += 1;
            }
            if (st.ty.is_function_type()) {
                var ret = st.ty.function_return();
                var key = _signature_key(ret.is_value() ? ret.value() : TypeName.void(), st.ty.function_params());
                var found = closures.try_get(key);
                var destroy = _field_position(structs[st.name], "__destroy");
                if (found.is_value()) {
                    for (var c in found.value()) {
                        bool direct = owner and destroy.is_value() and _chain_owner(nodes[c].name);
                        out.append(_Edge(c, direct, ChainKind.Closures, destroy.value_or(0), st.name));
                    }
                }
            }
            edges.append(out);
        }
        var component = _components(edges);
        # A component is recursive when it has an edge inside it; deep when
        # one of those is not steered.
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
            # One chain field per steered field, in declaration order.
            var fields = Array<ChainField>();
            for (var edge in edges[at]) {
                if (!edge.direct or component[edge.target] != c) {
                    continue;
                }
                if (fields.count == 0 or fields[fields.count - 1].position != edge.position) {
                    fields.append(ChainField(edge.kind, edge.position, edge.ty));
                }
                fields[fields.count - 1].targets.append(nodes[edge.target].name);
            }
            if (fields.count > 0) {
                chain_fields[name] = fields;
                if (_releases_fields_only(nodes[at])) {
                    chain_moves.insert(name);
                }
            }
        }
    }

    ## Whether struct `name`'s `__release` is one codegen generates (the
    ## standard one, or a function type's), so its last release may take
    ## its chain fields out (see `standard_release`).
    _chain_owner(name: String): bool {
        var desc = structs.try_get(name);
        return desc.is_value() and desc.value().release_counts.is_value();
    }

    ## Appends to `out` the structs a slot of type `ty`, field `position`
    ## of its struct, can hold: the struct it names, a trait's conformers,
    ## a pointer's or tuple's elements. Each is steered (`_Edge.direct`)
    ## when `owner` and the target has counts codegen generates, as `kind`;
    ## a pointer's elements only as a `Buffer`, never a tuple's. A weak
    ## reference owns nothing.
    _type_edges(
        ty: TypeName,
        owner: bool,
        kind: ChainKind,
        position: uint,
        nodes: Array<StructDef>,
        index: HashMap<String, ulong>,
        conformers: HashMap<String, Array<ulong>>,
        out: Array<_Edge>
    ) {
        if (ty.is_weak() or ty.is_extern_function_type()) {
            return;
        }
        if (ty.is_pointer() or ty.is_tuple()) {
            bool steered = owner and kind == ChainKind.Buffer and ty.is_pointer();
            for (var element in ty.sub_types) {
                bool slot = steered and !element.is_pointer() and !element.is_tuple();
                _type_edges(element, slot, ChainKind.Buffer, position, nodes, index, conformers, out);
            }
            return;
        }
        var name = ty.to_string();
        var found = conformers.try_get(name);
        if (found.is_value()) {
            var through = kind == ChainKind.Buffer ? ChainKind.Buffer : ChainKind.Trait;
            for (var c in found.value()) {
                out.append(_Edge(c, owner and _chain_owner(nodes[c].name), through, position, name));
            }
            return;
        }
        var target = index.try_get(name);
        if (target.is_value()) {
            out.append(_Edge(target.value(), owner and _chain_owner(name), kind, position, name));
        }
    }

    # Last releases of chain structs

    ## `T.__last_release(object)` for a struct with chain fields: a chain
    ## list on the stack, `T.__chain_destroy(object, list)`, then each
    ## listed object's `__chain_release` until the list is empty, and the
    ## list's heap buffer freed if it grew.
    emit_chain_last_release(ty_name: String, object: llvm.Value): Result<void> {
        var list_field = _list_field(ty_name);
        if (list_field.is_value()) {
            return emit_list_last_release(ty_name, object, list_field.value());
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

    ## The one chain field of struct `ty_name` that holds only its own type
    ## (a linked list, through a struct or trait field, or a closure whose
    ## one chain capture is `ty_name`), if that is its only chain field.
    _list_field(ty_name: String): ChainField? {
        var fields = chain_fields[ty_name];
        if (fields.count != 1 or fields[0].targets.count != 1) {
            return Optional<ChainField>.Empty;
        }
        var field = fields[0];
        if (field.kind == ChainKind.Closures) {
            var captures = chain_fields.try_get(field.targets[0]);
            if (!captures.is_value() or captures.value().count != 1) {
                return Optional<ChainField>.Empty;
            }
            var capture = captures.value()[0];
            if (capture.kind == ChainKind.Buffer or capture.targets.count != 1 or capture.targets[0] != ty_name) {
                return Optional<ChainField>.Empty;
            }
        } else if (field.kind == ChainKind.Buffer or field.targets[0] != ty_name) {
            return Optional<ChainField>.Empty;
        }
        return Optional<ChainField>.Value(field);
    }

    ## `T.__last_release(object)` for a struct whose one chain field holds
    ## its own type (`_list_field`): no list, a loop that takes the next
    ## link (`_list_link`), destroys the current one, and moves on while the
    ## taken link's count reaches 0.
    emit_list_last_release(ty_name: String, object: llvm.Value, field: ChainField): Result<void> {
        var function = builder.insert_block().parent();
        bool atomic = structs[ty_name].release_counts.value();
        var pointer = context.pointer_type();
        var i32_type = context.int32_type();
        var entry = builder.insert_block();
        var loop = context.append_block(function, "link_loop");
        var destroy = context.append_block(function, "link_destroy");
        var release = context.append_block(function, "link_release");
        var done = context.append_block(function, "link_done");
        builder.branch(loop);
        builder.position_at_end(loop);
        var current = builder.phi(pointer, "current");
        var links = Array<llvm.Value>();
        var from = Array<llvm.BasicBlock>();
        _list_link(ty_name, current, field, destroy, links, from)?;
        builder.position_at_end(destroy);
        var taken = builder.phi(pointer, "taken");
        taken.add_incoming(links, from);
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

    ## Branches to `destroy` with the link `current` (an `owner`) holds in
    ## `field`, claimed (`_chain_claim`), or with null when there is none
    ## to take; appends each to `links`, and its block to `from`.
    _list_link(
        owner: String,
        current: llvm.Value,
        field: ChainField,
        destroy: llvm.BasicBlock,
        links: Array<llvm.Value>,
        from: Array<llvm.BasicBlock>
    ): Result<void> {
        var function = builder.insert_block().parent();
        var pointer = context.pointer_type();
        var desc = structs[owner];
        var none = context.append_block(function, "link_none");
        if (field.kind == ChainKind.Closures) {
            var destroy_field = builder.load(
                pointer, builder.field_pointer(desc.llvm_type, current, field.position, "destroy_slot"), "destroy"
            );
            var closure = field.targets[0];
            var dtor = functions.try_get($"{closure}.__dtor");
            if (!dtor.is_value()) {
                builder.branch(none);
            } else {
                var matched = context.append_block(function, "closure_match");
                var same = builder.compare(llvm.IntPredicate.Equal, destroy_field, dtor.value(), "same_closure");
                builder.conditional_branch(same, matched, none);
                builder.position_at_end(matched);
                _list_link(closure, current, chain_fields[closure][0], destroy, links, from)?;
            }
        } else {
            var slot = builder.field_pointer(desc.llvm_type, current, field.position, "chain_field");
            llvm.Value link;
            if (is_trait_name(field.ty)) {
                var value = builder.load(types.get(field.ty).value(), slot, "link");
                link = object_pointer(value)?;
                var check = context.append_block(function, "link_type");
                builder.conditional_branch(builder.is_null(link, "no_link"), none, check);
                builder.position_at_end(check);
                var methods = traits[field.ty].methods.count as ulong;
                var id_type = type_id_value("").value_type();
                var id = builder.pointer_to_int(vtable_entry(value, VTABLE_METHODS + methods)?, id_type, "type_id");
                var matched = context.append_block(function, "link_check");
                var same = builder.compare(llvm.IntPredicate.Equal, id, type_id_value(field.targets[0]), "same_type");
                builder.conditional_branch(same, matched, none);
                builder.position_at_end(matched);
            } else {
                link = builder.load(pointer, slot, "link");
                var check = context.append_block(function, "link_check");
                builder.conditional_branch(builder.is_null(link, "no_link"), none, check);
                builder.position_at_end(check);
            }
            var moved = chain_moves.contains(owner) ? Optional<llvm.Value>.Value(slot) : Optional<llvm.Value>.Empty;
            _chain_claim(link, field.targets[0], moved, none)?;
            links.append(link);
            from.append(builder.insert_block());
            builder.branch(destroy);
        }
        builder.position_at_end(none);
        links.append(pointer.zero());
        from.append(none);
        builder.branch(destroy);
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
    ## once the count is 0. Pushes each object of its cycle that only one of
    ## its chain fields holds on `list`, with a reference of the list's own
    ## (`_chain_take_fields`), then runs the destructor and frees the memory
    ## (`destroy_object`).
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
        _chain_take_fields(ty_name, object, function.param(1))?;
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

    ## Takes into `list` each object of `ty_name`'s cycle that one of its
    ## chain fields holds, in `object` (a `ty_name`): moved out of the field
    ## when nothing sees it again (`chain_moves`), else only one the field
    ## alone holds, with an extra reference.
    _chain_take_fields(ty_name: String, object: llvm.Value, list: llvm.Value): Result<void> {
        var found = chain_fields.try_get(ty_name);
        if (!found.is_value()) {
            return Result<void>.ok();
        }
        var desc = structs[ty_name];
        bool move = chain_moves.contains(ty_name);
        for (var field in found.value()) {
            if (field.kind == ChainKind.Buffer) {
                _chain_take_buffer(desc, object, field, list)?;
            } else if (field.kind == ChainKind.Closures) {
                _chain_take_closures(desc, object, field, list)?;
            } else {
                var slot = builder.field_pointer(desc.llvm_type, object, field.position, "chain_field");
                _chain_take(list, slot, field.ty, field.targets, move)?;
            }
        }
        return Result<void>.ok();
    }

    ## Takes into `list` the object in `slot`, of sema type `ty` (a struct
    ## or a trait), when it is one of `targets` (`_chain_take_object`). A
    ## trait value's object is told apart by its vtable's type id.
    _chain_take(list: llvm.Value, slot: llvm.Value, ty: String, targets: String[], move: bool): Result<void> {
        var function = builder.insert_block().parent();
        var after = context.append_block(function, "chain_after");
        var moved = move ? Optional<llvm.Value>.Value(slot) : Optional<llvm.Value>.Empty;
        if (is_trait_name(ty)) {
            var value = builder.load(types.get(ty).value(), slot, "link");
            var object = object_pointer(value)?;
            var check = context.append_block(function, "chain_type");
            builder.conditional_branch(builder.is_null(object, "no_link"), after, check);
            builder.position_at_end(check);
            var methods = traits[ty].methods.count as ulong;
            var id_type = type_id_value("").value_type();
            var id = builder.pointer_to_int(vtable_entry(value, VTABLE_METHODS + methods)?, id_type, "type_id");
            for (var target in targets) {
                var matched = context.append_block(function, "chain_conformer");
                var next = context.append_block(function, "chain_type");
                var same = builder.compare(llvm.IntPredicate.Equal, id, type_id_value(target), "same_type");
                builder.conditional_branch(same, matched, next);
                builder.position_at_end(matched);
                _chain_take_object(list, object, target, moved)?;
                builder.branch(after);
                builder.position_at_end(next);
            }
        } else {
            var object = builder.load(context.pointer_type(), slot, "link");
            var check = context.append_block(function, "chain_check");
            builder.conditional_branch(builder.is_null(object, "no_link"), after, check);
            builder.position_at_end(check);
            _chain_take_object(list, object, ty, moved)?;
        }
        builder.branch(after);
        builder.position_at_end(after);
        return Result<void>.ok();
    }

    ## Takes `object`, a `target`, into `list` with its `__chain_release`
    ## when `_chain_claim` claims it. Leaves the builder after it.
    _chain_take_object(list: llvm.Value, object: llvm.Value, target: String, moved: llvm.Value?): Result<void> {
        var taken = context.append_block(builder.insert_block().parent(), "chain_taken");
        _chain_claim(object, target, moved, taken)?;
        var release = chain_release(target)?;
        if (moved.is_value() and _only_buffers(target)) {
            # Moved out of a field no destructor sees, an `Array` is
            # released at once: its elements go on the list, so this nests
            # one call deep, and nothing sees it go before its holder.
            builder.call(release.global_type(), release, [object, list], "");
        } else {
            _chain_push(list, object, release)?;
        }
        builder.branch(taken);
        builder.position_at_end(taken);
        return Result<void>.ok();
    }

    ## Whether every chain field of struct `name` is a buffer (an `Array`).
    _only_buffers(name: String): bool {
        var fields = chain_fields.try_get(name);
        if (!fields.is_value()) {
            return false;
        }
        for (var field in fields.value()) {
            if (field.kind != ChainKind.Buffer) {
                return false;
            }
        }
        return true;
    }

    ## Claims `object`, a `target`, for a chain, or branches to `skip`.
    ## With `moved`, the slot holding it: the slot's reference becomes the
    ## chain's and the slot becomes null (its object half, for a trait
    ## value), unless the object is immortal. Without, only an object whose
    ## count is 1 is claimed, with an extra reference: one another slot
    ## holds is not this chain's to destroy, and an immortal one's count is
    ## far above 1. Leaves the builder where it is claimed.
    _chain_claim(object: llvm.Value, target: String, moved: llvm.Value?, skip: llvm.BasicBlock): Result<void> {
        var desc = structs[target];
        bool atomic = desc.release_counts.value();
        var i32_type = context.int32_type();
        var take = context.append_block(builder.insert_block().parent(), "chain_take");
        if (moved.is_value() and !desc.immortal) {
            builder.branch(take);
        } else {
            var count = builder.load(i32_type, head_count_ptr(object, CountField.Strong)?, "link_count");
            if (atomic) {
                count.set_ordering(_MONOTONIC);
            }
            llvm.Value takes;
            if (moved.is_value()) {
                var limit = i32_type.const_uint(sema.STATIC_REFCOUNT as ulong);
                takes = builder.compare(llvm.IntPredicate.UnsignedLess, count, limit, "mortal");
            } else {
                takes = builder.compare(llvm.IntPredicate.Equal, count, i32_type.const_uint(1), "alone");
            }
            builder.conditional_branch(takes, take, skip);
        }
        builder.position_at_end(take);
        if (moved.is_value()) {
            builder.store(context.pointer_type().zero(), moved.value());
        } else {
            count_step(object, CountField.Strong, true, atomic, true)?;
        }
        return Result<void>.ok();
    }

    ## Takes into `list` the elements of an `Array` (`desc`) at `object`,
    ## last to first, so the list destroys the first one first, as `Array`'s
    ## destructor would. Elements of a struct with no immortal objects move
    ## to the list with the buffer's references, and `_size` drops to 0 so
    ## the destructor releases none of them; otherwise only those the
    ## buffer alone holds are taken, with an extra reference each.
    _chain_take_buffer(desc: StructDesc, object: llvm.Value, field: ChainField, list: llvm.Value): Result<void> {
        var size_position = _field_position(desc, "_size").value();
        var function = builder.insert_block().parent();
        var data_slot = builder.field_pointer(desc.llvm_type, object, field.position, "buffer_slot");
        var data = builder.load(context.pointer_type(), data_slot, "buffer");
        var size_type = desc.llvm_type.field(size_position);
        var size_slot = builder.field_pointer(desc.llvm_type, object, size_position, "size_slot");
        var size = builder.load(size_type, size_slot, "size");
        var element_type = slot_type(context, types.get(field.ty).value());
        var target = structs.try_get(field.ty);
        bool move = target.is_value() and !target.value().immortal;
        var entry = builder.insert_block();
        var loop = context.append_block(function, "buffer_loop");
        var body = context.append_block(function, "buffer_take");
        var done = context.append_block(function, "buffer_done");
        builder.branch(loop);
        builder.position_at_end(loop);
        var index = builder.phi(size_type, "index");
        builder.conditional_branch(
            builder.compare(llvm.IntPredicate.Equal, index, size_type.zero(), "empty"), done, body
        );
        builder.position_at_end(body);
        var last = builder.sub(index, size_type.const_uint(1), "last");
        var slot = builder.element_pointer(element_type, data, [last], true, "element");
        if (move) {
            var element = builder.load(context.pointer_type(), slot, "element");
            var push = context.append_block(function, "buffer_move");
            var next = context.append_block(function, "buffer_next");
            builder.conditional_branch(builder.is_null(element, "no_element"), next, push);
            builder.position_at_end(push);
            _chain_push(list, element, chain_release(field.ty)?)?;
            builder.branch(next);
            builder.position_at_end(next);
        } else {
            _chain_take(list, slot, field.ty, field.targets, false)?;
        }
        index.add_incoming([size, last], [entry, builder.insert_block()]);
        builder.branch(loop);
        builder.position_at_end(done);
        if (move) {
            builder.store(size_type.zero(), size_slot);
        }
        return Result<void>.ok();
    }

    ## Takes into `list` the captures of the closure a function type's
    ## object (`desc`, at `object`) is, when its `__destroy` is the
    ## `__dtor` of one of `field.targets`. Identical code folding may give
    ## two closures' `__dtor`s one address, but only when they release the
    ## same captures in the same places, so either's are taken correctly.
    _chain_take_closures(desc: StructDesc, object: llvm.Value, field: ChainField, list: llvm.Value): Result<void> {
        var function = builder.insert_block().parent();
        var destroy = builder.load(
            context.pointer_type(),
            builder.field_pointer(desc.llvm_type, object, field.position, "destroy_slot"),
            "destroy"
        );
        var after = context.append_block(function, "closure_after");
        for (var target in field.targets) {
            var dtor = functions.try_get($"{target}.__dtor");
            if (!dtor.is_value()) {
                continue;
            }
            var matched = context.append_block(function, "closure_match");
            var next = context.append_block(function, "closure_next");
            var same = builder.compare(llvm.IntPredicate.Equal, destroy, dtor.value(), "same_closure");
            builder.conditional_branch(same, matched, next);
            builder.position_at_end(matched);
            _chain_take_fields(target, object, list)?;
            builder.branch(after);
            builder.position_at_end(next);
        }
        builder.branch(after);
        builder.position_at_end(after);
        return Result<void>.ok();
    }
}

## Whether `st`'s destructor only releases fields, as `release_field_refs`
## writes it (`this.field.__release()`), with no `destruct` body before.
_releases_fields_only(st: StructDef): bool {
    for (var m in st.method_members) {
        if (m.name != "__dtor") {
            continue;
        }
        if (!m.body.is_value()) {
            return false;
        }
        for (var item in m.body.value().items) {
            if (!_is_field_release(item)) {
                return false;
            }
        }
        return true;
    }
    return false;
}

## Whether `item` is `this.field.__release()`.
_is_field_release(item: Statement): bool {
    if (item is Expression(e)) {
        if (e is MethodCall(call)) {
            if (call.method == "__release" and call.args.count == 0) {
                if (call.this_value is MemberRef(member)) {
                    return member.lhs is ThisRef;
                }
            }
        }
    }
    return false;
}

## The position of the field named `name` in struct `desc`, if it has one.
_field_position(desc: StructDesc, name: String): uint? {
    for (var at in 0..desc.fields.count) {
        if (desc.fields[at].0 == name) {
            return Optional<uint>.Value(at as uint);
        }
    }
    return Optional<uint>.Empty;
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
