## What the passes share: diagnostics at model locations, the facts about
## the model's declarations and expressions, and how types and names
## compare.

import compiler.ast;
import [Diagnostic, Location] from compiler.diagnostic;
import "builder";
import [Loc] from "loc";
import [Expression, StructDef, TypeName] from "model";
import [parse_type_string] from "type_name";

## Returns `loc` as a diagnostic's location.
##
## @param loc the location
## @returns the diagnostic location
export location_of(loc: Loc): Location {
    return Location(loc.file as ulong, loc.span);
}

## Where `loc` is, or nothing for a node with no position.
##
## @param loc the position
## @returns its location, if it has one
export known_location(loc: Loc): Location? {
    return loc.is_none() ? Optional<Location>.Empty : Optional<Location>.Value(location_of(loc));
}

## Returns the error `message` at `loc`.
##
## @param message the message
## @param loc where it points
## @returns the diagnostic
export error_at(message: String, loc: Loc): Diagnostic {
    return Diagnostic.error(message).at(location_of(loc));
}

## Facts about a struct definition.
export extend StructDef {
    ## Returns whether this is a value type (`[Value]`): copied, not
    ## counted.
    ##
    ## @returns true for a value type
    is_value(): bool {
        return has_bare_attribute(attributes, VALUE_ATTRIBUTE);
    }

    ## Returns whether this is a `[Value]` enum, whose cases' values share
    ## one storage after the tag, so only the case the tag names holds live
    ## values.
    ##
    ## @returns true for a value enum with a union layout
    has_union_layout(): bool {
        return is_value() and enum_cases.is_value();
    }
}

## A generic struct as declared, not one of its specializations.
_is_generic_base(st: StructDef): bool {
    return st.ty.sub_types.count > 0 and st.name == st.ty.name;
}

## Returns the location of an expression in the model.
##
## @param e the expression
## @returns its location, `Loc.none()` for one with none
export expression_loc(e: Expression): Loc {
    return _expression_loc(e);
}

## `expression_loc`, by the name the passes use.
_expression_loc(e: Expression): Loc {
    match (e) {
        SymbolRef(node) => {
            return node.loc;
        }
        MemberRef(node) => {
            return node.loc;
        }
        Binary(node) => {
            return node.loc;
        }
        Unary(node) => {
            return node.loc;
        }
        Cast(node) => {
            return node.loc;
        }
        Index(node) => {
            return node.loc;
        }
        ArrayIndex(node) => {
            return node.loc;
        }
        FunctionCall(node) => {
            return node.loc;
        }
        FunctionPointer(node) => {
            return node.loc;
        }
        FunctionRef(node) => {
            return node.loc;
        }
        MethodCall(node) => {
            return node.loc;
        }
        # A call through a function value is located at its callee.
        Invoke(node) => {
            return _expression_loc(node.callee);
        }
        MakeClosure(node) => {
            return node.loc;
        }
        ToTrait(node) => {
            return node.loc;
        }
        FromTrait(node) => {
            return node.loc;
        }
        Destructure(node) => {
            return node.loc;
        }
        Move(node) => {
            return node.loc;
        }
        StringLiteral(node) => {
            return node.loc;
        }
        StaticString(node) => {
            return node.loc;
        }
        Simd(node) => {
            return node.loc;
        }
        ClosureLiteral(c) => {
            return c.loc;
        }
        StaticValue(v) => {
            return v.loc;
        }
        StaticMember(m) => {
            return m.loc;
        }
        else => {
            return Loc.none();
        }
    }
}

## `ty` spelled one way, its integer types by their sized names (`i32` for
## `int`), a pointer `__ptr<T>` among them.
_canonical(ty: TypeName): TypeName {
    var parsed = parse_type_string(ty.to_string());
    var name = parsed.name;
    match (name) {
        "int" => {
            name = "i32";
        }
        "uint" => {
            name = "u32";
        }
        "long" => {
            name = "i64";
        }
        "ulong" => {
            name = "u64";
        }
        "short" => {
            name = "i16";
        }
        "ushort" => {
            name = "u16";
        }
        "char" => {
            name = "i8";
        }
        "byte" => {
            name = "u8";
        }
        "float" => {
            name = "f32";
        }
        "double" => {
            name = "f64";
        }
        else => {}
    }
    var args = Array<TypeName>();
    for (var t in parsed.sub_types) {
        args.append(_canonical(t));
    }
    return TypeName.with_args(name, args);
}

## `ty` spelled one way, its integer and float types by their sized names
## (`Range<i32>` for `Range<int>`), so every spelling of a type is one name.
##
## @param ty the type
## @returns its canonical spelling
export canonical_type(ty: TypeName): TypeName {
    return _canonical(ty);
}

## Compares two strings byte by byte: negative, 0 or positive.
_compare_bytes(a: String, b: String): long {
    ulong i = 0;
    while (i < a.size and i < b.size) {
        var x = a.byte_at(i);
        var y = b.byte_at(i);
        if (x != y) {
            return x < y ? -1 : 1;
        }
        i += 1;
    }
    if (a.size == b.size) {
        return 0;
    }
    return a.size < b.size ? -1 : 1;
}

## `ty` as the programmer spells it: `int` rather than the `i32` a literal
## is typed.
##
## @param ty the type
## @returns its display spelling
export constraint_spelled(ty: TypeName): String {
    var copy = ty.copy();
    _rename_sized(copy);
    return copy.display();
}

## `ty` with its integer and float types by the names programs use
## (`int` for `i32`): `_canonical` the other way.
_rename_sized(ty: TypeName) {
    match (ty.name) {
        "i8" => {
            ty.name = "char";
        }
        "u8" => {
            ty.name = "byte";
        }
        "i16" => {
            ty.name = "short";
        }
        "u16" => {
            ty.name = "ushort";
        }
        "i32" => {
            ty.name = "int";
        }
        "u32" => {
            ty.name = "uint";
        }
        "i64" => {
            ty.name = "long";
        }
        "u64" => {
            ty.name = "ulong";
        }
        "f32" => {
            ty.name = "float";
        }
        "f64" => {
            ty.name = "double";
        }
        else => {}
    }
    for (var t in ty.sub_types) {
        _rename_sized(t);
    }
}
