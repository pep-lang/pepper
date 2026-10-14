## Checking a program against declarations already checked (a checked
## unit's record, the runtime's first): their bodies are kept out of the
## passes, which walk bodies, until the checks that read callee bodies
## (`check_confinement`, `share_string_literals`) run, then put back.

import digest;
import io;
import os;
import [Loc] from "loc";
import [Block, Checked, FunctionDef, Module, StructDef, TraitType, TypeAliasDef] from "model";
import [CheckedDecls, UnitDecls, PendingBody] from "pending";
import [
    compare_bytes, DeltaBase, interface_text, RecordIn, RecordOut, summary_without_place, write_interface_summaries
] from "record";
import [
    decode_body, read_module, read_module_delta, read_type_alias, write_module, write_module_delta, write_type_alias
] from "record_codec";
import [method_key, PassState] from "state";
import "type_name";

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
        _stash(state, "", "", f);
    }
    for (var st in module.structs) {
        if (!module.checked.structs.contains(st.name)) {
            continue;
        }
        for (var m in st.method_members) {
            _stash(state, st.name, "method", m);
        }
        for (var c in st.constructors) {
            _stash(state, st.name, "constructor", c);
        }
        _stash(state, st.name, "destructor", st.destructor);
        _stash(state, st.name, "acquire", st.acquire);
        _stash(state, st.name, "release", st.release);
    }
    state.trait_memo.stashed = true;
}

# Stashes `function`'s body under `f {name}` for a free function, else
# `m {owner} {kind} {name}`.
_stash(state: PassState, owner: String, kind: String, function: FunctionDef) {
    if (!function.body.is_value()) {
        return;
    }
    var key = kind.is_empty ? $"f {function.name}" : $"m {owner} {kind} {function.name}";
    state.stashed_from.append((key, function));
    # A body the record's reader skipped stays undecoded.
    if (function.pending_body.is_value()) {
        state.stashed_pending[key] = function.pending_body.value();
        function.pending_body = Optional<PendingBody>.Empty;
    } else {
        state.stashed[key] = function.body.value();
    }
    function.body = Optional<Block>.Empty;
}

## Takes the body `stash_bodies` stashed under `key` out of the stash,
## decoding one a record's reader skipped.
##
## @param state the passes' state
## @param key the stash key
## @returns the body, if one is stashed
export take_stashed(state: PassState, key: String): Block? {
    var body = stashed_body(state, key);
    state.stashed.remove(key);
    return body;
}

## The body `stash_bodies` stashed under `key`, decoded if a record's
## reader skipped it (and kept decoded).
##
## @param state the passes' state
## @param key the stash key
## @returns the body, if one is stashed
export stashed_body(state: PassState, key: String): Block? {
    var found = state.stashed.try_get(key);
    if (found.is_value()) {
        return found;
    }
    var pending = state.stashed_pending.try_get(key);
    if (!pending.is_value()) {
        return Optional<Block>.Empty;
    }
    var body = decode_body(pending.value());
    state.stashed_pending.remove(key);
    state.stashed[key] = body;
    return Optional<Block>.Value(body);
}

## Whether anything is stashed.
##
## @param state the passes' state
## @returns true when a body is
export has_stashed(state: PassState): bool {
    return state.stashed.count > 0 or state.stashed_pending.count > 0;
}

## Whether `function`, a free function, has a body: its own, one a
## library's interface stripped, or one `stash_bodies` holds while the
## passes run (a checked compilation unit's function referenced as a value).
##
## @param module the module
## @param state the passes' state
## @param function the function
## @returns true when it has a body
export has_body(module: Module, state: PassState, function: FunctionDef): bool {
    if (function.body.is_value() or module.stripped.contains(function.loc)) {
        return true;
    }
    var key = $"f {function.name}";
    return state.stashed.contains(key) or state.stashed_pending.contains(key);
}

## Takes `function`'s body away, one a record's reader skipped too.
##
## @param function the function
export drop_body(function: FunctionDef) {
    function.body = Optional<Block>.Empty;
    function.pending_body = Optional<PendingBody>.Empty;
}

## A copy of `function` without its body: a signature, which copying the
## body only to drop it made most of the cost of.
##
## @param function the function, as it was once this returns
## @returns the copy
export copy_without_body(function: FunctionDef): FunctionDef {
    var body = function.body;
    var pending = function.pending_body;
    drop_body(function);
    var out = function.copy();
    function.body = body;
    function.pending_body = pending;
    return out;
}

## Gives `function` its whole body, decoding one a record's reader skipped
## (`PendingBody`): what codegen and the passes that walk checked bodies
## after `restore_bodies` need.
##
## @param function the function
export full_body(function: FunctionDef) {
    if (function.pending_body.is_value()) {
        function.body = Optional<Block>.Value(decode_body(function.pending_body.value()));
        function.pending_body = Optional<PendingBody>.Empty;
    }
}

## The declarations the compilation unit at hand adds (`UnitDecls`): every one
## without checked declarations, as when no unit below was checked. Kept
## on `module` while its lists stay as they are: a pass that replaces a
## declaration makes a new list.
##
## @param module the module
## @returns the compilation unit's structs and functions, in the module's order
export unit_decls(module: Module): UnitDecls {
    var extended = module.extended_checked.count as ulong;
    if (module.own_decls.is_value() and module.own_decls.value().fits(module.structs, module.functions, extended)) {
        return module.own_decls.value();
    }
    var out = UnitDecls(
        module.structs, module.functions, (module.structs.count as ulong, module.functions.count as ulong, extended)
    );
    for (var st in module.structs) {
        if (!module.checked.structs.contains(st.name) or module.extended_checked.contains(st.name)) {
            out.structs.append(st);
        }
    }
    for (var f in module.functions) {
        if (!is_checked_function(module, f)) {
            out.functions.append(f);
        }
    }
    module.own_decls = Optional<UnitDecls>.Value(out);
    return out;
}

## The checked declarations of `module` by name (`CheckedDecls`), built on
## first use and kept in `state` for the compilation unit.
##
## @param module the module
## @param state the passes' state
## @returns the declarations
export checked_decls(module: Module, state: PassState): CheckedDecls {
    if (state.checked_decls.is_value()) {
        return state.checked_decls.value();
    }
    var out = CheckedDecls();
    for (var f in module.functions) {
        if (!is_checked_function(module, f)) {
            continue;
        }
        if (f.is_generic_func) {
            out.generic_functions[f.name] = f;
        } else {
            out.functions[f.name] = f;
        }
    }
    for (var st in module.structs) {
        if (!module.checked.structs.contains(st.name)) {
            continue;
        }
        out.structs[st.ty.to_string()] = st;
        if (st.generic_params.count == 0) {
            for (var c in st.constructors) {
                out.constructors[c.name] = c;
            }
        }
    }
    for (var g in module.globals) {
        if (module.checked.globals.contains(g.name)) {
            out.globals[g.name] = g.ty;
        }
    }
    state.checked_decls = Optional<CheckedDecls>.Value(out);
    return out;
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
    state.trait_memo.stashed = false;
    if (!has_stashed(state)) {
        state.stashed_from.clear();
        return;
    }
    for (var (key, function) in state.stashed_from) {
        _restore(state, key, function);
    }
    state.stashed_from.clear();
    state.stashed = HashMap<String, Block>();
    state.stashed_pending = HashMap<String, PendingBody>();
}

# Puts back the body stashed under `key`: one never decoded goes back
# undecoded, behind an empty block.
_restore(state: PassState, key: String, function: FunctionDef) {
    var body = state.stashed.try_get(key);
    if (body.is_value()) {
        function.body = body;
        state.stashed.remove(key);
        state.restored.insert(key);
        return;
    }
    var pending = state.stashed_pending.try_get(key);
    if (pending.is_value()) {
        function.body = Optional<Block>.Value(Block());
        function.pending_body = pending;
        state.stashed_pending.remove(key);
        state.restored.insert(key);
    }
}

## The body `stash_bodies` took from `function`, a free function, if any.
##
## @param state the passes' state
## @param function the function
## @returns its stashed body
export stashed_function(state: PassState, function: FunctionDef): Block? {
    return stashed_body(state, $"f {function.name}");
}

## The body `stash_bodies` took from a member of struct `owner`.
##
## @param state the passes' state
## @param owner the struct's name
## @param kind "method", "constructor", "destructor", "acquire" or "release"
## @param name the member's name
## @returns its stashed body
export stashed_member(state: PassState, owner: String, kind: String, name: String): Block? {
    return stashed_body(state, $"m {owner} {kind} {name}");
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

# A settled summary without the position of what it blames, which moves
# with every edit above it: its first line ends in `;` and the blame, or
# `;-` when nothing is blamed. The trait calls it reaches (more lines) and
# the facts after `|` stay.
_without_blame(text: String): String {
    var line_end = text.find("\n");
    var bar = text.find("|");
    var end = line_end >= 0 ? line_end : (bar >= 0 ? bar : text.size as long);
    if (bar >= 0 and bar < end) {
        end = bar;
    }
    var head = text.substr_bytes(0, end as ulong);
    var tail = text.substr_bytes(end as ulong, text.size - end as ulong);
    var semi = head.rfind(";");
    if (semi < 0) {
        return text;
    }
    var blamed = head.substr_bytes(semi as ulong + 1, head.size - semi as ulong - 1);
    var rest = head.substr_bytes(0, semi as ulong);
    return blamed == "-" ? $"{rest};-{tail}" : $"{rest};blamed{tail}";
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

    ## Writes this to `out`: in full, or with `base`, as a delta on the
    ## module it indexes, so the list elements it holds as they are become
    ## references.
    ##
    ## @param out the record
    ## @param base the index of the module this unit was checked on
    write(out: RecordOut, base: DeltaBase? = Optional<DeltaBase>.Empty) {
        if (base.is_value()) {
            out.unsigned(1);
            # How many use contexts the base had: a merge moves the new
            # type uses' contexts by what it has instead.
            out.unsigned(base.value().size("use_contexts"));
            base.value().name_declarations(module);
            write_module_delta(out, module, base.value());
        } else {
            out.unsigned(0);
            write_module(out, module);
        }
        if (out.blank_locs) {
            write_interface_summaries(out, summaries);
        } else {
            # By location, so the bytes do not depend on the map's order.
            var locs = Array<Loc>();
            for (var (loc, _) in summaries) {
                locs.append(loc);
            }
            locs.sort((a, b) => {
                if (a.file != b.file) {
                    return a.file < b.file ? -1 : 1;
                }
                if (a.span.start != b.span.start) {
                    return a.span.start < b.span.start ? -1 : 1;
                }
                return a.span.end < b.span.end ? -1 : (a.span.end > b.span.end ? 1 : 0);
            });
            # A delta holds those the base does not: its own.
            var own = Array<Loc>();
            for (var loc in locs) {
                if (base.is_value()) {
                    var key = base.value().scratch();
                    key.loc(loc);
                    var value = base.value().scratch();
                    value.text(summaries[loc]);
                    if (base.value().entry("recorded_summaries", key, value) == 1) {
                        continue;
                    }
                }
                own.append(loc);
            }
            out.unsigned(own.count);
            for (var loc in own) {
                out.loc(loc);
                out.text(summaries[loc]);
                if (base.is_value()) {
                    base.value().own_at("recorded summary", loc, summary_without_place(summaries[loc]));
                }
            }
        }
        # A delta refers to the base's aliases, as other list elements.
        out.unsigned(aliases.count);
        for (var alias in aliases) {
            if (base.is_value()) {
                var scratch = base.value().scratch();
                write_type_alias(scratch, alias);
                var at = base.value().find("type_aliases", scratch);
                if (at >= 0) {
                    out.unsigned((at as ulong) * 2 + 1);
                    continue;
                }
                out.unsigned(0);
                var shown = RecordOut();
                shown.blank_locs = true;
                write_type_alias(shown, alias);
                base.value().own("aliases", interface_text(shown));
            }
            write_type_alias(out, alias);
        }
    }

    ## Reads what `write` wrote. A delta needs `base`: the module it was
    ## written on, as read back and resumed (`resume_checked`); its
    ## elements are shared, not copied.
    ##
    ## @param input the record
    ## @param base the module a delta was written on
    ## @returns the checked unit; `input.error` says when the record is not one
    static read(input: RecordIn, base: Module? = Optional<Module>.Empty): CheckedUnit {
        var kind = input.unsigned();
        var module = Module();
        if (kind == 0) {
            if (input.merging) {
                input.error = "a whole record does not merge";
            }
            module = read_module(input);
        } else if (kind == 1 and base.is_value()) {
            var contexts = input.unsigned();
            var uses = base.value().type_uses.count;
            var had = base.value().use_contexts.count;
            module = read_module_delta(input, base.value());
            if (input.merging) {
                for (var i in uses..module.type_uses.count) {
                    module.type_uses[i].context = module.type_uses[i].context - contexts + had;
                }
            }
        } else {
            input.fail("CheckedUnit", kind);
        }
        var out = CheckedUnit(module);
        bool delta = kind == 1 and base.is_value();
        if (delta) {
            # The base's summaries as it is now, then this unit's own.
            for (var (loc, text) in base.value().recorded_summaries) {
                out.summaries[loc] = text;
            }
        }
        var count = input.count();
        for (var _ in 0..count) {
            var loc = input.loc();
            out.summaries[loc] = input.text();
        }
        count = input.count();
        if (delta and input.merging) {
            # The base's aliases, then this unit's own.
            for (var alias in base.value().type_aliases) {
                out.aliases.append(alias);
            }
        }
        for (var _ in 0..count) {
            if (delta) {
                var tag = input.unsigned();
                if (tag & 1 == 1) {
                    if (!input.merging) {
                        out.aliases.append(base.value().type_aliases[tag >> 1]);
                    }
                    continue;
                }
            }
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
            drop_body(method);
        }
    }
    var summaries = module.checked.summaries;
    for (var (key, (blame, text)) in state.settled_summaries) {
        # Only the file of a checked summary is read again (to decode it):
        # without its bytes, an edit that only moves the function keeps
        # the summary, and the records after it, the same.
        var file = Loc();
        file.file = blame.file;
        summaries[key] = (file, text);
    }
    # So the next compilation units walk no checked value struct's bodies for
    # these.
    for (var (key, loc, text) in state.value_facts) {
        summaries[key] = (loc, text);
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

## Returns the hash of `unit`'s interface: the unit written with no
## locations and no bodies of functions that are not generic. The units
## checked on top of it depend on that alone: a change that keeps it, an
## edit inside a function body that changes no inferred type and no link
## summary, needs them checked again no more.
##
## @param unit the checked unit, as checked or as loaded
## @returns the hash, as hex
export interface_hash(unit: CheckedUnit): String {
    var trace = os.environment("PEPC_TRACE_INTERFACE");
    if (trace.is_value() and !trace.value().is_empty) {
        for (var (what, hash) in interface_fields(unit.module)) {
            io.File.stderr().write_all($"interface: {what} {hash.substr(0, 16)}\n");
        }
    }
    var out = RecordOut();
    out.blank_bodies = true;
    out.blank_locs = true;
    unit.write(out);
    var hasher = digest.Blake3();
    hasher.update(out.finish());
    var hash = hasher.finish_hex();
    if (trace.is_value() and !trace.value().is_empty) {
        io.File.stderr().write_all($"interface: the unit {hash.substr(0, 16)}\n");
    }
    return hash;
}

## Settles `module`, the records of compilation units merged
## (`RecordIn.merging`): what each compilation unit's passes kept in order
## across the whole module, merging puts in order again. Externs are in file
## order; trait types sorted by name, once each; a struct, function or method
## two compilation units both specialized is kept once, the first; and every
## extension merged has been applied. Globals are left to the driver, which
## knows their files' order.
##
## @param module the merged module
## @returns how many repeated specializations it dropped
export settle_merged(module: Module): ulong {
    module.externs.sort((a, b) => a.loc.file < b.loc.file ? -1 : (a.loc.file > b.loc.file ? 1 : 0));
    var types = HashMap<String, TraitType>();
    for (var t in module.trait_types) {
        var name = t.ty.to_string();
        if (!types.contains(name)) {
            types[name] = t;
        }
    }
    var sorted = Array<(String, TraitType)>();
    for (var (name, t) in types) {
        sorted.append((name, t));
    }
    sorted.sort((a, b) => {
        var (x, _) = a;
        var (y, _) = b;
        return compare_bytes(x.bytes(), y.bytes());
    });
    module.trait_types = Array<TraitType>();
    for (var (_, t) in sorted) {
        module.trait_types.append(t);
    }
    ulong dropped = 0;
    var seen = HashSet<String>();
    var structs = Array<StructDef>();
    for (var st in module.structs) {
        if (st.name.contains("<") and !seen.insert(st.name)) {
            dropped += 1;
            continue;
        }
        dropped += _settle_methods(st);
        structs.append(st);
    }
    module.structs = structs;
    seen = HashSet<String>();
    var functions = Array<FunctionDef>();
    for (var f in module.functions) {
        if (f.name.contains("<") and !f.is_generic_func and !seen.insert(f.name)) {
            dropped += 1;
            continue;
        }
        functions.append(f);
    }
    module.functions = functions;
    module.checked.extensions = module.extensions.count;
    return dropped;
}

# Keeps once each method of `st` that two compilation units both added, the
# first: a specialization of a generic method (`_address<Array<Path>>` of the
# runtime's `Copies`, from two files that copy an `Array<Path>`) or a method the
# passes synthesize for a use (`__copy`). Two methods of one name and the same
# parameter types are one method; overloads differ in their parameters. Returns
# how many it dropped.
_settle_methods(st: StructDef): ulong {
    ulong dropped = 0;
    var seen = HashSet<String>();
    var methods = Array<FunctionDef>();
    for (var m in st.method_members) {
        var parameters = Array<String>();
        for (var p in m.parameters) {
            parameters.append(p.ty.to_string());
        }
        if (!seen.insert($"{m.name}({", ".join(parameters)})")) {
            dropped += 1;
            continue;
        }
        methods.append(m);
    }
    if (dropped > 0) {
        st.method_members = methods;
    }
    return dropped;
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

## What other units can observe of each non-generic function and method sema
## checked: its return type, as sema resolved it, and its settled link summary,
## by the function's location. The build cache's interface hash puts this in
## place of the body (`driver/interface.pep`), so a body edit that changes
## neither leaves the file's interface alone. A function with no summary has no
## entry; its body stays part of the interface. Nor has one whose summary calls
## through a trait (a dependent summary): it keeps the joins of the
## implementations its compilation unit saw, a compilation unit whose
## implementations change one makes it again from the body, and which
## compilation units a build checked decides which one is at hand, so the
## interface would depend on the cache.
##
## @param module the checked module
## @param state the passes' state that checked its last compilation unit
## @returns each function's facts, by location
export function_facts(module: Module, state: PassState): HashMap<Loc, String> {
    var settled = HashMap<String, String>();
    for (var (key, (_, text)) in module.checked.summaries) {
        settled[key] = text;
    }
    for (var (key, (_, text)) in state.settled_summaries) {
        settled[key] = text;
    }
    var out = HashMap<Loc, String>();
    var add = (key: String, function: FunctionDef) => {
        if (function.is_generic_func or function.generic_params.count > 0 or function.loc.is_none()) {
            return;
        }
        var text = settled.try_get(key);
        if (!text.is_value()) {
            text = module.recorded_summaries.try_get(function.loc);
        }
        if (text.is_value() and !text.value().contains("\n")) {
            out[function.loc] = $"returns {function.ty}\nsummary {_without_blame(text.value())}";
        }
    };
    for (var f in module.functions) {
        add(f.name, f);
    }
    for (var st in module.structs) {
        for (var m in st.method_members) {
            add(method_key(st.name, m.name), m);
        }
    }
    return out;
}
