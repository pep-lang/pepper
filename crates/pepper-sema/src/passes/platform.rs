//! Platform selection: evaluates `Target(...)` attribute predicates against the
//! compile target (the host, or the one `--target` names, with the build
//! options `-D` defines; see [`Target`]) and drops top-level declarations and
//! attributed blocks that do not match. Runs before `struct_body::apply` so
//! filtered-out code never reaches synthesis or codegen.
//!
//! `Target(...)` takes exactly one argument: a boolean expression built from
//! `OS(v)` / `Arch(v)` / `BuildOption(NAME)` calls, comparisons of a
//! `BuildOption(NAME)` with a literal, combined with `&&`/`||` (and
//! `and`/`or`) and negated with `!`. Example:
//! `[Target(OS(Windows) && BuildOption(LOG_LEVEL) >= 2)]`.
//! `[BuildOption("NAME")]` is shorthand for `[Target(BuildOption(NAME))]`.

use crate::model::*;
use pepper_parser::ast::{self, Expression, Literal, Span};
use pepper_parser::diagnostic::FileId;
use pepper_parser::namespace::{demangle_name, display_name};
use pepper_parser::parser::parsers::{
    contains_platform_predicate, is_build_option_predicate_name, is_os_or_arch_name, is_platform_predicate_name,
};
use std::collections::BTreeMap;
use std::env::consts;

/// Why a `Target(...)` or `BuildOption(...)` attribute cannot be evaluated,
/// and the token to point at.
struct Invalid {
    message: String,
    span: Span,
}

/// `message`, located at the whole attribute `attr`.
fn invalid(attr: &ast::Attribute, message: String) -> Invalid {
    Invalid { message, span: attr.span }
}

/// Evaluate one attribute body against the target platform.
///
/// - Bare symbols that are not predicates (`[Export]`, `[Inline]`) are ignored (true).
/// - A bare `Target` or `BuildOption` without a call is an error.
/// - `Target(expr)`: `expr` must be a single boolean predicate over `OS(v)` /
///   `Arch(v)` / `BuildOption(NAME)`; the declaration is kept iff it
///   evaluates true on the target.
/// - `BuildOption(NAME)`: true iff `-D` defined `NAME`.
/// - Calls with other names (`[Align(8)]`) are ignored (true).
fn evaluate(body: &Expression, attr: &ast::Attribute) -> Result<bool, Invalid> {
    match body {
        Expression::SymbolRef { id, span } => {
            if is_build_option_predicate_name(id) {
                Err(Invalid { message: format!("'{id}' needs the name of a build option, such as '[{id}(\"USE_ZLIB\")]'"), span: *span })
            } else if is_platform_predicate_name(id) {
                Err(invalid(attr, format!("platform predicate `{id}` used without a value in {attr}")))
            } else {
                Ok(true)
            }
        }
        Expression::FunctionCall { function, arguments, span } => match function.as_ref() {
            Expression::SymbolRef { id, .. } if is_build_option_predicate_name(id) => {
                Ok(target_build_options().contains_key(build_option_name(id, arguments, *span)?))
            }
            Expression::SymbolRef { id, .. } if is_platform_predicate_name(id) => {
                let [arg] = arguments.as_slice() else {
                    return Err(invalid(
                        attr,
                        format!("Target takes exactly one value (a boolean over OS(...), Arch(...) and BuildOption(...)) in {attr}"),
                    ));
                };
                evaluate_predicate(arg, attr)
            }
            // Non-predicate attribute call (`[Export("x")]`) — ignore.
            _ => Ok(true),
        },
        // A qualified attribute (`[serialize.Ignore]`) is never a predicate.
        Expression::MemberAccess { .. } | Expression::TypeLiteral(_) => Ok(true),
        // Top-level `!` / `&&` / `||` is rejected by the parser; defensive.
        _ => Err(invalid(attr, bad_body(attr))),
    }
}

/// Evaluate the single boolean argument of `Target(...)`: `OS(v)` / `Arch(v)`
/// / `BuildOption(NAME)` calls, comparisons of a build option with a
/// literal, `!`, and `&&`/`||` (with `and`/`or`).
fn evaluate_predicate(e: &Expression, attr: &ast::Attribute) -> Result<bool, Invalid> {
    match e {
        Expression::FunctionCall { function, arguments, span } => match function.as_ref() {
            Expression::SymbolRef { id, .. } if is_os_or_arch_name(id) => {
                if id.to_ascii_lowercase() == "os" {
                    os_matches(arguments, attr).map_err(|m| invalid(attr, m))
                } else {
                    arch_matches(arguments, attr).map_err(|m| invalid(attr, m))
                }
            }
            Expression::SymbolRef { id, .. } if is_build_option_predicate_name(id) => {
                Ok(target_build_options().contains_key(build_option_name(id, arguments, *span)?))
            }
            Expression::SymbolRef { id, .. } if is_platform_predicate_name(id) => Err(invalid(
                attr,
                format!("`{id}` cannot be nested inside Target(...) in {attr}"),
            )),
            Expression::SymbolRef { id, .. } => Err(invalid(
                attr,
                format!("unknown predicate `{id}` (expected OS, Arch or BuildOption) in {attr}"),
            )),
            _ => Err(invalid(attr, bad_body(attr))),
        },
        Expression::Unary { op, prefix, operand, .. } => {
            if *prefix && op == "!" {
                Ok(!evaluate_predicate(operand, attr)?)
            } else {
                Err(invalid(attr, bad_body(attr)))
            }
        }
        Expression::Binary { lhs, op, rhs, span } => match op.as_str() {
            // Both operands are evaluated (no short-circuit) so a malformed
            // predicate in either half is reported on every host.
            "&&" | "and" => {
                let (l, r) = (evaluate_predicate(lhs, attr)?, evaluate_predicate(rhs, attr)?);
                Ok(l && r)
            }
            "||" | "or" => {
                let (l, r) = (evaluate_predicate(lhs, attr)?, evaluate_predicate(rhs, attr)?);
                Ok(l || r)
            }
            "==" | "!=" | "<" | "<=" | ">" | ">=" => compare(lhs, op, rhs, *span),
            _ => Err(invalid(attr, bad_body(attr))),
        },
        Expression::SymbolRef { id, .. } => Err(invalid(
            attr,
            format!("bare symbol `{id}` is not a predicate; expected OS(...), Arch(...) or BuildOption(...) in {attr}"),
        )),
        _ => Err(invalid(attr, bad_body(attr))),
    }
}

fn bad_body(attr: &ast::Attribute) -> String {
    format!("invalid platform predicate in {attr}")
}

/// The build options `-D` defines, by name: each one's value as written,
/// `"1"` for a bare `-D NAME` (as in C).
pub type BuildOptions = BTreeMap<String, String>;

/// Whether `name` can name a build option: a letter or `_`, then letters,
/// digits and `_`, as a C macro.
pub fn is_build_option_name(name: &str) -> bool {
    let mut chars = name.chars();
    chars.next().is_some_and(|c| c.is_ascii_alphabetic() || c == '_') && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

/// One `-D` argument, `NAME` or `NAME=value`, as a name and its value
/// (`"1"` for a bare `NAME`, as in C).
pub fn parse_build_option(text: &str) -> Result<(String, String), String> {
    let (name, value) = text.split_once('=').unwrap_or((text, "1"));
    if !is_build_option_name(name) {
        return Err(format!(
            "invalid build option name '{name}' in '-D {text}'; a name is a letter or '_' followed by letters, digits and '_'"
        ));
    }
    Ok((name.to_string(), value.to_string()))
}

/// The name a `BuildOption(...)` call (spelled `id`, at `span`) tests:
/// one argument, a name or a string holding one.
fn build_option_name<'a>(id: &str, arguments: &'a [Expression], span: Span) -> Result<&'a str, Invalid> {
    let [argument] = arguments else {
        return Err(Invalid { message: format!("'{id}' takes the name of one build option, such as '{id}(USE_ZLIB)'"), span });
    };
    let name = match argument {
        Expression::SymbolRef { id, .. } => id.as_str(),
        Expression::Literal { value: Literal::String(name), .. } => name.as_str(),
        other => {
            return Err(Invalid {
                message: format!("'{id}' takes the name of a build option, such as '{id}(USE_ZLIB)'"),
                span: other.span(),
            })
        }
    };
    if !is_build_option_name(name) {
        return Err(Invalid {
            message: format!("invalid build option name '{name}'; a name is a letter or '_' followed by letters, digits and '_'"),
            span: argument.span(),
        });
    }
    Ok(name)
}

/// `e` as a `BuildOption(...)` call: its spelling, arguments and span.
fn build_option_call(e: &Expression) -> Option<(&str, &[Expression], Span)> {
    match e {
        Expression::FunctionCall { function, arguments, span } => match function.as_ref() {
            Expression::SymbolRef { id, .. } if is_build_option_predicate_name(id) => Some((id, arguments, *span)),
            _ => None,
        },
        _ => None,
    }
}

/// `e` as a literal a build option can be compared with, a negative number
/// included (`-1`).
fn comparison_literal(e: &Expression) -> Option<Literal> {
    match e {
        Expression::Literal { value, .. } => Some(value.clone()),
        Expression::Unary { op, prefix: true, operand, .. } if op == "-" => match operand.as_ref() {
            Expression::Literal { value: Literal::Integer(n), .. } => Some(Literal::Integer(n.checked_neg()?)),
            Expression::Literal { value: Literal::Float(f), .. } => Some(Literal::Float(-f)),
            _ => None,
        },
        _ => None,
    }
}

/// The comparison `lhs op rhs` in a `Target(...)`, at `span` (from the
/// operator to the end of `rhs`): a
/// `BuildOption(NAME)` and a literal, either way round. The literal's type
/// says how the option's value is read. False when the option is not
/// defined (`undefined_build_option_comparisons` warns about it).
fn compare(lhs: &Expression, op: &str, rhs: &Expression, span: Span) -> Result<bool, Invalid> {
    let (option, literal, op) = match (build_option_call(lhs), build_option_call(rhs)) {
        (Some(_), Some(_)) => {
            return Err(Invalid {
                message: format!("'{op}' cannot compare two build options; compare a 'BuildOption(...)' with a literal"),
                span,
            })
        }
        (Some(option), None) => (option, rhs, op),
        // `2 <= BuildOption(X)` is `BuildOption(X) >= 2`.
        (None, Some(option)) => {
            let mirrored = match op {
                "<" => ">",
                "<=" => ">=",
                ">" => "<",
                ">=" => "<=",
                same => same,
            };
            (option, lhs, mirrored)
        }
        (None, None) => {
            return Err(Invalid {
                message: format!("'{op}' in a 'Target' must compare a 'BuildOption(...)' with a literal"),
                span,
            })
        }
    };
    let (id, arguments, option_span) = option;
    let name = build_option_name(id, arguments, option_span)?;
    let Some(value) = comparison_literal(literal).filter(|l| !matches!(l, Literal::Char(_) | Literal::Null)) else {
        return Err(Invalid {
            message: format!("build option '{name}' can only be compared with a literal: a number, 'true' or 'false', or a string"),
            span: literal.span(),
        });
    };
    if matches!(value, Literal::Bool(_)) && !matches!(op, "==" | "!=") {
        return Err(Invalid {
            message: format!("'{op}' cannot compare build option '{name}' with a bool; use '==' or '!='"),
            span,
        });
    }
    let options = target_build_options();
    let Some(defined) = options.get(name) else {
        return Ok(false);
    };
    let unreadable = |what: &str| Invalid {
        message: format!("build option '{name}' is '{defined}', which is not {what}"),
        span,
    };
    let ordering = match &value {
        Literal::Integer(n) => parse_integer(defined).ok_or_else(|| unreadable("an integer"))?.cmp(n),
        Literal::Float(f) => match defined.trim().parse::<f64>().map_err(|_| unreadable("a number"))?.partial_cmp(f) {
            Some(ordering) => ordering,
            // NaN: unequal to everything, ordered with nothing.
            None => return Ok(op == "!="),
        },
        Literal::Bool(b) => parse_bool(defined).ok_or_else(|| unreadable("'true' or 'false'"))?.cmp(b),
        Literal::String(s) => defined.as_bytes().cmp(s.as_bytes()),
        Literal::Char(_) | Literal::Null => unreachable!("rejected above"),
    };
    Ok(match op {
        "==" => ordering.is_eq(),
        "!=" => ordering.is_ne(),
        "<" => ordering.is_lt(),
        "<=" => ordering.is_le(),
        ">" => ordering.is_gt(),
        _ => ordering.is_ge(),
    })
}

/// A build option's value as a signed 64-bit integer: decimal, or
/// hexadecimal after `0x`, with an optional sign.
fn parse_integer(text: &str) -> Option<i64> {
    let text = text.trim();
    let (negative, digits) = match text.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, text.strip_prefix('+').unwrap_or(text)),
    };
    let magnitude = match digits.strip_prefix("0x").or_else(|| digits.strip_prefix("0X")) {
        Some(hex) => i128::from_str_radix(hex, 16).ok()?,
        None if digits.bytes().all(|b| b.is_ascii_digit()) => digits.parse::<i128>().ok()?,
        None => return None,
    };
    i64::try_from(if negative { -magnitude } else { magnitude }).ok()
}

/// A build option's value as a bool: `true`/`false`, `1`/`0`, `on`/`off`
/// or `yes`/`no`, in any case.
fn parse_bool(text: &str) -> Option<bool> {
    match text.trim().to_ascii_lowercase().as_str() {
        "true" | "1" | "on" | "yes" => Some(true),
        "false" | "0" | "off" | "no" => Some(false),
        _ => None,
    }
}

/// The build options `attribute` compares with a literal that this build
/// does not define, each with the span of its `BuildOption(...)` call, in
/// source order. Each such comparison is false; the program warns about it.
pub fn undefined_build_option_comparisons(attribute: &ast::Attribute) -> Vec<(String, Span)> {
    fn walk(e: &Expression, options: &BuildOptions, out: &mut Vec<(String, Span)>) {
        match e {
            Expression::Binary { lhs, op, rhs, .. } if matches!(op.as_str(), "==" | "!=" | "<" | "<=" | ">" | ">=") => {
                // Only a well-formed comparison: a malformed one is an error.
                let option = match (build_option_call(lhs), build_option_call(rhs)) {
                    (Some(option), None) if comparison_literal(rhs).is_some() => option,
                    (None, Some(option)) if comparison_literal(lhs).is_some() => option,
                    _ => return,
                };
                let (id, arguments, span) = option;
                if let Ok(name) = build_option_name(id, arguments, span)
                    && !options.contains_key(name)
                {
                    out.push((name.to_string(), span));
                }
            }
            Expression::Binary { lhs, rhs, .. } => {
                walk(lhs, options, out);
                walk(rhs, options, out);
            }
            Expression::Unary { operand, .. } => walk(operand, options, out),
            Expression::FunctionCall { arguments, .. } => arguments.iter().for_each(|a| walk(a, options, out)),
            _ => {}
        }
    }
    let mut out = vec![];
    walk(&attribute.body, &target_build_options(), &mut out);
    out
}

/// What a program is compiled for: the platform `Target(...)` predicates
/// evaluate against and codegen emits for (the host unless the compiler was
/// given `--target <triple>`), and the build options `-D` defines.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Target {
    /// The OS, as `std::env::consts::OS` spells it (`"windows"`, `"macos"`,
    /// `"linux"`, `"ios"`, `"android"`), or `"wasi"` for WebAssembly.
    pub os: String,
    /// The architecture, as `std::env::consts::ARCH` spells it (`"x86_64"`,
    /// `"aarch64"`, `"wasm32"`).
    pub arch: String,
    /// The LLVM target triple, or `None` for the host's own (LLVM's default
    /// triple, which also carries the host OS version on macOS).
    pub triple: Option<String>,
    /// The build options `-D` defines, which `BuildOption(...)` predicates
    /// and `static` blocks read.
    pub build_options: BuildOptions,
}

/// The triples `--target` accepts: each supported OS on each supported
/// architecture, as clang spells them, WebAssembly with WASI preview 1, and
/// the mobile platforms (iOS devices and the simulator on Apple silicon and
/// Intel Macs; Android on arm64 and x86_64).
pub const SUPPORTED_TRIPLES: &[&str] = &[
    "x86_64-unknown-linux-gnu",
    "aarch64-unknown-linux-gnu",
    "x86_64-apple-darwin",
    "aarch64-apple-darwin",
    "x86_64-pc-windows-msvc",
    "aarch64-pc-windows-msvc",
    "wasm32-wasip1",
    "aarch64-apple-ios",
    "aarch64-apple-ios-simulator",
    "x86_64-apple-ios-simulator",
    "aarch64-linux-android",
    "x86_64-linux-android",
];

/// The iOS version an `-apple-ios` triple without one targets: the oldest
/// Xcode 16 and later still build for.
pub const DEFAULT_IOS_VERSION: &str = "15.0";

/// The Android API level an `-android` triple without one targets, and the
/// oldest the runtime supports: Android 11, the first with `statx`. Its
/// file layer calls it for one `stat` layout on every architecture, as on
/// Linux; level 29 brought ELF thread-local storage (older levels need
/// LLVM's emulated TLS), `posix_spawn` and `getrandom`.
pub const DEFAULT_ANDROID_API: &str = "30";

impl Target {
    /// The machine the compiler runs on, with the default build options
    /// (none, unless [`set_default_build_options`] set some).
    pub fn host() -> Target {
        Target { os: consts::OS.to_string(), arch: consts::ARCH.to_string(), triple: None, build_options: default_build_options() }
    }

    /// The target `triple` names (`aarch64-apple-darwin`,
    /// `x86_64-pc-windows-msvc`). Accepts clang's spellings of the supported
    /// architectures (`x86_64`, `amd64`; `aarch64`, `arm64`) and operating
    /// systems (`linux-gnu`, `darwin` or `macosx`, `windows-msvc`), with any
    /// vendor and an OS version (`arm64-apple-macosx14.0`). WebAssembly is
    /// `wasm32-wasip1`, also spelled `wasm32-wasi` or `wasm32-unknown-wasi`;
    /// each becomes `wasm32-wasip1`, the name clang and wasi-sdk use now.
    pub fn parse(triple: &str) -> Result<Target, String> {
        let unsupported = || {
            format!(
                "unsupported target '{}'; expected one of: {}",
                triple,
                SUPPORTED_TRIPLES.join(", ")
            )
        };
        if matches!(triple, "wasm32-wasi" | "wasm32-wasip1" | "wasm32-unknown-wasi" | "wasm32-unknown-wasip1") {
            return Ok(Target { os: "wasi".to_string(), arch: "wasm32".to_string(), triple: Some("wasm32-wasip1".to_string()), build_options: default_build_options() });
        }
        let parts: Vec<&str> = triple.split('-').collect();
        if parts.len() < 3 || parts.iter().any(|p| p.is_empty()) {
            return Err(unsupported());
        }
        let arch = match parts[0] {
            "x86_64" | "amd64" => "x86_64",
            "aarch64" | "arm64" => "aarch64",
            _ => return Err(unsupported()),
        };
        // The OS and environment follow the vendor (`x86_64-pc-windows-msvc`),
        // or stand in for it (`x86_64-linux-gnu`).
        let system = &parts[1..];
        let names = |prefix: &str| system.iter().any(|p| p.starts_with(prefix));
        let os = if names("android") {
            return Target::android(arch, system, triple);
        } else if names("ios") {
            return Target::ios(arch, system).ok_or_else(unsupported);
        } else if names("linux") && system.iter().any(|p| p.starts_with("gnu")) {
            "linux"
        } else if names("darwin") || names("macos") {
            "macos"
        } else if names("windows") && system.last() == Some(&"msvc") {
            "windows"
        } else {
            return Err(unsupported());
        };
        Ok(Target { os: os.to_string(), arch: arch.to_string(), triple: Some(triple.to_string()), build_options: default_build_options() })
    }

    /// An Android target: `<arch>-linux-android<api>`, with the API level
    /// the triple's `android` part ends in (`android33`), else
    /// [`DEFAULT_ANDROID_API`], which is also the oldest accepted. Any
    /// vendor is accepted (`aarch64-unknown-linux-android`).
    fn android(arch: &str, system: &[&str], triple: &str) -> Result<Target, String> {
        let api = system.iter().find_map(|p| p.strip_prefix("android")).filter(|api| !api.is_empty()).unwrap_or(DEFAULT_ANDROID_API);
        let oldest: u32 = DEFAULT_ANDROID_API.parse().unwrap_or(0);
        match api.parse::<u32>() {
            Ok(level) if level >= oldest => {}
            Ok(_) => return Err(format!("unsupported target '{triple}': Pepper's runtime needs Android API level {oldest} or later (write 'android{oldest}')")),
            Err(_) => return Err(format!("unsupported target '{triple}': '{api}' is not an Android API level")),
        }
        let triple = format!("{arch}-linux-android{api}");
        Ok(Target { os: "android".to_string(), arch: arch.to_string(), triple: Some(triple), build_options: default_build_options() })
    }

    /// An iOS target: `<arch>-apple-ios<version>`, with `-simulator` for the
    /// simulator, which Rust spells `-sim` and an x86_64 triple implies (no
    /// iPhone is x86_64). The version is the triple's (`ios17.0`), else
    /// [`DEFAULT_IOS_VERSION`]. `None` for an environment other than the
    /// simulator (`-macabi`).
    fn ios(arch: &str, system: &[&str]) -> Option<Target> {
        let version = system.iter().find_map(|p| p.strip_prefix("ios")).filter(|v| !v.is_empty()).unwrap_or(DEFAULT_IOS_VERSION);
        let simulator = match system.last() {
            Some(&"simulator") | Some(&"sim") => true,
            Some(last) if last.starts_with("ios") => arch == "x86_64",
            _ => return None,
        };
        let triple = format!("{arch}-apple-ios{version}{}", if simulator { "-simulator" } else { "" });
        Some(Target { os: "ios".to_string(), arch: arch.to_string(), triple: Some(triple), build_options: default_build_options() })
    }

    /// The triple without its OS version, which names the platform's system
    /// root (`PEPPER_SYSROOT_AARCH64_APPLE_IOS_SIMULATOR` for every
    /// `aarch64-apple-ios<version>-simulator`): an iOS version or Android API
    /// level picks what the code may call, not where the SDK is.
    pub fn platform_triple(&self) -> Option<String> {
        let triple = self.triple.as_deref()?;
        let strip = |prefix: &str| -> Option<String> {
            let start = triple.find(prefix)? + prefix.len();
            let end = triple[start..].find('-').map_or(triple.len(), |i| start + i);
            Some(format!("{}{}", &triple[..start], &triple[end..]))
        };
        match self.os.as_str() {
            "ios" => strip("-apple-ios"),
            "android" => strip("-linux-android"),
            _ => Some(triple.to_string()),
        }
    }

    /// Whether this is an Apple platform built on Darwin (macOS or iOS):
    /// Mach-O objects, libSystem, and the SDK's `.tbd` stubs.
    pub fn is_apple(&self) -> bool {
        matches!(self.os.as_str(), "macos" | "ios")
    }

    /// Whether this is the machine the compiler runs on: the code it
    /// produces can run here.
    pub fn is_host(&self) -> bool {
        self.os == consts::OS && self.arch == consts::ARCH
    }
}

/// The build options a target has when none are given: what the language
/// server was told to assume.
static DEFAULT_BUILD_OPTIONS: std::sync::RwLock<BuildOptions> = std::sync::RwLock::new(BTreeMap::new());

/// Make `options` the build options of every target made from now on
/// ([`Target::host`], [`Target::parse`]), in every thread: for the language
/// server, whose analyses run on threads that never set a target.
pub fn set_default_build_options(options: BuildOptions) {
    *DEFAULT_BUILD_OPTIONS.write().unwrap_or_else(|e| e.into_inner()) = options;
}

fn default_build_options() -> BuildOptions {
    DEFAULT_BUILD_OPTIONS.read().unwrap_or_else(|e| e.into_inner()).clone()
}

thread_local! {
    /// The target that replaces the host while `with_target` runs.
    static TARGET: std::cell::RefCell<Option<Target>> = const { std::cell::RefCell::new(None) };
}

/// Run `f` compiling for `target`: `Target(...)` predicates, the checked
/// runtime and codegen all see it. Thread-local, so concurrent compiles do
/// not see each other's target; a thread that compiles on behalf of another
/// takes its target with `current_target` and sets it again.
pub fn with_target<R>(target: Target, f: impl FnOnce() -> R) -> R {
    let previous = TARGET.with(|t| t.replace(Some(target)));
    // Restore on unwind too, so a failing test does not leak its target.
    struct Restore(Option<Target>);
    impl Drop for Restore {
        fn drop(&mut self) {
            let previous = self.0.take();
            TARGET.with(|t| *t.borrow_mut() = previous);
        }
    }
    let _restore = Restore(previous);
    f()
}

/// The target this thread compiles for: the one `with_target` set, else the
/// host.
pub fn current_target() -> Target {
    TARGET.with(|t| t.borrow().clone()).unwrap_or_else(Target::host)
}

/// Evaluate `Target(...)` predicates inside `f` as if the host were `os` /
/// `arch` (spelled as `std::env::consts` spells them: `"windows"`,
/// `"macos"`, `"linux"`; `"x86_64"`, `"aarch64"`), while codegen keeps the
/// host's triple. For tests that push another platform's code through the
/// platform filter, sema and codegen on this host, to check it compiles, or
/// to JIT-run its portable parts here (`path_functions_on_every_platform`);
/// `with_target` compiles for the other platform's triple instead.
pub fn with_simulated_host<R>(os: &str, arch: &str, f: impl FnOnce() -> R) -> R {
    let build_options = current_target().build_options;
    with_target(Target { os: os.to_string(), arch: arch.to_string(), triple: None, build_options }, f)
}

/// The OS `Target(...)` predicates evaluate against: the target's (see
/// `current_target`).
pub fn target_os() -> String {
    TARGET
        .with(|t| t.borrow().as_ref().map(|t| t.os.clone()))
        .unwrap_or_else(|| consts::OS.to_string())
}

/// The build options `BuildOption(...)` predicates and `static` blocks
/// read: the target's (see `current_target`).
pub fn target_build_options() -> BuildOptions {
    TARGET.with(|t| t.borrow().as_ref().map(|t| t.build_options.clone())).unwrap_or_else(default_build_options)
}

/// The architecture `Target(...)` predicates evaluate against (see
/// `target_os`).
pub fn target_arch() -> String {
    TARGET
        .with(|t| t.borrow().as_ref().map(|t| t.arch.clone()))
        .unwrap_or_else(|| consts::ARCH.to_string())
}

fn os_matches(arguments: &[Expression], attr: &ast::Attribute) -> Result<bool, String> {
    let [value] = arguments else {
        return Err(format!("OS predicate takes exactly one value in {attr}"));
    };
    let Expression::SymbolRef { id, .. } = value else {
        return Err(format!(
            "OS predicate value must be a symbol (Windows, Mac, MacOS, Linux, Wasi, IOS, Android) in {attr}"
        ));
    };
    let host = match target_os().as_str() {
        "windows" => Some("windows"),
        "macos" => Some("macos"),
        "linux" => Some("linux"),
        "wasi" => Some("wasi"),
        "ios" => Some("ios"),
        "android" => Some("android"),
        _ => None,
    };
    match host {
        // Supported target: validate the value (unknown values are a hard
        // error) and compare.
        Some(h) => matches_os_value(id, h, attr),
        // Unsupported target: no OS predicate can match.
        None => Ok(false),
    }
}

/// Whether the `OS(value)` predicate holds on `host`. `Mac` holds on every
/// Darwin OS (macOS and iOS), as `TARGET_OS_MAC` does in C, and `Linux` on
/// every Linux kernel (Android too), as `__linux__` does: their system
/// calls and C libraries are mostly the same. `IOS` and `Android` narrow
/// that to the one OS.
fn matches_os_value(value: &str, host: &str, attr: &ast::Attribute) -> Result<bool, String> {
    match value.to_ascii_lowercase().as_str() {
        "windows" => Ok(host == "windows"),
        "mac" | "macos" => Ok(host == "macos" || host == "ios"),
        "linux" => Ok(host == "linux" || host == "android"),
        "wasi" => Ok(host == "wasi"),
        "ios" => Ok(host == "ios"),
        "android" => Ok(host == "android"),
        _ => Err(format!(
            "unknown OS value `{value}` (expected Windows, Mac, MacOS, Linux, Wasi, IOS, Android) in {attr}"
        )),
    }
}

fn arch_matches(arguments: &[Expression], attr: &ast::Attribute) -> Result<bool, String> {
    let [value] = arguments else {
        return Err(format!("Arch predicate takes exactly one value in {attr}"));
    };
    let Expression::SymbolRef { id, .. } = value else {
        return Err(format!(
            "Arch predicate value must be a symbol (x64, aarch64, wasm32) in {attr}"
        ));
    };
    let host = match target_arch().as_str() {
        "x86_64" => Some("x64"),
        "aarch64" => Some("aarch64"),
        "wasm32" => Some("wasm32"),
        _ => None,
    };
    match host {
        // Supported target: validate the value (unknown values are a hard
        // error) and compare.
        Some(h) => {
            let v = id.to_ascii_lowercase();
            if v == h {
                Ok(true)
            } else if v == "x64" || v == "aarch64" || v == "wasm32" {
                Ok(false)
            } else {
                Err(format!(
                    "unknown Arch value `{id}` (expected x64, aarch64, wasm32) in {attr}"
                ))
            }
        }
        // Unsupported target: no Arch predicate can match.
        None => Ok(false),
    }
}

/// The attribute that marks a unit test: `[Test]`.
pub const TEST_ATTRIBUTE: &str = "Test";

/// The attribute that makes a `[Test]` pass only when it panics.
pub const SHOULD_PANIC_ATTRIBUTE: &str = "ShouldPanic";

/// The build option `pep-build --test` defines: `[Test]` functions are
/// kept only when it is, and `[BuildOption("TEST")]` marks test-only code.
pub const TEST_BUILD_OPTION: &str = "TEST";

fn has_attribute(attributes: &[ast::Attribute], name: &str) -> bool {
    attributes.iter().any(|a| a.name() == Some(name))
}

/// Where an attribute's name is written: `Test` in `[Test]` and
/// `ShouldPanic` in `[ShouldPanic("m")]`.
fn attribute_name_loc(attribute: &ast::Attribute, file: FileId) -> Loc {
    let span = match &attribute.body {
        Expression::FunctionCall { function, .. } => function.span(),
        body => body.span(),
    };
    Loc::new(file, span)
}

/// Report a `[Test]` that is not on a free function taking nothing and
/// returning nothing, and a `[ShouldPanic]` without `[Test]`. Runs in every
/// build, before `[Test]` functions are dropped from a build without
/// `--test`, so a malformed test is caught everywhere.
fn check_tests(module: &Module) -> Result<(), Diagnostic> {
    for f in &module.functions {
        let file = f.loc.file;
        if let Some(should_panic) = f.attributes.iter().find(|a| a.name() == Some(SHOULD_PANIC_ATTRIBUTE)) {
            if !has_attribute(&f.attributes, TEST_ATTRIBUTE) {
                return Err(Diagnostic::error("'ShouldPanic' applies only to a '[Test]' function")
                    .at(attribute_name_loc(should_panic, file)));
            }
        }
        if !has_attribute(&f.attributes, TEST_ATTRIBUTE) {
            continue;
        }
        let name = demangle_name(&f.name);
        if let Some(parameter) = f.parameters.first() {
            return Err(Diagnostic::error(format!("test '{}' must take no parameters", name)).at(parameter.loc));
        }
        if !f.generic_params.is_empty() {
            return Err(Diagnostic::error(format!("test '{}' cannot be generic", name)).at(f.loc));
        }
        // A test declares no return type (`__auto` until bodies are
        // inferred) or `void`.
        if !(matches!(f.ty.name.as_str(), "void" | "__auto") && f.ty.sub_types.is_empty()) {
            return Err(Diagnostic::error(format!("test '{}' must return nothing, not '{}'", name, display_name(&f.ty.display())))
                .at(f.loc));
        }
    }
    let members = module
        .structs
        .iter()
        .flat_map(|s| s.method_members.iter().chain(&s.constructors))
        .chain(module.traits.iter().flat_map(|t| &t.methods))
        .chain(module.extensions.iter().flat_map(|e| &e.methods));
    for m in members {
        for attribute in &m.attributes {
            if let Some(name @ (TEST_ATTRIBUTE | SHOULD_PANIC_ATTRIBUTE)) = attribute.name() {
                return Err(Diagnostic::error(format!("'{}' applies only to a free function", name))
                    .at(attribute_name_loc(attribute, m.loc.file)));
            }
        }
    }
    Ok(())
}

/// Keep a node iff every attribute on it evaluates true (AND semantics).
/// Attributes that are not `Target(...)` selections (`[Export]`, `[Align(8)]`)
/// never drop anything, except `[__BuiltIn]`: a declaration of a compiler
/// built-in, which only the tools read, is dropped everywhere.
pub fn keep(attributes: &[ast::Attribute]) -> Result<bool, String> {
    if ast::is_built_in(attributes) {
        return Ok(false);
    }
    // A `[Test]` function is kept only in a test build, as if it said
    // `[BuildOption("TEST")]`.
    if has_attribute(attributes, TEST_ATTRIBUTE) && !target_build_options().contains_key(TEST_BUILD_OPTION) {
        return Ok(false);
    }
    for attr in attributes {
        if !contains_platform_predicate(&attr.body) {
            continue;
        }
        if !evaluate(&attr.body, attr).map_err(|e| e.message)? {
            return Ok(false);
        }
    }
    Ok(true)
}

/// Validate every attribute, reporting a malformed one, without short-circuiting
/// on a false predicate — so a bad attribute later in the list is still reported.
fn validate(attributes: &[ast::Attribute], file: FileId) -> Result<(), Diagnostic> {
    for attr in attributes {
        evaluate(&attr.body, attr).map_err(|e| Diagnostic::error(e.message).at(Loc::new(file, e.span)))?;
    }
    Ok(())
}

/// Drop attributed blocks that do not match the target, recursing into nested
/// blocks, branches, and loops.
fn filter_block(block: &mut Block, file: FileId) -> Result<(), Diagnostic> {
    let mut i = 0;
    while i < block.items.len() {
        match &mut block.items[i] {
            Statement::Block(inner) => {
                validate(&inner.attributes, file)?;
                let matched = keep(&inner.attributes).map_err(Diagnostic::error)?;
                // Walk the contents either way: a malformed predicate nested
                // inside a dropped block must still be reported on every host.
                filter_block(inner, file)?;
                if !matched {
                    // `remove` shifts the next item into `i`; don't skip it.
                    block.items.remove(i);
                    continue;
                }
            }
            Statement::Branch(br) => {
                filter_block(&mut br.if_block, file)?;
                if let Some(else_block) = &mut br.else_block {
                    filter_block(else_block, file)?;
                }
            }
            Statement::While(w) => filter_block(&mut w.block, file)?,
            _ => {}
        }
        i += 1;
    }
    Ok(())
}

/// Walk a function body, validating and filtering attributed blocks inside.
fn walk_function_body(function: &mut FunctionDef, file: FileId) -> Result<(), Diagnostic> {
    if let Some(body) = &mut function.body {
        filter_block(body, file)?;
    }
    Ok(())
}

/// Validate a function's own attributes, then walk its body. Used for
/// functions that survive filtering (methods, constructors, …).
fn filter_function(function: &mut FunctionDef, file: FileId) -> Result<(), Diagnostic> {
    // Synthesized members carry no location; their errors point into the
    // owner's file.
    let file = function.loc.known().map_or(file, |l| l.file);
    validate(&function.attributes, file)?;
    walk_function_body(function, file)
}

/// Apply platform selection to the whole module. Runs before
/// `struct_body::apply` so filtered code is never synthesized over.
pub fn apply_platform_filters(module: &mut Module) -> Result<(), Diagnostic> {
    check_tests(module)?;
    // Validate every top-level predicate first so a bad attribute in dropped
    // code is still reported. `validate` evaluates each attribute (no
    // short-circuit on a false one) so a malformed later attribute is caught.
    for f in &module.functions {
        validate(&f.attributes, f.loc.file)?;
    }
    for s in &module.structs {
        validate(&s.attributes, s.loc.file)?;
    }
    for t in &module.traits {
        validate(&t.attributes, t.loc.file)?;
    }
    for e in &module.extensions {
        validate(&e.attributes, e.loc.file)?;
    }
    for x in &module.externs {
        validate(&x.attributes, x.loc.file)?;
    }
    for g in &module.globals {
        validate(&g.attributes, g.loc.file)?;
    }
    for a in &module.type_aliases {
        validate(&a.attributes, a.loc.file)?;
    }
    for e in &module.enums {
        validate(&e.attributes, e.loc.file)?;
        for case in &e.cases {
            validate(&case.attributes, e.loc.file)?;
        }
    }

    // Top-level functions: keep iff all attributes match. Bodies are walked
    // whether or not the function survives, so a malformed predicate inside is
    // reported on every host (attributes were already validated above).
    let mut kept = Vec::with_capacity(module.functions.len());
    for f in std::mem::take(&mut module.functions) {
        let mut f = f;
        let file = f.loc.file;
        walk_function_body(&mut f, file)?;
        if keep(&f.attributes).unwrap_or(false) {
            kept.push(f);
        }
    }
    module.functions = kept;

    // Members of about-to-be-dropped structs/traits/extensions are filtered
    // here (before `retain`), mirroring the top-level validate-then-retain, so
    // a misspelled predicate in dropped code is reported on every host.
    // `filter_function` validates the member's own attributes and walks its
    // body; for constructors/destructors/acquire/release (non-Option fields,
    // never dropped) this also validates their attributes.
    for s in &mut module.structs {
        let file = s.loc.file;
        for m in &mut s.method_members {
            filter_function(m, file)?;
        }
        for constructor in &mut s.constructors {
            filter_function(constructor, file)?;
        }
        filter_function(&mut s.destructor, file)?;
        filter_function(&mut s.acquire, file)?;
        filter_function(&mut s.release, file)?;
    }
    for t in &mut module.traits {
        let file = t.loc.file;
        for m in &mut t.methods {
            filter_function(m, file)?;
        }
    }
    for e in &mut module.extensions {
        let file = e.loc.file;
        for m in &mut e.methods {
            filter_function(m, file)?;
        }
    }

    module.structs.retain(|s| keep(&s.attributes).unwrap_or(false));
    module.traits.retain(|t| keep(&t.attributes).unwrap_or(false));
    module.extensions.retain(|e| keep(&e.attributes).unwrap_or(false));
    module.externs.retain(|x| keep(&x.attributes).unwrap_or(false));
    // Aliases resolve after this pass with "last definition wins", so a
    // per-platform pair (`[Target(OS(Windows))] type H = ...;` and its
    // `!OS(Windows)` twin) must lose its dropped half here.
    module.globals.retain(|g| keep(&g.attributes).unwrap_or(false));
    module.type_aliases.retain(|a| keep(&a.attributes).unwrap_or(false));
    // A dropped case keeps the others' values: the builder numbered them all.
    module.enums.retain(|e| keep(&e.attributes).unwrap_or(false));
    for e in &mut module.enums {
        e.cases.retain(|c| keep(&c.attributes).unwrap_or(false));
    }

    // Members of surviving declarations: drop the ones that don't match.
    for s in &mut module.structs {
        s.method_members.retain(|m| keep(&m.attributes).unwrap_or(false));
        // A reference enum's case goes with its static method, which carries
        // the case's attributes; its fields stay, holding their defaults.
        if let Some(cases) = &mut s.enum_cases {
            cases.retain(|c| keep(&c.attributes).unwrap_or(false));
        }
    }
    for t in &mut module.traits {
        t.methods.retain(|m| keep(&m.attributes).unwrap_or(false));
    }
    for e in &mut module.extensions {
        e.methods.retain(|m| keep(&m.attributes).unwrap_or(false));
    }
    Ok(())
}
