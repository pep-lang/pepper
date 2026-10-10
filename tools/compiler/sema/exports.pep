## `[Export]`: free functions that C code calls, as `passes::exports` in
## Pepper.
##
## `[Export]` on a free function gives it a C symbol, its declared name or
## the one `[Export(name = "c_name")]` gives. Each parameter and the result
## must be a type C can hold: a number, `bool`, a pointer, a C function
## pointer, a `String` (UTF-8 bytes: a pointer and a size in, a
## NUL-terminated copy out, which C frees with `STRING_FREE`), or a
## reference to a struct, which C holds as an opaque handle. Each struct a
## handle names also gets `<struct>_retain` and `<struct>_release`, which
## step its reference count. `[Export]` anywhere else is a warning.

import compiler.ast;
import [Diagnostic, Location] from compiler.diagnostic;
import [demangle_name] from compiler.link;
import [known_location, location_of] from "common";
import "confinement";
import "copies";
import [Export, Exports, Handle, is_export_string, STRING_FREE] from "export_table";
import [Loc] from "loc";
import [FunctionDef, Module, StructDef, TypeName] from "model";
import [set_name] from "names";
import [PassState] from "state";
import "type_name";

## The attribute that exports a function to C.
export const EXPORT_ATTRIBUTE = "Export";

## Checks every `[Export]` and records the program's exports in
## `state.exports`. Misplaced attributes are warnings in `state.notes`; an
## exported function that C cannot call is an error.
##
## @param module the model
## @param state the passes' state
export collect_exports(module: Module, state: PassState) {
    var warnings = Array<Diagnostic>();
    for (var st in module.structs) {
        # A specialization repeats its generic's attributes.
        if (st.name != st.ty.name and st.ty.is_generic()) {
            continue;
        }
        _misplaced(warnings, st.attributes, st.loc, "a struct");
        for (var method in st.method_members) {
            _misplaced(warnings, method.attributes, method.loc, "a method");
        }
        for (var method in st.generic_methods) {
            _misplaced(warnings, method.attributes, method.loc, "a method");
        }
        for (var method in st.constructors) {
            _misplaced(warnings, method.attributes, method.loc, "a method");
        }
    }
    for (var t in module.traits) {
        _misplaced(warnings, t.attributes, t.loc, "a trait");
    }
    for (var e in module.externs) {
        _misplaced(warnings, e.attributes, e.loc, "an extern");
    }
    for (var g in module.globals) {
        _misplaced(warnings, g.attributes, g.loc, "a variable");
    }
    for (var f in module.functions) {
        if (!f.parent.is_value() and _is_generic(f)) {
            _misplaced(warnings, f.attributes, f.loc, "a generic function");
        }
    }
    state.notes.append_all(warnings);

    var exports = Exports();
    var symbols = HashMap<String, Loc>();
    var handles = HashMap<String, Handle>();
    for (var function in module.functions) {
        if (function.parent.is_value() or _is_generic(function)) {
            continue;
        }
        var attribute = _export_attribute(function.attributes);
        if (!attribute.is_value()) {
            continue;
        }
        var symbol = _symbol_of(attribute.value(), function);
        if (symbol.is_err()) {
            state.report(symbol.error());
            return;
        }
        if (!function.body.is_value() and !module.stripped.contains(function.loc)) {
            continue;
        }
        var parameters = Array<(String, TypeName)>();
        for (var parameter in function.parameters) {
            var loc = parameter.type_loc.is_none() ? parameter.loc : parameter.type_loc;
            var checked = _check_type(module, state, parameter.ty, symbol.value(), loc, handles);
            if (checked.is_value()) {
                state.report(checked.value());
                return;
            }
            parameters.append((parameter.name, parameter.ty));
        }
        var checked = _check_type(module, state, function.ty, symbol.value(), function.loc, handles);
        if (checked.is_value()) {
            state.report(checked.value());
            return;
        }
        var first = symbols.try_get(symbol.value());
        symbols[symbol.value()] = function.loc;
        if (first.is_value()) {
            state.report(
                _error_at_known(
                    $"two functions are exported as '{symbol.value()}'",
                    function.loc
                ).with_note(
                    "first exported here", known_location(first.value())
                ).with_note("give one a different C name with [Export(name = \"...\")]", Optional<Location>.Empty)
            );
            return;
        }
        exports.functions.append(Export(symbol.value(), function.name, parameters, function.ty, function.loc));
    }
    for (var e in exports.functions) {
        if (is_export_string(e.result)) {
            exports.frees_strings = true;
        }
    }
    var free = symbols.try_get(STRING_FREE);
    if (free.is_value() and exports.frees_strings) {
        state.report(
            _error_at_known($"'{STRING_FREE}' is exported already, to free the strings exports return", free.value())
        );
        return;
    }
    var names = Array<String>();
    for (var (name, _) in handles) {
        names.append(name);
    }
    names.sort((a: String, b: String) => a < b ? -1 : (a > b ? 1 : 0));
    for (var name in names) {
        var handle = handles[name];
        for (var symbol in [handle.retain, handle.release]) {
            var at = symbols.try_get(symbol);
            if (at.is_value()) {
                state.report(
                    _error_at_known(
                        $"'{symbol}' is exported already, as the handle function of '{handle.c_type}'", at.value()
                    )
                );
                return;
            }
        }
        exports.handles.append(handle);
    }
    exports.functions.sort((a: Export, b: Export) => a.symbol < b.symbol ? -1 : (a.symbol > b.symbol ? 1 : 0));
    state.exports = exports;
}

_misplaced(warnings: Diagnostic[], attributes: ast.Attribute[], loc: Loc, what: String) {
    var attribute = _export_attribute(attributes);
    if (attribute.is_value()) {
        warnings.append(
            Diagnostic.warning(
                $"'Export' has no effect on {what}; only a free function can be called from C"
            ).at(location_of(Loc.at(loc.file, attribute.value().span)))
        );
    }
}

## The `[Export]` attribute among `attributes`, if there is one.
_export_attribute(attributes: ast.Attribute[]): ast.Attribute? {
    for (var a in attributes) {
        if (a.name() == EXPORT_ATTRIBUTE) {
            return Optional<ast.Attribute>.Value(a);
        }
    }
    return Optional<ast.Attribute>.Empty;
}

_is_generic(function: FunctionDef): bool {
    return function.generic_params.count > 0 or function.is_generic_func;
}

## The C symbol `[Export]` or `[Export(name = "c_name")]` gives
## `function`.
_symbol_of(attribute: ast.Attribute, function: FunctionDef): Result<String, Diagnostic> {
    var file = function.loc.file;
    String? symbol = Optional<String>.Empty;
    match (attribute.body) {
        FunctionCall(_, arguments, _) => {
            for (var argument in arguments) {
                var value = argument;
                var named = false;
                match (argument) {
                    NamedArgument(name, name_span, inner, _) => {
                        if (name != "name") {
                            return Result<String, Diagnostic>.Err(
                                _error_at_known(
                                    "'Export' takes only 'name', the C symbol: [Export(name = \"c_name\")]",
                                    Loc.at(file, name_span)
                                )
                            );
                        }
                        value = inner;
                        named = true;
                    }
                    else => {}
                }
                if (!named) {
                    return Result<String, Diagnostic>.Err(
                        _error_at_known(
                            "'Export' takes only 'name', the C symbol: [Export(name = \"c_name\")]",
                            Loc.at(file, value.span())
                        )
                    );
                }
                var text = _string_literal(value);
                if (!text.is_value()) {
                    return Result<String, Diagnostic>.Err(
                        _error_at_known("'Export' argument 'name' must be a string", Loc.at(file, value.span()))
                    );
                }
                if (!_is_c_identifier(text.value())) {
                    return Result<String, Diagnostic>.Err(
                        _error_at_known($"'{text.value()}' is not a C identifier", Loc.at(file, value.span()))
                    );
                }
                symbol = text;
            }
        }
        else => {}
    }
    var out = symbol.is_value() ? symbol.value() : set_name(demangle_name(function.name));
    if (out == "main") {
        return Result<String, Diagnostic>.Err(_error_at_known("cannot export a function as 'main'", function.loc));
    }
    return Result<String, Diagnostic>.Ok(out);
}

_string_literal(e: ast.Expression): String? {
    match (e) {
        Literal(value, _) => {
            match (value) {
                String(text) => {
                    return Optional<String>.Value(text);
                }
                else => {}
            }
        }
        else => {}
    }
    return Optional<String>.Empty;
}

_is_ascii_letter(b: byte): bool {
    return (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z');
}

_is_ascii_digit(b: byte): bool {
    return b >= '0' and b <= '9';
}

## Whether `name` is a C identifier: a letter or `_`, then letters, digits
## and `_`.
_is_c_identifier(name: String): bool {
    if (name.size == 0) {
        return false;
    }
    var first = name.byte_at(0);
    if (!_is_ascii_letter(first) and first != '_') {
        return false;
    }
    ulong i = 1;
    while (i < name.size) {
        var b = name.byte_at(i);
        if (!_is_ascii_letter(b) and !_is_ascii_digit(b) and b != '_') {
            return false;
        }
        i += 1;
    }
    return true;
}

## Checks that C can hold `ty` (a parameter or result of the export
## `symbol`, written at `loc`), recording the handle functions of a
## struct; the error when it cannot.
_check_type(
    module: Module, state: PassState, ty: TypeName, symbol: String, loc: Loc, handles: HashMap<String, Handle>
): Diagnostic? {
    if (c_type(ty, state.enum_representations).is_value() or is_export_string(ty)) {
        return Optional<Diagnostic>.Empty;
    }
    var shown = demangle_name(ty.to_string());
    var key = ty.to_string();
    StructDef? found = Optional<StructDef>.Empty;
    for (var st in module.structs) {
        if (st.name == key) {
            found = Optional<StructDef>.Value(st);
            break;
        }
    }
    var why = "C passes numbers, 'bool', pointers and struct handles";
    if (found.is_value()) {
        var st = found.value();
        var is_value = ast.has_attribute(st.attributes, "Value");
        if (!is_value and !st.ty.is_generic() and !st.ty.is_tuple() and !ty.is_weak() and !st.enum_cases.is_value()) {
            if (!handles.contains(st.name)) {
                var c_name = demangle_name(st.name);
                var base = _snake_case(c_name);
                handles[st.name] = Handle(st.name, c_name, $"{base}_retain", $"{base}_release");
            }
            return Optional<Diagnostic>.Empty;
        }
        why = is_value ?
            "a value struct has no handle; pass its fields" :
            "only a non-generic struct passes to C, as a handle";
    }
    return Optional<Diagnostic>.Value(
        _error_at_known(
            $"cannot export '{symbol}': C cannot hold '{shown}'", loc
        ).with_note(why, Optional<Location>.Empty)
    );
}

## `ByteBuffer` as `byte_buffer`.
_snake_case(name: String): String {
    var out = "";
    bool previous_lower = false;
    ulong i = 0;
    while (i < name.size) {
        var b = name.byte_at(i);
        var one = name.substr_bytes(i, 1);
        if (b >= 'A' and b <= 'Z') {
            if (previous_lower) {
                out += "_";
            }
            out += one.lower();
            previous_lower = false;
        } else {
            out += one;
            previous_lower = (b >= 'a' and b <= 'z') or _is_ascii_digit(b);
        }
        i += 1;
    }
    return out;
}

## Returns the C spelling of a type that is not a struct handle: a number,
## `bool`, `void`, a pointer or a C function pointer (spelled with `{}`
## where the declared name goes, see `declarator`); none for any other
## type. An enum is spelled as the integer it is stored as.
##
## @param ty the type
## @returns the C type
export c_type(
    ty: TypeName, representations: HashMap<String, (String, long)> = HashMap<String, (String, long)>()
): String? {
    var none = Optional<String>.Empty;
    if (ty.is_extern_function_type()) {
        var result = c_type(ty.sub_types[0], representations);
        if (!result.is_value()) {
            return none;
        }
        var parameters = Array<String>();
        ulong i = 1;
        while (i < ty.sub_types.count) {
            var p = c_type(ty.sub_types[i], representations);
            if (!p.is_value()) {
                return none;
            }
            parameters.append(declarator(p.value(), ""));
            i += 1;
        }
        var listed = parameters.count == 0 ? "void" : ", ".join(parameters);
        return Optional<String>.Value(declarator(result.value(), "(*{})(" + listed + ")"));
    }
    if (ty.is_pointer()) {
        # C writes `__ptr<T>` as `T*`, and a pointer to anything it has no
        # name for as a `void*`.
        var target = c_type(ty.sub_types[0], representations);
        var spelled = target.is_value() and target.value().find("{") < 0 ? target.value() : "void";
        return Optional<String>.Value($"{spelled}*");
    }
    if (!ty.is_scalar() or ty.sub_types.count > 0) {
        return none;
    }
    var name = ty.name;
    var stored = representations.try_get(name);
    if (stored.is_value()) {
        var (representation, _) = stored.value();
        name = representation;
    }
    return _c_number(name);
}

## The C spelling of primitive `name`.
_c_number(name: String): String? {
    if (name == "void") {
        return Optional<String>.Value("void");
    }
    if (name == "bool") {
        return Optional<String>.Value("bool");
    }
    if (name == "char") {
        return Optional<String>.Value("char");
    }
    if (name == "i8") {
        return Optional<String>.Value("int8_t");
    }
    if (name == "u8" or name == "byte") {
        return Optional<String>.Value("uint8_t");
    }
    if (name == "i16" or name == "short") {
        return Optional<String>.Value("int16_t");
    }
    if (name == "u16" or name == "ushort") {
        return Optional<String>.Value("uint16_t");
    }
    if (name == "i32" or name == "int") {
        return Optional<String>.Value("int32_t");
    }
    if (name == "u32" or name == "uint") {
        return Optional<String>.Value("uint32_t");
    }
    if (name == "i64" or name == "long") {
        return Optional<String>.Value("int64_t");
    }
    if (name == "u64" or name == "ulong") {
        return Optional<String>.Value("uint64_t");
    }
    if (name == "f32" or name == "float") {
        return Optional<String>.Value("float");
    }
    if (name == "f64" or name == "double") {
        return Optional<String>.Value("double");
    }
    return Optional<String>.Empty;
}

## Returns a C declaration of `name` with type `c_type`: `int32_t count`,
## or for a function pointer, the name inside its parentheses.
##
## @param c_type the C type
## @param name the declared name, or empty
## @returns the declaration
export declarator(c_type: String, name: String): String {
    var at = c_type.find("{}");
    if (at >= 0) {
        return c_type.substr_bytes(0, at as ulong)
            + name
            + c_type.substr_bytes(at as ulong + 2, c_type.size - at as ulong - 2);
    }
    if (name.size == 0) {
        return c_type;
    }
    return $"{c_type} {name}";
}

## Returns the C type of `ty` in a library's header: as `c_type`, a
## handle's pointer, or for a `String` result, `char*`.
_header_type(ty: TypeName, handles: Handle[], representations: HashMap<String, (String, long)>): String {
    if (is_export_string(ty)) {
        return "char*";
    }
    var key = ty.to_string();
    for (var handle in handles) {
        if (handle.structure == key) {
            return handle.c_type + "*";
        }
    }
    var spelled = c_type(ty, representations);
    return spelled.is_value() ? spelled.value() : "void*";
}

## Returns the declarations of a C header for `exports`: the handle types,
## their retain and release functions, and each exported function, as
## `header_declarations` in `passes/exports.rs` writes them. `header`
## wraps them in an include guard.
##
## @param exports what the program exports
## @param representations each enum's stored type, by name
##   (`PassState.enum_representations`)
## @returns the declarations
export header_declarations(exports: Exports, representations: HashMap<String, (String, long)>): String {
    var out = StringBuilder();
    if (!exports.handles.is_empty) {
        out.append("/* Opaque handles to Pepper objects. A handle a function returns is one\n");
        out.append(" * reference, which the caller releases; a handle passed in stays the\n");
        out.append(" * caller's. */\n");
        for (var handle in exports.handles) {
            out.append($"typedef struct {handle.c_type} {handle.c_type};\n");
        }
        out.append("\n");
        for (var handle in exports.handles) {
            out.append($"void {handle.retain}({handle.c_type}* handle);\n");
            out.append($"void {handle.release}({handle.c_type}* handle);\n");
        }
        out.append("\n");
    }
    if (exports.frees_strings) {
        out.append("/* A string a function returns is a NUL-terminated UTF-8 copy, which the\n");
        out.append(" * caller frees with this. */\n");
        out.append($"void {STRING_FREE}(char* text);\n\n");
    }
    for (var e in exports.functions) {
        # A `String` parameter is its bytes and their size.
        var parameters = Array<String>();
        for (var (name, ty) in e.parameters) {
            if (is_export_string(ty)) {
                parameters.append($"const char* {name}, size_t {name}_size");
            } else {
                parameters.append(declarator(_header_type(ty, exports.handles, representations), name));
            }
        }
        var listed = parameters.is_empty ? "void" : ", ".join(parameters);
        var result = _header_type(e.result, exports.handles, representations);
        out.append(declarator(result, $"{e.symbol}({listed})") + ";\n");
    }
    return out.to_string();
}

## Returns a whole C header named `file_name` (`foo.h`) around
## `declarations` (`header_declarations`). `libraries` are those a program
## that links a static library must link too, which the header names in a
## comment.
##
## @param file_name the header's file name
## @param declarations what it declares
## @param libraries the libraries to link with a static library, by name
## @returns the header's text
export header(file_name: String, declarations: String, libraries: String[]): String {
    var guard = StringBuilder();
    for (var i in 0..file_name.size) {
        var b = file_name.byte_at(i);
        guard.append(_is_ascii_letter(b) or _is_ascii_digit(b) ? file_name.substr_bytes(i, 1).upper() : "_");
    }
    var name = guard.to_string();
    if (!name.is_empty and _is_ascii_digit(name.byte_at(0))) {
        name = "_" + name;
    }
    var out = StringBuilder();
    out.append($"/* {file_name}: generated by the Pepper compiler. Do not edit. */\n");
    if (!libraries.is_empty) {
        var flags = Array<String>();
        for (var library in libraries) {
            flags.append("-l" + library);
        }
        out.append($"/* Link the static library with: {" ".join(flags)} */\n");
    }
    out.append($"#ifndef {name}\n#define {name}\n\n#include <stdbool.h>\n#include <stddef.h>\n#include <stdint.h>\n\n");
    out.append("#ifdef __cplusplus\nextern \"C\" {\n#endif\n\n");
    out.append(declarations);
    out.append("\n#ifdef __cplusplus\n}\n#endif\n\n");
    out.append($"#endif /* {name} */\n");
    return out.to_string();
}
