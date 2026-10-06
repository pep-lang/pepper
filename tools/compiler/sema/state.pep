## What the passes keep between steps besides the model: the first error
## a pass reported, the closure numbering, and the facts some passes
## install for the later ones, as the Rust passes keep them in
## thread-locals.

import [Diagnostic, SourceText] from compiler.diagnostic;
import [Target] from compiler.link;
import [Exports] from "exports";
import [Loc] from "loc";
import [EnumCaseDef, EnumDef, GenericParam, TypeName] from "model";
import [is_integral_name] from "type_name";

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
    ## Each enum's representation and default value, by name.
    var enum_representations: HashMap<String, (String, long)> = HashMap<String, (String, long)>();
    ## The value structs' names (`[Value]`), as `value_structs::install`
    ## records them.
    var value_structs: HashSet<String> = HashSet<String>();
    ## The notes the passes report besides errors (`reflect.print`), in
    ## order: the Rust module's `warnings`.
    var notes: Diagnostic[] = Array<Diagnostic>();
    ## Each value type's methods (`Color::name`, `i32::doubled`): whether
    ## each is static, keyed by `method_key`, as `enums::install_methods`
    ## records them.
    var enum_methods: HashMap<String, bool> = HashMap<String, bool>();
    ## The reference enums by name (without type arguments), as
    ## `enums::install_reference_enums` records them.
    var reference_enums: HashMap<String, ReferenceEnum> = HashMap<String, ReferenceEnum>();
    ## The next `WithSubject` id no `match` uses, as
    ## `named_arguments::next_subject` numbers them.
    var next_subject: ulong = 9223372036854775807;
    ## `Module::settle_overloads_by_arity`: no argument type is still to
    ## come, so overload resolution may settle a call by arity alone.
    var settle_overloads_by_arity: bool = false;
    ## The traits each struct declares, by its spelled type and, for a
    ## generic base, by its name with its parameters, as
    ## `type_arguments::record_conformances` sets them.
    var conformances: HashMap<String, (String[], TypeName[])> = HashMap<String, (String[], TypeName[])>();
    ## Every trait's name, for a `match` on a trait value, as
    ## `enums::install_traits` records them.
    var trait_names: HashSet<String> = HashSet<String>();
    ## Each concrete struct: its type, its canonical spelling and the
    ## canonical spellings of the traits it declares.
    var trait_structs: Array<(TypeName, String, String[])> = Array<(TypeName, String, String[])>();
    ## Which extension (by index) was applied to which struct (by name), as
    ## `apply_extensions` records them: `"{index}\n{name}"`.
    var applied_extensions: HashSet<String> = HashSet<String>();
    ## The program's files' text, by file index, for fixes that edit near
    ## a declaration (`Module::sources`).
    var sources: SourceText[] = Array<SourceText>();
    ## What the program exports to C, as `exports::collect_exports` finds
    ## it (`Module::exports`).
    var exports: Exports = Exports();
    ## What `resolve_implicit_types` saw when it last ran, so its next run
    ## walks only the code a change since can affect.
    var implicit: ImplicitMemo = ImplicitMemo();

    ## Creates the state for compiling for `target`.
    ##
    ## @param target the compile target
    construct(target: Target) {
        this.target = target;
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

    ## Records each enum's representation and default value, as
    ## `enums::install` does: enum names are integer types from here on.
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
        if (name.ends_with("*")) {
            return false;
        }
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

## What a run of `resolve_implicit_types` leaves for the next: what each
## callable looked up and its fingerprint after its last walk, and the
## fingerprints of the declarations the walks look up.
export struct ImplicitMemo {
    ## Whether a run has filled this in.
    var kept: bool = false;
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

    construct() {}
}
