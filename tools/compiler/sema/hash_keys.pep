## Struct keys whose `==` and `hash<T>` disagree.
## `HashMap` and `HashSet` find a key
## by `hash<K>` and then `==`, so keys that are `==` must hash equally. A
## struct used as a key (any specialization of the runtime's
## `_HashTable<K, V>`, which both containers hold) that declares an `==`
## operator for itself but no `hash<K>` override keeps the identity (or,
## for a value struct, field-by-field) hash, which equal keys rarely
## share. A reference struct with a `hash<K>` override but no `==` still
## compares keys by identity. Both are errors, at the declaration to
## complete. A program's check skips the runtime's structs, which it
## cannot change; the suite checks those (`check_runtime_hash_keys`).

import compiler.ast;
import [Diagnostic, Location] from compiler.diagnostic;
import [VALUE_ATTRIBUTE] from "builder";
import [known_location] from "common";
import "confinement";
import "copies";
import [EQUATABLE_ATTRIBUTE, HASH_METHOD] from "equatable";
import [FunctionDef, Module, StructDef] from "model";
import [set_name] from "names";
import [PassState] from "state";

## The runtime struct both hash containers keep their entries in.
const _TABLE = "_HashTable";

## Reports a struct key whose `==` and hash disagree, and an override of
## an `[Equatable]` struct's derived hash.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_hash_keys(module: Module, state: PassState) {
    var keys = HashSet<String>();
    # The first struct of each name, and the first function of each name
    # that declares no type parameters: what the lookups below find.
    var structs = HashMap<String, StructDef>();
    for (var st in module.structs) {
        if (st.ty.name == _TABLE and st.ty.sub_types.count > 0) {
            keys.insert(st.ty.sub_types[0].to_string());
        }
        if (!structs.contains(st.name)) {
            structs[st.name] = st;
        }
    }
    var overrides = _overrides(module);
    # An `[Equatable]` struct's hash is derived with its `==`; an override
    # would replace one half.
    for (var st in module.structs) {
        if (!_is_derived(st)) {
            continue;
        }
        var hash_name = $"hash<{st.name}>";
        var hash = overrides.try_get(hash_name);
        if (hash.is_value()) {
            state.report(
                _error_at_known(
                    $"'{st.name}' is '[{EQUATABLE_ATTRIBUTE}]', so its hash is derived and '{hash_name}' cannot be overridden",
                    hash.value().loc
                ).with_note(
                    $"remove this override, or remove '[{EQUATABLE_ATTRIBUTE}]' to declare both '==' and 'hash' by hand",
                    Optional<Location>.Empty
                ).with_note($"'{st.name}' declared here", known_location(st.loc))
            );
        }
    }
    var sorted = Array<String>();
    for (var key in keys) {
        sorted.append(key);
    }
    sorted.sort((a: String, b: String) => a < b ? -1 : (a > b ? 1 : 0));
    var runtime = Optional<bool[]>.Empty;
    for (var key in sorted) {
        var found = structs.try_get(key);
        if (!found.is_value()) {
            continue;
        }
        var st = found.value();
        if (!runtime.is_value()) {
            runtime = Optional<bool[]>.Value(_runtime_files(state));
        }
        var files = runtime.value();
        if ((st.loc.file as ulong) >= files.count or files[st.loc.file as ulong]) {
            continue;
        }
        if (!_is_derived(st)) {
            _check_key(st, key, overrides, state);
        }
    }
}

## Reports each struct declared in the runtime whose `==` and hash
## disagree, as `check_hash_keys` reports a program's keys, whether or not
## the program uses it as a key. A generic struct is checked in each
## specialization `module` has. The suite runs it over the runtime's own
## structs, which `check_hash_keys` skips.
##
## @param module the model, after the passes
## @param state the passes' state, which takes the errors
export check_runtime_hash_keys(module: Module, state: PassState) {
    var overrides = _overrides(module);
    var files = _runtime_files(state);
    for (var st in module.structs) {
        var file = st.loc.file as ulong;
        if (file < files.count and files[file] and !_is_derived(st)) {
            _check_key(st, st.name, overrides, state);
        }
    }
}

## The first function of each name that declares no type parameters: what
## a lookup of a `hash<K>` override finds.
_overrides(module: Module): HashMap<String, FunctionDef> {
    var overrides = HashMap<String, FunctionDef>();
    for (var f in module.functions) {
        if (f.generic_params.count == 0 and !overrides.contains(f.name)) {
            overrides[f.name] = f;
        }
    }
    return overrides;
}

## Reports struct `st`, a key named `key`, that declares `==` but no
## `hash<K>` override, or, as a reference struct, the override but no `==`.
_check_key(st: StructDef, key: String, overrides: HashMap<String, FunctionDef>, state: PassState) {
    FunctionDef? equality = Optional<FunctionDef>.Empty;
    for (var m in st.method_members) {
        if (set_name(m.name) == "==" and m.parameters.count == 1 and m.parameters[0].ty.to_string() == key) {
            equality = Optional<FunctionDef>.Value(m);
            break;
        }
    }
    var hash_name = $"hash<{key}>";
    # An override declares no type parameters; the generic `hash<T>`'s
    # own specialization for `key` has the same name but keeps them.
    var hash = overrides.try_get(hash_name);
    if (equality.is_value() and !hash.is_value()) {
        state.report(
            _error_at_known(
                $"'{key}' declares '==' but no '{hash_name}', so as a HashMap or HashSet key, equal values will not find each other",
                equality.value().loc
            ).with_note(
                $"declare '{hash_name}(value: {key}): u64' hashing the fields '==' compares, or remove '==' and mark '{key}' '[{EQUATABLE_ATTRIBUTE}]' to derive both",
                Optional<Location>.Empty
            )
        );
    } else if (!equality.is_value() and hash.is_value() and !ast.has_attribute(st.attributes, VALUE_ATTRIBUTE)) {
        state.report(
            _error_at_known(
                $"'{hash_name}' is overridden but '{key}' declares no '==', so HashMap and HashSet keys still compare by identity",
                hash.value().loc
            ).with_note(
                $"declare '==(other: {key}): bool' comparing the fields the hash uses, or remove the override and mark '{key}' '[{EQUATABLE_ATTRIBUTE}]' to derive both",
                known_location(st.loc)
            )
        );
    }
}

## Whether `st` is `[Equatable]`: its `==` and hash are derived together.
_is_derived(st: StructDef): bool {
    for (var m in st.method_members) {
        if (m.name == HASH_METHOD) {
            return true;
        }
    }
    return false;
}
