## Platform selection: whether a declaration's attributes keep it on the
## compile target. `[Target(...)]` takes one boolean over `OS(v)`,
## `Arch(v)` and `BuildOption(NAME)` calls, comparisons of a build option
## with a literal, `!`, `&&` and `||`; `[BuildOption("NAME")]` is short for
## `[Target(BuildOption(NAME))]`. See docs/src/language/platform-selection.md.

import compiler.ast;
import [Attribute, Expression, Literal, Span] from compiler.ast;
import [Path] from io;
import [architecture, system_name] from os;

## The attribute that marks a unit test: `[Test]`.
export const TEST_ATTRIBUTE = "Test";

## The build option `pep-build --test` defines: `[Test]` functions are kept
## only when it is.
export const TEST_BUILD_OPTION = "TEST";

## The build option `pep-build --entry <name>` defines: the name of the
## function the program starts in, when it is not `main`.
export const ENTRY_BUILD_OPTION = "_PEP_ENTRY";

## The triples `--target` accepts: each supported OS on each supported
## architecture, as clang spells them, WebAssembly with WASI preview 1, and
## the mobile platforms (iOS devices and the simulator on Apple silicon and
## Intel Macs; Android on arm64 and x86_64).
##
## @returns the triples
export supported_triples(): String[] {
    return [
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
}

## The iOS version an `-apple-ios` triple without one targets: the oldest
## Xcode 16 and later still build for.
export const DEFAULT_IOS_VERSION = "15.0";

## The Android API level an `-android` triple without one targets, and the
## oldest the runtime supports: Android 11, the first with `statx`.
export const DEFAULT_ANDROID_API = "30";

## What a program is compiled for: the platform `Target(...)` predicates
## evaluate against, and the build options `-D` defines.
export struct Target {
    ## The OS: `"linux"`, `"macos"`, `"windows"`, `"wasi"`, `"ios"` or
    ## `"android"`.
    var os: String = "";
    ## The architecture: `"x86_64"`, `"aarch64"` or `"wasm32"`.
    var arch: String = "";
    ## The LLVM target triple `--target` names, or empty for the host's own
    ## (LLVM's default triple, which also carries the host OS version on
    ## macOS).
    var triple: String = "";
    ## The build options by name, each with its value as written (`"1"`
    ## for a bare `-D NAME`).
    var build_options: HashMap<String, String> = HashMap<String, String>();
    ## The `[features]` of the project's package that `--features` turns on.
    var features: String[] = Array<String>();
    ## Whether the project's package's `default` feature is on: false
    ## with `--no-default-features`.
    var default_features: bool = true;
    ## The names of the other workspace members built with the project's
    ## package (`--all`, `-p`), whose features are unified with its.
    var members: String[] = Array<String>();
    ## In the build of a package's build script (`--build-script DIR`), the
    ## folder whose `.pep/deps`, `pep.lock` and `[overrides]` serve the
    ## build that runs it: the script's package then sees its
    ## `[build-dependencies]` instead of its `[dependencies]`. Empty in any
    ## other build.
    var build_script_root: Path? = Optional<Path>.Empty;

    ## Creates the target the compiler runs on, with no build options.
    construct() {
        os = system_name();
        var name = architecture();
        arch = name == "x64" ? "x86_64" : name;
    }

    ## The target `triple` names (`aarch64-apple-darwin`,
    ## `x86_64-pc-windows-msvc`), with no build options, read from clang's
    ## spellings of the architectures (`x86_64`, `amd64`; `aarch64`,
    ## `arm64`) and operating systems (`linux-gnu`, `darwin` or `macosx`,
    ## `windows-msvc`), with any vendor and an OS version
    ## (`arm64-apple-macosx14.0`). WebAssembly is `wasm32-wasip1`, also
    ## spelled `wasm32-wasi` or `wasm32-unknown-wasi`; an iOS or Android
    ## triple without a version or API level gets `DEFAULT_IOS_VERSION` or
    ## `DEFAULT_ANDROID_API`.
    ##
    ## @param triple the triple
    ## @returns the target, or why it is not one Pepper compiles for
    static parse(triple: String): Result<Target, String> {
        var unsupported = $"unsupported target '{triple}'; expected one of: {", ".join(supported_triples())}";
        var target = Target();
        if (triple == "wasm32-wasi"
            or triple == "wasm32-wasip1"
            or triple == "wasm32-unknown-wasi"
            or triple == "wasm32-unknown-wasip1") {
            target.os = "wasi";
            target.arch = "wasm32";
            target.triple = "wasm32-wasip1";
            return Result<Target, String>.ok(target);
        }
        var parts = triple.split("-");
        if (parts.count < 3) {
            return Result<Target, String>.err(unsupported);
        }
        for (var part in parts) {
            if (part.is_empty) {
                return Result<Target, String>.err(unsupported);
            }
        }
        if (parts[0] == "x86_64" or parts[0] == "amd64") {
            target.arch = "x86_64";
        } else if (parts[0] == "aarch64" or parts[0] == "arm64") {
            target.arch = "aarch64";
        } else {
            return Result<Target, String>.err(unsupported);
        }
        # The OS and environment follow the vendor (`x86_64-pc-windows-msvc`),
        # or stand in for it (`x86_64-linux-gnu`).
        var system = Array<String>();
        for (var i in 1..parts.count) {
            system.append(parts[i]);
        }
        if (_names(system, "android")) {
            return _android(target, system, triple);
        }
        if (_names(system, "ios")) {
            var ios = _ios(target, system);
            if (!ios.is_value()) {
                return Result<Target, String>.err(unsupported);
            }
            return Result<Target, String>.ok(ios.value());
        }
        if (_names(system, "linux") and _names(system, "gnu")) {
            target.os = "linux";
        } else if (_names(system, "darwin") or _names(system, "macos")) {
            target.os = "macos";
        } else if (_names(system, "windows") and system[system.count - 1] == "msvc") {
            target.os = "windows";
        } else {
            return Result<Target, String>.err(unsupported);
        }
        target.triple = triple;
        return Result<Target, String>.ok(target);
    }

    ## The triple without its OS version, which names the platform's system
    ## root (`PEPPER_SYSROOT_AARCH64_APPLE_IOS_SIMULATOR` for every
    ## `aarch64-apple-ios<version>-simulator`): an iOS version or Android API
    ## level picks what the code may call, not where the SDK is. Empty for
    ## the host's own.
    ##
    ## @returns the triple
    platform_triple(): String {
        if (os == "ios") {
            return _strip_version(triple, "-apple-ios");
        }
        if (os == "android") {
            return _strip_version(triple, "-linux-android");
        }
        return triple;
    }

    ## Whether this is an Apple platform built on Darwin (macOS or iOS):
    ## Mach-O objects, libSystem, and the SDK's `.tbd` stubs.
    ##
    ## @returns true for macOS and iOS
    is_apple(): bool {
        return os == "macos" or os == "ios";
    }

    ## Whether this is the machine the compiler runs on: the code it
    ## produces can run here.
    ##
    ## @returns true for the host's OS and architecture
    is_host(): bool {
        var host = Target();
        return os == host.os and arch == host.arch;
    }

    ## Returns whether `attributes` keep their declaration on this target:
    ## every one evaluates true. Attributes that select nothing (`[Export]`,
    ## `[Align(8)]`) keep it, except `[__BuiltIn]`, which drops it
    ## everywhere, and `[Test]`, which keeps it only in a test build.
    ##
    ## @param attributes the declaration's attributes
    ## @returns whether it is kept, or why an attribute cannot be evaluated
    keep(attributes: Attribute[]): Result<bool, String> {
        if (ast.is_built_in(attributes)) {
            return Result<bool, String>.ok(false);
        }
        if (ast.has_attribute(attributes, TEST_ATTRIBUTE) and !build_options.contains(TEST_BUILD_OPTION)) {
            return Result<bool, String>.ok(false);
        }
        for (var attribute in attributes) {
            if (!contains_platform_predicate(attribute.body)) {
                continue;
            }
            var evaluator = _Evaluator(this, attribute);
            bool kept = evaluator.evaluate(attribute.body);
            if (evaluator.error.is_value()) {
                return Result<bool, String>.err(evaluator.error.value());
            }
            if (!kept) {
                return Result<bool, String>.ok(false);
            }
        }
        return Result<bool, String>.ok(true);
    }

    ## Returns why `attribute` cannot be evaluated, and where, if it
    ## cannot: a malformed `Target(...)` or `BuildOption(...)`. Every other
    ## attribute evaluates.
    ##
    ## @param attribute the attribute
    ## @returns the error and the span it points at, or none
    check(attribute: Attribute): (String, Span)? {
        var evaluator = _Evaluator(this, attribute);
        evaluator.evaluate(attribute.body);
        if (evaluator.error.is_value()) {
            return Optional<(String, Span)>.Value((evaluator.error.value(), evaluator.error_span));
        }
        return Optional<(String, Span)>.Empty;
    }

    ## Returns whether `attributes` keep their declaration, keeping it when
    ## one cannot be evaluated (that is reported elsewhere).
    ##
    ## @param attributes the declaration's attributes
    ## @returns whether it is kept
    keeps(attributes: Attribute[]): bool {
        var kept = keep(attributes);
        return kept.is_err() or kept.value();
    }
}

## Returns whether `body`, an attribute's body, selects a platform: a call
## of `Target(...)` or `BuildOption(...)`.
##
## @param body the attribute's body
## @returns true for a platform selection
export contains_platform_predicate(body: Expression): bool {
    match (body) {
        FunctionCall(function, _, _) => {
            match (function) {
                SymbolRef(id, _) => {
                    return _is_target(id) or _is_build_option(id);
                }
                else => {}
            }
        }
        else => {}
    }
    return false;
}

## What a build option's name is, for an error about one that is not.
export const BUILD_OPTION_NAME_RULE = "a name is a letter or '_' followed by letters, digits and '_'";

## Returns whether `name` can name a build option: a letter or `_`, then
## letters, digits and `_`.
##
## @param name the name
## @returns true for a valid name
export is_build_option_name(name: String): bool {
    if (name.is_empty) {
        return false;
    }
    ulong i = 0;
    while (i < name.size) {
        var b = name.byte_at(i);
        bool letter = (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or b == '_';
        bool digit = b >= '0' and b <= '9';
        if (!letter and !(digit and i > 0)) {
            return false;
        }
        i += 1;
    }
    return true;
}

_is_target(id: String): bool {
    return id.lower() == "target";
}

_is_build_option(id: String): bool {
    return id.lower() == "buildoption";
}

# Whether one of a triple's `system` parts (after the architecture)
# starts with `prefix`.
_names(system: String[], prefix: String): bool {
    for (var part in system) {
        if (part.starts_with(prefix)) {
            return true;
        }
    }
    return false;
}

# Whether `text` is all decimal digits, and not empty.
_is_number(text: String): bool {
    if (text.is_empty) {
        return false;
    }
    for (var i in 0..text.size) {
        var b = text.byte_at(i);
        if (b < '0' or b > '9') {
            return false;
        }
    }
    return true;
}

# An Android target: `<arch>-linux-android<api>`, with the API level the
# triple's `android` part ends in (`android33`), else
# `DEFAULT_ANDROID_API`, which is also the oldest accepted. Any vendor is
# accepted (`aarch64-unknown-linux-android`).
_android(target: Target, system: String[], triple: String): Result<Target, String> {
    var api = "";
    for (var part in system) {
        if (part.starts_with("android") and api.is_empty) {
            api = part.substr_bytes(7, part.size - 7);
        }
    }
    if (api.is_empty) {
        api = DEFAULT_ANDROID_API;
    }
    if (!_is_number(api)) {
        return Result<Target, String>.err($"unsupported target '{triple}': '{api}' is not an Android API level");
    }
    var level = ulong.parse(api);
    var oldest = ulong.parse(DEFAULT_ANDROID_API).value();
    if (!level.is_value() or level.value() < oldest) {
        return Result<Target, String>.err(
            $"unsupported target '{triple}': Pepper's runtime needs Android API level {oldest} or later (write 'android{oldest}')"
        );
    }
    target.os = "android";
    target.triple = $"{target.arch}-linux-android{api}";
    return Result<Target, String>.ok(target);
}

# An iOS target: `<arch>-apple-ios<version>`, with `-simulator` for the
# simulator, which some spell `-sim` and an x86_64 triple implies (no
# iPhone is x86_64). The version is the triple's (`ios17.0`), else
# `DEFAULT_IOS_VERSION`. None for an environment other than the simulator
# (`-macabi`).
_ios(target: Target, system: String[]): Target? {
    var version = "";
    for (var part in system) {
        if (part.starts_with("ios") and version.is_empty) {
            version = part.substr_bytes(3, part.size - 3);
        }
    }
    if (version.is_empty) {
        version = DEFAULT_IOS_VERSION;
    }
    var last = system[system.count - 1];
    bool simulator = false;
    if (last == "simulator" or last == "sim") {
        simulator = true;
    } else if (last.starts_with("ios")) {
        simulator = target.arch == "x86_64";
    } else {
        return Optional<Target>.Empty;
    }
    target.os = "ios";
    target.triple = $"{target.arch}-apple-ios{version}{simulator ? "-simulator" : ""}";
    return Optional<Target>.Value(target);
}

# `triple` without the version that follows `prefix` in it, up to the next
# `-` (`aarch64-apple-ios17.0-simulator` is `aarch64-apple-ios-simulator`).
_strip_version(triple: String, prefix: String): String {
    var at = triple.find(prefix);
    if (at < 0) {
        return triple;
    }
    var start = at as ulong + prefix.size;
    var end = triple.find("-", start);
    var rest = end < 0 ? "" : triple.substr_bytes(end as ulong, triple.size - end as ulong);
    return triple.substr_bytes(0, start) + rest;
}

# Evaluates one attribute against a target; `error` says why it cannot be.
struct _Evaluator {
    var target: Target;
    var attribute: Attribute;
    var error: String?;
    # Where `error` points: the whole attribute unless a part of it is to
    # blame.
    var error_span: Span = Span();

    construct(target: Target, attribute: Attribute) {
        this.target = target;
        this.attribute = attribute;
    }

    # Records the first error, at the whole attribute, and returns false.
    _fail(message: String): bool {
        return _fail_at(message, attribute.span);
    }

    # Records the first error, at `span`, and returns false.
    _fail_at(message: String, span: Span): bool {
        if (!error.is_value()) {
            error = Optional<String>.Value(message);
            error_span = span;
        }
        return false;
    }

    evaluate(body: Expression): bool {
        match (body) {
            SymbolRef(id, span) => {
                if (_is_build_option(id)) {
                    return _fail_at($"'{id}' needs the name of a build option, such as '[{id}(\"USE_ZLIB\")]'", span);
                }
                if (_is_target(id)) {
                    return _fail_at($"'{id}' needs a predicate, such as '[{id}(OS(Linux))]'", span);
                }
                return true;
            }
            FunctionCall(function, arguments, call_span) => {
                match (function) {
                    SymbolRef(id, _) => {
                        if (_is_build_option(id)) {
                            var name = _build_option_name(id, arguments, call_span);
                            return name.is_value() and target.build_options.contains(name.value());
                        }
                        if (_is_target(id)) {
                            if (arguments.count != 1) {
                                return _fail_at(
                                    $"'{id}' takes exactly one predicate, a boolean over 'OS(...)', 'Arch(...)' and 'BuildOption(...)'",
                                    call_span
                                );
                            }
                            return _predicate(arguments[0]);
                        }
                        return true;
                    }
                    else => {
                        return true;
                    }
                }
            }
            MemberAccess(_, _, _, _) => {
                return true;
            }
            TypeLiteral(_) => {
                return true;
            }
            else => {
                return _fail(_bad_body());
            }
        }
        return true;
    }

    _bad_body(): String {
        return $"invalid platform predicate in '{attribute_text(attribute)}'; expected 'OS(...)', 'Arch(...)' or 'BuildOption(...)'";
    }

    _predicate(e: Expression): bool {
        match (e) {
            FunctionCall(function, arguments, call_span) => {
                match (function) {
                    SymbolRef(id, id_span) => {
                        var lower = id.lower();
                        if (lower == "os") {
                            return _os_matches(id, arguments, call_span);
                        }
                        if (lower == "arch") {
                            return _arch_matches(id, arguments, call_span);
                        }
                        if (_is_build_option(id)) {
                            var name = _build_option_name(id, arguments, call_span);
                            return name.is_value() and target.build_options.contains(name.value());
                        }
                        if (_is_target(id)) {
                            return _fail_at($"'{id}' cannot be nested inside 'Target(...)'", id_span);
                        }
                        return _fail_at($"unknown predicate '{id}'; expected 'OS', 'Arch' or 'BuildOption'", id_span);
                    }
                    else => {
                        return _fail(_bad_body());
                    }
                }
            }
            Unary(op, prefix, operand, _) => {
                if (prefix and op == "!") {
                    bool value = _predicate(operand);
                    return error.is_empty() and !value;
                }
                return _fail(_bad_body());
            }
            Binary(lhs, op, rhs, span) => {
                # Both operands are evaluated, so a malformed predicate in
                # either half is reported on every host.
                if (op == "&&" or op == "and") {
                    bool left = _predicate(lhs);
                    bool right = _predicate(rhs);
                    return left and right;
                }
                if (op == "||" or op == "or") {
                    bool left = _predicate(lhs);
                    bool right = _predicate(rhs);
                    return left or right;
                }
                if (op == "==" or op == "!=" or op == "<" or op == "<=" or op == ">" or op == ">=") {
                    return _compare(lhs, op, rhs, span);
                }
                if (_is_arithmetic_operator(op)) {
                    return _fail_at(
                        $"'{op}' in a 'Target' must be part of a comparison, such as 'BuildOption(A) {op} 2 == 0'", span
                    );
                }
                return _fail(_bad_body());
            }
            SymbolRef(id, span) => {
                return _fail_at(
                    $"'{id}' is not a predicate; expected 'OS(...)', 'Arch(...)' or 'BuildOption(...)'", span
                );
            }
            else => {
                return _fail(_bad_body());
            }
        }
        return false;
    }

    # The name a `BuildOption(...)` call (spelled `id`) tests: one argument,
    # a name or a string holding one.
    _build_option_name(id: String, arguments: Expression[], span: Span): String? {
        if (arguments.count != 1) {
            _fail_at($"'{id}' takes the name of one build option, such as '{id}(USE_ZLIB)'", span);
            return Optional<String>.Empty;
        }
        var argument = arguments[0];
        var name = "";
        match (argument) {
            SymbolRef(symbol, _) => {
                name = symbol;
            }
            Literal(value, _) => {
                match (value) {
                    String(text) => {
                        name = text;
                    }
                    else => {
                        _fail_at($"'{id}' takes the name of a build option, such as '{id}(USE_ZLIB)'", argument.span());
                        return Optional<String>.Empty;
                    }
                }
            }
            else => {
                _fail_at($"'{id}' takes the name of a build option, such as '{id}(USE_ZLIB)'", argument.span());
                return Optional<String>.Empty;
            }
        }
        if (!is_build_option_name(name)) {
            _fail_at($"invalid build option name '{name}'; {BUILD_OPTION_NAME_RULE}", argument.span());
            return Optional<String>.Empty;
        }
        return Optional<String>.Value(name);
    }

    # `lhs op rhs`: a `BuildOption(NAME)` compared with a literal, either
    # way round, or with another, or arithmetic on options. False when an
    # option is not defined.
    _compare(lhs: Expression, op: String, rhs: Expression, span: Span): bool {
        if (_is_numeric_comparison(lhs, rhs)) {
            return _compare_numbers(lhs, op, rhs, span);
        }
        bool left = _is_build_option_call(lhs);
        bool right = _is_build_option_call(rhs);
        if (left and right) {
            return _compare_options(lhs, op, rhs, span);
        }
        if (!left and !right) {
            return _fail_at(
                $"'{op}' in a 'Target' must compare a 'BuildOption(...)' with a literal or another 'BuildOption(...)'",
                span
            );
        }
        var option = left ? lhs : rhs;
        var literal = left ? rhs : lhs;
        var compared = op;
        if (!left) {
            # `2 <= BuildOption(X)` is `BuildOption(X) >= 2`.
            match (op) {
                "<" => {
                    compared = ">";
                }
                "<=" => {
                    compared = ">=";
                }
                ">" => {
                    compared = "<";
                }
                ">=" => {
                    compared = "<=";
                }
                else => {}
            }
        }
        var name = _option_name(option);
        if (!name.is_value()) {
            return false;
        }
        var value = comparison_literal(literal);
        bool usable = value.is_value();
        if (usable) {
            match (value.value()) {
                Char(_) => {
                    usable = false;
                }
                Null => {
                    usable = false;
                }
                Unsigned(n) => {
                    return _fail_at(
                        $"build option '{name.value()}' cannot be compared with {n}: a build option is a 'long'",
                        literal.span()
                    );
                }
                else => {}
            }
        }
        if (!usable) {
            return _fail_at(
                $"build option '{name.value()}' can only be compared with a literal: a number, 'true' or 'false', or a string",
                literal.span()
            );
        }
        bool is_bool = false;
        match (value.value()) {
            Bool(_) => {
                is_bool = true;
            }
            else => {}
        }
        if (is_bool and compared != "==" and compared != "!=") {
            return _fail_at(
                $"'{compared}' cannot compare build option '{name.value()}' with a bool; use '==' or '!='", span
            );
        }
        var defined = target.build_options.try_get(name.value());
        if (!defined.is_value()) {
            return false;
        }
        var text = defined.value();
        int ordering = 0;
        match (value.value()) {
            Integer(n) => {
                var parsed = _parse_integer(text);
                if (!parsed.is_value()) {
                    return _fail_at($"build option '{name.value()}' is '{text}', which is not an integer", span);
                }
                ordering = parsed.value() < n ? -1 : (parsed.value() > n ? 1 : 0);
            }
            Float(f) => {
                var parsed = double.parse(text.trim());
                if (!parsed.is_value()) {
                    return _fail_at($"build option '{name.value()}' is '{text}', which is not a number", span);
                }
                var d = parsed.value();
                if (d != d or f != f) {
                    return compared == "!=";
                }
                ordering = d < f ? -1 : (d > f ? 1 : 0);
            }
            Bool(b) => {
                var parsed = _parse_bool(text);
                if (!parsed.is_value()) {
                    return _fail_at($"build option '{name.value()}' is '{text}', which is not 'true' or 'false'", span);
                }
                int l = parsed.value() ? 1 : 0;
                int r = b ? 1 : 0;
                ordering = l - r;
            }
            String(s) => {
                ordering = text.compare(s);
                ordering = ordering < 0 ? -1 : (ordering > 0 ? 1 : 0);
            }
            else => {}
        }
        return _ordered(compared, ordering);
    }

    # `BuildOption(A) op BuildOption(B)`: as integers when both values are,
    # else as numbers when both are, else as text, which only `==` and `!=`
    # compare. False when either option is not defined, as with a literal.
    _compare_options(lhs: Expression, op: String, rhs: Expression, span: Span): bool {
        var left = _option_name(lhs);
        var right = _option_name(rhs);
        if (!left.is_value() or !right.is_value()) {
            return false;
        }
        var a = target.build_options.try_get(left.value());
        var b = target.build_options.try_get(right.value());
        if (!a.is_value() or !b.is_value()) {
            return false;
        }
        var m = _parse_integer(a.value());
        var n = _parse_integer(b.value());
        if (m.is_value() and n.is_value()) {
            return _ordered(op, m.value() < n.value() ? -1 : (m.value() > n.value() ? 1 : 0));
        }
        var x = double.parse(a.value().trim());
        var y = double.parse(b.value().trim());
        if (x.is_value() and y.is_value()) {
            var d = x.value();
            var e = y.value();
            if (d != d or e != e) {
                return op == "!=";
            }
            return _ordered(op, d < e ? -1 : (d > e ? 1 : 0));
        }
        if (op != "==" and op != "!=") {
            var name = x.is_value() ? right.value() : left.value();
            var text = x.is_value() ? b.value() : a.value();
            return _fail_at(
                $"build option '{name}' is '{text}', which is not a number; '{op}' compares two build options only as numbers",
                span
            );
        }
        return (a.value() == b.value()) == (op == "==");
    }

    # `lhs op rhs` with arithmetic on a side: as integers when every value
    # in it is one, else as numbers. False when an option is not defined.
    _compare_numbers(lhs: Expression, op: String, rhs: Expression, span: Span): bool {
        # Both sides are evaluated, so an error in either is reported.
        var a = _number(lhs, op, span);
        var b = _number(rhs, op, span);
        if (!a.is_value() or !b.is_value()) {
            return false;
        }
        var x = a.value();
        var y = b.value();
        if (x.integer.is_value() and y.integer.is_value()) {
            var m = x.integer.value();
            var n = y.integer.value();
            return _ordered(op, m < n ? -1 : (m > n ? 1 : 0));
        }
        if (x.real != x.real or y.real != y.real) {
            return op == "!=";
        }
        return _ordered(op, x.real < y.real ? -1 : (x.real > y.real ? 1 : 0));
    }

    # The value of `e`, an operand of `op` (at `op_span`): a build option, a
    # number, or `+ - * / %` on them. Empty when an option in it is not
    # defined, or after reporting an error.
    _number(e: Expression, op: String, op_span: Span): _Number? {
        bool arithmetic = _is_arithmetic_operator(op);
        if (e is Binary(lhs, inner, rhs, span)) {
            if (_is_arithmetic_operator(inner)) {
                var a = _number(lhs, inner, span);
                var b = _number(rhs, inner, span);
                if (!a.is_value() or !b.is_value()) {
                    return Optional<_Number>.Empty;
                }
                return _arithmetic(a.value(), inner, b.value(), span);
            }
        }
        if (_is_build_option_call(e)) {
            var name = _option_name(e);
            if (!name.is_value()) {
                return Optional<_Number>.Empty;
            }
            var text = target.build_options.try_get(name.value());
            if (!text.is_value()) {
                return Optional<_Number>.Empty;
            }
            var integer = _parse_integer(text.value());
            if (integer.is_value()) {
                return Optional<_Number>.Value(_Number.of_integer(integer.value()));
            }
            var real = double.parse(text.value().trim());
            if (real.is_value()) {
                return Optional<_Number>.Value(_Number.of_real(real.value()));
            }
            var rule = arithmetic ? "takes only numbers" : "compares arithmetic only with numbers";
            _fail_at(
                $"build option '{name.value()}' is '{text.value()}', which is not a number; '{op}' {rule}", op_span
            );
            return Optional<_Number>.Empty;
        }
        var literal = comparison_literal(e);
        if (literal.is_value()) {
            match (literal.value()) {
                Integer(n) => {
                    return Optional<_Number>.Value(_Number.of_integer(n));
                }
                Float(f) => {
                    return Optional<_Number>.Value(_Number.of_real(f));
                }
                else => {}
            }
        }
        var rule = arithmetic ? "takes only" : "compares arithmetic only with";
        _fail_at($"'{op}' in a 'Target' {rule} build options and numbers", e.span());
        return Optional<_Number>.Empty;
    }

    # `a op b` (at `span`) for `+ - * / %`: as `long`s when both are
    # integers, where dividing by zero and overflowing are errors, else as
    # `double`s.
    _arithmetic(a: _Number, op: String, b: _Number, span: Span): _Number? {
        if (!a.integer.is_value() or !b.integer.is_value()) {
            match (op) {
                "+" => {
                    return Optional<_Number>.Value(_Number.of_real(a.real + b.real));
                }
                "-" => {
                    return Optional<_Number>.Value(_Number.of_real(a.real - b.real));
                }
                "*" => {
                    return Optional<_Number>.Value(_Number.of_real(a.real * b.real));
                }
                "/" => {
                    return Optional<_Number>.Value(_Number.of_real(a.real / b.real));
                }
                else => {
                    return Optional<_Number>.Value(_Number.of_real(a.real % b.real));
                }
            }
        }
        var m = a.integer.value();
        var n = b.integer.value();
        var result = Optional<long>.Empty;
        match (op) {
            "+" => {
                result = m.checked_add(n);
            }
            "-" => {
                result = m.checked_sub(n);
            }
            "*" => {
                result = m.checked_mul(n);
            }
            else => {
                if (n == 0) {
                    var what = op == "/" ? "division" : "remainder";
                    _fail_at($"{what} by zero in a 'Target' condition", span);
                    return Optional<_Number>.Empty;
                }
                # `m / -1` overflows only for the lowest `long`, and the
                # machine's `%` traps there.
                if (n == -1) {
                    result = op == "/" ? (0 as long).checked_sub(m) : Optional<long>.Value(0);
                } else {
                    result = Optional<long>.Value(op == "/" ? m / n : m % n);
                }
            }
        }
        if (!result.is_value()) {
            _fail_at($"integer overflow: '{m} {op} {n}' does not fit in a 'long'", span);
            return Optional<_Number>.Empty;
        }
        return Optional<_Number>.Value(_Number.of_integer(result.value()));
    }

    # The name `option`, a `BuildOption(...)` call, tests.
    _option_name(option: Expression): String? {
        match (option) {
            FunctionCall(function, arguments, span) => {
                match (function) {
                    SymbolRef(id, _) => {
                        return _build_option_name(id, arguments, span);
                    }
                    else => {}
                }
            }
            else => {}
        }
        return Optional<String>.Empty;
    }

    _os_matches(name: String, arguments: Expression[], call_span: Span): bool {
        var value = _value_of(name, arguments, call_span, _OS_VALUES);
        if (!value.is_value()) {
            return false;
        }
        var value_span = arguments[0].span();
        var host = target.os;
        if (host != "windows"
            and host != "macos"
            and host != "linux"
            and host != "wasi"
            and host != "ios"
            and host != "android") {
            return false;
        }
        match (value.value().lower()) {
            "windows" => {
                return host == "windows";
            }
            "mac", "macos" => {
                return host == "macos" or host == "ios";
            }
            "linux" => {
                return host == "linux" or host == "android";
            }
            "wasi" => {
                return host == "wasi";
            }
            "ios" => {
                return host == "ios";
            }
            "android" => {
                return host == "android";
            }
            else => {
                return _fail_at($"unknown OS '{value.value()}'; expected {_OS_VALUES}", value_span);
            }
        }
    }

    _arch_matches(name: String, arguments: Expression[], call_span: Span): bool {
        var value = _value_of(name, arguments, call_span, _ARCH_VALUES);
        if (!value.is_value()) {
            return false;
        }
        var host = "";
        match (target.arch) {
            "x86_64" => {
                host = "x64";
            }
            "aarch64" => {
                host = "aarch64";
            }
            "wasm32" => {
                host = "wasm32";
            }
            else => {
                return false;
            }
        }
        var lower = value.value().lower();
        if (lower == host) {
            return true;
        }
        if (lower == "x64" or lower == "aarch64" or lower == "wasm32") {
            return false;
        }
        return _fail_at($"unknown Arch '{value.value()}'; expected {_ARCH_VALUES}", arguments[0].span());
    }

    # The one name `OS(...)` or `Arch(...)` (`name`) is given, which is one of
    # `values`; empty after reporting a call without one.
    _value_of(name: String, arguments: Expression[], call_span: Span, values: String): String? {
        if (arguments.count != 1) {
            _fail_at($"'{name}' takes exactly one value: {values}", call_span);
            return Optional<String>.Empty;
        }
        if (arguments[0] is SymbolRef(id, _)) {
            return Optional<String>.Value(id);
        }
        _fail_at($"the value of '{name}' must be a name: {values}", arguments[0].span());
        return Optional<String>.Empty;
    }
}

# The values `OS(...)` takes, as an error lists them.
const _OS_VALUES = "'Windows', 'Mac', 'MacOS', 'Linux', 'Wasi', 'IOS' or 'Android'";

# The values `Arch(...)` takes, as an error lists them.
const _ARCH_VALUES = "'x64', 'aarch64' or 'wasm32'";

## A comparison with a build option the target does not define, which is
## false.
export struct UndefinedOption {
    ## The option's name.
    var name: String;
    ## The `BuildOption(...)` call.
    var span: Span;

    ## Creates one.
    ##
    ## @param name the option's name
    ## @param span the call
    construct(name: String, span: Span) {
        this.name = name;
        this.span = span;
    }
}

## Returns the well-formed comparisons in `attribute` with a build option
## `target` does not define, in source order.
##
## @param target the target
## @param attribute an attribute that tests build options
## @returns each comparison's option and `BuildOption(...)` call
export undefined_build_option_comparisons(target: Target, attribute: Attribute): UndefinedOption[] {
    var out = Array<UndefinedOption>();
    _undefined_options(_Evaluator(target, attribute), attribute.body, out);
    return out;
}

_undefined_options(evaluator: _Evaluator, e: Expression, out: UndefinedOption[]) {
    match (e) {
        Binary(lhs, op, rhs, _) => {
            if (op == "==" or op == "!=" or op == "<" or op == "<=" or op == ">" or op == ">=") {
                # Only a well-formed comparison, of an option with a
                # literal or another option, or of arithmetic on options:
                # a malformed one is an error.
                bool left = _is_build_option_call(lhs);
                bool right = _is_build_option_call(rhs);
                if (!(left and right)
                    and !(left and comparison_literal(rhs).is_value())
                    and !(right and comparison_literal(lhs).is_value())
                    and !_is_numeric_comparison(lhs, rhs)) {
                    return;
                }
                _undefined_operands(evaluator, lhs, out);
                _undefined_operands(evaluator, rhs, out);
                return;
            }
            _undefined_options(evaluator, lhs, out);
            _undefined_options(evaluator, rhs, out);
        }
        Unary(_, _, operand, _) => {
            _undefined_options(evaluator, operand, out);
        }
        FunctionCall(_, arguments, _) => {
            for (var a in arguments) {
                _undefined_options(evaluator, a, out);
            }
        }
        else => {}
    }
}

# The options `e`, a side of a comparison, uses that the target does not
# define: `e` itself, or those in its arithmetic.
_undefined_operands(evaluator: _Evaluator, e: Expression, out: UndefinedOption[]) {
    if (_is_build_option_call(e)) {
        var name = evaluator._option_name(e);
        if (name.is_value() and !evaluator.target.build_options.contains(name.value())) {
            out.append(UndefinedOption(name.value(), e.span()));
        }
    } else if (e is Binary(lhs, op, rhs, _)) {
        if (_is_arithmetic_operator(op)) {
            _undefined_operands(evaluator, lhs, out);
            _undefined_operands(evaluator, rhs, out);
        }
    }
}

# Whether `op` is one of `+ - * / %`.
_is_arithmetic_operator(op: String): bool {
    return op == "+" or op == "-" or op == "*" or op == "/" or op == "%";
}

# Whether `e` is `+ - * / %`.
_is_arithmetic(e: Expression): bool {
    if (e is Binary(_, op, _, _)) {
        return _is_arithmetic_operator(op);
    }
    return false;
}

# Whether `e` is a build option or arithmetic with one in it.
_uses_option(e: Expression): bool {
    if (e is Binary(lhs, op, rhs, _)) {
        return _is_arithmetic_operator(op) and (_uses_option(lhs) or _uses_option(rhs));
    }
    return _is_build_option_call(e);
}

# Whether `lhs` compared with `rhs` is arithmetic on build options.
_is_numeric_comparison(lhs: Expression, rhs: Expression): bool {
    return (_is_arithmetic(lhs) or _is_arithmetic(rhs)) and (_uses_option(lhs) or _uses_option(rhs));
}

# A value a `Target` condition computes: a `long` (`integer`) when every
# value it is made from is an integer, else a `double` (`real`).
struct _Number {
    var integer: long?;
    var real: double;

    construct(integer: long?, real: double) {
        this.integer = integer;
        this.real = real;
    }

    static of_integer(n: long): _Number {
        return _Number(Optional<long>.Value(n), n as double);
    }

    static of_real(d: double): _Number {
        return _Number(Optional<long>.Empty, d);
    }
}

_is_build_option_call(e: Expression): bool {
    match (e) {
        FunctionCall(function, _, _) => {
            match (function) {
                SymbolRef(id, _) => {
                    return _is_build_option(id);
                }
                else => {}
            }
        }
        else => {}
    }
    return false;
}

## Returns `e` as a literal a build option can be compared with, a
## negative number included (`-1`).
##
## @param e the expression
## @returns the literal, or none
export comparison_literal(e: Expression): Literal? {
    match (e) {
        Literal(value, _) => {
            return Optional<Literal>.Value(value);
        }
        Unary(op, prefix, operand, _) => {
            if (!prefix or op != "-") {
                return Optional<Literal>.Empty;
            }
            match (operand) {
                Literal(value, _) => {
                    match (value) {
                        Integer(n) => {
                            return Optional<Literal>.Value(Literal.Integer(-n));
                        }
                        Float(f) => {
                            return Optional<Literal>.Value(Literal.Float(-f));
                        }
                        else => {}
                    }
                }
                else => {}
            }
        }
        else => {}
    }
    return Optional<Literal>.Empty;
}

# A build option's value as an integer: decimal, or hexadecimal after
# `0x`, with an optional sign; empty when it is not one or does not fit in
# a `long`.
_parse_integer(text: String): long? {
    var digits = text.trim();
    bool negative = false;
    if (digits.starts_with("-")) {
        negative = true;
        digits = digits.substr_bytes(1, digits.size - 1);
    } else if (digits.starts_with("+")) {
        digits = digits.substr_bytes(1, digits.size - 1);
    }
    ulong radix = 10;
    if (digits.starts_with("0x") or digits.starts_with("0X")) {
        radix = 16;
        digits = digits.substr_bytes(2, digits.size - 2);
    }
    if (digits.is_empty) {
        return Optional<long>.Empty;
    }
    # Counted down, so the lowest `long` fits; empty when it does not fit.
    var value = Optional<long>.Value(0);
    ulong i = 0;
    while (i < digits.size) {
        var b = digits.byte_at(i);
        long digit = 0;
        if (b >= '0' and b <= '9') {
            digit = (b - '0') as long;
        } else if (radix == 16 and b >= 'a' and b <= 'f') {
            digit = (b - 'a') as long + 10;
        } else if (radix == 16 and b >= 'A' and b <= 'F') {
            digit = (b - 'A') as long + 10;
        } else {
            return Optional<long>.Empty;
        }
        value = value.value().checked_mul(radix as long);
        if (value.is_value()) {
            value = value.value().checked_sub(digit);
        }
        if (!value.is_value()) {
            return value;
        }
        i += 1;
    }
    return negative ? value : (0 as long).checked_sub(value.value());
}

# A build option's value as a bool: `true`/`false`, `1`/`0`, `on`/`off` or
# `yes`/`no`, in any case.
_parse_bool(text: String): bool? {
    match (text.trim().lower()) {
        "true", "1", "on", "yes" => {
            return Optional<bool>.Value(true);
        }
        "false", "0", "off", "no" => {
            return Optional<bool>.Value(false);
        }
        else => {
            return Optional<bool>.Empty;
        }
    }
}

# Whether `ordering` (-1, 0 or 1, left against right) satisfies `op`.
_ordered(op: String, ordering: int): bool {
    match (op) {
        "==" => {
            return ordering == 0;
        }
        "!=" => {
            return ordering != 0;
        }
        "<" => {
            return ordering < 0;
        }
        "<=" => {
            return ordering <= 0;
        }
        ">" => {
            return ordering > 0;
        }
        else => {
            return ordering >= 0;
        }
    }
}

## Returns an attribute as diagnostics quote it: `[Target(OS(Linux) &&
## Arch(x64))]`, a top-level binary and a call's one binary argument
## without parentheses.
##
## @param attribute the attribute
## @returns the text
export attribute_text(attribute: Attribute): String {
    match (attribute.body) {
        Binary(lhs, op, rhs, _) => {
            return $"[{expression_text(lhs)} {op} {expression_text(rhs)}]";
        }
        FunctionCall(function, arguments, _) => {
            bool symbol = false;
            match (function) {
                SymbolRef(_, _) => {
                    symbol = true;
                }
                else => {}
            }
            if (symbol and arguments.count == 1) {
                match (arguments[0]) {
                    Binary(lhs, op, rhs, _) => {
                        return $"[{expression_text(function)}({expression_text(lhs)} {op} {expression_text(rhs)})]";
                    }
                    else => {
                        return $"[{expression_text(function)}({expression_text(arguments[0])})]";
                    }
                }
            }
        }
        else => {}
    }
    return $"[{expression_text(attribute.body)}]";
}

## Returns an expression of the kinds an attribute holds, written with
## every binary in parentheses.
##
## @param e the expression
## @returns the text
export expression_text(e: Expression): String {
    match (e) {
        Literal(value, _) => {
            return literal_text(value);
        }
        SymbolRef(id, _) => {
            return id;
        }
        TypeLiteral(type_name) => {
            return type_name.to_string();
        }
        SizeOf(type_name) => {
            return $"sizeof<{type_name.to_string()}>()";
        }
        Unary(op, prefix, operand, _) => {
            return prefix ? op + expression_text(operand) : expression_text(operand) + op;
        }
        Binary(lhs, op, rhs, _) => {
            return $"({expression_text(lhs)} {op} {expression_text(rhs)})";
        }
        Cast(expr, type_name, _, _, optional) => {
            return $"({expression_text(expr)} as{optional ? "?" : ""} {type_name.to_string()})";
        }
        Ternary(condition, true_expr, false_expr, _) => {
            return $"({expression_text(condition)} ? {expression_text(true_expr)} : {expression_text(false_expr)})";
        }
        Index(lhs, rhs, _) => {
            return $"{expression_text(lhs)}[{expression_text(rhs)}]";
        }
        MemberAccess(lhs, name, _, _) => {
            return $"{expression_text(lhs)}.{name}";
        }
        FunctionCall(function, arguments, _) => {
            return $"{expression_text(function)}({_texts(arguments)})";
        }
        NamedArgument(name, _, value, _) => {
            return $"{name} = {expression_text(value)}";
        }
        Tuple(elements, labels, _) => {
            if (labels.count == 0) {
                return $"({_texts(elements)})";
            }
            var parts = Array<String>();
            ulong i = 0;
            while (i < elements.count and i < labels.count) {
                parts.append($"{labels[i].name}: {expression_text(elements[i])}");
                i += 1;
            }
            return $"({", ".join(parts)})";
        }
        ArrayLiteral(elements, _) => {
            return $"[{_texts(elements)}]";
        }
        else => {
            return "...";
        }
    }
}

_texts(expressions: Expression[]): String {
    var parts = Array<String>();
    for (var e in expressions) {
        parts.append(expression_text(e));
    }
    return ", ".join(parts);
}

## Returns a literal as source writes it: a string quoted with its escapes.
##
## @param value the literal
## @returns the text
export literal_text(value: Literal): String {
    match (value) {
        String(text) => {
            var out = StringBuilder();
            out.append("\"");
            for (var c in text) {
                match (c) {
                    "\n" => {
                        out.append("\\n");
                    }
                    "\t" => {
                        out.append("\\t");
                    }
                    "\r" => {
                        out.append("\\r");
                    }
                    "\0" => {
                        out.append("\\0");
                    }
                    "\\" => {
                        out.append("\\\\");
                    }
                    "\"" => {
                        out.append("\\\"");
                    }
                    else => {
                        out.append(c);
                    }
                }
            }
            out.append("\"");
            return out.to_string();
        }
        Integer(n) => {
            return $"{n}";
        }
        Unsigned(n) => {
            return $"{n}";
        }
        Float(f) => {
            return $"{f}";
        }
        Bool(b) => {
            return b ? "true" : "false";
        }
        Char(b) => {
            return $"'{b}'";
        }
        Null => {
            return "null";
        }
    }
    return "";
}
