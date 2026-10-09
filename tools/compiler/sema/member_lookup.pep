## What a member access names, for the language server:
## `pepper_sema::member_lookup` in Pepper. The field or method that
## `lhs.name` (or `lhs.name(...)`) reaches, found by the static type of
## `lhs` in the checked model. Chains need nothing special: `x.y.z` types
## `x.y` first, as codegen would.

import [Loc] from "loc";
import [Block, Declaration, Expression, FunctionDef, Module, Statement, StructDef, TypeName, VariableDef] from "model";
import [set_name] from "names";
import "resolve_implicit_types";
import [PassState] from "state";
import [StructTable, static_type_of] from "static_type";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## What a member access names.
export enum FoundMember {
    ## A field.
    ##
    ## @param field its declaration
    Field(field: VariableDef),
    ## A method.
    ##
    ## @param method its declaration
    Method(method: FunctionDef),
}

## Where member `member` is declared.
##
## @param member the member
## @returns its declaration's location
export member_loc(member: FoundMember): Loc {
    match (member) {
        Field(field) => {
            return field.loc;
        }
        Method(method) => {
            return method.loc;
        }
    }
    return Loc.none();
}

## The type of the field whose name, in file `file`, covers `offset` in a
## member access (`core` in `worker.core`), as the owner's type has it.
##
## @param module the checked model
## @param state what the passes recorded
## @param file the file
## @param source its text
## @param offset the byte offset in it
## @returns the field's type; none for a method or no member access
export field_type(module: Module, state: PassState, file: uint, source: String, offset: ulong): TypeName? {
    var member = member_at(module, state, file, source, offset);
    if (member.is_empty()) {
        return Optional<TypeName>.Empty;
    }
    if (member.value() is Field(field)) {
        return Optional<TypeName>.Value(field.ty);
    }
    return Optional<TypeName>.Empty;
}

## The member whose name, in file `file`, covers `offset`: what the owner's
## static type declares under that name. Only a name the source spells
## there counts, so sema's own calls (`xs[i]` as `__index_get`, a `for`
## loop's `next()`) are not members.
##
## @param module the checked model
## @param state what the passes recorded
## @param file the file
## @param source its text
## @param offset the byte offset in it
## @returns the member; none when no member access is there, or its
##   owner's type is not a struct or trait the model knows
export member_at(module: Module, state: PassState, file: uint, source: String, offset: ulong): FoundMember? {
    var none = Optional<FoundMember>.Empty;
    var finder = _Finder(file, source, offset);
    # Only code the file declares can spell a name in it.
    for (var function in module.functions) {
        finder.search(function, Optional<TypeName>.Empty);
    }
    for (var st in module.structs) {
        var current = Optional<TypeName>.Value(st.ty);
        for (var c in st.constructors) {
            finder.search(c, current);
        }
        finder.search(st.destructor, current);
        for (var method in st.method_members) {
            finder.search(method, current);
        }
    }
    if (finder.owner.is_empty()) {
        return none;
    }
    var owner = finder.owner.value();
    var ty = static_type_of(owner, StructTable(module, memo = state.trait_types_memo()), finder.current, state);
    if (ty.is_empty()) {
        # A static call names the struct itself: `S.make()`.
        if (owner is SymbolRef(node)) {
            ty = Optional<TypeName>.Value(TypeName.named(node.id));
        } else {
            return none;
        }
    }
    var pointee = ty.value().to_string();
    while (pointee.ends_with("*")) {
        pointee = pointee.substr_bytes(0, pointee.size - 1);
    }
    var angle = pointee.find("<");
    var base = angle < 0 ? pointee : pointee.substr_bytes(0, angle as ulong);
    # A generic method's specialization (`pick<int>`) is `pick`; an
    # overload member (`add$2`) belongs to its set.
    var name = _before_angle(finder.name);
    var st = _struct_named(module, pointee, base);
    if (st.is_empty()) {
        return _trait_method(module, base, name, finder.used);
    }
    var found = _struct_member(st.value(), name);
    if (found.is_empty()) {
        return none;
    }
    # A captured local is a field of its closure's struct, declared where
    # it is used: not a member the source declares.
    var loc = member_loc(found.value());
    if (loc.is_none() or loc == finder.used or st.value().name.starts_with("__closure")) {
        return none;
    }
    return found;
}

## The type sema gave the local, closure parameter or module-scope variable
## whose name starts at `name` in file `file`: what `var worker =
## _async_worker()` infers. In generic code, the first specialization's
## type stands for all of them.
##
## @param module the checked model
## @param file the file
## @param name the byte offset of the variable's name
## @returns its type; none when no checked code declares one there
export local_type(module: Module, file: uint, name: ulong): TypeName? {
    # A module-scope variable (`const key = make_key()`).
    for (var global in module.globals) {
        if (_declares(global, file, name)) {
            return Optional<TypeName>.Value(global.ty);
        }
    }
    var functions = _functions(module);
    for (var function in functions) {
        if (function.body.is_value()) {
            var found = _local_in(function.body.value(), file, name);
            if (found.is_value()) {
                return found;
            }
        }
    }
    # A parameter whose type sema inferred: a closure's (`(a, b) => ...`),
    # which becomes a parameter of its struct's method.
    for (var function in functions) {
        for (var p in function.parameters) {
            if (_declares(p, file, name)) {
                return Optional<TypeName>.Value(p.ty);
            }
        }
    }
    return Optional<TypeName>.Empty;
}

# Finds the innermost member access whose name, in `file`, covers
# `offset`, with the type `this` has in the code around it.
struct _Finder {
    var file: uint;
    var source: String;
    var offset: ulong;
    # What was found: the access's owner, the member's name, `this`'s type
    # there and where the name is used.
    var owner: Expression?;
    var name: String;
    var current: TypeName?;
    var used: Loc;
    # `this`'s type in the function being searched.
    var _searching: TypeName?;

    construct(file: uint, source: String, offset: ulong) {
        this.file = file;
        this.source = source;
        this.offset = offset;
        this.owner = Optional<Expression>.Empty;
        this.name = "";
        this.current = Optional<TypeName>.Empty;
        this.used = Loc.none();
        this._searching = Optional<TypeName>.Empty;
    }

    # Searches `function`, a member of the struct `current` when it has
    # one.
    search(function: FunctionDef, current: TypeName?) {
        if (function.loc.file != file) {
            return;
        }
        _searching = current;
        for (var p in function.parameters) {
            if (p.default.is_value()) {
                rewrite_expression(p.default.value(), this);
            }
        }
        if (function.body.is_value()) {
            rewrite_block(function.body.value(), this);
        }
    }

    rewrite(e: Expression): Expression {
        match (e) {
            MemberRef(node) => {
                _consider(node.lhs, node.name, node.loc);
            }
            MethodCall(node) => {
                _consider(node.this_value, node.method, node.loc);
            }
            else => {}
        }
        return e;
    }

    # Keeps the access of `name` on `owner` at `loc` when its name covers
    # the offset, is spelled there, and is narrower than what was found.
    _consider(owner: Expression, name: String, loc: Loc) {
        var span = loc.span;
        if (loc.file != file or offset < span.start or offset > span.end or span.end > source.size) {
            return;
        }
        var member = set_name(_before_angle(name));
        if (source.substr_bytes(span.start, span.end - span.start) != member) {
            return;
        }
        if (this.owner.is_value() and span.end - span.start >= used.span.end - used.span.start) {
            return;
        }
        this.owner = Optional<Expression>.Value(owner);
        this.name = name;
        this.current = _searching;
        this.used = loc;
    }
}

extend _Finder with Rewriter;

# The struct whose type is `pointee`, else the first named `base`.
_struct_named(module: Module, pointee: String, base: String): StructDef? {
    for (var st in module.structs) {
        if (st.ty.to_string() == pointee) {
            return Optional<StructDef>.Value(st);
        }
    }
    for (var st in module.structs) {
        if (st.name == base) {
            return Optional<StructDef>.Value(st);
        }
    }
    return Optional<StructDef>.Empty;
}

# The method `name` the trait `base` declares, when a trait is used as a
# type (`_Driver`).
_trait_method(module: Module, base: String, name: String, used: Loc): FoundMember? {
    for (var t in module.traits) {
        if (t.name != base) {
            continue;
        }
        for (var m in t.methods) {
            if (m.name != name and set_name(m.name) != name) {
                continue;
            }
            if (m.loc.is_none() or m.loc == used) {
                return Optional<FoundMember>.Empty;
            }
            return Optional<FoundMember>.Value(FoundMember.Method(m));
        }
        return Optional<FoundMember>.Empty;
    }
    return Optional<FoundMember>.Empty;
}

# The field `name` of `st`, else its method of that name or set.
_struct_member(st: StructDef, name: String): FoundMember? {
    for (var field in st.field_members) {
        if (field.name == name) {
            return Optional<FoundMember>.Value(FoundMember.Field(field));
        }
    }
    for (var m in st.method_members) {
        if (m.name == name or set_name(m.name) == name) {
            return Optional<FoundMember>.Value(FoundMember.Method(m));
        }
    }
    for (var m in st.generic_methods) {
        if (m.name == name or set_name(m.name) == name) {
            return Optional<FoundMember>.Value(FoundMember.Method(m));
        }
    }
    return Optional<FoundMember>.Empty;
}

# Every function of `module` with a body to search: free functions, then
# each struct's constructors, destructor and methods.
_functions(module: Module): FunctionDef[] {
    var out = Array<FunctionDef>();
    for (var function in module.functions) {
        out.append(function);
    }
    for (var st in module.structs) {
        for (var c in st.constructors) {
            out.append(c);
        }
        out.append(st.destructor);
        for (var method in st.method_members) {
            out.append(method);
        }
    }
    return out;
}

# Whether `v` is declared with its name at `name` in `file`, with a type
# sema settled.
_declares(v: VariableDef, file: uint, name: ulong): bool {
    return v.loc.file == file and v.loc.span.start == name and !v.ty.is_auto() and !v.ty.is_empty();
}

# The type of the local `block` declares at `name`, nested blocks included.
_local_in(block: Block, file: uint, name: ulong): TypeName? {
    for (var statement in block.items) {
        var found = _local_in_statement(statement, file, name);
        if (found.is_value()) {
            return found;
        }
    }
    return Optional<TypeName>.Empty;
}

_local_in_statement(statement: Statement, file: uint, name: ulong): TypeName? {
    match (statement) {
        Declaration(declaration) => {
            if (declaration is Variable(v)) {
                if (_declares(v, file, name)) {
                    return Optional<TypeName>.Value(v.ty);
                }
            }
        }
        Block(block) => {
            return _local_in(block, file, name);
        }
        Branch(branch) => {
            var found = _local_in(branch.if_block, file, name);
            if (found.is_value() or branch.else_block.is_empty()) {
                return found;
            }
            return _local_in(branch.else_block.value(), file, name);
        }
        While(loop) => {
            return _local_in(loop.block, file, name);
        }
        else => {}
    }
    return Optional<TypeName>.Empty;
}
