## Platform selection: whether a declaration's attributes keep it on the
## compile target. `[Target(...)]` takes one boolean over `OS(v)`,
## `Arch(v)` and `BuildOption(NAME)` calls, comparisons of a build option
## with a literal, `!`, `&&` and `||`; `[BuildOption("NAME")]` is short for
## `[Target(BuildOption(NAME))]`. See docs/src/language/platform-selection.md.

import compiler.ast;
import [Attribute, Expression, Literal, Span] from compiler.ast;
import [architecture, system_name] from os;

## The attribute that marks a unit test: `[Test]`.
export const TEST_ATTRIBUTE = "Test";

## The build option `pep-build --test` defines: `[Test]` functions are kept
## only when it is.
export const TEST_BUILD_OPTION = "TEST";

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

    ## Creates the target the compiler runs on, with no build options.
    construct() {
        os = system_name();
        var name = architecture();
        arch = name == "x64" ? "x86_64" : name;
    }

    ## The target `triple` names (`aarch64-apple-darwin`,
    ## `x86_64-pc-windows-msvc`), with no build options, as
    ## `pepper_sema::Target::parse` reads it: clang's spellings of the
    ## architectures (`x86_64`, `amd64`; `aarch64`, `arm64`) and operating
    ## systems (`linux-gnu`, `darwin` or `macosx`, `windows-msvc`), with any
    ## vendor and an OS version (`arm64-apple-macosx14.0`). WebAssembly is
    ## `wasm32-wasip1`, also spelled `wasm32-wasi` or `wasm32-unknown-wasi`;
    ## an iOS or Android triple without a version or API level gets
    ## `DEFAULT_IOS_VERSION` or `DEFAULT_ANDROID_API`.
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
                    return _fail($"platform predicate `{id}` used without a value in {attribute_text(attribute)}");
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
                                return _fail(
                                    $"Target takes exactly one value (a boolean over OS(...), Arch(...) and BuildOption(...)) in {attribute_text(attribute)}"
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
        return $"invalid platform predicate in {attribute_text(attribute)}";
    }

    _predicate(e: Expression): bool {
        match (e) {
            FunctionCall(function, arguments, call_span) => {
                match (function) {
                    SymbolRef(id, _) => {
                        var lower = id.lower();
                        if (lower == "os") {
                            return _os_matches(arguments);
                        }
                        if (lower == "arch") {
                            return _arch_matches(arguments);
                        }
                        if (_is_build_option(id)) {
                            var name = _build_option_name(id, arguments, call_span);
                            return name.is_value() and target.build_options.contains(name.value());
                        }
                        if (_is_target(id)) {
                            return _fail($"`{id}` cannot be nested inside Target(...) in {attribute_text(attribute)}");
                        }
                        return _fail(
                            $"unknown predicate `{id}` (expected OS, Arch or BuildOption) in {attribute_text(attribute)}"
                        );
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
                return _fail(_bad_body());
            }
            SymbolRef(id, _) => {
                return _fail(
                    $"bare symbol `{id}` is not a predicate; expected OS(...), Arch(...) or BuildOption(...) in {attribute_text(attribute)}"
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
            _fail_at(
                $"invalid build option name '{name}'; a name is a letter or '_' followed by letters, digits and '_'",
                argument.span()
            );
            return Optional<String>.Empty;
        }
        return Optional<String>.Value(name);
    }

    # `lhs op rhs`: a `BuildOption(NAME)` compared with a literal, either
    # way round. False when the option is not defined.
    _compare(lhs: Expression, op: String, rhs: Expression, span: Span): bool {
        bool left = _is_build_option_call(lhs);
        bool right = _is_build_option_call(rhs);
        if (left and right) {
            return _fail_at(
                $"'{op}' cannot compare two build options; compare a 'BuildOption(...)' with a literal", span
            );
        }
        if (!left and !right) {
            return _fail_at($"'{op}' in a 'Target' must compare a 'BuildOption(...)' with a literal", span);
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
        var id = "";
        var arguments = Array<Expression>();
        var call_span = Span();
        match (option) {
            FunctionCall(function, call_arguments, option_span) => {
                match (function) {
                    SymbolRef(name, _) => {
                        id = name;
                    }
                    else => {}
                }
                arguments = call_arguments;
                call_span = option_span;
            }
            else => {}
        }
        var name = _build_option_name(id, arguments, call_span);
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
        match (compared) {
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

    _os_matches(arguments: Expression[]): bool {
        if (arguments.count != 1) {
            return _fail($"OS predicate takes exactly one value in {attribute_text(attribute)}");
        }
        var value = "";
        match (arguments[0]) {
            SymbolRef(id, _) => {
                value = id;
            }
            else => {
                return _fail(
                    $"OS predicate value must be a symbol (Windows, Mac, MacOS, Linux, Wasi, IOS, Android) in {attribute_text(attribute)}"
                );
            }
        }
        var host = target.os;
        if (host != "windows"
            and host != "macos"
            and host != "linux"
            and host != "wasi"
            and host != "ios"
            and host != "android") {
            return false;
        }
        match (value.lower()) {
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
                return _fail(
                    $"unknown OS value `{value}` (expected Windows, Mac, MacOS, Linux, Wasi, IOS, Android) in {attribute_text(attribute)}"
                );
            }
        }
    }

    _arch_matches(arguments: Expression[]): bool {
        if (arguments.count != 1) {
            return _fail($"Arch predicate takes exactly one value in {attribute_text(attribute)}");
        }
        var value = "";
        match (arguments[0]) {
            SymbolRef(id, _) => {
                value = id;
            }
            else => {
                return _fail(
                    $"Arch predicate value must be a symbol (x64, aarch64, wasm32) in {attribute_text(attribute)}"
                );
            }
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
        var lower = value.lower();
        if (lower == host) {
            return true;
        }
        if (lower == "x64" or lower == "aarch64" or lower == "wasm32") {
            return false;
        }
        return _fail($"unknown Arch value `{value}` (expected x64, aarch64, wasm32) in {attribute_text(attribute)}");
    }
}

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
                # Only a well-formed comparison: a malformed one is an
                # error.
                bool left = _is_build_option_call(lhs)
                    and !_is_build_option_call(rhs)
                    and comparison_literal(rhs).is_value();
                bool right = _is_build_option_call(rhs)
                    and !_is_build_option_call(lhs)
                    and comparison_literal(lhs).is_value();
                if (!left and !right) {
                    return;
                }
                match (left ? lhs : rhs) {
                    FunctionCall(function, arguments, span) => {
                        match (function) {
                            SymbolRef(id, _) => {
                                var name = evaluator._build_option_name(id, arguments, span);
                                if (name.is_value() and !evaluator.target.build_options.contains(name.value())) {
                                    out.append(UndefinedOption(name.value(), span));
                                }
                            }
                            else => {}
                        }
                    }
                    else => {}
                }
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
# `0x`, with an optional sign.
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
    long value = 0;
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
        value = value * radix as long + digit;
        i += 1;
    }
    return Optional<long>.Value(negative ? -value : value);
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
