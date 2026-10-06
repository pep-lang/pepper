## Checking a program against declarations already checked (a checked
## unit's record, the runtime's first): their bodies are kept out of the
## passes, which walk bodies, until the checks that read callee bodies
## (`check_confinement`, `share_string_literals`) run, then put back. Port
## of `crates/pepper-sema/src/checked.rs`.

import [Loc] from "loc";
import [Block, Checked, FunctionDef, Module, TypeAliasDef] from "model";
import [RecordIn, RecordOut] from "record";
import [read_module, read_type_alias, write_module, write_type_alias] from "record_codec";
import [method_key, PassState] from "state";

## Takes the bodies of `module`'s checked declarations out of it, into
## `state.stashed`.
##
## @param module the module
## @param state the passes' state
export stash_bodies(module: Module, state: PassState) {
    if (module.checked.functions.is_empty and module.checked.structs.is_empty) {
        return;
    }
    for (var f in module.functions) {
        if (!f.body.is_value() or !is_checked_function(module, f)) {
            continue;
        }
        state.stashed[$"f {f.name}"] = f.body.value();
        f.body = Optional<Block>.Empty;
    }
    for (var st in module.structs) {
        if (!module.checked.structs.contains(st.name)) {
            continue;
        }
        for (var m in st.method_members) {
            _stash(state, $"m {st.name} method {m.name}", m);
        }
        for (var c in st.constructors) {
            _stash(state, $"m {st.name} constructor {c.name}", c);
        }
        _stash(state, $"m {st.name} destructor {st.destructor.name}", st.destructor);
        _stash(state, $"m {st.name} acquire {st.acquire.name}", st.acquire);
        _stash(state, $"m {st.name} release {st.release.name}", st.release);
    }
}

_stash(state: PassState, key: String, function: FunctionDef) {
    if (!function.body.is_value()) {
        return;
    }
    state.stashed[key] = function.body.value();
    function.body = Optional<Block>.Empty;
}

## Whether `function` was checked with a unit below: its name is a checked
## function's, and it is not a concrete override still spelled as the
## generic it overrides (`compare<Point>` reads `compare` until
## `concrete_overrides` renames it).
##
## @param module the module
## @param function the function
## @returns true for a checked function
export is_checked_function(module: Module, function: FunctionDef): bool {
    if (!module.checked.functions.contains(function.name)) {
        return false;
    }
    for (var p in function.generic_params) {
        if (p.is_argument) {
            return false;
        }
    }
    return true;
}

## Puts back what `stash_bodies` took.
##
## @param module the module
## @param state the passes' state
export restore_bodies(module: Module, state: PassState) {
    if (state.stashed.count == 0) {
        return;
    }
    for (var f in module.functions) {
        if (is_checked_function(module, f)) {
            _restore(state, $"f {f.name}", f);
        }
    }
    for (var st in module.structs) {
        if (!module.checked.structs.contains(st.name)) {
            continue;
        }
        for (var m in st.method_members) {
            _restore(state, $"m {st.name} method {m.name}", m);
        }
        for (var c in st.constructors) {
            _restore(state, $"m {st.name} constructor {c.name}", c);
        }
        _restore(state, $"m {st.name} destructor {st.destructor.name}", st.destructor);
        _restore(state, $"m {st.name} acquire {st.acquire.name}", st.acquire);
        _restore(state, $"m {st.name} release {st.release.name}", st.release);
    }
    state.stashed = HashMap<String, Block>();
}

_restore(state: PassState, key: String, function: FunctionDef) {
    var body = state.stashed.try_get(key);
    if (!body.is_value()) {
        return;
    }
    function.body = body;
    state.stashed.remove(key);
}

## The body `stash_bodies` took from `function`, a free function, if any.
##
## @param state the passes' state
## @param function the function
## @returns its stashed body
export stashed_function(state: PassState, function: FunctionDef): Block? {
    return state.stashed.try_get($"f {function.name}");
}

## The body `stash_bodies` took from a member of struct `owner`.
##
## @param state the passes' state
## @param owner the struct's name
## @param kind "method", "constructor", "destructor", "acquire" or "release"
## @param name the member's name
## @returns its stashed body
export stashed_member(state: PassState, owner: String, kind: String, name: String): Block? {
    return state.stashed.try_get($"m {owner} {kind} {name}");
}

## Everything `module` declares now, its extensions included: what a
## checked unit marks checked once the passes are done with it.
##
## @param module the module
## @param summaries the link summaries of the checked functions, by key
## @returns the checked declarations
export all_checked(module: Module, summaries: HashMap<String, (Loc, String)>): Checked {
    var out = Checked();
    for (var st in module.structs) {
        out.structs.insert(st.name);
    }
    for (var f in module.functions) {
        out.functions.insert(f.name);
    }
    for (var g in module.globals) {
        out.globals.insert(g.name);
    }
    out.extensions = module.extensions.count;
    out.summaries = summaries;
    return out;
}

## A unit checked with everything before it (a record in the build cache):
## the module the passes left, its declarations marked checked, with what
## the units checked on top of it need back.
export struct CheckedUnit {
    ## The module.
    var module: Module;
    ## The link summaries recorded for the build cache's skipped bodies
    ## (`Module.recorded_summaries`), by function location.
    var summaries: HashMap<Loc, String> = HashMap<Loc, String>();
    ## Its type aliases as built: the passes expand them away, and the
    ## files checked on top of it use them.
    var aliases: TypeAliasDef[] = Array<TypeAliasDef>();

    construct(module: Module) {
        this.module = module;
    }

    ## Writes this to `out`.
    ##
    ## @param out the record
    write(out: RecordOut) {
        write_module(out, module);
        out.unsigned(summaries.count);
        for (var (loc, text) in summaries) {
            out.loc(loc);
            out.text(text);
        }
        out.unsigned(aliases.count);
        for (var alias in aliases) {
            write_type_alias(out, alias);
        }
    }

    ## Reads what `write` wrote.
    ##
    ## @param input the record
    ## @returns the checked unit; `input.error` says when the record is not one
    static read(input: RecordIn): CheckedUnit {
        var out = CheckedUnit(read_module(input));
        var count = input.count();
        for (var _ in 0..count) {
            var loc = input.loc();
            out.summaries[loc] = input.text();
        }
        count = input.count();
        for (var _ in 0..count) {
            out.aliases.append(read_type_alias(input));
        }
        return out;
    }
}

## Marks everything `module` declares checked, once the passes are done
## with it: the bodies of the extensions of structs that are not generic
## have been applied for good, so they go; the link summaries settled now
## join those of the units checked before. `module` stays usable: the next
## unit's files are built on top of it (`build_on`).
##
## @param module the checked module
## @param state the passes' state that checked it
## @param aliases the type aliases of every unit checked so far, as built
## @returns the record of the unit
export finish_checked(module: Module, state: PassState, aliases: TypeAliasDef[]): CheckedUnit {
    for (var extension in module.extensions) {
        if (extension.target.is_generic()) {
            continue;
        }
        for (var method in extension.methods) {
            method.body = Optional<Block>.Empty;
        }
    }
    var summaries = module.checked.summaries;
    for (var (key, value) in state.settled_summaries) {
        summaries[key] = value;
    }
    module.checked = all_checked(module, summaries);
    module.record_summaries = false;
    var out = CheckedUnit(module);
    for (var (loc, text) in module.recorded_summaries) {
        out.summaries[loc] = text;
    }
    for (var (loc, text) in module.summaries_to_record) {
        out.summaries[loc] = text;
    }
    out.aliases = aliases;
    return out;
}

## Readies `unit`'s module, just checked or loaded, for the next files:
## its aliases as built and its recorded summaries back in place.
##
## @param unit the checked unit
## @returns its module
export resume_checked(unit: CheckedUnit): Module {
    var module = unit.module;
    module.type_aliases = Array<TypeAliasDef>();
    for (var alias in unit.aliases) {
        module.type_aliases.append(alias.copy());
    }
    module.recorded_summaries = unit.summaries;
    module.summaries_to_record = Array<(Loc, String)>();
    return module;
}

## Puts back only the stashed bodies whose link summaries the checked units
## did not settle (`Checked.summaries`): `check_confinement` summarizes
## those again from their bodies, and takes the rest as recorded.
##
## @param module the module
## @param state the passes' state
export restore_unsettled(module: Module, state: PassState) {
    if (state.stashed.count == 0) {
        return;
    }
    var settled = module.checked.summaries;
    for (var f in module.functions) {
        if (is_checked_function(module, f) and !settled.contains(f.name)) {
            _restore(state, $"f {f.name}", f);
        }
    }
    for (var st in module.structs) {
        if (!module.checked.structs.contains(st.name)) {
            continue;
        }
        for (var m in st.method_members) {
            if (!settled.contains(method_key(st.name, m.name))) {
                _restore(state, $"m {st.name} method {m.name}", m);
            }
        }
        for (var c in st.constructors) {
            if (!settled.contains(method_key(c.name, "__ctor"))) {
                _restore(state, $"m {st.name} constructor {c.name}", c);
            }
        }
    }
}
