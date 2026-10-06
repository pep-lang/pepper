## Methods of struct specializations, specialized only when used. Each
## `Box<int>` gets every method of `Box<T>` declared, but a method's body
## waits until a call, a method value or another use names it: most
## methods of a runtime type like `Array<T>` go unused by any one
## specialization, and every pass after specializing would walk them.
## What is still unused when specializing ends is dropped.

import [Block, Expression, FunctionDef, Module, StructDef, TypeName] from "model";
import [set_name] from "names";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## The methods the passes and code generation call without a use in the
## source naming them: iteration, copies, hashing, interpolation and the
## accessors, and the helpers literals and `?` lower to.
_called_implicitly(name: String): bool {
    if (name.starts_with("_literal_")) {
        return true;
    }
    match (name) {
        "iterate", "next", "current", "copy", "to_string", "hash", "get", "set", "call", "matches", "count", "is_empty", "_from_residual" => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## Whether `method` of a specialization keeps its body from the start:
## when its return type is inferred from it, when the passes or code
## generation may call it with no use naming it, or when a trait may
## dispatch to it.
_needed_at_once(method: FunctionDef, trait_methods: HashSet<String>): bool {
    var name = set_name(method.name);
    if (method.ty.is_auto() or method.trait_default.is_value()) {
        return true;
    }
    if (name.starts_with("__") or name.size == 0) {
        return true;
    }
    # An operator (`==`, `[]`, `<`).
    var first = name.byte_at(0);
    if (!((first >= 'a' and first <= 'z') or (first >= 'A' and first <= 'Z') or first == '_' or first >= 128)) {
        return true;
    }
    return _called_implicitly(name) or trait_methods.contains(name);
}

## The names of every trait's methods.
_trait_methods(module: Module): HashSet<String> {
    var names = HashSet<String>();
    for (var t in module.traits) {
        for (var m in t.methods) {
            names.insert(set_name(m.name));
        }
    }
    return names;
}

## Takes the bodies of the methods of `specialized` no use has named yet,
## keeping them in `state.deferred` until one does.
##
## @param module the model
## @param specialized a struct specialization, just made
## @param state the passes' state
export defer_methods(module: Module, specialized: StructDef, state: PassState) {
    if (!state.lazy_methods) {
        return;
    }
    if (!state.trait_method_names.is_value()) {
        state.trait_method_names = Optional<HashSet<String>>.Value(_trait_methods(module));
    }
    var trait_methods = state.trait_method_names.value();
    var deferred = HashMap<String, Block>();
    for (var m in specialized.method_members) {
        if (m.body.is_value() and !_needed_at_once(m, trait_methods)) {
            deferred[m.name] = m.body.value();
            m.body = Optional<Block>.Empty;
        }
    }
    if (deferred.count > 0) {
        state.deferred[specialized.name] = deferred;
    }
}

## Gives back the bodies of the deferred methods that the code walked so
## far names, as `_MethodUses` finds them.
##
## @param module the model
## @param state the passes' state
## @returns whether any body came back
export specialize_used_methods(module: Module, state: PassState, by_name: bool = false): bool {
    if (state.deferred.count == 0) {
        return false;
    }
    var uses = _MethodUses(module, state);
    uses.by_name = by_name;
    for (var st in module.structs) {
        if (st.generic_params.count != 0) {
            continue;
        }
        uses.current = Optional<TypeName>.Value(st.ty);
        uses.owner = st.name;
        var methods = Array<FunctionDef>();
        methods.append_all(st.method_members);
        methods.append_all(st.constructors);
        methods.append(st.destructor);
        for (var m in methods) {
            if (m.body.is_value()) {
                rewrite_block(m.body.value(), uses);
            }
            for (var p in m.parameters) {
                if (p.default.is_value()) {
                    rewrite_expression(p.default.value(), uses);
                }
            }
        }
    }
    uses.current = Optional<TypeName>.Empty;
    uses.owner = "";
    for (var f in module.functions) {
        if (!f.is_generic_func and f.body.is_value()) {
            rewrite_block(f.body.value(), uses);
        }
    }
    for (var g in module.globals) {
        if (g.default.is_value()) {
            rewrite_expression(g.default.value(), uses);
        }
    }
    # A use on a type spelled as written rather than as the struct is
    # named (`Result<Uri>` for `Result<Uri@uri>`) counts by name alone.
    var names = HashSet<String>();
    for (var st in module.structs) {
        for (var spelled in _spellings(st)) {
            names.insert(spelled);
        }
    }
    for (var key in uses.on) {
        var at = key.find("\n");
        if (!names.contains(key.substr_bytes(0, at as ulong))) {
            uses.anywhere.insert(key.substr_bytes(at as ulong + 1, key.size - at as ulong - 1));
        }
    }
    bool any = false;
    for (var st in module.structs) {
        var waiting = state.deferred.try_get(st.name);
        if (!waiting.is_value()) {
            continue;
        }
        var bodies = waiting.value();
        var spellings = _spellings(st);
        for (var m in st.method_members) {
            if (m.body.is_value()) {
                continue;
            }
            var body = bodies.try_get(m.name);
            if (!body.is_value()) {
                continue;
            }
            var name = set_name(m.name);
            bool by_type = false;
            for (var spelled in spellings) {
                by_type = by_type or uses.on.contains($"{spelled}\n{name}");
            }
            bool used = by_type or uses.anywhere.contains(name);
            if (used) {
                m.body = Optional<Block>.Value(body.value());
                bodies.remove(m.name);
                any = true;
            }
        }
        if (bodies.count == 0) {
            state.deferred.remove(st.name);
        }
    }
    return any;
}

## Drops the methods no use named by the end of specializing, with their
## places in the overload sets.
##
## @param module the model
## @param state the passes' state
export drop_unused_methods(module: Module, state: PassState) {
    if (state.deferred.count == 0) {
        return;
    }
    for (var st in module.structs) {
        var waiting = state.deferred.try_get(st.name);
        if (!waiting.is_value()) {
            continue;
        }
        var bodies = waiting.value();
        var kept = Array<FunctionDef>();
        for (var m in st.method_members) {
            if (m.body.is_value() or !bodies.contains(m.name)) {
                kept.append(m);
            }
        }
        st.method_members = kept;
        var sets = module.method_overload_sets.try_get(st.name);
        if (sets.is_value()) {
            var emptied = Array<String>();
            for (var (set, members) in sets.value()) {
                var left = Array<String>();
                for (var member in members) {
                    if (!bodies.contains(member)) {
                        left.append(member);
                    }
                }
                members.clear();
                members.append_all(left);
                if (members.count == 0) {
                    emptied.append(set);
                }
            }
            for (var set in emptied) {
                sets.value().remove(set);
            }
        }
    }
    state.deferred.clear();
}

## Finds the methods the code names: by the type of the value they are
## called on, or by name alone when that type is not known yet.
struct _MethodUses {
    var module: Module;
    var state: PassState;
    var current: TypeName? = Optional<TypeName>.Empty;
    ## The struct whose methods are walked, for calls with no receiver.
    var owner: String = "";
    var table: StructTable? = Optional<StructTable>.Empty;
    ## `"{struct}\n{method}"` of each use on a known type.
    var on: HashSet<String> = HashSet<String>();
    ## The methods used on values of a type not known yet.
    var anywhere: HashSet<String> = HashSet<String>();
    ## Whether every use counts by name alone, whatever its type.
    var by_name: bool = false;

    construct(module: Module, state: PassState) {
        this.module = module;
        this.state = state;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            MethodCall(node) => {
                _found(node.this_value, node.method);
            }
            MemberRef(node) => {
                _found(node.lhs, node.name);
            }
            FunctionCall(node) => {
                _named(node.function);
            }
            SymbolRef(node) => {
                _named(node.id);
            }
            else => {}
        }
        return e;
    }

    # A call or value with no receiver: a sibling method (`count()` in a
    # method), or a static one spelled with its type (`Box<int>.make`).
    _named(name: String) {
        var dot = name.rfind(".");
        if (dot > 0) {
            # The type may be spelled as written, not as resolved.
            anywhere.insert(set_name(name.substr_bytes(dot as ulong + 1, name.size - dot as ulong - 1)));
            return;
        }
        if (owner.size > 0) {
            on.insert($"{owner}\n{set_name(name)}");
        }
    }

    _found(receiver: Expression, method: String) {
        var name = set_name(method);
        if (state.deferred.count == 0) {
            return;
        }
        if (by_name) {
            anywhere.insert(name);
            return;
        }
        # A static call through a type (`Result<Uri>.ok`): the type may be
        # spelled as written, not as its struct is named.
        if (receiver is FunctionCall(call)) {
            if (call.args.count == 0) {
                anywhere.insert(name);
                return;
            }
        }
        if (!table.is_value()) {
            table = Optional<StructTable>.Value(StructTable(module, memo = state.trait_types_memo()));
        }
        var ty = static_type_of(receiver, table.value(), current, state);
        if (!ty.is_value() or ty.value().contains_auto()) {
            anywhere.insert(name);
            return;
        }
        var key = ty.value().to_string();
        while (key.ends_with("*")) {
            key = key.substr_bytes(0, key.size - 1);
        }
        on.insert($"{key}\n{name}");
    }
}

extend _MethodUses with Rewriter;

## How code may spell `st`'s type: as named, and without its trailing type
## arguments, which have defaults (`Result<Uri>` for `Result<Uri, Error>`).
_spellings(st: StructDef): String[] {
    var out = Array<String>();
    out.append(st.name);
    var ty = st.ty.copy();
    while (ty.sub_types.count > 1) {
        ty.sub_types.pop();
        out.append(ty.to_string());
    }
    return out;
}
