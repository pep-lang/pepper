## Confinement: `check_confinement`. What a `with` block over an
## `[Isolated]` guard (a `Mutex<T>`'s lock, a `ThreadLocal<T>`'s value) may
## do, and the checks that make it sound.
##
## Inside such a block every value of a type that is not thread-safe is part of
## the locked value (the lock's region), of the rest of the program (the outer
## region), or new (a fresh region, which may join either). A call links the
## regions of the operands its callee links, as its link summary says; linking
## the lock's region with the outer one (or another lock's) is an error at the
## value that would cross, as is returning part of the locked value from the
## block. Summaries are a least fixed point over the call graph; a call through
## a trait value joins the summaries of the methods implementing it. A summary a
## checked compilation unit recorded keeps, for each trait call it reaches, the
## join it was made with rather than the structs it reached, and holds in a
## later compilation unit wherever those joins are the same (`_stale`). The pass
## also checks guard use, `[Move]` arguments, `ThreadLocal<T>.get()` and
## `Mutex<T>` of a number, and use after `move`.

import compiler.ast;
import [Diagnostic, Fix, Location] from compiler.diagnostic;
import io;
import [Path] from io;
import [absolute, demangle_name, Runtime, Target] from compiler.link;
import os;
import [has_stashed, is_checked_function, unit_decls, take_stashed] from "checked";
import [expression_children] from "closure_sites";
import [CALL_METHOD] from "closures";
import "common";
import [READS_ATTRIBUTE] from "lazy";
import [Loc] from "loc";
import [
    BinaryOp,
    Block,
    Branch,
    Expression,
    FunctionDef,
    LoopBreakKind,
    Module,
    MoveExpression,
    Statement,
    StructDef,
    TypeName,
    VariableDef,
    WeakOp
] from "model";
import "resolve_implicit_types";
import [use_site] from "shared_type_checks";
import [ThreadSafeStructs, unsafe_part_in] from "shared_types";
import [method_key, PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [parse_type_string, TUPLE] from "type_name";
import [Rewriter, rewrite_block] from "walk";

## A struct that can only be the scope of a `with` header.
export const ISOLATED_ATTRIBUTE = "Isolated";

## A parameter whose argument must be disconnected.
export const MOVE_ATTRIBUTE = "Move";

## A runtime free function's parameter whose argument is moved in.
export const MOVE_SOURCE_ATTRIBUTE = "MoveSource";

## A runtime function-value parameter that is called with a locked value.
export const LOCKED_ATTRIBUTE = "Locked";

## How many rounds the summaries may take to settle, per function.
const _MAX_ROUNDS: ulong = 64;

## Returns whether a parameter with these attributes takes over the
## caller's reference instead of acquiring one: `[Move]` and `[MoveSource]`.
##
## @param attributes the parameter's attributes
## @returns true for either
export takes_over(attributes: ast.Attribute[]): bool {
    return ast.has_attribute(attributes, MOVE_ATTRIBUTE) or ast.has_attribute(attributes, MOVE_SOURCE_ATTRIBUTE);
}

## Reports the first confinement error: an attribute in the wrong place, a
## guard kept or used outside a `with` header, a locked value that would
## escape its block, an argument to a `[Move]` parameter that is not new,
## and a use after `move`. Wraps each argument to a `[MoveSource]`
## parameter in a `Move` first, and fills `module.summaries_to_record` when
## `module.record_summaries` asks.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_confinement(module: Module, state: PassState) {
    _lower_moved_arguments(module);
    module.summaries_to_record = Array<(Loc, String)>();
    var program = _Confinement(module, state);
    if (_check_parameter_attributes(program) or _check_mutex_arguments(program) or _check_guard_fields(program)) {
        return;
    }
    var triggers = _triggers(program);
    # The settled summaries used hold while the joins of their trait calls
    # do: when one no longer does, it is dropped and everything is
    # summarized and checked again without it.
    while (true) {
        var error = _confine(program, triggers);
        var stale = _stale(program);
        if (stale.count == 0) {
            _settle(program);
            var verify = os.environment("PEPC_VERIFY_SUMMARIES");
            if (verify.is_value() and !verify.value().is_empty) {
                _verify_summaries(program);
            }
            if (error.is_value()) {
                state.report(error.value());
                return;
            }
            break;
        }
        for (var key in stale) {
            program.dropped.insert(key);
            module.checked.summaries.remove(key);
        }
        program.reset();
    }
    module.summaries_to_record = program.recorded_out;
}

# With `PEPC_VERIFY_SUMMARIES` set: makes every summary the pass used again
# from scratch, without the dependent summaries recorded before, and
# reports on standard error each one that differs, then the counts.
_verify_summaries(program: _Confinement) {
    var fresh = _Confinement(program.module, program.state);
    for (var (key, value) in program.module.checked.summaries) {
        var (_, text) = value;
        if (text.contains("\n")) {
            fresh.dropped.insert(key);
        }
    }
    for (var (key, body) in program._restored) {
        fresh._restored[key] = body;
        fresh._by_key()[key] = body;
        fresh.bodies.insert(key);
    }
    var keys = Array<String>();
    for (var (key, _) in program.summaries) {
        keys.append(key);
    }
    _summaries(fresh, keys);
    ulong same = 0;
    ulong missing = 0;
    for (var key in keys) {
        var a = program.summaries[key];
        var b = fresh.summary(key);
        if (!b.is_value()) {
            missing += 1;
        } else if (a.links() != b.value().links()) {
            var shown = key.replace("\n", ".");
            io.File.stderr().write_all($"verify-summaries: {shown} {a.links()} fresh {b.value().links()}\n");
        } else {
            same += 1;
        }
    }
    io.File.stderr().write_all(
        $"verify-summaries: {same} same, {missing} missing, {program.tentative.count} tentative\n"
    );
}

# Summarizes what the checks need, then checks every function that may
# break a rule: the first error.
_confine(program: _Confinement, triggers: HashSet<String>): Diagnostic? {
    var none = Optional<Diagnostic>.Empty;
    var module = program.module;
    var roots = _roots(program);
    # Only a function with a `with` block needs the region walk.
    var with_blocks = HashSet<String>();
    for (var key in roots) {
        with_blocks.insert(key);
    }
    if (module.record_summaries) {
        _record_summaries(program);
    } else if (roots.count > 0) {
        _summaries(program, roots);
    }
    for (var body in program.all) {
        var regions = with_blocks.contains(body.key);
        if (program.is_settled(body.key) or (!regions and !_mentions(body.function, triggers))) {
            continue;
        }
        # A checked unit's bodies were checked with it; one is here only for
        # its summary.
        if (_is_checked(module, body)) {
            continue;
        }
        var error = _check_function(program, body.owner, body.function, regions);
        if (error.is_value()) {
            return error;
        }
    }
    return none;
}

# ── Summaries ────────────────────────────────────────────────────────────

## What a function's body links: for each operand slot (`this` first for a
## method, then the parameters) and each result slot (one per element of a
## tuple result, else one), the smallest slot of its class; and whether each
## result is tainted.
struct _Summary {
    var classes: ulong[];
    ## One per result slot.
    var tainted: bool[];
    ## The first `return` whose value shares an operand's class or is
    ## tainted, for notes. Not compared.
    var blame: Loc? = Optional<Loc>.Empty;
    ## The calls through a trait value it reaches, its own and those of the
    ## functions it calls by name (not the implementations'): for each,
    ## `trait\tmethod\toperands\tresults`, the joined summary of the
    ## implementations it was made with (`links`). It holds wherever those
    ## joins are the same, whichever structs implement the traits there.
    var dispatched: HashMap<String, String> = HashMap<String, String>();

    construct(classes: ulong[], tainted: bool[]) {
        this.classes = classes;
        this.tainted = tainted;
    }

    results(): ulong {
        return tainted.count;
    }

    operands(): ulong {
        return classes.count - tainted.count;
    }

    ## Result slot `n` shares nothing with the operands.
    fresh_at(n: ulong): bool {
        if (tainted[n]) {
            return false;
        }
        var result = classes[operands() + n];
        ulong slot = 0;
        while (slot < operands()) {
            if (classes[slot] == result) {
                return false;
            }
            slot += 1;
        }
        return true;
    }

    ## Both summaries' links, for a call through a trait value. Summaries
    ## of different shapes join to the top.
    join(other: _Summary): _Summary {
        if (classes.count != other.classes.count or results() != other.results()) {
            return _top(operands(), results());
        }
        var slots = classes.count;
        var sets = _identity_sets(slots);
        ulong slot = 0;
        while (slot < slots) {
            _union_sets(sets, slot, classes[slot]);
            _union_sets(sets, slot, other.classes[slot]);
            slot += 1;
        }
        var joined = Array<ulong>();
        slot = 0;
        while (slot < slots) {
            ulong s = 0;
            while (_find_set(sets, s) != _find_set(sets, slot)) {
                s += 1;
            }
            joined.append(s);
            slot += 1;
        }
        var taints = Array<bool>();
        ulong n = 0;
        while (n < tainted.count) {
            taints.append(tainted[n] or other.tainted[n]);
            n += 1;
        }
        var out = _Summary(joined, taints);
        out.blame = blame.is_value() ? blame : other.blame;
        return out;
    }

    ## It reaches a call through a trait value.
    dependent(): bool {
        return dispatched.count > 0;
    }

    ## Whether `other` links and taints the same, with the same joins.
    same_links(other: _Summary): bool {
        if (dispatched.count != other.dispatched.count
            or classes.count != other.classes.count
            or tainted.count != other.tainted.count) {
            return false;
        }
        for (var (call, links) in dispatched) {
            var theirs = other.dispatched.try_get(call);
            if (!theirs.is_value() or theirs.value() != links) {
                return false;
            }
        }
        ulong i = 0;
        while (i < classes.count) {
            if (classes[i] != other.classes[i]) {
                return false;
            }
            i += 1;
        }
        i = 0;
        while (i < tainted.count) {
            if (tainted[i] != other.tainted[i]) {
                return false;
            }
            i += 1;
        }
        return true;
    }

    ## What it links and taints: `classes;taints` (`0,1,0;0`).
    links(): String {
        var class_text = Array<String>();
        for (var c in classes) {
            class_text.append($"{c}");
        }
        var taint_text = Array<String>();
        for (var t in tainted) {
            taint_text.append(t ? "1" : "0");
        }
        return $"{_joined(class_text)};{_joined(taint_text)}";
    }

    ## The summary as recorded for the build cache: `classes;taints;blame`
    ## (`0,1,0;0;12-30`), the blame's span from `base` on (its function's
    ## start, for a settled summary, so moving the function keeps it).
    encode(base: Loc? = Optional<Loc>.Empty): String {
        var blamed = "-";
        if (blame.is_value()) {
            var at = blame.value().span;
            if (!base.is_value()) {
                blamed = $"{at.start}-{at.end}";
            } else if (base.value().file == blame.value().file and at.start >= base.value().span.start) {
                var start = base.value().span.start;
                blamed = $"{at.start - start}-{at.end - start}";
            }
        }
        return $"{links()};{blamed}";
    }

    ## The summary as a checked unit records it: `encode`, then a line for
    ## each call through a trait value it reaches, in order,
    ## `trait\tmethod\toperands\tresults\tlinks`.
    ##
    ## @param base the function's location, which the blame is recorded from
    settled_text(base: Loc): String {
        var calls = Array<String>();
        for (var (call, _) in dispatched) {
            calls.append(call);
        }
        calls.sort((a: String, b: String) => a < b ? -1 : (a > b ? 1 : 0));
        var out = StringBuilder();
        out.append(encode(Optional<Loc>.Value(base)));
        for (var call in calls) {
            out.append($"\n{call}\t{dispatched[call]}");
        }
        return out.to_string();
    }
}

_joined(parts: String[]): String {
    var out = StringBuilder();
    ulong i = 0;
    while (i < parts.count) {
        if (i > 0) {
            out.append(",");
        }
        out.append(parts[i]);
        i += 1;
    }
    return out.to_string();
}

## Nothing linked, nothing tainted: every slot its own class.
_bottom(operands: ulong, results: ulong): _Summary {
    var classes = Array<ulong>();
    ulong i = 0;
    while (i < operands + results) {
        classes.append(i);
        i += 1;
    }
    var tainted = Array<bool>();
    i = 0;
    while (i < results) {
        tainted.append(false);
        i += 1;
    }
    return _Summary(classes, tainted);
}

## Everything linked and every result tainted: a callee nothing is known
## about.
_top(operands: ulong, results: ulong): _Summary {
    var classes = Array<ulong>();
    ulong i = 0;
    while (i < operands + results) {
        classes.append(0);
        i += 1;
    }
    var tainted = Array<bool>();
    i = 0;
    while (i < results) {
        tainted.append(true);
        i += 1;
    }
    return _Summary(classes, tainted);
}

## Parses a comma-separated list of numbers; none when one is not a
## number.
_numbers(field: String): ulong[]? {
    var out = Array<ulong>();
    if (field.is_empty) {
        return Optional<ulong[]>.Value(out);
    }
    for (var part in field.split(",")) {
        var n = ulong.parse(part);
        if (!n.is_value()) {
            return Optional<ulong[]>.Empty;
        }
        out.append(n.value());
    }
    return Optional<ulong[]>.Value(out);
}

## A summary `_Summary.encode` wrote, for a function in `file`: its blame
## from `base` on when given (a settled summary's, `base` its function's
## start); none when the function is not found then.
_decode(text: String, file: uint, base: ulong? = Optional<ulong>.Empty, settled: bool = false): _Summary? {
    var none = Optional<_Summary>.Empty;
    # What follows `|` is other passes'.
    var bar = text.find("|");
    var own = bar < 0 ? text : text.substr_bytes(0, bar as ulong);
    # What follows a newline is a dependent summary's trait calls, one a
    # line, each with the joined summary it was made with.
    var lines = own.split("\n");
    own = lines[0];
    var fields = own.split(";");
    if (fields.count < 3) {
        return none;
    }
    var classes = _numbers(fields[0]);
    var taints = _numbers(fields[1]);
    if (!classes.is_value() or !taints.is_value()) {
        return none;
    }
    var tainted = Array<bool>();
    for (var t in taints.value()) {
        tainted.append(t != 0);
    }
    var summary = _Summary(classes.value(), tainted);
    if (fields[2] != "-") {
        var span = fields[2].split_once("-");
        if (!span.is_value()) {
            return none;
        }
        var (start_text, end_text) = span.value();
        var start = ulong.parse(start_text);
        var end = ulong.parse(end_text);
        if (!start.is_value() or !end.is_value()) {
            return none;
        }
        if (!settled) {
            summary.blame = Optional<Loc>.Value(Loc.at(file, ast.Span(start.value(), end.value())));
        } else if (base.is_value()) {
            summary.blame = Optional<Loc>.Value(
                Loc.at(file, ast.Span(start.value() + base.value(), end.value() + base.value()))
            );
        }
    }
    for (var i in 1..lines.count) {
        var tab = lines[i].rfind("\t");
        if (tab < 0) {
            return none;
        }
        var call = lines[i].substr_bytes(0, tab as ulong);
        summary.dispatched[call] = lines[i].substr_bytes(tab as ulong + 1, lines[i].size - tab as ulong - 1);
    }
    return Optional<_Summary>.Value(summary);
}

## The number of elements of a tuple type, or 1.
_result_slots(ty: TypeName): ulong {
    return ty.name == TUPLE and ty.sub_types.count > 0 ? ty.sub_types.count : 1;
}

_identity_sets(count: ulong): ulong[] {
    var out = Array<ulong>();
    ulong i = 0;
    while (i < count) {
        out.append(i);
        i += 1;
    }
    return out;
}

_find_set(sets: ulong[], x: ulong): ulong {
    var root = x;
    while (sets[root] != root) {
        root = sets[root];
    }
    var at = x;
    while (sets[at] != root) {
        var next = sets[at];
        sets[at] = root;
        at = next;
    }
    return root;
}

_union_sets(sets: ulong[], a: ulong, b: ulong) {
    var x = _find_set(sets, a);
    var y = _find_set(sets, b);
    if (x != y) {
        if (x < y) {
            sets[y] = x;
        } else {
            sets[x] = y;
        }
    }
}

# ── Regions ──────────────────────────────────────────────────────────────

## What a region is part of.
enum _RegionPart {
    ## New: may join anything.
    Fresh,
    ## The rest of the program (in a function being checked).
    Outer,
    ## Operand slot `slot` of the function being summarized.
    Operand(slot: ulong),
    ## The value locked by with block `lock`.
    Locked(lock: ulong),
}

_same_part(a: _RegionPart, b: _RegionPart): bool {
    match (a) {
        Fresh => {
            return _is_fresh_part(b);
        }
        Outer => {
            return _is_outer_part(b);
        }
        Operand(x) => {
            if (b is Operand(y)) {
                return x == y;
            }
            return false;
        }
        Locked(x) => {
            return _locked_index(b) == x as long;
        }
    }
}

_is_fresh_part(p: _RegionPart): bool {
    match (p) {
        Fresh => {
            return true;
        }
        else => {
            return false;
        }
    }
}

_is_outer_part(p: _RegionPart): bool {
    match (p) {
        Outer => {
            return true;
        }
        else => {
            return false;
        }
    }
}

_is_operand_part(p: _RegionPart): bool {
    match (p) {
        Operand(slot) => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## The lock of a locked part, or -1.
_locked_index(p: _RegionPart): long {
    match (p) {
        Locked(n) => {
            return n as long;
        }
        else => {
            return -1;
        }
    }
}

struct _Region {
    var parent: ulong;
    var part: _RegionPart;
    ## May also be referenced from somewhere the walk cannot see.
    var tainted: bool = false;
    ## A pointer the walk cannot follow back to its owner: a reference read
    ## through it is tainted.
    var untracked: bool = false;
    ## Operand slots in the region (summaries).
    var operands: ulong[] = Array<ulong>();
    ## A tuple value: the region of each element (-1 for a thread-safe
    ## one). Never unioned: linking goes element by element.
    var parts: long[] = Array<long>();
    ## Reachable from outside the function.
    var shared: bool = false;

    construct(parent: ulong, part: _RegionPart) {
        this.parent = parent;
        this.part = part;
    }
}

## A `with` block over an `[Isolated]` guard: what was locked, as written,
## and the locking call.
struct _Lock {
    var name: String;
    var loc: Loc;

    construct(name: String, loc: Loc) {
        this.name = name;
        this.loc = loc;
    }
}

## A local in scope: its region (-1 for none) and type.
struct _ScopeLocal {
    var name: String;
    var region: long;
    var ty: TypeName;

    construct(name: String, region: long, ty: TypeName) {
        this.name = name;
        this.region = region;
        this.ty = ty;
    }
}

## A `return`'s value region (-1 for none) and location.
struct _Returned {
    var region: long;
    var loc: Loc;

    construct(region: long, loc: Loc) {
        this.region = region;
        this.loc = loc;
    }
}

## A compiled function body, with the struct it belongs to and its summary
## key.
struct _Body {
    var owner: TypeName?;
    var key: String;
    var function: FunctionDef;

    construct(owner: TypeName?, key: String, function: FunctionDef) {
        this.owner = owner;
        this.key = key;
        this.function = function;
    }
}

## The function a call resolves to.
enum _Callee {
    ## A free function, method or constructor with a body: its summary key
    ## and definition.
    Known(key: String, function: FunctionDef),
    ## A method called through a trait value: `trait\tmethod`, and every
    ## implementation's key.
    Trait(call: String, keys: String[]),
    ## `copy(x)`: fresh, linking nothing.
    Copy,
    ## An `extern`: links nothing; a pointer result is marked.
    Extern,
    ## Anything else: links everything, result tainted.
    Unknown,
}

## A method call's callee, and whether the receiver names a type.
struct _ResolvedMethod {
    var callee: _Callee;
    var is_static: bool;

    construct(callee: _Callee, is_static: bool) {
        this.callee = callee;
        this.is_static = is_static;
    }
}

## What the pass knows of the program.
struct _Confinement {
    var module: Module;
    var state: PassState;
    var table: StructTable;
    var safe: ThreadSafeStructs;
    var summaries: HashMap<String, _Summary> = HashMap<String, _Summary>();
    # The recorded summaries of the functions whose bodies were skipped, by
    # key, decoded on first use.
    var _recorded_text: HashMap<String, (Loc, String)> = HashMap<String, (Loc, String)>();
    ## The functions whose summaries were recorded before.
    var settled: HashSet<String> = HashSet<String>();
    # The checked summaries `_decode_checked` looked for.
    var _tried: HashSet<String> = HashSet<String>();
    ## The settled summaries decoded that call through a trait value, in
    ## the order decoded: they hold only while their joins do (`stale`).
    var tentative: Array<String> = Array<String>();
    ## The checked summaries found stale, never decoded again.
    var dropped: HashSet<String> = HashSet<String>();
    ## Every compiled function body.
    var all: Array<_Body>;
    var bodies: HashSet<String> = HashSet<String>();
    var structs: HashMap<String, StructDef> = HashMap<String, StructDef>();
    ## Each constructor by the name a call gives it.
    var constructors: HashMap<String, FunctionDef> = HashMap<String, FunctionDef>();
    var constructor_structs: HashMap<String, StructDef> = HashMap<String, StructDef>();
    ## The first non-generic free function of each name.
    var functions: HashMap<String, FunctionDef> = HashMap<String, FunctionDef>();
    var externs: HashSet<String> = HashSet<String>();
    var traits: HashSet<String> = HashSet<String>();
    var isolated: HashSet<String> = HashSet<String>();
    var region_types: HashMap<String, bool> = HashMap<String, bool>();
    var recorded_out: Array<(Loc, String)> = Array<(Loc, String)>();
    ## Whether each file is part of the runtime, found on first use.
    var runtime_files: bool[]? = Optional<bool[]>.Empty;
    # The structs implementing each trait, by trait name, found on first use.
    var _implementors: HashMap<String, StructDef[]>? = Optional<HashMap<String, StructDef[]>>.Empty;
    # The checked bodies `restore` brought back or looked up, by summary key.
    var _stashed_bodies: HashMap<String, (_Body, String)> = HashMap<String, (_Body, String)>();
    # Every body by key (`_by_key`).
    var _known: HashMap<String, _Body> = HashMap<String, _Body>();
    var _known_filled: bool = false;
    # The bodies `restore` put back, by key.
    var _restored: HashMap<String, _Body> = HashMap<String, _Body>();
    # `dispatched`'s answers, by trait and method.
    var _dispatch: HashMap<String, String[]> = HashMap<String, String[]>();

    construct(module: Module, state: PassState) {
        this.module = module;
        this.state = state;
        table = StructTable(module, memo = state.trait_types_memo());
        safe = ThreadSafeStructs(module, state);
        all = _bodies(module);
        for (var body in all) {
            bodies.insert(body.key);
        }
        for (var st in module.structs) {
            structs[st.name] = st;
            for (var c in st.constructors) {
                constructors[c.name] = c;
                constructor_structs[c.name] = st;
            }
            if (ast.has_attribute(st.attributes, ISOLATED_ATTRIBUTE)) {
                isolated.insert(st.name);
            }
        }
        for (var f in module.functions) {
            if (!f.is_generic_func and !functions.contains(f.name)) {
                functions[f.name] = f;
            }
        }
        for (var e in module.externs) {
            externs.insert(e.name);
        }
        for (var t in module.traits) {
            traits.insert(t.name);
        }
        _recorded_text = _recorded(module);
    }

    ## The summary of `key`, as computed or recorded.
    summary(key: String): _Summary? {
        var found = summaries.try_get(key);
        if (found.is_value()) {
            return found;
        }
        _decode_checked(key);
        return summaries.try_get(key);
    }

    ## Whether the summary of `key` was recorded before.
    is_settled(key: String): bool {
        if (settled.contains(key)) {
            return true;
        }
        _decode_checked(key);
        return settled.contains(key);
    }

    # A checked unit's summary is decoded on first use: a compilation unit reads
    # few of those below it.
    _decode_checked(key: String) {
        if (summaries.contains(key) or !_tried.insert(key)) {
            return;
        }
        var skipped = _recorded_text.try_get(key);
        if (skipped.is_value()) {
            var (at, text) = skipped.value();
            var decoded = _decode(text, at.file);
            if (decoded.is_value()) {
                summaries[key] = decoded.value();
                settled.insert(key);
                return;
            }
        }
        var recorded = module.checked.summaries.try_get(key);
        if (!recorded.is_value() or dropped.contains(key)) {
            return;
        }
        var (loc, text) = recorded.value();
        var decoded = _decode(text, loc.file, _function_start(key), true);
        if (decoded.is_value()) {
            summaries[key] = decoded.value();
            settled.insert(key);
            if (decoded.value().dependent()) {
                tentative.append(key);
            }
        }
    }

    ## Forgets every summary, to summarize again without the `dropped`
    ## ones. The bodies `restore` put back stay.
    reset() {
        summaries = HashMap<String, _Summary>();
        settled = HashSet<String>();
        _tried = HashSet<String>();
        tentative = Array<String>();
        recorded_out = Array<(Loc, String)>();
    }

    ## The summary a call of `key` uses, sized for its operands and results
    ## when there is none yet: the bottom for a body (a caller is walked
    ## again once it has its own), the top for a function without one.
    callee_summary(key: String, operands: ulong, results: ulong): _Summary {
        var found = summary(key);
        if (found.is_value()) {
            return found.value();
        }
        # A checked function no summary settled starts at the bottom like
        # any other body.
        if (bodies.contains(key) or restore(key).is_value()) {
            return _bottom(operands, results);
        }
        return _top(operands, results);
    }

    ## The summary of a call through a trait value: every implementation's
    ## joined, or the top when there is none.
    dispatch_summary(keys: String[], operands: ulong, results: ulong): _Summary {
        _Summary? joined = Optional<_Summary>.Empty;
        for (var key in keys) {
            var s = callee_summary(key, operands, results);
            joined = Optional<_Summary>.Value(joined.is_value() ? joined.value().join(s) : s);
        }
        return joined.is_value() ? joined.value() : _top(operands, results);
    }

    ## What a summary's `dispatched` call joins to now: its
    ## implementations' summaries joined, as `links`; empty for a malformed
    ## call.
    joined_links(call: String): String {
        var parts = call.split("\t");
        var operands = parts.count == 4 ? ulong.parse(parts[2]) : Optional<ulong>.Empty;
        var results = parts.count == 4 ? ulong.parse(parts[3]) : Optional<ulong>.Empty;
        if (!operands.is_value() or !results.is_value()) {
            return "";
        }
        return dispatch_summary(dispatched_call(call), operands.value(), results.value()).links();
    }

    ## The keys of method `method` of every struct that implements trait
    ## `trait_name`, by struct name: what a call through the trait may
    ## reach.
    dispatched(trait_name: String, method: String): String[] {
        var memo = $"{trait_name}\t{method}";
        var known = _dispatch.try_get(memo);
        if (known.is_value()) {
            return known.value();
        }
        var keys = Array<String>();
        for (var owner in _dispatch_owners(implementors(), trait_name, method)) {
            keys.append(method_key(owner, method));
        }
        _dispatch[memo] = keys;
        return keys;
    }

    ## The keys of the implementations a trait call of a summary's
    ## `dispatched` may reach.
    dispatched_call(call: String): String[] {
        var parts = call.split("\t");
        return parts.count < 2 ? Array<String>() : dispatched(parts[0], parts[1]);
    }

    ## The function a summary key names: a compiled body, or a checked one
    ## `restore` brought back.
    function_of(key: String): FunctionDef? {
        var body = _by_key().try_get(key);
        if (body.is_value()) {
            return Optional<FunctionDef>.Value(body.value().function);
        }
        return Optional<FunctionDef>.Empty;
    }

    ## Puts back the stashed body of the checked function `key` names, so
    ## its summary can be made; none when there is no such body. A body put
    ## back before comes back again.
    restore(key: String): _Body? {
        var none = Optional<_Body>.Empty;
        var restored = _restored.try_get(key);
        if (restored.is_value()) {
            return restored;
        }
        if (!has_stashed(state)) {
            return none;
        }
        var found = _stashed(key);
        if (!found.is_value()) {
            return none;
        }
        var (body, stash_key) = found.value();
        var stashed = take_stashed(state, stash_key);
        if (!stashed.is_value()) {
            return none;
        }
        body.function.body = stashed;
        state.trait_memo.bodies_back = true;
        _by_key()[key] = body;
        _restored[key] = body;
        bodies.insert(key);
        return Optional<_Body>.Value(body);
    }

    # Where the function `key` names starts, compiled or checked.
    _function_start(key: String): ulong? {
        var function = function_of(key);
        if (function.is_value()) {
            return Optional<ulong>.Value(function.value().loc.span.start);
        }
        var stashed = _stashed(key);
        if (!stashed.is_value()) {
            return Optional<ulong>.Empty;
        }
        var (body, _) = stashed.value();
        return Optional<ulong>.Value(body.function.loc.span.start);
    }

    # The checked function `key` names, as a body with its stash key.
    _stashed(key: String): (_Body, String)? {
        var none = Optional<(_Body, String)>.Empty;
        var known = _stashed_bodies.try_get(key);
        if (known.is_value()) {
            return known;
        }
        var newline = key.find("\n");
        if (newline < 0) {
            var f = functions.try_get(key);
            if (!f.is_value() or !is_checked_function(module, f.value())) {
                return none;
            }
            var found = (_Body(Optional<TypeName>.Empty, key, f.value()), $"f {key}");
            _stashed_bodies[key] = found;
            return Optional<(_Body, String)>.Value(found);
        }
        var owner = key.substr_bytes(0, newline as ulong);
        var method = key.substr_bytes(newline as ulong + 1, key.size - newline as ulong - 1);
        var st = method == "__ctor" ? constructor_structs.try_get(owner) : structs.try_get(owner);
        if (!st.is_value() or !module.checked.structs.contains(st.value().name) or _is_generic_base(st.value())) {
            return none;
        }
        var ty = Optional<TypeName>.Value(TypeName.named(st.value().name));
        var found = Optional<(_Body, String)>.Empty;
        if (method == "__ctor") {
            for (var c in st.value().constructors) {
                if (c.name == owner) {
                    found = Optional<(_Body, String)>.Value(
                        (_Body(ty, key, c), $"m {st.value().name} constructor {c.name}")
                    );
                }
            }
        } else {
            for (var m in st.value().method_members) {
                if (!m.is_generic_func and m.name == method) {
                    found = Optional<(_Body, String)>.Value(
                        (_Body(ty, key, m), $"m {st.value().name} method {m.name}")
                    );
                }
            }
        }
        if (found.is_value()) {
            _stashed_bodies[key] = found.value();
        }
        return found;
    }

    # Every body by key: the compiled ones and those `restore` brought back.
    _by_key(): HashMap<String, _Body> {
        if (!_known_filled) {
            _known_filled = true;
            for (var body in all) {
                _known[body.key] = body;
            }
        }
        return _known;
    }

    ## The structs implementing each trait, by trait name.
    implementors(): HashMap<String, StructDef[]> {
        if (!_implementors.is_value()) {
            _implementors = Optional<HashMap<String, StructDef[]>>.Value(_implementors_of(module));
        }
        return _implementors.value();
    }

    is_isolated(ty: TypeName): bool {
        return isolated.count > 0 and isolated.contains(ty.to_string());
    }

    ## Whether values of `ty` belong to regions: references to structs that
    ## are not thread-safe, plain function values, weak references to
    ## those, and raw pointers.
    has_region(ty: TypeName): bool {
        var key = ty.to_string();
        var known = region_types.try_get(key);
        if (known.is_value()) {
            return known.value();
        }
        bool answer = false;
        if (!(ty.is_empty() or ty.is_auto() or ty.name == "void" or is_isolated(ty))) {
            answer = ty.is_pointer() or unsafe_part_in(ty, safe).is_value();
        }
        region_types[key] = answer;
        return answer;
    }

    ## Whether `file` is part of the runtime: under the directory of the
    ## runtime's first file. With no runtime or no name for the file,
    ## everything is.
    is_runtime_file(file: uint): bool {
        if (!runtime_files.is_value()) {
            runtime_files = Optional<bool[]>.Value(_runtime_files(state));
        }
        var known = runtime_files.value();
        return (file as ulong) >= known.count or known[file as ulong];
    }

    struct_named(name: String): StructDef? {
        return structs.try_get(name);
    }

    is_trait(ty: TypeName): bool {
        return traits.contains(ty.name);
    }
}

# The structs implementing each trait of `module`, by trait name.
_implementors_of(module: Module): HashMap<String, StructDef[]> {
    var out = HashMap<String, StructDef[]>();
    for (var candidate in module.structs) {
        var seen = HashSet<String>();
        for (var t in candidate.traits) {
            if (!seen.insert(t.name)) {
                continue;
            }
            var list = out.try_get(t.name);
            if (!list.is_value()) {
                out[t.name] = Array<StructDef>();
                list = out.try_get(t.name);
            }
            list.value().append(candidate);
        }
    }
    return out;
}

# The names of the structs a call of `method` through trait `trait_name`
# may reach.
_dispatch_owners(implementors: HashMap<String, StructDef[]>, trait_name: String, method: String): String[] {
    var out = Array<String>();
    var list = implementors.try_get(trait_name);
    if (!list.is_value()) {
        return out;
    }
    for (var candidate in list.value()) {
        if (_method_named(candidate, method).is_value()) {
            out.append(candidate.name);
        }
    }
    # By name: units checked later may add specializations in another order.
    out.sort((a: String, b: String) => a < b ? -1 : (a > b ? 1 : 0));
    return out;
}

## The settled summaries `program` decoded that no longer hold: a call
## through a trait value they reach now joins other summaries than they
## were made with (a struct implementing the trait since, or an
## implementation summarized again). Summarizes first every
## implementation those calls reach that has no summary yet.
##
## @param program the pass's view of the program, its summaries made
## @returns their keys, in the order decoded
_stale(program: _Confinement): String[] {
    # Every implementation the decoded ones' calls reach, with a summary
    # (decoding more of them on the way, which are checked in turn).
    ulong done = 0;
    var seen = HashSet<String>();
    while (done < program.tentative.count) {
        var missing = Array<String>();
        while (done < program.tentative.count) {
            var summary = program.summaries[program.tentative[done]];
            done += 1;
            for (var (call, _) in summary.dispatched) {
                if (!seen.insert(call)) {
                    continue;
                }
                for (var key in program.dispatched_call(call)) {
                    if (!program.summary(key).is_value()) {
                        missing.append(key);
                    }
                }
            }
        }
        if (missing.count > 0) {
            _summaries(program, missing);
        }
    }
    var out = Array<String>();
    var joins = HashMap<String, String>();
    for (var key in program.tentative) {
        for (var (call, links) in program.summaries[key].dispatched) {
            var now = joins.try_get(call);
            if (!now.is_value()) {
                var joined = program.joined_links(call);
                joins[call] = joined;
                now = Optional<String>.Value(joined);
            }
            if (now.value() != links) {
                out.append(key);
                break;
            }
        }
    }
    return out;
}

## Whether each of the program's files is under the runtime's directory.
_runtime_files(state: PassState): bool[] {
    var out = Array<bool>();
    var runtime = Runtime.discover();
    String? directory = Optional<String>.Empty;
    if (runtime.sources.count > 0) {
        var parent = runtime.sources[0].parent();
        if (parent.is_value()) {
            var real = parent.value().canonicalize();
            if (real.is_ok()) {
                directory = Optional<String>.Value(real.value().to_string());
            }
        }
    }
    for (var source in state.sources) {
        if (!directory.is_value()) {
            out.append(true);
            continue;
        }
        var real = absolute(Path(source.name)).canonicalize();
        if (!real.is_ok()) {
            out.append(false);
            continue;
        }
        var path = real.value().to_string();
        var dir = directory.value();
        out.append(path == dir or path.starts_with(dir + "/") or path.starts_with(dir + "\\"));
    }
    return out;
}

## Whether the function or method with summary key `key` (a function's
## name, or `Struct.method`) returns a fresh value: one that shares nothing
## with its inputs, so it may move into a locked value or be passed to a
## `[Move]` parameter. For the language server's hover.
##
## @param module the checked model
## @param target the compile target
## @param key the summary key
## @returns empty when it has no body or returns a value of a thread-safe
##     type, which crosses freely anyway
export returns_fresh(module: Module, target: Target, key: String): bool? {
    var none = Optional<bool>.Empty;
    var program = _Confinement(module, PassState(target));
    var found = Optional<_Body>.Empty;
    for (var body in program.all) {
        if (body.key == key) {
            found = Optional<_Body>.Value(body);
            break;
        }
    }
    if (found.is_empty() or !program.has_region(found.value().function.ty)) {
        return none;
    }
    _summaries(program, [key]);
    var stale = _stale(program);
    while (stale.count > 0) {
        for (var dropped in stale) {
            program.dropped.insert(dropped);
        }
        program.reset();
        _summaries(program, [key]);
        stale = _stale(program);
    }
    var summary = program.summary(key);
    if (summary.is_empty()) {
        return none;
    }
    var s = summary.value();
    ulong n = 0;
    while (n < s.results()) {
        if (!s.fresh_at(n)) {
            return Optional<bool>.Value(false);
        }
        n += 1;
    }
    return Optional<bool>.Value(true);
}

# Whether `body` belongs to a checked unit.
_is_checked(module: Module, body: _Body): bool {
    if (body.owner.is_value()) {
        return module.checked.structs.contains(body.owner.value().name);
    }
    return module.checked.functions.contains(body.function.name);
}

## Every compiled function body: free functions, then each struct's
## methods and constructors.
_bodies(module: Module): Array<_Body> {
    var out = Array<_Body>();
    var none = Optional<TypeName>.Empty;
    for (var f in module.functions) {
        if (!f.is_generic_func and f.body.is_value()) {
            out.append(_Body(none, f.name, f));
        }
    }
    for (var st in module.structs) {
        if (_is_generic_base(st)) {
            continue;
        }
        var owner = Optional<TypeName>.Value(TypeName.named(st.name));
        for (var m in st.method_members) {
            if (!m.is_generic_func and m.body.is_value()) {
                out.append(_Body(owner, method_key(st.name, m.name), m));
            }
        }
        for (var c in st.constructors) {
            if (c.body.is_value()) {
                out.append(_Body(owner, method_key(c.name, "__ctor"), c));
            }
        }
    }
    return out;
}

## The recorded summaries of a checked runtime's functions and of the
## functions whose bodies were skipped, by summary key.
_recorded(module: Module): HashMap<String, (Loc, String)> {
    var out = HashMap<String, (Loc, String)>();
    if (module.recorded_summaries.count == 0) {
        return out;
    }
    for (var f in module.functions) {
        _seed(module, out, Optional<String>.Empty, f);
    }
    for (var st in module.structs) {
        for (var m in st.method_members) {
            _seed(module, out, Optional<String>.Value(st.name), m);
        }
    }
    return out;
}

_seed(module: Module, out: HashMap<String, (Loc, String)>, owner: String?, function: FunctionDef) {
    if (function.body.is_value()) {
        return;
    }
    var text = module.recorded_summaries.try_get(function.loc);
    if (!text.is_value()) {
        return;
    }
    out[owner.is_value() ? method_key(owner.value(), function.name) : function.name] = (function.loc, text.value());
}

## Records the summary of every function the build cache may skip the
## body of later: each non-generic function and method at its own
## location, whose summary does not depend on the rest of the program.
_record_summaries(program: _Confinement) {
    var keys = Array<String>();
    for (var body in program.all) {
        keys.append(body.key);
    }
    _summaries(program, keys);
    var at = HashMap<Loc, String?>();
    var order = Array<Loc>();
    for (var body in program.all) {
        var function = body.function;
        if (function.loc.is_none()
            or !function.owner.is_none()
            or body.key.contains("<")
            or body.key.ends_with("\n__ctor")) {
            continue;
        }
        String? text = Optional<String>.Empty;
        var summary = program.summary(body.key);
        if (summary.is_value() and !summary.value().dependent()) {
            text = Optional<String>.Value(summary.value().encode());
        }
        if (at.contains(function.loc)) {
            at[function.loc] = Optional<String>.Empty;
        } else {
            at[function.loc] = text;
            order.append(function.loc);
        }
    }
    var out = Array<(Loc, String)>();
    for (var loc in order) {
        var text = at[loc];
        if (text.is_value()) {
            out.append((loc, text.value()));
        }
    }
    out.sort(_compare_recorded);
    program.recorded_out = out;
}

## Keeps every summary the passes made of a function not settled before,
## by key: what a checked unit records for the units checked on top of it.
## A summary that calls through a trait keeps the joined summary each such
## call was made with (`_Summary.settled_text`), and holds where those
## joins are the same.
_settle(program: _Confinement) {
    for (var (key, summary) in program.summaries) {
        if (program.is_settled(key)) {
            continue;
        }
        var function = program.function_of(key);
        if (!function.is_value()) {
            continue;
        }
        var blame = summary.blame.is_value() ? summary.blame.value() : function.value().loc;
        program.state.settled_summaries[key] = (blame, summary.settled_text(function.value().loc));
    }
}

_compare_recorded(a: (Loc, String), b: (Loc, String)): int {
    var (x, _) = a;
    var (y, _) = b;
    if (x.file != y.file) {
        return x.file < y.file ? -1 : 1;
    }
    if (x.span.start != y.span.start) {
        return x.span.start < y.span.start ? -1 : 1;
    }
    return 0;
}

## The number of operand slots of `function`: `this` (for a non-static
## method) and its parameters.
_slots(body: _Body): ulong {
    var this_slot = body.owner.is_value() and !body.function.is_static and !body.key.ends_with("\n__ctor");
    return body.function.parameters.count + (this_slot ? 1 : 0);
}

## Summarizes one function with the current summaries, and the keys of the
## functions it calls.
_summarize(program: _Confinement, body: _Body): (_Summary, String[]) {
    var function = body.function;
    var n = _slots(body);
    var results = _result_slots(function.ty);
    var walk = _RegionWalk(program, false, body.owner);
    # A constructor's `this` is the object it builds: a local of its body.
    walk.function(function, function.is_static or body.key.ends_with("\n__ctor"), true);
    var result = Array<long>();
    ulong k = 0;
    while (k < results) {
        result.append(-1);
        k += 1;
    }
    Loc? blame = Optional<Loc>.Empty;
    for (var returned in walk.returns) {
        var value = returned.region;
        if (value < 0) {
            continue;
        }
        var parts = walk.parts_of(value);
        var elements = Array<Array<long>>();
        if (results > 1 and parts.count == results) {
            for (var p in parts) {
                elements.append(p >= 0 ? walk.leaves(p) : Array<long>());
            }
        } else {
            var leaves = walk.leaves(value);
            k = 0;
            while (k < results) {
                elements.append(leaves);
                k += 1;
            }
        }
        ulong slot = 0;
        while (slot < elements.count) {
            for (var leaf in elements[slot]) {
                var root = walk.find(leaf);
                var region = walk.regions[root as ulong];
                if ((region.tainted or region.operands.count > 0) and !blame.is_value()) {
                    blame = Optional<Loc>.Value(returned.loc);
                }
                if (result[slot] >= 0) {
                    var joined = walk.union(result[slot], leaf);
                    result[slot] = joined >= 0 ? joined : result[slot];
                } else {
                    result[slot] = leaf;
                }
            }
            slot += 1;
        }
    }
    var summary = _bottom(n, results);
    var roots = Array<long>();
    ulong slot = 0;
    while (slot < n) {
        var r = slot < walk.operands.count ? walk.operands[slot] : -1;
        roots.append(r >= 0 ? walk.find(r) : -1);
        slot += 1;
    }
    slot = 0;
    while (slot < n) {
        if (roots[slot] >= 0) {
            ulong s = 0;
            while (roots[s] != roots[slot]) {
                s += 1;
            }
            summary.classes[slot] = s;
        }
        slot += 1;
    }
    var result_roots = Array<long>();
    for (var r in result) {
        result_roots.append(r >= 0 ? walk.find(r) : -1);
    }
    k = 0;
    while (k < results) {
        var root = result_roots[k];
        if (root >= 0) {
            bool placed = false;
            slot = 0;
            while (slot < n) {
                if (roots[slot] == root) {
                    summary.classes[n + k] = summary.classes[slot];
                    placed = true;
                    break;
                }
                slot += 1;
            }
            if (!placed) {
                ulong j = 0;
                while (j < k) {
                    if (result_roots[j] == root) {
                        summary.classes[n + k] = summary.classes[n + j];
                        break;
                    }
                    j += 1;
                }
            }
            summary.tainted[k] = walk.regions[root as ulong].tainted;
        }
        k += 1;
    }
    summary.blame = blame;
    # The joins of its own trait calls, and those its callees by name were
    # made with: an implementation's reach the caller only through its
    # call's join.
    summary.dispatched = walk.dispatched;
    for (var key in walk.named) {
        var known = program.summary(key);
        if (!known.is_value()) {
            continue;
        }
        # Their joins as they are now: one made earlier in the fixed point
        # may be below it.
        for (var (call, _) in known.value().dispatched) {
            if (!summary.dispatched.contains(call)) {
                summary.dispatched[call] = program.joined_links(call);
            }
        }
    }
    return (summary, walk.called);
}

## The link summaries of the functions `roots` reach, as a least fixed
## point: a worklist that summarizes each function once its callees'
## summaries are known, and again when one of them changes.
_summaries(program: _Confinement, roots: String[]) {
    var all = HashMap<String, _Body>();
    for (var body in program.all) {
        all[body.key] = body;
    }
    var callers = HashMap<String, Array<String>>();
    # Each callee and caller pair in `callers`.
    var linked = HashSet<String>();
    var queue = Array<String>();
    var queued = HashSet<String>();
    for (var key in roots) {
        var body = all.try_get(key);
        if (!body.is_value() and !program.is_settled(key)) {
            # A checked implementation `_stale` needs the summary of.
            body = program.restore(key);
            if (body.is_value()) {
                all[key] = body.value();
            }
        }
        if (!body.is_value() or program.is_settled(key) or queued.contains(key)) {
            continue;
        }
        queued.insert(key);
        program.summaries[key] = _bottom(_slots(body.value()), _result_slots(body.value().function.ty));
        queue.append(key);
    }
    var count = all.count > 0 ? all.count : 1;
    var budget = _MAX_ROUNDS * count;
    ulong head = 0;
    while (head < queue.count) {
        var key = queue[head];
        head += 1;
        queued.remove(key);
        if (budget == 0) {
            break;
        }
        budget -= 1;
        var (summary, called) = _summarize(program, all[key]);
        for (var callee in called) {
            var callee_body = all.try_get(callee);
            if (!callee_body.is_value() and !program.is_settled(callee)) {
                # A checked function no summary settled: its body comes
                # back from the stash, for its summary only.
                callee_body = program.restore(callee);
                if (callee_body.is_value()) {
                    all[callee] = callee_body.value();
                }
            }
            if (!callee_body.is_value()) {
                continue;
            }
            var list = callers.try_get(callee);
            if (!list.is_value()) {
                callers[callee] = Array<String>();
                list = callers.try_get(callee);
            }
            if (linked.insert($"{callee}\t{key}")) {
                list.value().append(key);
            }
            if (!program.summary(callee).is_value()) {
                program.summaries[callee] = _bottom(
                    _slots(callee_body.value()), _result_slots(callee_body.value().function.ty)
                );
                queued.insert(callee);
                queue.append(callee);
            }
        }
        var before = program.summary(key);
        var changed = !before.is_value() or !before.value().same_links(summary);
        program.summaries[key] = summary;
        if (changed) {
            var waiting = callers.try_get(key);
            if (waiting.is_value()) {
                for (var caller in waiting.value().copy()) {
                    if (!queued.contains(caller)) {
                        queued.insert(caller);
                        queue.append(caller);
                    }
                }
            }
        }
    }
}

## Whether any parameter of `function` has attribute `name`.
_has_parameter_attribute(function: FunctionDef, name: String): bool {
    for (var p in function.parameters) {
        if (ast.has_attribute(p.attributes, name)) {
            return true;
        }
    }
    return false;
}

## The functions whose checks need summaries: those with a `with` block or
## a `move`, or a call to a function with a `[Move]` parameter (by name,
## generously); and the closures passed to a `[Locked]` parameter.
_roots(program: _Confinement): String[] {
    var module = program.module;
    var sending = HashSet<String>();
    var locked = HashSet<String>();
    for (var st in module.structs) {
        for (var c in st.constructors) {
            if (_has_parameter_attribute(c, MOVE_ATTRIBUTE)) {
                sending.insert(st.name);
                sending.insert(c.name);
            }
        }
        for (var m in st.method_members) {
            if (_has_parameter_attribute(m, MOVE_ATTRIBUTE)) {
                sending.insert(m.name);
            }
            if (_has_parameter_attribute(m, LOCKED_ATTRIBUTE)) {
                locked.insert(m.name);
            }
        }
    }
    for (var f in module.functions) {
        if (_has_parameter_attribute(f, MOVE_ATTRIBUTE)) {
            sending.insert(f.name);
        }
        if (_has_parameter_attribute(f, LOCKED_ATTRIBUTE)) {
            locked.insert(f.name);
        }
    }
    var out = Array<String>();
    for (var body in program.all) {
        if (program.is_settled(body.key) or !body.function.body.is_value()) {
            continue;
        }
        var finder = _RootFinder(sending, locked);
        rewrite_block(body.function.body.value(), finder);
        if (finder.found) {
            out.append(body.key);
        }
        for (var closure in finder.closures) {
            out.append(closure);
        }
    }
    return out;
}

struct _RootFinder {
    var sending: HashSet<String>;
    var locked: HashSet<String>;
    var found: bool = false;
    var closures: Array<String> = Array<String>();

    construct(sending: HashSet<String>, locked: HashSet<String>) {
        this.sending = sending;
        this.locked = locked;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            SymbolRef(node) => {
                if (node.id.starts_with("__with_scope_")) {
                    found = true;
                }
            }
            Move(node) => {
                found = true;
            }
            FunctionCall(node) => {
                call(node.function, node.args);
            }
            MethodCall(node) => {
                call(node.method, node.args);
            }
            else => {}
        }
        return e;
    }

    call(function: String, args: Expression[]) {
        if (sending.contains(function)) {
            found = true;
        }
        if (locked.contains(function)) {
            for (var a in args) {
                if (a is MakeClosure(node)) {
                    closures.append(method_key(node.closure, CALL_METHOD));
                }
            }
        }
    }
}

extend _RootFinder with Rewriter;

## The names a function must mention for the expression checks to find
## anything: methods that return a guard, guard types, `get`, and callees
## with a `[Move]` or `[Locked]` parameter.
_triggers(program: _Confinement): HashSet<String> {
    var names = HashSet<String>();
    names.insert("get");
    for (var st in program.module.structs) {
        if (program.isolated.contains(st.name)) {
            names.insert(st.name);
        }
        for (var m in st.method_members) {
            if (program.is_isolated(m.ty)
                or _has_parameter_attribute(m, MOVE_ATTRIBUTE)
                or _has_parameter_attribute(m, LOCKED_ATTRIBUTE)) {
                names.insert(m.name);
            }
        }
        for (var c in st.constructors) {
            if (_has_parameter_attribute(c, MOVE_ATTRIBUTE)) {
                names.insert(st.name);
                names.insert(c.name);
            }
        }
    }
    for (var f in program.module.functions) {
        if (program.is_isolated(f.ty)
            or _has_parameter_attribute(f, MOVE_ATTRIBUTE)
            or _has_parameter_attribute(f, LOCKED_ATTRIBUTE)) {
            names.insert(f.name);
        }
    }
    return names;
}

## Whether `function` calls, constructs or declares anything in `names`.
_mentions(function: FunctionDef, names: HashSet<String>): bool {
    for (var p in function.parameters) {
        if (names.contains(p.ty.to_string())) {
            return true;
        }
    }
    return function.body.is_value() and _block_mentions(function.body.value(), names);
}

_block_mentions(block: Block, names: HashSet<String>): bool {
    for (var statement in block.items) {
        match (statement) {
            Expression(e) => {
                if (_expression_mentions(e, names)) {
                    return true;
                }
            }
            Block(inner) => {
                if (_block_mentions(inner, names)) {
                    return true;
                }
            }
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    if (names.contains(variable.ty.to_string())) {
                        return true;
                    }
                    if (variable.default.is_value() and _expression_mentions(variable.default.value(), names)) {
                        return true;
                    }
                }
            }
            Branch(branch) => {
                if (_expression_mentions(branch.condition, names) or _block_mentions(branch.if_block, names)) {
                    return true;
                }
                if (branch.else_block.is_value() and _block_mentions(branch.else_block.value(), names)) {
                    return true;
                }
            }
            While(loop) => {
                if (_expression_mentions(loop.condition, names) or _block_mentions(loop.block, names)) {
                    return true;
                }
            }
            Return(ret) => {
                if (ret.expr.is_value() and _expression_mentions(ret.expr.value(), names)) {
                    return true;
                }
            }
            else => {}
        }
    }
    return false;
}

_expression_mentions(e: Expression, names: HashSet<String>): bool {
    var stack = Array<Expression>();
    stack.append(e);
    while (stack.count > 0) {
        var next = stack.pop();
        match (next) {
            FunctionCall(node) => {
                if (names.contains(node.function)) {
                    return true;
                }
            }
            MethodCall(node) => {
                if (names.contains(node.method)) {
                    return true;
                }
            }
            else => {}
        }
        for (var child in expression_children(next)) {
            stack.append(child);
        }
    }
    return false;
}

## Wraps each argument to a `[MoveSource]` parameter in a `Move`, so the
## checks treat `move(x)` as moving `x` and codegen hands its reference
## over.
_lower_moved_arguments(module: Module) {
    var moved = HashMap<String, bool[]>();
    for (var f in module.functions) {
        if (f.is_generic_func or !_has_parameter_attribute(f, MOVE_SOURCE_ATTRIBUTE)) {
            continue;
        }
        var flags = Array<bool>();
        for (var p in f.parameters) {
            flags.append(ast.has_attribute(p.attributes, MOVE_SOURCE_ATTRIBUTE));
        }
        moved[f.name] = flags;
    }
    if (moved.count == 0) {
        return;
    }
    var lower = _MoveArguments(moved);
    # A checked body was lowered with its unit (and is stashed).
    var own = unit_decls(module);
    for (var f in own.functions) {
        lower.function(f);
    }
    for (var st in own.structs) {
        if (_is_generic_base(st)) {
            continue;
        }
        for (var m in st.method_members) {
            lower.function(m);
        }
        for (var c in st.constructors) {
            lower.function(c);
        }
        lower.function(st.destructor);
    }
}

struct _MoveArguments {
    var moved: HashMap<String, bool[]>;

    construct(moved: HashMap<String, bool[]>) {
        this.moved = moved;
    }

    function(f: FunctionDef) {
        if (!f.is_generic_func and f.body.is_value()) {
            rewrite_block(f.body.value(), this);
        }
    }

    rewrite(e: Expression): Expression {
        if (e is FunctionCall(node)) {
            var flags = moved.try_get(node.function);
            if (flags.is_value()) {
                ulong i = 0;
                while (i < node.args.count and i < flags.value().count) {
                    if (flags.value()[i] and !_is_move(node.args[i])) {
                        node.args[i] = Expression.Move(MoveExpression(node.args[i], node.loc));
                    }
                    i += 1;
                }
            }
        }
        return e;
    }
}

extend _MoveArguments with Rewriter;

_is_move(e: Expression): bool {
    match (e) {
        Move(node) => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## An error at `loc`, or at no location when `loc` is none.
_error_at_known(message: String, loc: Loc): Diagnostic {
    var out = Diagnostic.error(message);
    return loc.is_none() ? out : out.at(location_of(loc));
}

## A parameter takes `[Move]`, `[Locked]` in the runtime, or `[MoveSource]`
## on a runtime free function's parameter only. Any other parameter
## attribute is an error.
_check_parameter_attributes(program: _Confinement): bool {
    # The declarations checked with a unit below were checked with it.
    var decls = unit_decls(program.module);
    var functions = Array<(FunctionDef, bool)>();
    for (var f in decls.functions) {
        functions.append((f, true));
    }
    for (var st in decls.structs) {
        for (var m in st.method_members) {
            functions.append((m, false));
        }
        for (var c in st.constructors) {
            functions.append((c, false));
        }
        for (var m in st.generic_methods) {
            functions.append((m, false));
        }
    }
    for (var (function, free) in functions) {
        for (var p in function.parameters) {
            for (var attribute in p.attributes) {
                var at = Loc.at(function.loc.file, attribute.span);
                var name = "";
                if (attribute.body is SymbolRef(id, _)) {
                    name = id;
                }
                if (name == MOVE_ATTRIBUTE) {
                    continue;
                }
                # An empty `[__Lazy]` argument arrives at a `[__Reads]`
                # parameter as null (an internal of the runtime's copies).
                if (name == READS_ATTRIBUTE) {
                    continue;
                }
                if (name == LOCKED_ATTRIBUTE) {
                    if (program.is_runtime_file(function.loc.file)) {
                        continue;
                    }
                    program.state.report(
                        _error_at_known(
                            $"'[{LOCKED_ATTRIBUTE}]' is only allowed in the runtime",
                            at
                        ).with_note(
                            "a function that reads a locked value runs inside a 'with' block", Optional<Location>.Empty
                        )
                    );
                    return true;
                }
                if (name != MOVE_SOURCE_ATTRIBUTE) {
                    var error = _error_at_known(
                        $"unknown parameter attribute '{_attribute_text(program, at)}'", at
                    ).with_note($"a parameter takes '[{MOVE_ATTRIBUTE}]'", Optional<Location>.Empty);
                    if (name == "Sending") {
                        error = error.with_fix(
                            Fix(
                                $"Replace '[Sending]' with '[{MOVE_ATTRIBUTE}]'", location_of(at), $"[{MOVE_ATTRIBUTE}]"
                            )
                        );
                    }
                    program.state.report(error);
                    return true;
                }
                if (!program.is_runtime_file(function.loc.file)) {
                    program.state.report(
                        _error_at_known(
                            $"'[{MOVE_SOURCE_ATTRIBUTE}]' is only allowed in the runtime",
                            at
                        ).with_note(
                            "take the value with '[Move]', and have callers pass 'move(x)'", Optional<Location>.Empty
                        )
                    );
                    return true;
                }
                if (!free) {
                    program.state.report(
                        _error_at_known(
                            $"'[{MOVE_SOURCE_ATTRIBUTE}]' is only supported on a free function's parameter", at
                        )
                    );
                    return true;
                }
            }
        }
    }
    return false;
}

## The source text at `loc`, or `?` when it is not available.
_attribute_text(program: _Confinement, loc: Loc): String {
    var file = loc.file as ulong;
    if (file >= program.state.sources.count) {
        return "?";
    }
    var text = program.state.sources[file].text;
    if (loc.span.end > text.size or loc.span.start > loc.span.end) {
        return "?";
    }
    return text.substr_bytes(loc.span.start, loc.span.end - loc.span.start);
}

## A guard kept in a struct's field would hold its lock past any block.
_check_guard_fields(program: _Confinement): bool {
    # A checked struct's fields were checked with its unit.
    for (var st in unit_decls(program.module).structs) {
        if (program.isolated.contains(st.name) or _is_generic_base(st)) {
            continue;
        }
        for (var field in st.field_members) {
            if (!program.is_isolated(field.ty)) {
                continue;
            }
            var at = !field.type_loc.is_none() ? field.type_loc : (!field.loc.is_none() ? field.loc : st.loc);
            program.state.report(
                _error_at_known(
                    $"'{field.ty.display()}' can only be the scope of a 'with' block",
                    at
                ).with_note(
                    "a guard kept in a field would hold its lock past the block; lock where the value is used",
                    Optional<Location>.Empty
                )
            );
            return true;
        }
    }
    return false;
}

## `Mutex<T>` of a number: its `with` binding would be a copy the block
## could never change back.
_check_mutex_arguments(program: _Confinement): bool {
    # A checked specialization was checked with its unit.
    for (var st in unit_decls(program.module).structs) {
        if (st.ty.sub_types.count == 0 or demangle_name(st.ty.name) != "Mutex" or st.name == st.ty.name) {
            continue;
        }
        var argument = st.ty.sub_types[0];
        bool locks = false;
        for (var m in st.method_members) {
            if (m.name == "lock" and program.is_isolated(m.ty)) {
                locks = true;
            }
        }
        if (!locks or !(argument.is_integral() or argument.is_pointer())) {
            continue;
        }
        var site = use_site(program.module, st.name);
        var at = site.is_value() ? site.value() : st.loc;
        program.state.report(
            _error_at_known(
                $"'{st.ty.display()}' cannot protect a number: its 'with' binding is a copy that the block cannot store back",
                at
            ).with_note(
                $"use 'async.Atomic<{argument.display()}>' for a number that threads share", Optional<Location>.Empty
            )
        );
        return true;
    }
    return false;
}

## Every check on one function; the first error.
_check_function(program: _Confinement, owner: TypeName?, function: FunctionDef, regions: bool): Diagnostic? {
    var exempt = (owner.is_value() and program.is_isolated(owner.value())) or program.is_isolated(function.ty);
    var is_static = function.is_static or function.name == (owner.is_value() ? owner.value().to_string() : "");
    if (regions) {
        var walk = _RegionWalk(program, true, owner);
        walk.function(function, is_static, true);
        if (walk.error.is_value()) {
            return walk.error;
        }
        if (function.body.is_value()) {
            var moves = _Moves(_MoveFailure());
            moves.block(function.body.value());
            if (moves.failure.error.is_value()) {
                return moves.failure.error;
            }
        }
    }
    var checks = _Checks(program, _RegionWalk(program, true, owner), exempt);
    checks.walk.function(function, is_static, false);
    if (function.body.is_value()) {
        checks.block(function.body.value());
    }
    return checks.error;
}

## Checks the body of closure struct `closure` (its `__call`) as a `with`
## block's: its parameters are a locked value.
_check_locked_closure(program: _Confinement, closure: String): Diagnostic? {
    var none = Optional<Diagnostic>.Empty;
    var st = program.struct_named(closure);
    if (!st.is_value()) {
        return none;
    }
    for (var m in st.value().method_members) {
        if (m.name == CALL_METHOD) {
            var walk = _RegionWalk(program, true, Optional<TypeName>.Value(st.value().ty));
            walk.locked_parameters = true;
            walk.function(m, false, true);
            return walk.error;
        }
    }
    return none;
}

# ── The walk ─────────────────────────────────────────────────────────────

## The region walk over one function: summarizing it (`checking` false,
## operands have their own regions) or checking its `with` blocks
## (operands are outer).
struct _RegionWalk {
    var program: _Confinement;
    var checking: bool;
    var regions: Array<_Region> = Array<_Region>();
    var scopes: Array<Array<_ScopeLocal>> = Array<Array<_ScopeLocal>>();
    var locks: Array<_Lock> = Array<_Lock>();
    ## The lock of each `with` block the walk is inside, innermost last.
    var open: Array<ulong> = Array<ulong>();
    var current: TypeName?;
    var returns: Array<_Returned> = Array<_Returned>();
    ## The region of each operand slot (-1 for none).
    var operands: Array<long> = Array<long>();
    ## The summary keys of the functions the walk called.
    var called: Array<String> = Array<String>();
    ## Those it called by name, not through a trait value.
    var named: Array<String> = Array<String>();
    ## The joined summary of each call through a trait value it made, as
    ## `_Summary.dispatched`.
    var dispatched: HashMap<String, String> = HashMap<String, String>();
    ## The operand slots of `[Move]` parameters (summaries).
    var sending: Array<ulong> = Array<ulong>();
    ## Walking a `[Locked]` closure's body: its parameters are the locked
    ## value.
    var locked_parameters: bool = false;
    var error: Diagnostic? = Optional<Diagnostic>.Empty;
    ## Which parts the last failed `union` would have joined.
    var clash_into: _RegionPart = _RegionPart.Fresh;
    var clash_moving: _RegionPart = _RegionPart.Fresh;
    ## How many `move`s the walk has checked.
    var moves: ulong = 0;
    ## How many loops the walk is inside.
    var loops: ulong = 0;
    ## On a loop's second pass, the lock its first pass made for the next
    ## `with` block, which stays the same lock.
    var relock: ulong = 0;
    var relocking: bool = false;

    construct(program: _Confinement, checking: bool, current: TypeName?) {
        this.program = program;
        this.checking = checking;
        this.current = current;
        scopes.append(Array<_ScopeLocal>());
    }

    region(part: _RegionPart): long {
        var r = _Region(regions.count, part);
        if (part is Operand(slot)) {
            r.operands.append(slot);
        }
        regions.append(r);
        return (regions.count - 1) as long;
    }

    fresh(): long {
        return region(_RegionPart.Fresh);
    }

    ## A tuple value whose elements are in `parts`.
    tuple(parts: long[]): long {
        var r = fresh();
        regions[r as ulong].parts = parts;
        return r;
    }

    parts_of(x: long): long[] {
        return regions[find(x) as ulong].parts;
    }

    ## The regions a value is made of: its own, or its elements'.
    leaves(x: long): Array<long> {
        var out = Array<long>();
        var parts = parts_of(x);
        if (parts.count == 0) {
            out.append(x);
            return out;
        }
        for (var p in parts) {
            if (p >= 0) {
                for (var leaf in leaves(p)) {
                    out.append(leaf);
                }
            }
        }
        return out;
    }

    find(x: long): long {
        var root = x as ulong;
        while (regions[root].parent != root) {
            root = regions[root].parent;
        }
        var at = x as ulong;
        while (regions[at].parent != root) {
            var next = regions[at].parent;
            regions[at].parent = root;
            at = next;
        }
        return root as long;
    }

    part_of(x: long): _RegionPart {
        return regions[find(x) as ulong].part;
    }

    ## Links two regions: the root, or -1 when they are parts that must
    ## stay apart (`clash_into` and `clash_moving` say which).
    union(into: long, moving: long): long {
        var a = find(into);
        var b = find(moving);
        if (a == b) {
            return a;
        }
        var ra = regions[a as ulong];
        var rb = regions[b as ulong];
        var pa = ra.part;
        var pb = rb.part;
        _RegionPart part = pa;
        if (_is_fresh_part(pa)) {
            part = pb;
        } else if (_is_fresh_part(pb)) {
            part = pa;
        } else if (_is_operand_part(pa) and _is_operand_part(pb)) {
            part = pa;
        } else if (!_same_part(pa, pb)) {
            clash_into = pa;
            clash_moving = pb;
            return -1;
        }
        rb.parent = a as ulong;
        ra.part = part;
        ra.tainted = ra.tainted or rb.tainted;
        ra.untracked = ra.untracked or rb.untracked;
        for (var slot in rb.operands) {
            ra.operands.append(slot);
        }
        rb.operands = Array<ulong>();
        ra.shared = ra.shared or rb.shared;
        return a;
    }

    ## Links `moving` (the region of `e`) into `into`, reporting a clash at
    ## `e`.
    link(into: long, moving: long, e: Expression): long {
        if (into >= 0 and moving >= 0) {
            # Tuples link element by element, or, against a single value,
            # every element with it.
            var pa = parts_of(into);
            var pb = parts_of(moving);
            if (pa.count > 0 or pb.count > 0) {
                if (pa.count == pb.count) {
                    ulong i = 0;
                    while (i < pa.count) {
                        link(pa[i], pb[i], e);
                        i += 1;
                    }
                } else if (pa.count == 0) {
                    for (var y in pb) {
                        link(into, y, e);
                    }
                } else {
                    for (var x in pa) {
                        link(x, moving, e);
                    }
                }
                return into;
            }
            var root = union(into, moving);
            if (root < 0) {
                clash(clash_into, clash_moving, e);
                return into;
            }
            return root;
        }
        return into >= 0 ? into : moving;
    }

    report(diagnostic: Diagnostic) {
        if (!error.is_value()) {
            error = Optional<Diagnostic>.Value(diagnostic);
        }
    }

    clash(into: _RegionPart, moving: _RegionPart, e: Expression) {
        var what = _describe(e);
        var found = ty(e);
        var spelled = found.is_value() ? found.value().display() : "value";
        var a = _locked_index(into);
        var b = _locked_index(moving);
        var message = "";
        var lock_loc = Loc.none();
        var advice = "";
        if (a >= 0 and b < 0) {
            var lock = locks[a as ulong];
            message = $"'{what}' cannot move into the value locked by '{lock.name}'";
            lock_loc = lock.loc;
            advice = $"'{spelled}' is not thread-safe, so the locked value cannot share it with the rest of the program; pass 'copy({what})'";
        } else if (a < 0 and b >= 0) {
            var lock = locks[b as ulong];
            message = $"'{what}' is part of the value locked by '{lock.name}' and cannot outlive the lock";
            lock_loc = lock.loc;
            advice = $"'{spelled}' is not thread-safe, so no part of the locked value may be kept outside the block; take 'copy({what})'";
        } else if (a >= 0 and b >= 0) {
            var from = locks[b as ulong];
            message = $"'{what}' is part of the value locked by '{from.name}' and cannot move into the value locked by '{locks[a as ulong].name}'";
            lock_loc = from.loc;
            advice = $"'{spelled}' is not thread-safe, so two locked values cannot share it; pass 'copy({what})'";
        } else {
            return;
        }
        report(
            _error_at_known(
                message, _expression_loc(e)
            ).with_note("locked here", known_location(lock_loc)).with_note(advice, Optional<Location>.Empty)
        );
    }

    # ── Types ──

    local(name: String): _ScopeLocal? {
        var s = scopes.count;
        while (s > 0) {
            s -= 1;
            var scope = scopes[s];
            var i = scope.count;
            while (i > 0) {
                i -= 1;
                if (scope[i].name == name) {
                    return Optional<_ScopeLocal>.Value(scope[i]);
                }
            }
        }
        return Optional<_ScopeLocal>.Empty;
    }

    local_region(name: String): long {
        var found = local(name);
        return found.is_value() ? found.value().region : -1;
    }

    ty(e: Expression): TypeName? {
        match (e) {
            SymbolRef(node) => {
                var found = local(node.id);
                if (found.is_value()) {
                    return Optional<TypeName>.Value(found.value().ty);
                }
            }
            ThisRef => {
                var found = local("this");
                if (found.is_value()) {
                    return Optional<TypeName>.Value(found.value().ty);
                }
            }
            # A raw read (`_data[i]`) is typed only in codegen: its pointee.
            Index(node) => {
                var pointee = _pointee(ty(node.lhs));
                if (pointee.is_value()) {
                    return pointee;
                }
            }
            ArrayIndex(node) => {
                var pointee = _pointee(ty(node.lhs));
                if (pointee.is_value()) {
                    return pointee;
                }
            }
            else => {}
        }
        var found = static_type_of(e, program.table, current, program.state);
        if (found.is_value() and found.value().is_auto()) {
            return Optional<TypeName>.Empty;
        }
        return found;
    }

    has_region(e: Expression): bool {
        var found = ty(e);
        return found.is_value() and program.has_region(found.value());
    }

    is_pointer_typed(e: Expression): bool {
        var found = ty(e);
        return found.is_value() and found.value().is_pointer();
    }

    declare(name: String, region: long, declared: TypeName) {
        scopes.last().append(_ScopeLocal(name, region, declared));
    }

    ## Where a local declared now belongs: new, except outside every
    ## `with` block in a check, where it is part of the rest of the
    ## program.
    new_local_region(): long {
        return checking and open.count == 0 ? region(_RegionPart.Outer) : fresh();
    }

    ## A local's region, shaped like its initializer.
    local_like(value: long): long {
        var parts = parts_of(value);
        if (parts.count == 0) {
            return new_local_region();
        }
        var shaped = Array<long>();
        for (var p in parts) {
            shaped.append(p >= 0 ? local_like(p) : -1);
        }
        return tuple(shaped);
    }

    # ── Statements ──

    ## Walks `f`: its operands (`this` unless `is_static`, then the
    ## parameters) are outer in a check, and each its own in a summary.
    ## Walks the body only when `walk_body`.
    function(f: FunctionDef, is_static: bool, walk_body: bool) {
        var names = Array<String>();
        var types = Array<TypeName>();
        if (current.is_value() and !is_static) {
            names.append("this");
            types.append(current.value());
        }
        var first_parameter = names.count;
        for (var p in f.parameters) {
            names.append(p.name);
            types.append(p.ty);
        }
        ulong slot = 0;
        while (slot < names.count) {
            var declared = types[slot];
            # A `[Move]` parameter's value is disconnected on entry.
            var takes = slot >= first_parameter and takes_over(f.parameters[slot - first_parameter].attributes);
            long r = -1;
            if (!program.has_region(declared)) {
                r = -1;
            } else if (locked_parameters and slot >= first_parameter) {
                var parameter = f.parameters[slot - first_parameter];
                var index = locks.count;
                locks.append(_Lock(parameter.name, parameter.loc));
                open.append(index);
                r = region(_RegionPart.Locked(index));
            } else if (takes) {
                r = fresh();
                if (!checking) {
                    regions[r as ulong].operands.append(slot);
                    sending.append(slot);
                }
            } else if (checking) {
                r = region(_RegionPart.Outer);
                regions[r as ulong].shared = true;
            } else {
                r = region(_RegionPart.Operand(slot));
            }
            operands.append(r);
            declare(names[slot], r, declared);
            slot += 1;
        }
        if (walk_body and f.body.is_value()) {
            block(f.body.value());
        }
    }

    block(b: Block) {
        scopes.append(Array<_ScopeLocal>());
        # Only a check tags a locked value; a summary walks the block as
        # written.
        var lock = checking ? isolated_with(b) : Optional<_Lock>.Empty;
        if (lock.is_value()) {
            with_block(b, lock.value());
        } else {
            for (var s in b.items) {
                statement(s);
            }
        }
        scopes.pop();
    }

    ## The lock of a `with` block over an `[Isolated]` guard: the block the
    ## builder lowers `with` to, whose hidden scope local has an
    ## `[Isolated]` type.
    isolated_with(b: Block): _Lock? {
        var none = Optional<_Lock>.Empty;
        var scope = _variable_at(b, 0);
        if (b.items.count != 3 or !scope.is_value() or !_variable_at(b, 1).is_value() or !_branch_at(b, 2).is_value()) {
            return none;
        }
        var variable = scope.value();
        if (!variable.name.starts_with("__with_scope_") or !variable.default.is_value()) {
            return none;
        }
        var guard = variable.default.value();
        var declared = variable.ty;
        if (declared.is_auto()) {
            var found = ty(guard);
            if (!found.is_value()) {
                return none;
            }
            declared = found.value();
        }
        if (!program.is_isolated(declared)) {
            return none;
        }
        if (guard is MethodCall(node)) {
            return Optional<_Lock>.Value(_Lock(_describe(node.this_value), node.loc));
        }
        return Optional<_Lock>.Value(_Lock(_describe(guard), variable.loc));
    }

    with_block(b: Block, lock: _Lock) {
        var scope = _variable_at(b, 0).value();
        var binding = _variable_at(b, 1).value();
        var branch = _branch_at(b, 2).value();
        # The guard expression itself (`names.lock()`) may use outer values.
        if (scope.default.is_value()) {
            eval(scope.default.value());
        }
        declare(scope.name, -1, scope.ty);
        var index = locks.count;
        if (relocking) {
            index = relock;
            relock += 1;
        } else {
            locks.append(lock);
        }
        long r = -1;
        if (program.has_region(binding.ty) or binding.ty.is_auto()) {
            r = region(_RegionPart.Locked(index));
        }
        declare(binding.name, r, binding.ty);
        open.append(index);
        eval(branch.condition);
        block(branch.if_block);
        if (branch.else_block.is_value()) {
            block(branch.else_block.value());
        }
        open.pop();
    }

    statement(s: Statement) {
        if (error.is_value()) {
            return;
        }
        match (s) {
            Expression(e) => {
                eval(e);
            }
            Block(inner) => {
                block(inner);
            }
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    variable_statement(variable);
                }
            }
            Branch(branch) => {
                eval(branch.condition);
                block(branch.if_block);
                if (branch.else_block.is_value()) {
                    block(branch.else_block.value());
                }
            }
            While(loop) => {
                # A link made later in the body is there on the next pass,
                # so a check walks an outermost loop that moves a second
                # time: links only add up, so the first pass made them all.
                var moved = moves;
                var outermost = checking and loops == 0;
                var first_lock = locks.count;
                loops += 1;
                eval(loop.condition);
                block(loop.block);
                if (outermost and moves != moved) {
                    relock = first_lock;
                    relocking = true;
                    eval(loop.condition);
                    block(loop.block);
                    relocking = false;
                }
                loops -= 1;
            }
            Return(ret) => {
                long value = -1;
                if (ret.expr.is_value()) {
                    value = eval(ret.expr.value());
                }
                if (value >= 0 and ret.expr.is_value()) {
                    var locked = locked_leaf(value);
                    if (locked >= 0) {
                        var lock = locks[locked as ulong];
                        var e = ret.expr.value();
                        var what = _describe(e);
                        report(
                            _error_at_known(
                                $"'{what}' is part of the value locked by '{lock.name}' and cannot be returned from the block",
                                _expression_loc(e)
                            ).with_note(
                                "locked here", known_location(lock.loc)
                            ).with_note($"return 'copy({what})' instead", Optional<Location>.Empty)
                        );
                    }
                }
                returns.append(_Returned(value, ret.loc));
            }
            else => {}
        }
    }

    variable_statement(variable: VariableDef) {
        long value = -1;
        if (variable.default.is_value()) {
            value = eval(variable.default.value());
        }
        var declared = variable.ty;
        if (declared.is_auto()) {
            declared = TypeName.auto();
            if (variable.default.is_value()) {
                var found = ty(variable.default.value());
                if (found.is_value()) {
                    declared = found.value();
                }
            }
        }
        if (!program.has_region(declared)) {
            declare(variable.name, -1, declared);
            return;
        }
        var r = value >= 0 ? local_like(value) : new_local_region();
        var joined = r;
        if (value >= 0 and variable.default.is_value()) {
            joined = link(r, value, variable.default.value());
        }
        declare(variable.name, joined, declared);
    }

    ## The lock of the first leaf of `value` that is locked, or -1.
    locked_leaf(value: long): long {
        for (var leaf in leaves(value)) {
            var n = _locked_index(part_of(leaf));
            if (n >= 0) {
                return n;
            }
        }
        return -1;
    }

    # ── Expressions ──

    eval(e: Expression): long {
        if (error.is_value()) {
            return -1;
        }
        return eval_inner(e);
    }

    ## A region read through memory the walk cannot follow back.
    untracked(): long {
        var r = fresh();
        regions[r as ulong].untracked = true;
        return r;
    }

    eval_inner(e: Expression): long {
        match (e) {
            SymbolRef(node) => {
                return local_region(node.id);
            }
            ThisRef => {
                return local_region("this");
            }
            MemberRef(node) => {
                var owner = eval(node.lhs);
                # An element of a tuple value: its own region.
                var index = _tuple_index(node.name);
                if (owner >= 0 and index >= 0) {
                    var parts = parts_of(owner);
                    if (parts.count > 0) {
                        return (index as ulong) < parts.count ? parts[index as ulong] : -1;
                    }
                }
                if (!has_region(e)) {
                    return -1;
                }
                # A field of a thread-safe object: raw memory that other
                # threads may reach too.
                return owner >= 0 ? owner : untracked();
            }
            # A payload value bound by a match arm: a field of the subject.
            CaseValue(value) => {
                var owner = eval(value.subject);
                if (!has_region(e)) {
                    return -1;
                }
                return owner >= 0 ? owner : untracked();
            }
            WithSubject(subject) => {
                eval(subject.subject);
                return eval(subject.body);
            }
            # The value a `match` expression examines.
            Subject(node) => {
                return has_region(e) ? untracked() : -1;
            }
            StringLiteral(node) => {
                return fresh();
            }
            PointerLiteral => {
                return fresh();
            }
            Default(declared) => {
                return fresh();
            }
            Allocate(declared) => {
                return fresh();
            }
            Binary(node) => {
                if (_is_assignment(node.op)) {
                    var value = eval(node.rhs);
                    var target = place(node.lhs);
                    link(target, value, node.rhs);
                    return -1;
                }
                eval(node.lhs);
                eval(node.rhs);
                return -1;
            }
            Unary(node) => {
                eval(node.operand);
                return -1;
            }
            Cast(node) => {
                var r = eval(node.expr);
                if (!has_region(e)) {
                    return -1;
                }
                return r >= 0 ? r : fresh();
            }
            Ternary(node) => {
                eval(node.condition);
                var a = eval(node.true_expr);
                var b = eval(node.false_expr);
                return link(a, b, node.false_expr);
            }
            Index(node) => {
                return read(e, node.lhs, node.rhs);
            }
            ArrayIndex(node) => {
                return read(e, node.lhs, node.rhs);
            }
            RefCount(declared, value) => {
                eval(value);
                return -1;
            }
            Address(declared, value) => {
                eval(value);
                return -1;
            }
            Weak(op, declared, value) => {
                var r = eval(value);
                return op == WeakOp.Expired ? -1 : r;
            }
            AtomicLoad(declared, value) => {
                eval(value);
                return -1;
            }
            AtomicStore(declared, pointer, value) => {
                eval(pointer);
                eval(value);
                return -1;
            }
            AtomicFetch(op, declared, pointer, value) => {
                eval(pointer);
                eval(value);
                return -1;
            }
            # Vectors hold numbers only.
            Simd(node) => {
                for (var arg in node.args) {
                    eval(arg);
                }
                return -1;
            }
            # Stores like an assignment, so it links the same way.
            ConstructAt(slot, value) => {
                var r = eval(value);
                var target = place(slot);
                link(target, r, value);
                return -1;
            }
            AtomicCmpXchg(declared, pointer, expected, desired) => {
                eval(pointer);
                eval(expected);
                eval(desired);
                return -1;
            }
            FunctionCall(node) => {
                return call_function(e, node.function, node.args);
            }
            MethodCall(node) => {
                return call_method(e, node.this_value, node.method, node.args);
            }
            Invoke(node) => {
                # A function value reaches nothing that is not thread-safe
                # besides its arguments and its captures (its own region),
                # so its result links only those.
                var acc = eval(node.callee);
                for (var arg in node.args) {
                    var r = eval(arg);
                    acc = link(acc, r, arg);
                }
                if (!has_region(e)) {
                    return -1;
                }
                return acc >= 0 ? acc : fresh();
            }
            MakeClosure(node) => {
                # The closure struct's constructor call, with the captures
                # as arguments: the closure's region holds what it captures.
                long r = has_region(e) ? fresh() : -1;
                if (node.value is FunctionCall(call)) {
                    for (var arg in call.args) {
                        r = captured(r, arg);
                    }
                }
                return r;
            }
            CallPointer(node) => {
                eval(node.pointer);
                for (var arg in node.args) {
                    eval(arg);
                }
                return -1;
            }
            ForIterator(value) => {
                return eval(value);
            }
            Destructure(node) => {
                return eval(node.value);
            }
            NamedArgument(node) => {
                return eval(node.value);
            }
            Move(node) => {
                return eval_move(node.value);
            }
            MatchArm(test) => {
                for (var child in expression_children(e)) {
                    eval(child);
                }
                return -1;
            }
            WithEntered(value) => {
                eval(value);
                return -1;
            }
            ToTrait(node) => {
                return eval(node.value);
            }
            FromTrait(node) => {
                return eval(node.value);
            }
            else => {
                return -1;
            }
        }
    }

    ## A capture of a closure made here, whose region is `closure`: part of
    ## a locked value is an error, and the captured value joins the
    ## closure's region, so it is shared for as long as the closure is.
    captured(closure: long, arg: Expression): long {
        var r = eval(arg);
        if (r < 0) {
            return closure;
        }
        var locked = locked_leaf(r);
        if (locked >= 0) {
            var lock = locks[locked as ulong];
            var what = _describe(arg);
            report(
                _error_at_known(
                    $"closure captures '{what}', which is part of the value locked by '{lock.name}'",
                    _expression_loc(arg)
                ).with_note(
                    "locked here",
                    known_location(lock.loc)
                ).with_note(
                    $"a function value can carry what it captures out of the block; capture 'copy({what})'",
                    Optional<Location>.Empty
                )
            );
        }
        if (closure < 0) {
            # A closure without a region of its own: what it captures may
            # be reached through it from anywhere.
            regions[find(r) as ulong].tainted = true;
            return closure;
        }
        return link(closure, r, arg);
    }

    ## `p[i]`: the pointer's region; a reference read through a pointer an
    ## extern returned may be referenced from wherever C keeps it.
    read(e: Expression, lhs: Expression, rhs: Expression): long {
        eval(rhs);
        var pointer = eval(lhs);
        if (!has_region(e)) {
            return -1;
        }
        var r = pointer >= 0 ? pointer : fresh();
        var root = regions[find(r) as ulong];
        if (root.untracked and !is_pointer_typed(e)) {
            root.tainted = true;
        }
        return r;
    }

    ## `move(value)`: a local or parameter that is the only holder of a
    ## disconnected value hands it over; a raw slot (runtime only) hands
    ## over a value the runtime promises nothing else references.
    eval_move(value: Expression): long {
        moves += 1;
        if (value is SymbolRef(node)) {
            var found = local(node.id);
            if (found.is_value()) {
                if (found.value().region < 0) {
                    return -1;
                }
                var root_index = find(found.value().region);
                var root = regions[root_index as ulong];
                var others = sharers(root_index, node.id);
                bool shares = _locked_index(root.part) >= 0
                    or _is_operand_part(root.part)
                    or root.shared
                    or root.tainted;
                for (var slot in root.operands) {
                    if (!sending.contains(slot)) {
                        shares = true;
                    }
                }
                if (checking and (shares or others.count > 0)) {
                    var why = "its value shares objects with the rest of the program";
                    if (others.count > 0) {
                        # A hidden local (a `for` loop's iterator) is named
                        # only when no local of the user's is.
                        why = "a hidden value of the code around it (such as a loop's iterator) also references its value";
                        for (var other in others) {
                            if (!other.starts_with("__")) {
                                why = $"'{other}' also references its value";
                                break;
                            }
                        }
                    }
                    report(
                        _error_at_known(
                            $"'{node.id}' cannot be moved: {why}",
                            node.loc
                        ).with_note(
                            "only a variable that holds the one reference to a new value can hand it over; pass 'copy(...)' instead",
                            Optional<Location>.Empty
                        )
                    );
                }
                # The variable gives the value up: it goes on as a new one.
                return fresh();
            }
        }
        var lhs = _index_lhs(value);
        if (lhs.is_value() and is_pointer_typed(lhs.value())) {
            eval(value);
            var at = _expression_loc(value);
            if (checking and !program.is_runtime_file(at.file)) {
                report(
                    _error_at_known(
                        "only the runtime may move a value out of raw memory",
                        at
                    ).with_note(
                        "it promises that the slot held the only reference, which the compiler cannot check",
                        Optional<Location>.Empty
                    )
                );
            }
            return fresh();
        }
        if (checking) {
            report(
                _error_at_known(
                    $"'{_describe(value)}' cannot be moved: only a local variable or parameter can hand over its value",
                    _expression_loc(value)
                )
            );
        }
        return eval(value);
    }

    ## The locals still in scope, other than the innermost one named
    ## `moving`, whose value is in the region `root`: those that would
    ## still reference a value moved out of `moving`. A local whose scope
    ## has ended, a closure included, references nothing any more.
    sharers(root: long, moving: String): Array<String> {
        var out = Array<String>();
        bool skipped = false;
        var s = scopes.count;
        while (s > 0) {
            s -= 1;
            var scope = scopes[s];
            var i = scope.count;
            while (i > 0) {
                i -= 1;
                var l = scope[i];
                if (l.name == moving and !skipped) {
                    skipped = true;
                } else if (l.region >= 0) {
                    for (var leaf in leaves(l.region)) {
                        if (find(leaf) == root) {
                            out.append(l.name);
                            break;
                        }
                    }
                }
            }
        }
        return out;
    }

    ## The region an assignment to `target` stores into.
    place(target: Expression): long {
        match (target) {
            SymbolRef(node) => {
                return local_region(node.id);
            }
            MemberRef(node) => {
                return eval(node.lhs);
            }
            Index(node) => {
                eval(node.rhs);
                return eval(node.lhs);
            }
            ArrayIndex(node) => {
                eval(node.rhs);
                return eval(node.lhs);
            }
            else => {
                return eval(target);
            }
        }
    }

    call_function(e: Expression, function: String, args: Expression[]): long {
        # A tuple literal keeps its elements apart.
        if (_is_tuple_call(function)) {
            var parts = Array<long>();
            for (var a in args) {
                parts.append(eval(a));
            }
            return tuple(parts);
        }
        var callee = resolve_function(function);
        var operand_regions = Array<long>();
        for (var a in args) {
            operand_regions.append(eval(a));
        }
        return apply(e, callee, operand_regions, args);
    }

    call_method(e: Expression, this_value: Expression, method: String, args: Expression[]): long {
        var resolved = resolve_method(this_value, method);
        var operand_regions = Array<long>();
        var operand_exprs = Array<Expression>();
        if (!resolved.is_static) {
            operand_regions.append(eval(this_value));
            operand_exprs.append(this_value);
        }
        for (var a in args) {
            operand_regions.append(eval(a));
            operand_exprs.append(a);
        }
        return apply(e, resolved.callee, operand_regions, operand_exprs);
    }

    resolve_function(function: String): _Callee {
        if (function.starts_with("copy<")) {
            return _Callee.Copy;
        }
        if (program.externs.contains(function)) {
            return _Callee.Extern;
        }
        var constructor = program.constructors.try_get(function);
        if (constructor.is_value()) {
            return _Callee.Known(method_key(constructor.value().name, "__ctor"), constructor.value());
        }
        var f = program.functions.try_get(function);
        if (f.is_value()) {
            return _Callee.Known(function, f.value());
        }
        return _Callee.Unknown;
    }

    ## The method `this_value.method` calls, and whether it is static.
    resolve_method(this_value: Expression, method: String): _ResolvedMethod {
        bool receiver_is_local = false;
        match (this_value) {
            SymbolRef(node) => {
                receiver_is_local = local(node.id).is_value();
                if (!receiver_is_local) {
                    var st = program.struct_named(node.id);
                    if (st.is_value()) {
                        var m = _method_named(st.value(), method);
                        if (m.is_value()) {
                            return _ResolvedMethod(_Callee.Known(method_key(st.value().name, method), m.value()), true);
                        }
                        return _ResolvedMethod(_Callee.Unknown, true);
                    }
                }
            }
            else => {}
        }
        var found = ty(this_value);
        if (!found.is_value()) {
            return _ResolvedMethod(_Callee.Unknown, false);
        }
        var receiver = found.value();
        var owner = receiver.without_pointers().to_string();
        var st = program.struct_named(owner);
        if (st.is_value()) {
            var m = _method_named(st.value(), method);
            if (m.is_value()) {
                return _ResolvedMethod(
                    _Callee.Known(method_key(st.value().name, method), m.value()), m.value().is_static
                );
            }
            return _ResolvedMethod(_Callee.Unknown, false);
        }
        if (program.is_trait(receiver)) {
            var keys = program.dispatched(receiver.name, method);
            return _ResolvedMethod(_Callee.Trait($"{receiver.name}\t{method}", keys), false);
        }
        return _ResolvedMethod(_Callee.Unknown, false);
    }

    ## The summary of a call, sized for its operands and results; none for
    ## `copy` and an `extern`.
    summary_of(callee: _Callee, operands: ulong, results: ulong): _Summary? {
        match (callee) {
            Known(key, function) => {
                return Optional<_Summary>.Value(program.callee_summary(key, operands, results));
            }
            Trait(call, keys) => {
                var joined = program.dispatch_summary(keys, operands, results);
                dispatched[$"{call}\t{operands}\t{results}"] = joined.links();
                return Optional<_Summary>.Value(joined);
            }
            Unknown => {
                return Optional<_Summary>.Value(_top(operands, results));
            }
            else => {
                return Optional<_Summary>.Empty;
            }
        }
    }

    ## Links a call's operands as its callee does, and gives its result a
    ## region.
    apply(e: Expression, callee: _Callee, operand_regions: long[], operand_exprs: Expression[]): long {
        bool copies = false;
        bool external = false;
        match (callee) {
            Known(key, function) => {
                called.append(key);
                named.append(key);
            }
            Trait(call, keys) => {
                for (var key in keys) {
                    called.append(key);
                }
            }
            Copy => {
                copies = true;
            }
            Extern => {
                external = true;
            }
            else => {}
        }
        var has_result = has_region(e);
        if (copies) {
            return has_result ? fresh() : -1;
        }
        if (external) {
            if (!has_result and !is_pointer_typed(e)) {
                return -1;
            }
            return untracked();
        }
        var result_type = ty(e);
        var results = result_type.is_value() ? _result_slots(result_type.value()) : 1;
        var found = summary_of(callee, operand_regions.count, results);
        if (!found.is_value()) {
            return -1;
        }
        var summary = found.value();
        var first_result = summary.operands();
        # Link the operands in each class, in operand order.
        var class_region = HashMap<ulong, long>();
        ulong slot = 0;
        while (slot < operand_regions.count) {
            var r = operand_regions[slot];
            # A slot the summary does not know (a variadic or default
            # argument) stays unlinked.
            if (r >= 0 and slot < first_result) {
                var slot_class = summary.classes[slot];
                var into = class_region.try_get(slot_class);
                if (into.is_value()) {
                    class_region[slot_class] = link(into.value(), r, operand_exprs[slot]);
                } else {
                    class_region[slot_class] = r;
                }
            }
            slot += 1;
        }
        if (!has_result) {
            return -1;
        }
        # Each result slot: the region of the operands in its class, or a
        # new one.
        var out = Array<long>();
        ulong n = 0;
        while (n < summary.results()) {
            var slot_class = summary.classes[first_result + n];
            var linked = class_region.try_get(slot_class);
            long r = -1;
            if (linked.is_value()) {
                r = linked.value();
            } else {
                r = fresh();
                # Results in one class share their region.
                class_region[slot_class] = r;
            }
            if (summary.tainted[n]) {
                var root = regions[find(r) as ulong];
                if (_is_fresh_part(root.part) and checking) {
                    root.part = _RegionPart.Outer;
                }
                root.tainted = true;
            }
            out.append(r);
            n += 1;
        }
        if (out.count == 1) {
            return out[0];
        }
        return tuple(out);
    }
}

_pointee(pointer: TypeName?): TypeName? {
    var pointee = pointer.is_value() ? pointer.value().pointee() : Optional<TypeName>.Empty;
    return pointee.is_value() ? Optional<TypeName>.Value(pointee.value().copy()) : pointee;
}

_is_tuple_call(function: String): bool {
    return function == TUPLE or function.starts_with(TUPLE + "<");
}

## The index a tuple element's member name spells, or -1.
_tuple_index(name: String): long {
    if (name.is_empty) {
        return -1;
    }
    var n = ulong.parse(name);
    if (!n.is_value() or $"{n.value()}" != name) {
        return -1;
    }
    return n.value() as long;
}

_index_lhs(e: Expression): Expression? {
    match (e) {
        Index(node) => {
            return Optional<Expression>.Value(node.lhs);
        }
        ArrayIndex(node) => {
            return Optional<Expression>.Value(node.lhs);
        }
        else => {
            return Optional<Expression>.Empty;
        }
    }
}

_method_named(st: StructDef, method: String): FunctionDef? {
    for (var m in st.method_members) {
        if (m.name == method) {
            return Optional<FunctionDef>.Value(m);
        }
    }
    return Optional<FunctionDef>.Empty;
}

_variable_at(b: Block, i: ulong): VariableDef? {
    if (i < b.items.count) {
        if (b.items[i] is Declaration(declaration)) {
            if (declaration is Variable(variable)) {
                return Optional<VariableDef>.Value(variable);
            }
        }
    }
    return Optional<VariableDef>.Empty;
}

_branch_at(b: Block, i: ulong): Branch? {
    if (i < b.items.count) {
        if (b.items[i] is Branch(branch)) {
            return Optional<Branch>.Value(branch);
        }
    }
    return Optional<Branch>.Empty;
}

## An expression as the programmer wrote it, near enough for a message.
_describe(e: Expression): String {
    match (e) {
        SymbolRef(node) => {
            return node.id;
        }
        ThisRef => {
            return "this";
        }
        MemberRef(node) => {
            if (node.lhs is ThisRef) {
                return node.name;
            }
            return $"{_describe(node.lhs)}.{node.name}";
        }
        IntLiteral(value) => {
            return $"{value}";
        }
        StringLiteral(node) => {
            return $"\"{node.value}\"";
        }
        MethodCall(node) => {
            var args = _described_args(node.args);
            if (node.method == "__index_get") {
                return $"{_describe(node.this_value)}[{args}]";
            }
            return $"{_describe(node.this_value)}.{_before_angle(node.method)}({args})";
        }
        FunctionCall(node) => {
            # A string literal becomes `String(raw, size, length)`.
            if (node.function == "String" and node.args.count > 0) {
                if (node.args[0] is StringLiteral(literal)) {
                    return $"\"{literal.value}\"";
                }
            }
            return $"{_before_angle(node.function)}({_described_args(node.args)})";
        }
        Index(node) => {
            return $"{_describe(node.lhs)}[{_describe(node.rhs)}]";
        }
        ArrayIndex(node) => {
            return $"{_describe(node.lhs)}[{_describe(node.rhs)}]";
        }
        Cast(node) => {
            return _describe(node.expr);
        }
        ToTrait(node) => {
            return _describe(node.value);
        }
        Invoke(node) => {
            return $"{_describe(node.callee)}({_described_args(node.args)})";
        }
        else => {
            return "value";
        }
    }
}

_described_args(args: Expression[]): String {
    var out = StringBuilder();
    ulong i = 0;
    while (i < args.count) {
        if (i > 0) {
            out.append(", ");
        }
        out.append(_describe(args[i]));
        i += 1;
    }
    return out.to_string();
}

# ── Expression checks ────────────────────────────────────────────────────

## The checks that look at single expressions: guard use, `[Move]`
## arguments, `[Locked]` closures and `ThreadLocal.get`.
struct _Checks {
    var program: _Confinement;
    ## For types and local lookups.
    var walk: _RegionWalk;
    ## A function that makes guards (it returns one, or is the guard's own
    ## method).
    var exempt: bool;
    var error: Diagnostic? = Optional<Diagnostic>.Empty;

    construct(program: _Confinement, walk: _RegionWalk, exempt: bool) {
        this.program = program;
        this.walk = walk;
        this.exempt = exempt;
    }

    block(b: Block) {
        walk.scopes.append(Array<_ScopeLocal>());
        for (var s in b.items) {
            if (error.is_value()) {
                break;
            }
            statement(s);
        }
        walk.scopes.pop();
    }

    statement(s: Statement) {
        match (s) {
            Expression(e) => {
                expression(e, false);
            }
            Block(inner) => {
                block(inner);
            }
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    variable_statement(variable);
                }
            }
            Branch(branch) => {
                expression(branch.condition, false);
                block(branch.if_block);
                if (branch.else_block.is_value()) {
                    block(branch.else_block.value());
                }
            }
            While(loop) => {
                expression(loop.condition, false);
                block(loop.block);
            }
            Return(ret) => {
                if (ret.expr.is_value()) {
                    expression(ret.expr.value(), false);
                }
            }
            else => {}
        }
    }

    variable_statement(variable: VariableDef) {
        var scope = variable.name.starts_with("__with_scope_");
        if (variable.default.is_value()) {
            expression(variable.default.value(), scope);
        }
        var declared = variable.ty;
        if (declared.is_auto()) {
            declared = TypeName.auto();
            if (variable.default.is_value()) {
                var found = walk.ty(variable.default.value());
                if (found.is_value()) {
                    declared = found.value();
                }
            }
        }
        if (!scope
            and !variable.hidden
            and !exempt
            and program.is_isolated(declared)
            and !variable.type_loc.is_none()) {
            guard_error(declared, variable.type_loc);
        }
        walk.declare(variable.name, -1, declared);
    }

    guard_error(declared: TypeName, at: Loc) {
        if (!error.is_value()) {
            error = Optional<Diagnostic>.Value(
                _error_at_known(
                    $"'{declared.display()}' can only be the scope of a 'with' block",
                    at
                ).with_note(
                    "a guard unlocks when its block ends; write 'with (var value = ...) { ... }'",
                    Optional<Location>.Empty
                )
            );
        }
    }

    ## Checks `e` and everything in it. `scope`: it is a `with` header's
    ## scope, where a guard belongs.
    expression(e: Expression, scope: bool) {
        if (error.is_value()) {
            return;
        }
        if (!scope and !exempt and program.isolated.count > 0 and !_is_with_scope(e)) {
            var found = walk.ty(e);
            if (found.is_value() and program.is_isolated(found.value())) {
                guard_error(found.value(), _expression_loc(e));
                return;
            }
        }
        match (e) {
            MethodCall(node) => {
                thread_local_get(node.this_value, node.method, node.loc);
                var callee = walk.resolve_method(node.this_value, node.method).callee;
                sending(callee, node.args);
                locked(callee, node.args);
            }
            FunctionCall(node) => {
                var callee = walk.resolve_function(node.function);
                sending(callee, node.args);
                locked(callee, node.args);
            }
            else => {}
        }
        for (var child in expression_children(e)) {
            expression(child, false);
        }
    }

    ## `ThreadLocal<T>.get()` or `TaskLocal<T>.get()` for a `T` that is not
    ## thread-safe.
    thread_local_get(this_value: Expression, method: String, loc: Loc) {
        if (method != "get" or error.is_value()) {
            return;
        }
        var found = walk.ty(this_value);
        if (!found.is_value() or found.value().sub_types.count == 0) {
            return;
        }
        var local_type = found.value();
        var value = local_type.sub_types[0];
        var base = demangle_name(local_type.name);
        var owner = "";
        if (base == "ThreadLocal") {
            owner = "thread";
        } else if (base == "TaskLocal") {
            owner = "task";
        } else {
            return;
        }
        var st = program.struct_named(local_type.to_string());
        bool enters = false;
        if (st.is_value()) {
            for (var m in st.value().method_members) {
                if (m.name == "enter" and program.is_isolated(m.ty)) {
                    enters = true;
                }
            }
        }
        if (!enters or !unsafe_part_in(value, program.safe).is_value()) {
            return;
        }
        error = Optional<Diagnostic>.Value(
            _error_at_known(
                $"'get' is not available on '{local_type.display()}', because '{value.display()}' is not thread-safe",
                loc
            ).with_note(
                $"reach this {owner}'s value with 'with (var value = {_describe(this_value)}.enter())'",
                Optional<Location>.Empty
            )
        );
    }

    ## Each argument to a `[Locked]` parameter must be a closure written at
    ## the call, whose body keeps the locked value it is given apart from
    ## everything else.
    locked(callee: _Callee, args: Expression[]) {
        if (callee is Known(key, function)) {
            ulong i = 0;
            while (i < function.parameters.count and i < args.count) {
                var parameter = function.parameters[i];
                var arg = args[i];
                i += 1;
                if (error.is_value() or !ast.has_attribute(parameter.attributes, LOCKED_ATTRIBUTE)) {
                    continue;
                }
                if (arg is MakeClosure(node)) {
                    error = _check_locked_closure(program, node.closure);
                    continue;
                }
                error = Optional<Diagnostic>.Value(
                    _error_at_known(
                        $"parameter '{parameter.name}' takes a closure written at the call, because it is called with a locked value",
                        _expression_loc(arg)
                    ).with_note(
                        $"'{parameter.name}' is declared [{LOCKED_ATTRIBUTE}] here",
                        known_location(parameter.loc)
                    ).with_note(
                        "write the function here, as a closure, so the compiler can check that it keeps the value to itself",
                        Optional<Location>.Empty
                    )
                );
            }
        }
    }

    ## Each argument to a `[Move]` parameter must be disconnected.
    sending(callee: _Callee, args: Expression[]) {
        if (callee is Known(key, function)) {
            ulong i = 0;
            while (i < function.parameters.count and i < args.count) {
                var parameter = function.parameters[i];
                var arg = args[i];
                i += 1;
                if (error.is_value() or !ast.has_attribute(parameter.attributes, MOVE_ATTRIBUTE)) {
                    continue;
                }
                if (disconnected(arg)) {
                    continue;
                }
                var what = _describe(arg);
                var diagnostic = _error_at_known(
                    $"'{what}' is not a new value, but parameter '{parameter.name}' takes a value that nothing else references",
                    _expression_loc(arg)
                ).with_note($"'{parameter.name}' is declared [Move] here", known_location(parameter.loc));
                var blamed = blame(arg);
                if (blamed.is_value()) {
                    diagnostic = diagnostic.with_note(
                        $"'{what}' does not return a new value: this return shares its inputs",
                        known_location(blamed.value())
                    );
                }
                # A local can hand its value over instead of copying it.
                bool handed = false;
                if (arg is SymbolRef(node)) {
                    if (walk.local(node.id).is_value()) {
                        handed = true;
                        diagnostic = diagnostic
                            .with_note(
                                $"hand it over with 'move({what})', or pass a new value, such as 'copy({what})'",
                                Optional<Location>.Empty
                            )
                            .with_fix(
                                Fix(
                                    $"Hand '{node.id}' over with 'move({node.id})'",
                                    location_of(node.loc),
                                    $"move({node.id})"
                                )
                            )
                            .with_fix(
                                Fix($"Pass a copy with 'copy({node.id})'", location_of(node.loc), $"copy({node.id})")
                            );
                    }
                }
                if (!handed) {
                    diagnostic = diagnostic.with_note(
                        $"pass a new value, such as 'copy({what})'", Optional<Location>.Empty
                    );
                }
                error = Optional<Diagnostic>.Value(diagnostic);
            }
        }
    }

    ## The `return` that keeps a call's result from being fresh.
    blame(arg: Expression): Loc? {
        var none = Optional<Loc>.Empty;
        _Callee callee = _Callee.Unknown;
        match (arg) {
            FunctionCall(node) => {
                callee = walk.resolve_function(node.function);
            }
            MethodCall(node) => {
                callee = walk.resolve_method(node.this_value, node.method).callee;
            }
            else => {
                return none;
            }
        }
        if (callee is Known(key, function)) {
            var found = program.summary(key);
            if (found.is_value()) {
                return found.value().blame;
            }
        }
        return none;
    }

    ## A disconnected expression: nothing else references its value.
    disconnected(e: Expression): bool {
        if (!walk.has_region(e)) {
            return true;
        }
        match (e) {
            StringLiteral(node) => {
                return true;
            }
            PointerLiteral => {
                return true;
            }
            Default(declared) => {
                return true;
            }
            Allocate(declared) => {
                return true;
            }
            # The region walk checks what may be moved.
            Move(node) => {
                return true;
            }
            Cast(node) => {
                return disconnected(node.expr);
            }
            ToTrait(node) => {
                return disconnected(node.value);
            }
            Ternary(node) => {
                return disconnected(node.true_expr) and disconnected(node.false_expr);
            }
            FunctionCall(node) => {
                if (_is_tuple_call(node.function)) {
                    for (var a in node.args) {
                        if (!disconnected(a)) {
                            return false;
                        }
                    }
                    return true;
                }
                return call_disconnected(e, walk.resolve_function(node.function), node.args);
            }
            MethodCall(node) => {
                var resolved = walk.resolve_method(node.this_value, node.method);
                var operands = Array<Expression>();
                if (!resolved.is_static) {
                    operands.append(node.this_value);
                }
                for (var a in node.args) {
                    operands.append(a);
                }
                return call_disconnected(e, resolved.callee, operands);
            }
            # A function value's result links only its arguments and its
            # captures (a `shared` one's are thread-safe).
            Invoke(node) => {
                if (!disconnected(node.callee)) {
                    return false;
                }
                for (var a in node.args) {
                    if (!disconnected(a)) {
                        return false;
                    }
                }
                return true;
            }
            else => {
                return false;
            }
        }
    }

    ## A call's result is disconnected when the operands in its class are.
    call_disconnected(call: Expression, callee: _Callee, operands: Expression[]): bool {
        match (callee) {
            Copy => {
                return true;
            }
            Extern => {
                return false;
            }
            else => {}
        }
        var result_type = walk.ty(call);
        var results = result_type.is_value() ? _result_slots(result_type.value()) : 1;
        var found = walk.summary_of(callee, operands.count, results);
        if (!found.is_value()) {
            return false;
        }
        var summary = found.value();
        var first_result = summary.operands();
        ulong n = 0;
        while (n < summary.results()) {
            if (summary.tainted[n]) {
                return false;
            }
            var result = summary.classes[first_result + n];
            ulong slot = 0;
            while (slot < operands.count and slot < first_result) {
                if (summary.classes[slot] == result and !disconnected(operands[slot])) {
                    return false;
                }
                slot += 1;
            }
            n += 1;
        }
        return true;
    }
}

_is_with_scope(e: Expression): bool {
    if (e is SymbolRef(node)) {
        return node.id.starts_with("__with_scope_");
    }
    return false;
}

# ── Use after move ───────────────────────────────────────────────────────

## The first use after `move`, shared by every copy of a `_Moves` walk.
struct _MoveFailure {
    var error: Diagnostic? = Optional<Diagnostic>.Empty;

    construct() {}
}

## How a statement or block ends every path through it: not at all,
## leaving (`return` or `break`), or `continue`.
const _GOES_ON: int = 0;
const _LEAVES: int = 1;
const _CONTINUES: int = 2;

## Use after `move`: a forward walk over a function's statements that
## tracks the locals moved on some path and not assigned since.
struct _Moves {
    var moved: HashMap<String, Loc> = HashMap<String, Loc>();
    var failure: _MoveFailure;

    construct(failure: _MoveFailure) {
        this.failure = failure;
    }

    clone(): _Moves {
        var out = _Moves(failure);
        out.moved = moved.copy();
        return out;
    }

    block(b: Block): int {
        var declared_before = HashSet<String>();
        for (var (name, _) in moved) {
            declared_before.insert(name);
        }
        var local = HashSet<String>();
        for (var s in b.items) {
            var exit = statement(s, local);
            if (failure.error.is_value()) {
                return _GOES_ON;
            }
            if (exit != _GOES_ON) {
                return exit;
            }
        }
        # A local declared in the block goes out of scope with it.
        var gone = Array<String>();
        for (var (name, _) in moved) {
            if (!declared_before.contains(name) and local.contains(name)) {
                gone.append(name);
            }
        }
        for (var name in gone) {
            moved.remove(name);
        }
        return _GOES_ON;
    }

    statement(s: Statement, local: HashSet<String>): int {
        match (s) {
            Expression(e) => {
                expression(e);
            }
            Block(inner) => {
                return block(inner);
            }
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    if (variable.default.is_value()) {
                        expression(variable.default.value());
                    }
                    # A new variable of the name starts with a value.
                    moved.remove(variable.name);
                    local.insert(variable.name);
                }
            }
            Branch(branch) => {
                expression(branch.condition);
                if (failure.error.is_value()) {
                    return _GOES_ON;
                }
                var then = clone();
                var then_exit = then.block(branch.if_block);
                var other = clone();
                var other_exit = _GOES_ON;
                if (branch.else_block.is_value()) {
                    other_exit = other.block(branch.else_block.value());
                }
                var merged = HashMap<String, Loc>();
                if (then_exit == _GOES_ON) {
                    for (var (name, at) in then.moved) {
                        merged[name] = at;
                    }
                }
                if (other_exit == _GOES_ON) {
                    for (var (name, at) in other.moved) {
                        merged[name] = at;
                    }
                }
                moved = merged;
                if (then_exit == _LEAVES and other_exit == _LEAVES) {
                    return _LEAVES;
                }
                if (then_exit != _GOES_ON and other_exit != _GOES_ON) {
                    return _CONTINUES;
                }
                return _GOES_ON;
            }
            While(loop) => {
                # Again after the first pass, unless the body always leaves:
                # a move in the body reaches its next iteration.
                int pass = 0;
                while (pass < 2) {
                    expression(loop.condition);
                    if (failure.error.is_value()) {
                        return _GOES_ON;
                    }
                    var body = clone();
                    var exit = body.block(loop.block);
                    for (var (name, at) in body.moved) {
                        moved[name] = at;
                    }
                    if (exit == _LEAVES) {
                        break;
                    }
                    pass += 1;
                }
            }
            Return(ret) => {
                if (ret.expr.is_value()) {
                    expression(ret.expr.value());
                }
                return _LEAVES;
            }
            LoopBreak(b) => {
                return b.kind == LoopBreakKind.Continue ? _CONTINUES : _LEAVES;
            }
            else => {}
        }
        return _GOES_ON;
    }

    ## Uses in `e` of moved locals are errors; then its moves take effect,
    ## and a plain assignment gives a local its value back.
    expression(e: Expression) {
        if (failure.error.is_value()) {
            return;
        }
        var moves = Array<(String, Loc)>();
        var assigned = Array<String>();
        visit(e, moves, assigned);
        if (failure.error.is_value()) {
            return;
        }
        for (var name in assigned) {
            moved.remove(name);
        }
        for (var (name, at) in moves) {
            moved[name] = at;
        }
    }

    visit(e: Expression, moves: Array<(String, Loc)>, assigned: String[]) {
        if (failure.error.is_value()) {
            return;
        }
        match (e) {
            Move(node) => {
                if (node.value is SymbolRef(symbol)) {
                    var earlier = moved.try_get(symbol.id);
                    if (earlier.is_value()) {
                        fail(symbol.id, _expression_loc(node.value), earlier.value());
                        return;
                    }
                    moves.append((symbol.id, node.loc));
                    return;
                }
            }
            SymbolRef(node) => {
                var earlier = moved.try_get(node.id);
                if (earlier.is_value()) {
                    fail(node.id, node.loc, earlier.value());
                    return;
                }
            }
            Binary(node) => {
                if (node.op == BinaryOp.Assign) {
                    if (node.lhs is SymbolRef(target)) {
                        visit(node.rhs, moves, assigned);
                        assigned.append(target.id);
                        return;
                    }
                }
            }
            else => {}
        }
        for (var child in expression_children(e)) {
            visit(child, moves, assigned);
        }
    }

    fail(name: String, at: Loc, moved_at: Loc) {
        if (!failure.error.is_value()) {
            failure.error = Optional<Diagnostic>.Value(
                _error_at_known(
                    $"'{name}' is used after its value was moved",
                    at
                ).with_note(
                    $"'{name}' was moved here; assign it a new value before using it again", known_location(moved_at)
                )
            );
        }
    }
}
