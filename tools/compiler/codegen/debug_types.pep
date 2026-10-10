## Debug types for `-g` (see `debug.pep`): `crates/pepper-codegen/src/debug_types.rs`
## in Pepper. Pepper's numeric types are base types under their Pepper
## names; a raw pointer (`__ptr<T>`) points at its pointee's type; a plain
## enum is an enumeration; a tuple a structure with members `0`, `1`, and
## so on; a trait value its object and vtable pointers; a struct reference
## (which covers a generic's instantiation such as `Array<int>`, an enum
## with payloads and a function type's object) a pointer to a structure
## type with every field, the `__refcount`/`__weakcount` head included, so
## ownership bugs can be diagnosed in the debugger; and a value struct
## (`[Value]`, such as `Optional<T>` and `Result<T>`) the structure itself,
## which has no head.
##
## Types refer to each other through fields and elements, in cycles too
## (`struct Node { Node next; }`). A struct's type is built after its
## fields' structs, from a work stack; a reference back to a struct or
## tuple still being built is a declaration, which the debugger resolves
## to the definition by name.

import llvm;
import compiler.sema;
import [display_name, is_pointer_name, parse_type_string, pointee_name] from compiler.sema;
import [DebugInfo] from "debug";
import [Generator] from "generator";
import [simd_shape] from "types";

const _POINTER_BITS: ulong = 64;

## The width and encoding of a Pepper numeric type.
_scalar(name: String): (ulong, llvm.DwarfEncoding)? {
    match (name) {
        "bool", "i1" => {
            return Optional<(ulong, llvm.DwarfEncoding)>.Value((8, llvm.DwarfEncoding.Boolean));
        }
        "i8", "char" => {
            return Optional<(ulong, llvm.DwarfEncoding)>.Value((8, llvm.DwarfEncoding.SignedChar));
        }
        "u8", "byte" => {
            return Optional<(ulong, llvm.DwarfEncoding)>.Value((8, llvm.DwarfEncoding.UnsignedChar));
        }
        "i16", "short" => {
            return Optional<(ulong, llvm.DwarfEncoding)>.Value((16, llvm.DwarfEncoding.Signed));
        }
        "u16", "ushort" => {
            return Optional<(ulong, llvm.DwarfEncoding)>.Value((16, llvm.DwarfEncoding.Unsigned));
        }
        "i32", "int" => {
            return Optional<(ulong, llvm.DwarfEncoding)>.Value((32, llvm.DwarfEncoding.Signed));
        }
        "u32", "uint" => {
            return Optional<(ulong, llvm.DwarfEncoding)>.Value((32, llvm.DwarfEncoding.Unsigned));
        }
        "i64", "long" => {
            return Optional<(ulong, llvm.DwarfEncoding)>.Value((64, llvm.DwarfEncoding.Signed));
        }
        "u64", "ulong" => {
            return Optional<(ulong, llvm.DwarfEncoding)>.Value((64, llvm.DwarfEncoding.Unsigned));
        }
        "f32", "float" => {
            return Optional<(ulong, llvm.DwarfEncoding)>.Value((32, llvm.DwarfEncoding.Float));
        }
        "f64", "double" => {
            return Optional<(ulong, llvm.DwarfEncoding)>.Value((64, llvm.DwarfEncoding.Float));
        }
        else => {
            return Optional<(ulong, llvm.DwarfEncoding)>.Empty;
        }
    }
}

## The name a program writes for a numeric type sema spells by width (an
## integer literal's `i32` is an `int`).
_written(name: String): String {
    match (name) {
        "i1" => {
            return "bool";
        }
        "i16" => {
            return "short";
        }
        "u16" => {
            return "ushort";
        }
        "i32" => {
            return "int";
        }
        "u32" => {
            return "uint";
        }
        "i64" => {
            return "long";
        }
        "u64" => {
            return "ulong";
        }
        "f32" => {
            return "float";
        }
        "f64" => {
            return "double";
        }
        else => {
            return name;
        }
    }
}

## A type's name as the user writes it: `Point@geo` is `Point`, and the
## tuple `(int, Node@geo)` is `(int, Node)`.
_shown(name: String): String {
    return display_name(parse_type_string(name).display());
}

## `name` under its raw pointers: the innermost pointee, and how many
## pointers lead to it (`int` and 2 for `__ptr<__ptr<int>>`).
_pointer_base(name: String): (String, ulong) {
    var base = name;
    ulong pointers = 0;
    while (is_pointer_name(base)) {
        base = pointee_name(base).value();
        pointers += 1;
    }
    return (base, pointers);
}

extend Generator {
    ## The debug type of a value of sema type `name`: none when debug info
    ## is off or does not describe it.
    debug_type(name: String): llvm.Metadata? {
        if (!debug.is_value()) {
            return Optional<llvm.Metadata>.Empty;
        }
        var known = debug.value().types.try_get(name);
        if (known.is_value()) {
            return known;
        }
        # `__ptr<__ptr<T>>` is `T` behind two pointers: built from the inside
        # out.
        var (base, pointers) = _pointer_base(name);
        llvm.Metadata? base_type;
        if (_is_debug_struct(base)) {
            base_type = _debug_struct_reference(base);
        } else if (tuples.contains(base)) {
            base_type = _debug_tuple(base);
        } else if (types.is_trait(base)) {
            base_type = Optional<llvm.Metadata>.Value(_debug_trait_value(base));
        } else {
            base_type = _debug_value_type(base, pointers > 0);
        }
        if (!base_type.is_value()) {
            return Optional<llvm.Metadata>.Empty;
        }
        return Optional<llvm.Metadata>.Value(_debug_pointers(base, pointers, base_type.value()));
    }

    # Whether `name` is a struct the debug info describes as one: not a
    # trait, a tuple or a weak trait value.
    _is_debug_struct(name: String): bool {
        return structs.contains(name) and !types.is_trait(name) and !tuples.contains(name);
    }

    # `ty` (the type of `base`) behind `pointers` raw pointers.
    _debug_pointers(base: String, pointers: ulong, ty: llvm.Metadata): llvm.Metadata {
        var spelled = base;
        var out = ty;
        for (var _ in 0..pointers) {
            spelled = $"__ptr<{spelled}>";
            out = _debug_pointer(spelled, out);
        }
        return out;
    }

    # The type of `base` when it is not a struct: a number, a plain enum, a
    # vector, or `void` behind a pointer (`pointee`).
    _debug_value_type(base: String, pointee: bool): llvm.Metadata? {
        if (base == "void" and pointee) {
            return Optional<llvm.Metadata>.Value(_debug_base_type("void", 8, llvm.DwarfEncoding.UnsignedChar));
        }
        var scalar = _scalar(base);
        if (scalar.is_value()) {
            var (bits, encoding) = scalar.value();
            return Optional<llvm.Metadata>.Value(_debug_base_type(_written(base), bits, encoding));
        }
        var shape = simd_shape(base);
        if (shape.is_value()) {
            var (lane, count) = shape.value();
            return _debug_vector(base, lane, count);
        }
        if (debug.value().enums.contains(base)) {
            return _debug_enum(base);
        }
        var found = types.get(base);
        if (found.is_value() and found.value().kind() == llvm.TypeKind.Integer) {
            return Optional<llvm.Metadata>.Value(
                _debug_base_type(_shown(base), found.value().int_width() as ulong, llvm.DwarfEncoding.Signed)
            );
        }
        return Optional<llvm.Metadata>.Empty;
    }

    # A vector, `__simd<T, N>`: an array of its `N` lanes, or, for a mask's
    # `bool` lanes (one bit each in memory), an unsigned number of its bits.
    _debug_vector(name: String, lane: String, count: uint): llvm.Metadata? {
        var vector = types.get(name);
        if (!vector.is_value() or vector.value().kind() != llvm.TypeKind.Vector) {
            return Optional<llvm.Metadata>.Empty;
        }
        var bits = machine.store_size_of(vector.value()) * 8;
        if (lane == "bool") {
            return Optional<llvm.Metadata>.Value(_debug_base_type(_shown(name), bits, llvm.DwarfEncoding.Unsigned));
        }
        var scalar = _scalar(lane);
        if (!scalar.is_value()) {
            return Optional<llvm.Metadata>.Empty;
        }
        var (lane_bits, encoding) = scalar.value();
        var lane_type = _debug_base_type(_written(lane), lane_bits, encoding);
        var info = debug.value();
        var known = info.types.try_get(name);
        if (known.is_value()) {
            return known;
        }
        var made = info.array(bits, lane_bits as uint, lane_type, count as long);
        info.types[name] = made;
        return Optional<llvm.Metadata>.Value(made);
    }

    _debug_base_type(name: String, bits: ulong, encoding: llvm.DwarfEncoding): llvm.Metadata {
        var info = debug.value();
        var known = info.types.try_get(name);
        if (known.is_value()) {
            return known.value();
        }
        var made = info.builder.basic_type(name, bits, encoding);
        info.types[name] = made;
        return made;
    }

    _debug_pointer(name: String, pointee: llvm.Metadata): llvm.Metadata {
        var info = debug.value();
        var known = info.types.try_get(name);
        if (known.is_value()) {
            return known.value();
        }
        var made = info.builder.pointer_type(pointee, _POINTER_BITS, _shown(name));
        info.types[name] = made;
        return made;
    }

    # A reference to the struct `name`: a pointer to its structure type.
    # Structs reach each other through fields to any depth (and in cycles),
    # so their types are built from a work stack, after the structs their
    # fields name; a field naming a struct still being built points at a
    # declaration of it, which the debugger resolves to the definition by
    # name.
    _debug_struct_reference(name: String): llvm.Metadata? {
        var info = debug.value();
        if (info.building.contains(name)) {
            return Optional<llvm.Metadata>.Value(_debug_declaration(name));
        }
        var building = HashSet<String>();
        var stack = Array<(String, bool)>();
        stack.append((name, false));
        while (stack.count > 0) {
            var (current, fields_done) = stack.pop();
            if (info.types.contains(current)) {
                continue;
            }
            if (!fields_done) {
                building.insert(current);
                info.building.insert(current);
                stack.append((current, true));
                for (var (_, field) in structs[current].fields) {
                    var (base, _) = _pointer_base(field);
                    if (_is_debug_struct(base) and !building.contains(base) and !info.types.contains(base)) {
                        stack.append((base, false));
                    }
                }
                continue;
            }
            var structure = _debug_structure(current);
            building.remove(current);
            info.building.remove(current);
            if (values.contains(current)) {
                # A value struct is held inline: the structure itself.
                info.types[current] = structure;
                continue;
            }
            # Named as the user writes the type: a reference is the struct.
            info.types[current] = info.builder.pointer_type(structure, _POINTER_BITS, _shown(current));
        }
        return info.types.try_get(name);
    }

    # The structure type of the struct `name`, whose fields' structs are
    # built already or being built.
    _debug_structure(name: String): llvm.Metadata {
        var desc = structs[name];
        var info = debug.value();
        var members = Array<llvm.Metadata>();
        for (var index in 0..desc.fields.count) {
            var (field, ty) = desc.fields[index];
            # A field's struct is built already, or is being built: never
            # build one from here, which would recurse as deep as the
            # structs nest.
            var (base, pointers) = _pointer_base(ty);
            llvm.Metadata? member_type;
            if (_is_debug_struct(base)) {
                var known = info.types.try_get(base);
                var reference = known.is_value() ? known.value() : _debug_declaration(base);
                member_type = Optional<llvm.Metadata>.Value(_debug_pointers(base, pointers, reference));
            } else {
                member_type = debug_type(ty);
            }
            if (!member_type.is_value()) {
                continue;
            }
            var offset = machine.offset_of(desc.llvm_type, index as uint) * 8;
            var bits = info.size_in_bits(member_type.value());
            # An enum's payload field `Case.value` is `Case__value`: a
            # debugger's expressions and natvis cannot name a member with a
            # dot in it.
            var loc = index < desc.field_locs.count ? desc.field_locs[index] : desc.loc;
            members.append(info.member(field.replace(".", "__"), loc, bits, offset, member_type.value()));
        }
        return info.structure(_shown(name), desc.loc, desc.size * 8, members, name);
    }

    # A struct or tuple whose type is still being built: a declaration of
    # it, behind a pointer for a struct reference. A value (a tuple or a
    # value struct) is held inline, so its declaration carries its size.
    _debug_declaration(name: String): llvm.Metadata {
        var info = debug.value();
        ulong size = 0;
        bool inline = false;
        if (values.contains(name)) {
            size = structs[name].size * 8;
            inline = true;
        } else if (tuples.contains(name)) {
            var ty = types.get(name);
            size = ty.is_value() ? machine.size_of(ty.value()) * 8 : 0;
            inline = true;
        }
        var declared = info.structure(_shown(name), sema.Loc.none(), size, Array<llvm.Metadata>(), name, true);
        if (inline) {
            return declared;
        }
        return info.builder.pointer_type(declared, _POINTER_BITS, _shown(name));
    }

    # A plain enum: an enumeration of its cases over its representation.
    _debug_enum(name: String): llvm.Metadata? {
        var info = debug.value();
        var (loc, representation, cases) = info.enums[name];
        var scalar = _scalar(representation);
        if (!scalar.is_value()) {
            return Optional<llvm.Metadata>.Empty;
        }
        var (bits, encoding) = scalar.value();
        var underlying = _debug_base_type(representation, bits, encoding);
        var is_unsigned = encoding == llvm.DwarfEncoding.Unsigned or encoding == llvm.DwarfEncoding.UnsignedChar;
        var enumerators = Array<llvm.Metadata>();
        for (var (case, value) in cases) {
            enumerators.append(info.enumerator(case, value, is_unsigned));
        }
        var made = info.enumeration(_shown(name), loc, bits, enumerators, underlying);
        info.types[name] = made;
        return Optional<llvm.Metadata>.Value(made);
    }

    # A tuple: a structure with a member per element, named `0`, `1`, and
    # so on. An element that leads back to the tuple, through a struct, is
    # a declaration (see the module comment).
    _debug_tuple(name: String): llvm.Metadata? {
        var info = debug.value();
        if (info.building.contains(name)) {
            return Optional<llvm.Metadata>.Value(_debug_declaration(name));
        }
        var elements = tuples[name];
        var llvm_type = types.get(name);
        if (!llvm_type.is_value()) {
            return Optional<llvm.Metadata>.Empty;
        }
        info.building.insert(name);
        var members = Array<llvm.Metadata>();
        for (var index in 0..elements.count) {
            var element_type = debug_type(elements[index]);
            if (!element_type.is_value()) {
                continue;
            }
            var offset = machine.offset_of(llvm_type.value(), index as uint) * 8;
            var bits = info.size_in_bits(element_type.value());
            members.append(info.member($"{index}", sema.Loc.none(), bits, offset, element_type.value()));
        }
        info.building.remove(name);
        var size = machine.size_of(llvm_type.value()) * 8;
        var made = info.structure(_shown(name), sema.Loc.none(), size, members, name);
        info.types[name] = made;
        return Optional<llvm.Metadata>.Value(made);
    }

    # A trait value (`Shape`): the object it refers to and its vtable.
    _debug_trait_value(name: String): llvm.Metadata {
        var info = debug.value();
        var byte = _debug_base_type("void", 8, llvm.DwarfEncoding.UnsignedChar);
        var pointer = _debug_pointers("void", 1, byte);
        var members = Array<llvm.Metadata>();
        var names = ["object", "vtable"];
        for (var index in 0..names.count) {
            members.append(info.member(names[index], sema.Loc.none(), _POINTER_BITS, index * _POINTER_BITS, pointer));
        }
        var made = info.structure(_shown(name), sema.Loc.none(), 2 * _POINTER_BITS, members, name);
        info.types[name] = made;
        return made;
    }
}
