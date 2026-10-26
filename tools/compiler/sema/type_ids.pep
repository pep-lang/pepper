## Types interned while the passes run, so asking a type for its spelling,
## its canonical form or whether it equals another costs its own node, not
## the levels nested in it: each level of `[[...[1]...]]` asked that of
## every level below it, which made a nested literal build in time quadratic
## in its depth (#210).
##
## Each distinct type (its name, flags, labels and arguments) has one entry
## in the table of the thread's running passes (`begin_type_ids`), and each
## `TypeName` remembers its entry's id in `type_id`. An id is trusted only while
## the node's own name, flags, labels and arguments' ids are still the
## entry's, which a pass changing the type it holds breaks, so the id is
## found again. The nodes below a type are not looked at: no pass changes a
## type below the one it holds (`TypeName.copy`).

import async;
import [Fingerprint] from "fingerprint";
import [TypeFlags, TypeName] from "model";
import [AUTO, FUNCTION, SHARED_FUNCTION, TUPLE, WEAK] from "type_name";

# The thread's cell, a C allocation so that tests' allocation counts do not
# see it: like the runtime's own thread-local tables, it is bookkeeping.
extern void* calloc(ulong count, ulong size);

# Each table's serial, in the top half of its ids: an id from another table
# (an earlier run's, kept in a checked unit's types) never matches this one.
const _serials = async.Atomic<ulong>(1);

# The calling thread's cell, which holds the table of its running passes, or
# null. A raw cell, since a `ThreadLocal<T>` of a type that is not
# thread-safe hands out no references; the table never leaves the thread.
[ThreadLocal]
var _cell: __ptr<void>;

const _LOW: ulong = 0xffffffff;
const _HIGH: ulong = 0xffffffff00000000;

## One distinct type, and what the passes ask of it.
export struct TypeFacts {
    var name: String;
    var flags: TypeFlags;
    var labels: String[];
    ## The arguments' ids.
    var args: ulong[];
    ## The id of this type without its labels, at any depth: what `==`
    ## compares.
    var bare: ulong = 0;
    ## `type_print` of the type.
    var print: ulong = 0;
    ## Whether `auto` appears in it.
    var auto: bool = false;
    ## The spelling, once asked for.
    var spelling: String? = Optional<String>.Empty;
    ## The type as a node of the table's own, once asked for: no labels,
    ## and arguments that are the table's nodes too.
    var node: TypeName? = Optional<TypeName>.Empty;
    ## The id of `_canonical`'s answer, once asked for.
    var canonical: ulong = 0;
    ## The distinct names in it, its own included: shared with an argument
    ## that has them all, so each level of a nested type adds no list.
    var names: String[] = Array<String>();
    ## Whether a name in it holds a `<` (a type carried as a flat name).
    var angled: bool = false;
    ## Whether a name in it is a static block's `field.Type`.
    var member_type: bool = false;
    ## Whether a function, weak or tuple type is in it, itself included.
    var special: bool = false;
    ## Whether a tuple with labels is in it, itself included.
    var labeled_tuple: bool = false;
    ## The next entry (its index plus one) whose key collides with this one's.
    var next: ulong = 0;

    construct(name: String, flags: TypeFlags, labels: String[], args: ulong[]) {
        this.name = name;
        this.flags = flags;
        this.labels = labels;
        this.args = args;
    }
}

## The passes' table of types.
export struct TypeIds {
    var _serial: ulong;
    var _entries: Array<TypeFacts> = Array<TypeFacts>();
    # The first entry (index plus one) of each key.
    var _first: HashMap<ulong, ulong> = HashMap<ulong, ulong>();
    # What `parse_type_string` made of each text.
    var _parsed: HashMap<String, ulong> = HashMap<String, ulong>();

    construct() {
        _serial = _serials.fetch_add(1) << 32;
    }

    ## Returns the id of `ty`, which `ty` keeps.
    ##
    ## @param ty the type
    ## @returns its id
    id(ty: TypeName): ulong {
        var known = ty.type_id;
        if ((known & _HIGH) == _serial and _matches(_entry(known), ty)) {
            return known;
        }
        var args = Array<ulong>();
        for (var sub in ty.sub_types) {
            args.append(id(sub));
        }
        var made = _intern(ty.name, ty.flags, ty.labels, args);
        ty.type_id = made;
        return made;
    }

    ## Returns whether `a` and `b` are the same type, labels aside.
    same(a: TypeName, b: TypeName): bool {
        return _entry(id(a)).bare == _entry(id(b)).bare;
    }

    ## Returns `ty.to_string()`.
    spelling(ty: TypeName): String {
        return _spelling(id(ty));
    }

    ## Returns what the table knows of `ty`.
    facts(ty: TypeName): TypeFacts {
        return _entry(id(ty));
    }

    ## Returns what `parse_type_string` made of `text` before, if anything:
    ## a copy of the table's node, which shares its arguments.
    parsed(text: String): TypeName? {
        var known = _parsed.try_get(text);
        if (!known.is_value()) {
            return Optional<TypeName>.Empty;
        }
        return Optional<TypeName>.Value(_handed(known.value()));
    }

    ## Notes what `parse_type_string` made of `text`.
    note_parsed(text: String, ty: TypeName) {
        _parsed[text.copy()] = id(ty);
    }

    ## Returns the canonical form of `ty` noted before, if any: a copy of
    ## the table's node.
    canonical(ty: TypeName): TypeName? {
        var e = _entry(id(ty));
        if (e.canonical == 0) {
            return Optional<TypeName>.Empty;
        }
        return Optional<TypeName>.Value(_handed(e.canonical));
    }

    ## Notes `canonical` as the canonical form of `ty`, and of itself.
    note_canonical(ty: TypeName, canonical: TypeName) {
        var made = id(canonical);
        _entry(id(ty)).canonical = made;
        _entry(made).canonical = made;
    }

    _entry(id: ulong): TypeFacts {
        return _entries[(id & _LOW) - 1];
    }

    # Whether `ty` is still entry `e`: its own fields, and its arguments'
    # ids as they keep them.
    static _matches(e: TypeFacts, ty: TypeName): bool {
        if (e.args.count != ty.sub_types.count or e.flags != ty.flags or e.labels.count != ty.labels.count) {
            return false;
        }
        if (!(e.name == ty.name)) {
            return false;
        }
        ulong i = 0;
        while (i < e.args.count) {
            if (ty.sub_types[i].type_id != e.args[i]) {
                return false;
            }
            i += 1;
        }
        i = 0;
        while (i < e.labels.count) {
            if (!(e.labels[i] == ty.labels[i])) {
                return false;
            }
            i += 1;
        }
        return true;
    }

    _intern(name: String, flags: TypeFlags, labels: String[], args: ulong[]): ulong {
        var key = Fingerprint();
        key.add_text(name);
        key.add(flags == TypeFlags.Function ? 1 : 0);
        for (var a in args) {
            key.add(a);
        }
        for (var l in labels) {
            key.add_text(l);
        }
        var first = _first.try_get(key.value);
        ulong at = first.is_value() ? first.value() : 0;
        while (at != 0) {
            var e = _entries[at - 1];
            if (e.flags == flags and e.args == args and e.name == name and e.labels == labels) {
                return _serial | at;
            }
            at = e.next;
        }
        var e = TypeFacts(name, flags, labels.copy(), args);
        e.next = first.is_value() ? first.value() : 0;
        _entries.append(e);
        ulong made = _serial | _entries.count;
        _first[key.value] = _entries.count;
        var prints = Array<ulong>();
        bool bare = labels.count == 0;
        bool is_tuple = name == TUPLE and args.count >= 2;
        e.auto = name == AUTO;
        e.angled = name.contains("<");
        e.member_type = name.ends_with(".Type");
        e.special = ((name == FUNCTION or name == SHARED_FUNCTION) and args.count > 0)
            or (name == WEAK and args.count == 1)
            or is_tuple;
        e.labeled_tuple = is_tuple and labels.count > 0;
        ulong widest = 0;
        for (var a in args) {
            var arg = _entry(a);
            prints.append(arg.print);
            bare = bare and arg.bare == a;
            e.auto = e.auto or arg.auto;
            e.angled = e.angled or arg.angled;
            e.member_type = e.member_type or arg.member_type;
            e.special = e.special or arg.special;
            e.labeled_tuple = e.labeled_tuple or arg.labeled_tuple;
            if (arg.names.count > widest) {
                widest = arg.names.count;
                e.names = arg.names;
            }
        }
        e.names = _with_names(e.names, name, args);
        e.print = _print(name, flags, labels, prints);
        if (bare) {
            e.bare = made;
        } else {
            var bare_args = Array<ulong>();
            for (var a in args) {
                bare_args.append(_entry(a).bare);
            }
            e.bare = _intern(name, flags, Array<String>(), bare_args);
        }
        return made;
    }

    # `names` with `name` and the names of `args` added: a list of its own
    # only when one is missing from it.
    _with_names(names: String[], name: String, args: ulong[]): String[] {
        var out = names;
        bool own = false;
        if (!out.contains(name)) {
            out = out.clone();
            own = true;
            out.append(name);
        }
        for (var a in args) {
            var arg = _entry(a);
            if (arg.names === names) {
                continue;
            }
            for (var n in arg.names) {
                if (!out.contains(n)) {
                    if (!own) {
                        out = out.clone();
                        own = true;
                    }
                    out.append(n);
                }
            }
        }
        return out;
    }

    _spelling(id: ulong): String {
        var e = _entry(id);
        if (e.args.count == 0) {
            return e.name;
        }
        if (e.spelling.is_value()) {
            return e.spelling.value();
        }
        # Labels are not spelled: share the bare type's.
        if (e.bare != id) {
            var spelled = _spelling(e.bare);
            e.spelling = Optional<String>.Value(spelled);
            return spelled;
        }
        var out = StringBuilder();
        out.append(e.name);
        out.append("<");
        ulong i = 0;
        while (i < e.args.count) {
            if (i > 0) {
                out.append(", ");
            }
            out.append(_spelling(e.args[i]));
            i += 1;
        }
        out.append(">");
        var spelled = out.to_string();
        e.spelling = Optional<String>.Value(spelled);
        return spelled;
    }

    # The table's node for `id` as a caller may change it: the type and its
    # arguments copies of their own, the levels below shared. A parse used
    # to make every node afresh, so a pass may hold an argument of one as
    # its own type and change it, which must not change the table's.
    _handed(id: ulong): TypeName {
        var out = _node(id).copy();
        ulong i = 0;
        while (i < out.sub_types.count) {
            out.sub_types[i] = out.sub_types[i].copy();
            i += 1;
        }
        return out;
    }

    _node(id: ulong): TypeName {
        var e = _entry(id);
        if (e.bare != id) {
            return _node(e.bare);
        }
        if (e.node.is_value()) {
            return e.node.value();
        }
        var args = Array<TypeName>();
        for (var a in e.args) {
            args.append(_node(a));
        }
        var made = TypeName(name = e.name, sub_types = args, flags = e.flags);
        made.type_id = id;
        e.node = Optional<TypeName>.Value(made);
        return made;
    }
}

## Returns the table of the calling thread's running passes, if any.
##
## @returns the table
export type_ids(): TypeIds? {
    __ptr<TypeIds> cell = _cell;
    if (cell == __null or cell[0] == __null) {
        return Optional<TypeIds>.Empty;
    }
    return Optional<TypeIds>.Value(cell[0]);
}

## Gives the calling thread a new table of types, for the passes about to
## run: `end_type_ids` drops it, so it lives only as long as they do.
##
## @returns the table it replaces, for `end_type_ids`
export begin_type_ids(): TypeIds? {
    __ptr<TypeIds> cell = _cell;
    if (cell == __null) {
        cell = calloc(1, 8);
        _cell = cell;
    }
    var outer = type_ids();
    cell[0] = TypeIds();
    return outer;
}

## Drops the table `begin_type_ids` gave the calling thread.
##
## @param outer what `begin_type_ids` returned
export end_type_ids(outer: TypeIds?) {
    __ptr<TypeIds> cell = _cell;
    if (outer.is_value()) {
        cell[0] = outer.value();
    } else {
        cell[0] = __null;
    }
}

## Returns a hash of everything that tells types apart, labels included:
## what `TypeName.fingerprint` adds.
##
## @param ty the type
## @returns the hash
export type_print(ty: TypeName): ulong {
    var ids = type_ids();
    if (ids.is_value()) {
        return ids.value().facts(ty).print;
    }
    var prints = Array<ulong>();
    for (var sub in ty.sub_types) {
        prints.append(type_print(sub));
    }
    return _print(ty.name, ty.flags, ty.labels, prints);
}

_print(name: String, flags: TypeFlags, labels: String[], prints: ulong[]): ulong {
    var into = Fingerprint();
    into.add_text(name);
    into.add(prints.count);
    for (var p in prints) {
        into.add(p);
    }
    into.add(flags == TypeFlags.Function ? 1 : 0);
    into.add(labels.count);
    for (var l in labels) {
        into.add_text(l);
    }
    return into.value;
}
