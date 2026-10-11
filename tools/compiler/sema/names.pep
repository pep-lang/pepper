## Names as the user writes them, for messages: `display_name`.

import [demangle] from compiler.diagnostic;
import [OVERLOAD_SEPARATOR] from compiler.link;

## Returns a whole mangled name as the user would write it, every namespace
## and overload member number removed wherever it appears:
## `Box<Point@geo/shapes>.area$2` is `Box<Point>.area`.
##
## @param name the mangled name
## @returns the name as written
export display_name(name: String): String {
    var shown = demangle($"'{name}'");
    return shown.substr_bytes(1, shown.size - 2);
}

## Returns the overload set a member of one belongs to: `f` for `f$2`, and
## any other name itself.
##
## @param member the member's name
## @returns the set's name
export set_name(member: String): String {
    var at = member.rfind(OVERLOAD_SEPARATOR);
    if (at < 0) {
        return member;
    }
    var start = at as ulong + 1;
    if (start >= member.size) {
        return member;
    }
    ulong i = start;
    while (i < member.size) {
        var b = member.byte_at(i);
        if (b < '0' or b > '9') {
            return member;
        }
        i += 1;
    }
    return member.substr_bytes(0, at as ulong);
}

## Returns a call's function name without its explicit type arguments:
## `make` for `make<String>`, and any other name itself.
##
## @param function the called name
## @returns the name before its type arguments
export without_type_arguments(function: String): String {
    var at = function.find("<");
    if (at < 0) {
        return function;
    }
    return function.substr_bytes(0, at as ulong);
}
