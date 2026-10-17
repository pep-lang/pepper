## What the passes keep between steps besides the model: the first error
## a pass reported, the closure numbering, and the facts some passes
## install for the later ones.

import [Diagnostic, SourceText] from compiler.diagnostic;
import [Target] from compiler.link;
import [Exports] from "export_table";
import [Loc] from "loc";
import [Block, EnumCaseDef, EnumDef, FunctionDef, GenericParam, StructDef, TypeName] from "model";
import [CheckedDecls, PendingBody] from "pending";
import [StaticRecording] from "static_source";
import [StructInfo] from "struct_info";
import [is_integral_name] from "type_name";

## How long each pass took, summed over its runs, for `-T passes`. One is
## shared by every run of the passes that a build makes (the compilation
## units', the program's).
export struct PassTimes {
    ## Each pass's nanoseconds and runs, by name (`pass_name`).
    var times: HashMap<String, (ulong, uint)> = HashMap<String, (ulong, uint)>();

    construct() {}

    ## Adds `nanoseconds` and one run to the pass that step `call` runs.
    add(call: String, nanoseconds: ulong) {
        var name = pass_name(call);
        var before = times.try_get(name);
        if (before.is_value()) {
            var (spent, runs) = before.value();
            times[name] = (spent + nanoseconds, runs + 1);
        } else {
            times[name] = (nanoseconds, 1);
        }
    }

    ## Adds what `other` recorded (a compilation unit worker's) to these.
    add_all(other: PassTimes) {
        for (var (name, (spent, runs)) in other.times) {
            var before = times.try_get(name);
            if (before.is_value()) {
                var (mine, my_runs) = before.value();
                times[name] = (mine + spent, my_runs + runs);
            } else {
                times[name] = (spent, runs);
            }
        }
    }

    ## The lines `-T passes` prints, the slowest pass first (by name when
    ## two took as long): `pass:   470.763 ms   12x resolve_implicit_types`.
    report(): String {
        var all = Array<(String, ulong, uint)>();
        for (var (name, (spent, runs)) in times) {
            all.append((name, spent, runs));
        }
        all.sort((a, b) => {
            var (x_name, x, _) = a;
            var (y_name, y, _) = b;
            if (x != y) {
                return x > y ? -1 : 1;
            }
            return x_name < y_name ? -1 : (x_name > y_name ? 1 : 0);
        });
        var out = StringBuilder();
        for (var (name, spent, runs) in all) {
            var micros = (spent + 500) / 1000;
            var fraction = $"{micros % 1000}";
            while (fraction.size < 3) {
                fraction = "0" + fraction;
            }
            out.append($"pass: {_pad($"{micros / 1000}.{fraction}", 9)} ms {_pad($"{runs}", 4)}x {name}\n");
        }
        return out.to_string();
    }

    ## The lines a compilation unit worker passes back (`<name>\t<ns>\t<runs>`),
    ## which `parse` reads.
    to_text(): String {
        var out = StringBuilder();
        for (var (name, (spent, runs)) in times) {
            out.append($"{name}\t{spent}\t{runs}\n");
        }
        return out.to_string();
    }

    ## The times `to_text` wrote.
    static parse(text: String): PassTimes {
        var out = PassTimes();
        for (var line in text.split("\n")) {
            var fields = line.split("\t");
            if (fields.count != 3) {
                continue;
            }
            var spent = ulong.parse(fields[1]);
            var runs = uint.parse(fields[2]);
            if (spent.is_value() and runs.is_value()) {
                out.times[fields[0]] = (spent.value(), runs.value());
            }
        }
        return out;
    }
}

## The name of the pass step `call` runs: its function, and the file it is
## in when the two differ (`check_casts` for
## `check_casts::check_casts(module)`, `value_structs::check` for
## `crate::value_structs::check(module)`), as the steps are spelled.
##
## @param call the step, as `--emit-steps` names it
## @returns the pass's name
export pass_name(call: String): String {
    var open = call.find("(");
    var function = open < 0 ? call : call.substr_bytes(0, open as ulong);
    var path = Array<String>();
    for (var part in function.split("::")) {
        if (part != "crate" and part != "passes") {
            path.append(part);
        }
    }
    if (path.is_empty) {
        return function;
    }
    if (path.count >= 2 and path[path.count - 2] != path[path.count - 1]) {
        return $"{path[path.count - 2]}::{path[path.count - 1]}";
    }
    return path[path.count - 1];
}

# `text` with spaces before it, to `width` bytes.
_pad(text: String, width: ulong): String {
    var out = text;
    while (out.size < width) {
        out = " " + out;
    }
    return out;
}

## The passes' state for one program.
export struct PassState {
    ## The compile target.
    var target: Target;
    ## The first error reported since the last `take_error`.
    var error: Diagnostic? = Optional<Diagnostic>.Empty;
    ## The program's file namespaces, by file, for naming closures.
    var namespaces: String[] = Array<String>();
    ## How many closures each file has (by file index; `-1` for code in no
    ## file).
    var closure_counts: HashMap<long, ulong> = HashMap<long, ulong>();
    ## The methods and constructors of checked structs whose bodies are
    ## checked again (a re-check of an edit), by stash key (`m <struct>
    ## <kind> <name>`): their bodies stay in, and their structs count as
    ## extended (`extended_checked`).
    var rechecked_methods: HashSet<String> = HashSet<String>();
    ## The structs a re-check replaced to add a field whose `__copy()` code
    ## the record keeps calls, by name: `synthesize_copies` makes it again.
    var copies_again: HashSet<String> = HashSet<String>();
    ## Each enum's representation and default value, by name.
    var enum_representations: HashMap<String, (String, long)> = HashMap<String, (String, long)>();
    ## The value structs' names (`[Value]`), as `synthesize` and
    ## `check_value_structs` record them.
    var value_structs: HashSet<String> = HashSet<String>();
    ## While `--emit-static` or `--debug-static=expanded` records them, the
    ## `static` blocks' expansions as source (`static_source.pep`).
    var static_recording: StaticRecording? = Optional<StaticRecording>.Empty;
    ## The name of each step run, in order (`--emit-steps`).
    var step_names: String[] = Array<String>();
    ## With `-T passes`, where each pass's time adds up (`PassTimes`).
    var pass_times: PassTimes? = Optional<PassTimes>.Empty;
    ## The notes the passes report besides errors (`reflect.print`), in
    ## order.
    var notes: Diagnostic[] = Array<Diagnostic>();
    ## Each value type's methods (`Color::name`, `i32::doubled`): whether
    ## each is static, keyed by `method_key`, as `enums.install_methods`
    ## records them.
    var enum_methods: HashMap<String, bool> = HashMap<String, bool>();
    ## The reference enums by name (without type arguments), as
    ## `enums.install_reference_enums` records them.
    var reference_enums: HashMap<String, ReferenceEnum> = HashMap<String, ReferenceEnum>();
    ## The next `WithSubject` id no `match` uses, as named-argument binding
    ## (`_hoist`) numbers them.
    var next_subject: ulong = 9223372036854775807;
    ## No argument type is still to come, so overload resolution may settle
    ## a call by arity alone.
    var settle_overloads_by_arity: bool = false;
    ## The traits each struct declares, by its spelled type and, for a
    ## generic base, by its name with its parameters, as
    ## `type_arguments.record_conformances` sets them.
    var conformances: HashMap<String, (String[], TypeName[])> = HashMap<String, (String[], TypeName[])>();
    ## Every trait's name, for a `match` on a trait value, as
    ## `enums.install_traits` records them.
    var trait_names: HashSet<String> = HashSet<String>();
    ## Each concrete struct: its type, its canonical spelling and the
    ## canonical spellings of the traits it declares.
    var trait_structs: Array<(TypeName, String, String[])> = Array<(TypeName, String, String[])>();
    ## Which extension (by index) was applied to which struct (by name), as
    ## `apply_extensions` records them: `"{index}\n{name}"`.
    var applied_extensions: HashSet<String> = HashSet<String>();
    ## The program's files' text, by file index, for fixes that edit near a
    ## declaration.
    var sources: SourceText[] = Array<SourceText>();
    ## What the program exports to C, as `exports.collect_exports` finds it.
    var exports: Exports = Exports();
    ## What `resolve_implicit_types` saw when it last ran, so its next run
    ## walks only the code a change since can affect.
    var implicit: ImplicitMemo = ImplicitMemo();
    ## What `used_trait_types` found in the checked declarations.
    var trait_memo: TraitTypeMemo = TraitTypeMemo();
    ## The callees of the checked declarations, built once: a `Callees`,
    ## as `named_arguments` keeps it.
    var checked_callees: PassMemo? = Optional<PassMemo>.Empty;
    ## The checked declarations by name (`checked.checked_decls`), found
    ## once per compilation unit.
    var checked_decls: CheckedDecls? = Optional<CheckedDecls>.Empty;
    ## The checked declarations' tables for `resolve_implicit_types`, built
    ## once per unit: an `ImplicitTables`, as `resolve_implicit_types`
    ## keeps it.
    var checked_implicit: PassMemo? = Optional<PassMemo>.Empty;
    ## The bodies of checked declarations, taken out while the passes run
    ## (`checked.stash_bodies`), by declaration.
    var stashed: HashMap<String, Block> = HashMap<String, Block>();
    ## The stashed bodies a record's reader skipped, not decoded yet
    ## (`checked.stashed_body`), by the same keys.
    var stashed_pending: HashMap<String, PendingBody> = HashMap<String, PendingBody>();
    ## The declarations a body was stashed from, with its key: what
    ## `checked.restore_bodies` puts back.
    var stashed_from: Array<(String, FunctionDef)> = Array<(String, FunctionDef)>();
    ## The declarations `checked.restore_bodies` put a stashed body back
    ## in, by the same keys.
    var restored: HashSet<String> = HashSet<String>();
    ## The checked structs an extension of the files being checked
    ## changed (`apply_extensions`), by name.
    var extended_checked: HashSet<String> = HashSet<String>();
    ## The value structs' mutating methods `check_value_structs` found, as
    ## a checked unit records them (`value_structs.VALUE_FACTS`): key,
    ## where, and the order found.
    var value_facts: Array<(String, Loc, String)> = Array<(String, Loc, String)>();
    ## How many of `Module.struct_specs` and `Module.func_specs` met their
    ## constraints already (`check_specializations`).
    var checked_specs: (ulong, ulong) = (0, 0);
    ## The link summaries `check_confinement` settled for the functions not
    ## checked before, by summary key:
    ## a checked unit's record keeps them (`Checked.summaries`).
    var settled_summaries: HashMap<String, (Loc, String)> = HashMap<String, (Loc, String)>();
    ## Whether struct specializations get a method's body only once a use
    ## names it (`lazy_methods`). Off to specialize every method, as the
    ## passes' expected models were recorded.
    var lazy_methods: bool = false;
    ## The bodies of the specializations' methods no use has named yet, by
    ## struct and method name.
    var deferred: HashMap<String, HashMap<String, Block>> = HashMap<String, HashMap<String, Block>>();
    ## Every trait's method names, which a trait may dispatch to.
    var trait_method_names: HashSet<String>? = Optional<HashSet<String>>.Empty;

    ## Creates the state for compiling for `target`.
    ##
    ## @param target the compile target
    construct(target: Target) {
        this.target = target;
    }

    ## `trait_memo`, for `used_trait_types` and `StructTable`.
    trait_types_memo(): TraitTypeMemo? {
        return Optional<TraitTypeMemo>.Value(trait_memo);
    }

    ## Records an error. Only the first is kept: later ones are usually
    ## fallout from it.
    ##
    ## @param diagnostic the error
    report(diagnostic: Diagnostic) {
        if (!error.is_value()) {
            error = Optional<Diagnostic>.Value(diagnostic);
        }
    }

    ## Returns the error reported since the last call, clearing it.
    ##
    ## @returns the error, if any
    take_error(): Diagnostic? {
        var out = error;
        error = Optional<Diagnostic>.Empty;
        return out;
    }

    ## Records each enum's representation and default value: enum names are integer types from here on.
    ##
    ## @param enums the program's enums
    install_enums(enums: EnumDef[]) {
        enum_representations.clear();
        for (var e in enums) {
            enum_representations[e.name] = (e.representation.name, _default_value(e));
        }
    }

    ## Returns the default value of the enum named `name`, or none when it
    ## names no enum.
    ##
    ## @param name the type's name
    ## @returns the value
    enum_default(name: String): long? {
        var found = enum_representations.try_get(name);
        if (!found.is_value()) {
            return Optional<long>.Empty;
        }
        var (_, value) = found.value();
        return Optional<long>.Value(value);
    }

    ## Returns whether the type spelled `name` is a value struct.
    ##
    ## @param name the type's spelling
    ## @returns true for a `[Value]` struct
    is_value_struct(name: String): bool {
        var open = name.find("<");
        var base = open < 0 ? name : name.substr_bytes(0, open as ulong);
        return value_structs.contains(base);
    }

    ## Returns whether `name` is a primitive type or an enum.
    ##
    ## @param name the type's name
    ## @returns true for an integral type
    is_integral(name: String): bool {
        return is_integral_name(name) or enum_representations.contains(name);
    }
}

## What the passes know of a reference enum: its cases, where its name is,
## its type parameters, and the declared types of each case's values.
export struct ReferenceEnum {
    ## The cases, in order.
    var cases: EnumCaseDef[];
    ## Where the enum's name is.
    var loc: Loc;
    ## The enum's type parameters.
    var generic_params: GenericParam[];
    ## Each case's values' declared types, in `cases` order.
    var payload_types: Array<TypeName[]>;

    construct(cases: EnumCaseDef[], loc: Loc, generic_params: GenericParam[], payload_types: Array<TypeName[]>) {
        this.cases = cases;
        this.loc = loc;
        this.generic_params = generic_params;
        this.payload_types = payload_types;
    }
}

## The key `PassState.enum_methods` files method `method` of value type
## `owner` under.
##
## @param owner the value type's key
## @param method the method, as spelled in its function's name
## @returns the key
export method_key(owner: String, method: String): String {
    return $"{owner}\n{method}";
}

## The value of a slot nothing was stored in yet: the case whose value is
## 0, else the first case (0 for an enum with no cases).
_default_value(e: EnumDef): long {
    for (var c in e.cases) {
        if (c.value == 0) {
            return 0;
        }
    }
    return e.cases.count > 0 ? e.cases[0].value : 0;
}

## What a pass keeps in `PassState` of a type this file cannot name: the
## file that declares the type extends it with `PassMemo`, and reads it
## back with `as?`. The state then imports no pass, so the passes that
## import it are not one import cycle with it.
export trait PassMemo {}

## What `used_trait_types` found in the checked declarations whose bodies
## are stashed: those stay as they are while the passes run, so each is
## looked through once per unit. Each holds the types that may name a
## trait, in the order they were looked through.
export struct TraitTypeMemo {
    ## The types each settled struct's declarations looked through, by
    ## struct name, with how many fields, methods and constructors the
    ## struct had: a specialization or extension may add more. Rebuilding
    ## `checked_types` replays these, so it walks only changed structs.
    var structs: HashMap<String, (ulong, TypeName[])> = HashMap<String, (ulong, TypeName[])>();
    ## The same for each checked function without a body, by name.
    var functions: HashMap<String, TypeName[]> = HashMap<String, TypeName[]>();
    ## Each checked struct's `StructTable` entry, by name, with how many
    ## fields and methods it had, and its type's spelling.
    var infos: HashMap<String, (ulong, ulong, String, StructInfo)> = HashMap<String, (ulong, ulong, String, StructInfo)>();
    ## The checked structs' and functions' `StructTable`, which every pass's
    ## table falls back to, with how many checked structs and functions,
    ## and how many fields and methods those structs had, it was built
    ## from (a `StructTable`, as `static_type` keeps it); `apply_extensions`
    ## drops it when it changes a checked struct.
    var checked_table: PassMemo? = Optional<PassMemo>.Empty;
    ## Each checked struct's overloaded methods for `Overloads`, by name,
    ## as `overload_select` keeps them.
    var members: HashMap<String, PassMemo> = HashMap<String, PassMemo>();
    var checked_counts: (ulong, ulong, ulong, ulong) = (0, 0, 0, 0);
    ## Whether the checked declarations' bodies are stashed: from
    ## `stash_bodies` to `restore_bodies`. While they are, `used_trait_types`
    ## looks through the checked declarations once, into `checked_types`.
    var stashed: bool = false;
    ## What `used_trait_types` found in the settled checked declarations
    ## (the trait types, and the names and types it looked through), with
    ## the checked structs it must look through each time (not settled),
    ## and how many checked structs and functions, and fields and methods
    ## of those structs, there were.
    var checked_types: (TypeName[], HashSet<String>, HashSet<String>, HashSet<String>)? = Optional<(TypeName[], HashSet<String>, HashSet<String>, HashSet<String>)>.Empty;
    var checked_types_counts: (ulong, ulong, ulong, ulong) = (0, 0, 0, 0);

    construct() {}
}

## What a run of `resolve_implicit_types` leaves for the next: what each
## callable looked up and its fingerprint after its last walk, and the
## fingerprints of the declarations the walks look up.
export struct ImplicitMemo {
    ## Whether a run has filled this in.
    var kept: bool = false;
    ## Each checked struct's methods (name, type) and arities (set name,
    ## fewest and most arguments), for `resolve_implicit_types`' tables, by
    ## name, with the struct and how many fields and methods it had.
    var struct_parts: HashMap<String, (StructDef, ulong, ulong, Array<(String, TypeName)>, Array<(String, ulong, ulong)>)> = HashMap<String, (StructDef, ulong, ulong, Array<(String, TypeName)>, Array<(String, ulong, ulong)>)>();
    ## What each callable looked up in its last walk, by its place.
    var reads: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>();
    ## Each callable's fingerprint after its last walk, by its place.
    var prints: HashMap<String, ulong> = HashMap<String, ulong>();
    ## Each declaration's fingerprint, by its id.
    var declarations: HashMap<String, ulong> = HashMap<String, ulong>();
    ## The read keys a change to each declaration announces, by its id.
    var announces: HashMap<String, Array<String>> = HashMap<String, Array<String>>();
    ## The fingerprint of what no read key covers (traits, extensions,
    ## enums, ...): when it changes, every callable is walked.
    var context: ulong = 0;
    ## What the last run changed that its callers have not looked for yet
    ## (when it stopped at its limit of runs).
    var pending: HashSet<String> = HashSet<String>();
    ## The callables whose last walk made a selection settling overloads
    ## by arity could change, by place.
    var unsettled: HashSet<String> = HashSet<String>();

    construct() {}
}
