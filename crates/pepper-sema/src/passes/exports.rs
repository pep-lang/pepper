//! `[Export]`: free functions that C code calls (see the book's "Calling
//! Pepper from C").
//!
//! `[Export]` on a free function gives it a C symbol, its declared name or
//! the one `[Export(name = "c_name")]` gives. Each parameter and the result
//! must be a type C can hold: a number, `bool`, a pointer (`__ptr<T>`), a C
//! function pointer (`extern (P) => R`), or a reference to a struct, which
//! C holds as an opaque handle. Each struct a handle names also gets two
//! exported functions, `<struct>_retain` and `<struct>_release`, which step
//! its reference count.
//!
//! [`collect_exports`] checks the attributes and fills
//! [`Module::exports`]; the code generator emits one C-ABI function per
//! export (calling the Pepper function) and the driver writes
//! [`header`]. `[Export]` anywhere else is a warning: it has no effect
//! there.

use crate::model::*;
use crate::type_name::TypeName;
use pepper_parser::ast;
use pepper_parser::namespace::demangle_name;
use std::collections::{BTreeMap, HashMap};

/// The attribute that exports a function to C.
pub const EXPORT_ATTRIBUTE: &str = "Export";

/// A free function C code can call.
#[derive(Debug, Clone, PartialEq)]
pub struct Export {
    /// The C symbol.
    pub symbol: String,
    /// The function it calls, by its model name.
    pub function: String,
    /// Each parameter's name and type.
    pub parameters: Vec<(String, TypeName)>,
    /// The result type (`void` for none).
    pub result: TypeName,
    /// Where the function is declared.
    pub loc: Loc,
}

/// The struct handle functions C uses to keep a reference: `retain` adds
/// one, `release` drops one (freeing the object when it was the last).
#[derive(Debug, Clone, PartialEq)]
pub struct Handle {
    /// The struct, by its model name.
    pub structure: String,
    /// Its C type name (the struct's declared name).
    pub c_type: String,
    /// The C symbols of its retain and release functions.
    pub retain: String,
    pub release: String,
}

/// What a program exports to C: its exported functions, and the handle
/// functions of every struct they pass. Both are in C symbol order.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Exports {
    pub functions: Vec<Export>,
    pub handles: Vec<Handle>,
}

impl Exports {
    pub fn is_empty(&self) -> bool {
        self.functions.is_empty()
    }
}

/// Check every `[Export]` and record the program's exports in
/// `module.exports`. Misplaced attributes are warnings; an exported
/// function that C cannot call is an error.
pub fn collect_exports(module: &mut Module) {
    let mut warnings = vec![];
    let mut misplaced = |attributes: &[ast::Attribute], loc: Loc, what: &str| {
        if let Some(attr) = export_attribute(attributes) {
            warnings.push(
                Diagnostic::warning(format!("'Export' has no effect on {}; only a free function can be called from C", what))
                    .at(Loc::new(loc.file, attr.span)),
            );
        }
    };
    for st in &module.structs {
        if st.name != st.ty.name && st.ty.is_generic() {
            continue; // a specialization repeats its generic's attributes
        }
        misplaced(&st.attributes, st.loc, "a struct");
        for method in st.method_members.iter().chain(&st.generic_methods).chain(&st.constructors) {
            misplaced(&method.attributes, method.loc, "a method");
        }
    }
    for tr in &module.traits {
        misplaced(&tr.attributes, tr.loc, "a trait");
    }
    for ext in &module.externs {
        misplaced(&ext.attributes, ext.loc, "an extern");
    }
    for global in &module.globals {
        misplaced(&global.attributes, global.loc, "a variable");
    }
    for function in module.functions.iter().filter(|f| f.parent.is_none() && is_generic(f)) {
        misplaced(&function.attributes, function.loc, "a generic function");
    }
    module.warnings.extend(warnings);

    let mut exports = Exports::default();
    let mut symbols: HashMap<String, Loc> = HashMap::new();
    let mut handles: BTreeMap<String, Handle> = BTreeMap::new();
    for function in module.functions.iter().filter(|f| f.parent.is_none() && !is_generic(f)) {
        let Some(attr) = export_attribute(&function.attributes) else { continue };
        let at = |span: ast::Span| Loc::new(function.loc.file, span);
        let symbol = match symbol_of(attr, function, at) {
            Ok(symbol) => symbol,
            Err(error) => return crate::errors::report(error),
        };
        if function.body.is_none() && !module.is_defined(function) {
            continue;
        }
        let mut parameters = vec![];
        for parameter in &function.parameters {
            let loc = if parameter.type_loc.is_none() { parameter.loc } else { parameter.type_loc };
            if let Err(error) = check_type(module, &parameter.ty, &symbol, loc, &mut handles) {
                return crate::errors::report(error);
            }
            parameters.push((parameter.name.clone(), parameter.ty.clone()));
        }
        if let Err(error) = check_type(module, &function.ty, &symbol, function.loc, &mut handles) {
            return crate::errors::report(error);
        }
        if let Some(first) = symbols.insert(symbol.clone(), function.loc) {
            return crate::errors::report(
                Diagnostic::error(format!("two functions are exported as '{}'", symbol))
                    .at(function.loc)
                    .with_note("first exported here", Some(first))
                    .with_note("give one a different C name with [Export(name = \"...\")]", None),
            );
        }
        exports.functions.push(Export {
            symbol,
            function: function.name.clone(),
            parameters,
            result: function.ty.clone(),
            loc: function.loc,
        });
    }
    for handle in handles.values() {
        for symbol in [&handle.retain, &handle.release] {
            if let Some(&loc) = symbols.get(symbol) {
                return crate::errors::report(
                    Diagnostic::error(format!("'{}' is exported already, as the handle function of '{}'", symbol, handle.c_type))
                        .at(loc),
                );
            }
        }
    }
    exports.functions.sort_by(|a, b| a.symbol.cmp(&b.symbol));
    exports.handles = handles.into_values().collect();
    module.exports = exports;
}

/// The function's `[Export]` attribute, if it has one.
fn export_attribute(attributes: &[ast::Attribute]) -> Option<&ast::Attribute> {
    attributes.iter().find(|a| a.name() == Some(EXPORT_ATTRIBUTE))
}

fn is_generic(function: &FunctionDef) -> bool {
    !function.generic_params.is_empty() || function.is_generic_func
}

/// The C symbol `[Export]` or `[Export(name = "c_name")]` gives `function`.
fn symbol_of(attr: &ast::Attribute, function: &FunctionDef, at: impl Fn(ast::Span) -> Loc) -> Result<String, Diagnostic> {
    let mut symbol = None;
    for argument in attr.arguments() {
        let Some(("name", _)) = argument.name else {
            let loc = argument.name.map_or(at(argument.value.span()), |(_, span)| at(span));
            return Err(Diagnostic::error("'Export' takes only 'name', the C symbol: [Export(name = \"c_name\")]").at(loc));
        };
        let ast::Expression::Literal { value: ast::Literal::String(value), span } = argument.value else {
            return Err(Diagnostic::error("'Export' argument 'name' must be a string").at(at(argument.value.span())));
        };
        if !is_c_identifier(value) {
            return Err(Diagnostic::error(format!("'{}' is not a C identifier", value)).at(at(*span)));
        }
        symbol = Some(value.clone());
    }
    let symbol = symbol.unwrap_or_else(|| super::overloads::set_name(demangle_name(&function.name)).to_string());
    if symbol == "main" {
        return Err(Diagnostic::error("cannot export a function as 'main'").at(function.loc));
    }
    Ok(symbol)
}

/// Whether `name` is a C identifier: a letter or `_`, then letters, digits
/// and `_`.
fn is_c_identifier(name: &str) -> bool {
    let mut bytes = name.bytes();
    bytes.next().is_some_and(|b| b.is_ascii_alphabetic() || b == b'_') && bytes.all(|b| b.is_ascii_alphanumeric() || b == b'_')
}

/// Check that C can hold `ty` (a parameter or result of the export
/// `symbol`, written at `loc`), recording the handle functions of a struct.
fn check_type(module: &Module, ty: &TypeName, symbol: &str, loc: Loc, handles: &mut BTreeMap<String, Handle>) -> Result<(), Diagnostic> {
    if c_type(ty).is_some() {
        return Ok(());
    }
    let cannot = |why: &str| {
        Diagnostic::error(format!("cannot export '{}': C cannot hold '{}'", symbol, demangle_name(&ty.to_string()))).at(loc).with_note(why, None)
    };
    if ty.name == "String" && ty.sub_types.is_empty() {
        return Err(cannot("pass the bytes as a '__ptr<u8>' and a 'ulong' size, and make the String with 'String(p, size)'"));
    }
    let structure = module.structs.iter().find(|s| s.name == ty.to_string());
    match structure {
        Some(st) if !st.is_value() && !st.ty.is_generic() && !st.ty.is_tuple() && !ty.is_weak() && st.enum_cases.is_none() => {
            let c_type = demangle_name(&st.name).to_string();
            let base = snake_case(&c_type);
            handles.entry(st.name.clone()).or_insert_with(|| Handle {
                structure: st.name.clone(),
                c_type,
                retain: format!("{}_retain", base),
                release: format!("{}_release", base),
            });
            Ok(())
        }
        Some(st) if st.is_value() => Err(cannot("a value struct has no handle; pass its fields")),
        Some(_) => Err(cannot("only a non-generic struct passes to C, as a handle")),
        None => Err(cannot("C passes numbers, 'bool', pointers and struct handles")),
    }
}

/// `ByteBuffer` as `byte_buffer`.
fn snake_case(name: &str) -> String {
    let mut out = String::new();
    let mut previous_lower = false;
    for c in name.chars() {
        if c.is_ascii_uppercase() {
            if previous_lower {
                out.push('_');
            }
            out.push(c.to_ascii_lowercase());
            previous_lower = false;
        } else {
            out.push(c);
            previous_lower = c.is_ascii_lowercase() || c.is_ascii_digit();
        }
    }
    out
}

/// The C spelling of a type that is not a struct handle: a number, `bool`,
/// `void`, a pointer or a C function pointer (spelled with `{}` where the
/// declared name goes, see [`declarator`]). `None` for any other type.
fn c_type(ty: &TypeName) -> Option<String> {
    if ty.is_extern_function_type() {
        let result = c_type(&ty.sub_types[0])?;
        let parameters: Option<Vec<String>> = ty.sub_types[1..].iter().map(|p| c_type(p).map(|c| declarator(&c, ""))).collect();
        let parameters = parameters?;
        let parameters = if parameters.is_empty() { "void".to_string() } else { parameters.join(", ") };
        return Some(declarator(&result, &format!("(*{{}})({})", parameters)));
    }
    if !ty.is_scalar() || !ty.sub_types.is_empty() {
        return None;
    }
    if let Some(target) = ty.name.strip_suffix('*') {
        // A pointer to anything C has no name for is a `void*`.
        let target = c_type(&TypeName::new(target)).filter(|t| !t.contains('{')).unwrap_or_else(|| "void".to_string());
        return Some(format!("{}*", target));
    }
    Some(
        match crate::enums::stored_as(&ty.name).as_ref() {
            "void" => "void",
            "bool" => "bool",
            "char" => "char",
            "i8" => "int8_t",
            "u8" | "byte" => "uint8_t",
            "i16" | "short" => "int16_t",
            "u16" | "ushort" => "uint16_t",
            "i32" | "int" => "int32_t",
            "u32" | "uint" => "uint32_t",
            "i64" | "long" => "int64_t",
            "u64" | "ulong" => "uint64_t",
            "f32" | "float" => "float",
            "f64" | "double" => "double",
            _ => return None,
        }
        .to_string(),
    )
}

/// A C declaration of `name` with type `c_type`: `int32_t count`, or for a
/// function pointer, the name inside its parentheses.
fn declarator(c_type: &str, name: &str) -> String {
    if c_type.contains("{}") {
        return c_type.replacen("{}", name, 1);
    }
    if name.is_empty() {
        return c_type.to_string();
    }
    format!("{} {}", c_type, name)
}

/// Whether C treats `ty` as a signed integer narrower than `int`, or an
/// unsigned one (`Some(false)`), which the C ABI widens; `None` for every
/// other type.
pub fn small_integer_is_signed(ty: &TypeName) -> Option<bool> {
    match crate::enums::stored_as(&ty.name).as_ref() {
        "char" | "i8" | "i16" | "short" => Some(true),
        "bool" | "u8" | "byte" | "u16" | "ushort" => Some(false),
        _ => None,
    }
}

/// The C type of `ty` in the header: as [`c_type`], or a handle pointer.
fn header_type(ty: &TypeName, handles: &[Handle]) -> String {
    match handles.iter().find(|h| h.structure == ty.to_string()) {
        Some(handle) => format!("{}*", handle.c_type),
        None => c_type(ty).unwrap_or_else(|| "void*".to_string()),
    }
}

/// The declarations of a C header for `exports`: the handle types, their
/// retain and release functions, and each exported function. The driver
/// wraps them in an include guard (see [`header`]).
pub fn header_declarations(exports: &Exports) -> String {
    let mut out = String::new();
    if !exports.handles.is_empty() {
        out.push_str("/* Opaque handles to Pepper objects. A handle a function returns is one\n");
        out.push_str(" * reference, which the caller releases; a handle passed in stays the\n");
        out.push_str(" * caller's. */\n");
        for handle in &exports.handles {
            out.push_str(&format!("typedef struct {0} {0};\n", handle.c_type));
        }
        out.push('\n');
        for handle in &exports.handles {
            out.push_str(&format!("void {}({}* handle);\n", handle.retain, handle.c_type));
            out.push_str(&format!("void {}({}* handle);\n", handle.release, handle.c_type));
        }
        out.push('\n');
    }
    for export in &exports.functions {
        let parameters: Vec<String> =
            export.parameters.iter().map(|(name, ty)| declarator(&header_type(ty, &exports.handles), name)).collect();
        let parameters = if parameters.is_empty() { "void".to_string() } else { parameters.join(", ") };
        let result = header_type(&export.result, &exports.handles);
        out.push_str(&format!("{};\n", declarator(&result, &format!("{}({})", export.symbol, parameters))));
    }
    out
}

/// A whole C header named `file_name` (`foo.h`) around `declarations`
/// ([`header_declarations`]). `libraries` are those a program that links a
/// static library must link too, which the header names in a comment.
pub fn header(file_name: &str, declarations: &str, libraries: &[String]) -> String {
    let guard: String = file_name
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_uppercase() } else { '_' })
        .collect();
    let guard = if guard.starts_with(|c: char| c.is_ascii_digit()) { format!("_{}", guard) } else { guard };
    let mut out = format!("/* {}: generated by the Pepper compiler. Do not edit. */\n", file_name);
    if !libraries.is_empty() {
        let flags: Vec<String> = libraries.iter().map(|l| format!("-l{}", l)).collect();
        out.push_str(&format!("/* Link the static library with: {} */\n", flags.join(" ")));
    }
    out.push_str(&format!(
        "#ifndef {guard}\n\
         #define {guard}\n\
         \n\
         #include <stdbool.h>\n\
         #include <stdint.h>\n\
         \n\
         #ifdef __cplusplus\n\
         extern \"C\" {{\n\
         #endif\n\
         \n\
         {declarations}\
         \n\
         #ifdef __cplusplus\n\
         }}\n\
         #endif\n\
         \n\
         #endif /* {guard} */\n"
    ));
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn c_types() {
        assert_eq!(c_type(&TypeName::new("int")).as_deref(), Some("int32_t"));
        assert_eq!(c_type(&TypeName::new("ulong")).as_deref(), Some("uint64_t"));
        assert_eq!(c_type(&TypeName::new("int*")).as_deref(), Some("int32_t*"));
        assert_eq!(c_type(&TypeName::new("Point*")).as_deref(), Some("void*"));
        assert_eq!(c_type(&TypeName::new("String")), None);
        let callback = TypeName::with_args("__extern_function", vec![TypeName::new("int"), TypeName::new("double")]);
        assert_eq!(declarator(&c_type(&callback).unwrap(), "f"), "int32_t (*f)(double)");
    }

    #[test]
    fn names() {
        assert_eq!(snake_case("ByteBuffer"), "byte_buffer");
        assert_eq!(snake_case("IoError"), "io_error");
        assert_eq!(snake_case("Counter"), "counter");
        assert!(is_c_identifier("add_2"));
        assert!(!is_c_identifier("2add"));
        assert!(!is_c_identifier("a-b"));
    }
}
