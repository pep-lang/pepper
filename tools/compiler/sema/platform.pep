## Platform selection over the model: `apply_platform_filters`. Drops the
## declarations, members and attributed blocks whose `Target(...)`
## attributes do not hold on the compile target, after reporting a malformed
## attribute anywhere, kept or not, and a malformed `[Test]`.

import compiler.ast;
import [Diagnostic, Location] from compiler.diagnostic;
import [demangle_name, Target] from compiler.link;
import [Loc] from "loc";
import [Block, FunctionDef, Module] from "model";
import [display_name] from "names";

## The attribute that marks a unit test: `[Test]`.
const _TEST_ATTRIBUTE = "Test";

## The attribute that keeps a function out of line (#640): a function rarely
## called, such as a slow path, gets LLVM's `cold` and `noinline`
## (`Generator.mark_cold`), so its callers' fast paths stay small.
export const COLD_ATTRIBUTE = "Cold";

## The attribute that makes a `[Test]` pass only when it panics.
const _SHOULD_PANIC_ATTRIBUTE = "ShouldPanic";

## Drops what the target does not select from `module`, as
## `apply_platform_filters` does.
##
## @param module the model, changed in place
## @param target the compile target
## @returns the first error: a malformed test or platform attribute
export apply_platform_filters(module: Module, target: Target): Diagnostic? {
    var error = _check_tests(module);
    if (error.is_value()) {
        return error;
    }
    error = _check_cold(module);
    if (error.is_value()) {
        return error;
    }
    # Every top-level predicate first, so a bad attribute in dropped code is
    # still reported.
    for (var f in module.functions) {
        error = _validate(target, f.attributes, f.loc.file);
        if (error.is_value()) {
            return error;
        }
    }
    for (var s in module.structs) {
        error = _validate(target, s.attributes, s.loc.file);
        if (error.is_value()) {
            return error;
        }
    }
    for (var t in module.traits) {
        error = _validate(target, t.attributes, t.loc.file);
        if (error.is_value()) {
            return error;
        }
    }
    for (var e in module.extensions) {
        error = _validate(target, e.attributes, e.loc.file);
        if (error.is_value()) {
            return error;
        }
    }
    for (var x in module.externs) {
        error = _validate(target, x.attributes, x.loc.file);
        if (error.is_value()) {
            return error;
        }
    }
    for (var g in module.globals) {
        error = _validate(target, g.attributes, g.loc.file);
        if (error.is_value()) {
            return error;
        }
    }
    for (var a in module.type_aliases) {
        error = _validate(target, a.attributes, a.loc.file);
        if (error.is_value()) {
            return error;
        }
    }
    for (var e in module.enums) {
        error = _validate(target, e.attributes, e.loc.file);
        if (error.is_value()) {
            return error;
        }
        for (var c in e.cases) {
            error = _validate(target, c.attributes, e.loc.file);
            if (error.is_value()) {
                return error;
            }
        }
    }
    # Top-level functions: bodies are walked whether or not the function
    # survives, so a malformed predicate inside is reported on every host.
    var kept = Array<FunctionDef>();
    for (var f in module.functions) {
        error = _filter_body(target, f, f.loc.file);
        if (error.is_value()) {
            return error;
        }
        if (_keeps(target, f.attributes)) {
            kept.append(f);
        }
    }
    module.functions = kept;
    # Members of declarations about to be dropped too, so a misspelled
    # predicate in dropped code is reported on every host.
    for (var s in module.structs) {
        var file = s.loc.file;
        for (var m in s.method_members) {
            error = _filter_function(target, m, file);
            if (error.is_value()) {
                return error;
            }
        }
        for (var constructor in s.constructors) {
            error = _filter_function(target, constructor, file);
            if (error.is_value()) {
                return error;
            }
        }
        for (var special in [s.destructor, s.acquire, s.release]) {
            error = _filter_function(target, special, file);
            if (error.is_value()) {
                return error;
            }
        }
    }
    for (var t in module.traits) {
        for (var m in t.methods) {
            error = _filter_function(target, m, t.loc.file);
            if (error.is_value()) {
                return error;
            }
        }
    }
    for (var e in module.extensions) {
        for (var m in e.methods) {
            error = _filter_function(target, m, e.loc.file);
            if (error.is_value()) {
                return error;
            }
        }
    }
    _retain(module.structs, (s) => _keeps(target, s.attributes));
    _retain(module.traits, (t) => _keeps(target, t.attributes));
    _retain(module.extensions, (e) => _keeps(target, e.attributes));
    _retain(module.externs, (x) => _keeps(target, x.attributes));
    # Aliases resolve "last definition wins", so a per-platform pair must
    # lose its dropped half here.
    _retain(module.globals, (g) => _keeps(target, g.attributes));
    _retain(module.type_aliases, (a) => _keeps(target, a.attributes));
    # A dropped case keeps the others' values: the builder numbered them.
    _retain(module.enums, (e) => _keeps(target, e.attributes));
    for (var e in module.enums) {
        _retain(e.cases, (c) => _keeps(target, c.attributes));
    }
    # Members of surviving declarations.
    for (var s in module.structs) {
        _retain(s.method_members, (m) => _keeps(target, m.attributes));
        # A reference enum's case goes with its static method, which carries
        # the case's attributes; its fields stay, holding their defaults.
        if (s.enum_cases.is_value()) {
            _retain(s.enum_cases.value(), (c) => _keeps(target, c.attributes));
        }
    }
    for (var t in module.traits) {
        _retain(t.methods, (m) => _keeps(target, m.attributes));
    }
    for (var e in module.extensions) {
        _retain(e.methods, (m) => _keeps(target, m.attributes));
    }
    return Optional<Diagnostic>.Empty;
}

## Keeps the items `keep` holds for, in order.
_retain<T>(items: T[], keep: (T) => bool) {
    ulong out = 0;
    ulong i = 0;
    while (i < items.count) {
        if (keep(items[i])) {
            if (out != i) {
                items[out] = items[i];
            }
            out += 1;
        }
        i += 1;
    }
    items.truncate(out);
}

## Whether `attributes` keep their node: every one holds, and none could
## not be evaluated.
_keeps(target: Target, attributes: ast.Attribute[]): bool {
    var kept = target.keep(attributes);
    return kept.is_ok() and kept.value();
}

## The first attribute of `attributes` that cannot be evaluated, as an
## error in `file`; every one is evaluated, a false one included.
_validate(target: Target, attributes: ast.Attribute[], file: uint): Diagnostic? {
    for (var attribute in attributes) {
        var invalid = target.check(attribute);
        if (invalid.is_value()) {
            var (message, span) = invalid.value();
            return Optional<Diagnostic>.Value(Diagnostic.error(message).at(Location(file as ulong, span)));
        }
    }
    return Optional<Diagnostic>.Empty;
}

## Validates `function`'s own attributes, then filters its body.
## Synthesized members have no location; their errors point into `file`,
## their owner's.
_filter_function(target: Target, function: FunctionDef, file: uint): Diagnostic? {
    var own = function.loc.is_none() ? file : function.loc.file;
    var error = _validate(target, function.attributes, own);
    if (error.is_value()) {
        return error;
    }
    return _filter_body(target, function, own);
}

## Filters `function`'s body, if it has one.
_filter_body(target: Target, function: FunctionDef, file: uint): Diagnostic? {
    if (function.body.is_value()) {
        return _filter_block(target, function.body.value(), file);
    }
    return Optional<Diagnostic>.Empty;
}

## A block `_filter_block` walks: the next item, and when it is an
## attributed block inside another, whether to drop it from there.
struct _Frame {
    var block: Block;
    var next: ulong = 0;
    var parent: _Frame?;
    var drop: bool = false;

    construct(block: Block, parent: _Frame?, drop: bool) {
        this.block = block;
        this.parent = parent;
        this.drop = drop;
    }
}

## Drops the attributed blocks in `block` that do not match the target,
## nested ones included: inside blocks, branches and loops. A dropped
## block's contents are checked too.
_filter_block(target: Target, block: Block, file: uint): Diagnostic? {
    var stack = [_Frame(block, Optional<_Frame>.Empty, false)];
    while (stack.count > 0) {
        var frame = stack.last();
        if (frame.next >= frame.block.items.count) {
            stack.pop();
            if (frame.parent.is_value()) {
                var parent = frame.parent.value();
                if (frame.drop) {
                    parent.block.items.remove_at(parent.next);
                } else {
                    parent.next += 1;
                }
            }
            continue;
        }
        match (frame.block.items[frame.next]) {
            Block(inner) => {
                var error = _validate(target, inner.attributes, file);
                if (error.is_value()) {
                    return error;
                }
                var kept = target.keep(inner.attributes);
                if (kept.is_err()) {
                    return Optional<Diagnostic>.Value(Diagnostic.error(kept.error()));
                }
                # The parent moves on (or drops it) once its contents are
                # walked.
                stack.append(_Frame(inner, Optional<_Frame>.Value(frame), !kept.value()));
            }
            Branch(branch) => {
                frame.next += 1;
                if (branch.else_block.is_value()) {
                    stack.append(_Frame(branch.else_block.value(), Optional<_Frame>.Empty, false));
                }
                stack.append(_Frame(branch.if_block, Optional<_Frame>.Empty, false));
            }
            While(loop) => {
                frame.next += 1;
                stack.append(_Frame(loop.block, Optional<_Frame>.Empty, false));
            }
            else => {
                frame.next += 1;
            }
        }
    }
    return Optional<Diagnostic>.Empty;
}

## Where an attribute's name is written: `Test` in `[Test]` and
## `ShouldPanic` in `[ShouldPanic("m")]`.
_attribute_name_location(attribute: ast.Attribute, file: uint): Location {
    var span = attribute.body.span();
    match (attribute.body) {
        FunctionCall(function, _, _) => {
            span = function.span();
        }
        else => {}
    }
    return Location(file as ulong, span);
}

## The first `[Cold]` with arguments, or on anything but a function, method
## or constructor.
_check_cold(module: Module): Diagnostic? {
    var functions = Array<FunctionDef>();
    functions.append_all(module.functions);
    for (var s in module.structs) {
        functions.append_all(s.method_members);
        functions.append_all(s.constructors);
        functions.append_all(s.generic_methods);
    }
    for (var t in module.traits) {
        functions.append_all(t.methods);
    }
    for (var e in module.extensions) {
        functions.append_all(e.methods);
    }
    for (var f in functions) {
        for (var attribute in f.attributes) {
            if (attribute.name() != COLD_ATTRIBUTE) {
                continue;
            }
            match (attribute.body) {
                SymbolRef(_, _) => {}
                else => {
                    return Optional<Diagnostic>.Value(
                        Diagnostic.error(
                            "'Cold' takes no arguments"
                        ).at(Location(f.loc.file as ulong, attribute.body.span()))
                    );
                }
            }
        }
    }
    for (var s in module.structs) {
        var misplaced = Array<(ast.Attribute, Loc)>();
        for (var attribute in s.attributes) {
            misplaced.append((attribute, s.loc));
        }
        for (var field in s.field_members) {
            for (var attribute in field.attributes) {
                misplaced.append((attribute, field.loc));
            }
        }
        for (var (attribute, loc) in misplaced) {
            if (attribute.name() == COLD_ATTRIBUTE) {
                return Optional<Diagnostic>.Value(
                    Diagnostic.error(
                        "'Cold' applies only to a function, method or constructor"
                    ).at(_attribute_name_location(attribute, loc.file))
                );
            }
        }
    }
    return Optional<Diagnostic>.Empty;
}

## The first `[Test]` that is not on a free function taking and returning
## nothing, or `[ShouldPanic]` without `[Test]`. Every build checks, before
## a build without `--test` drops the tests.
_check_tests(module: Module): Diagnostic? {
    for (var f in module.functions) {
        var file = f.loc.file;
        bool test = ast.has_attribute(f.attributes, _TEST_ATTRIBUTE);
        for (var attribute in f.attributes) {
            if (attribute.name() == _SHOULD_PANIC_ATTRIBUTE) {
                if (!test) {
                    return Optional<Diagnostic>.Value(
                        Diagnostic.error(
                            "'ShouldPanic' applies only to a '[Test]' function"
                        ).at(_attribute_name_location(attribute, file))
                    );
                }
                break;
            }
        }
        if (!test) {
            continue;
        }
        var name = demangle_name(f.name);
        if (f.parameters.count > 0) {
            return Optional<Diagnostic>.Value(
                Diagnostic.error($"test '{name}' must take no parameters").at(_at(f.parameters[0].loc))
            );
        }
        if (f.generic_params.count > 0) {
            return Optional<Diagnostic>.Value(Diagnostic.error($"test '{name}' cannot be generic").at(_at(f.loc)));
        }
        # A test declares no return type (`__auto` until bodies are
        # inferred) or `void`.
        if (!((f.ty.name == "void" or f.ty.name == "__auto") and f.ty.sub_types.count == 0)) {
            return Optional<Diagnostic>.Value(
                Diagnostic.error(
                    $"test '{name}' must return nothing, not '{display_name(f.ty.display())}'"
                ).at(_at(f.loc))
            );
        }
    }
    var members = Array<FunctionDef>();
    for (var s in module.structs) {
        members.append_all(s.method_members);
        members.append_all(s.constructors);
    }
    for (var t in module.traits) {
        members.append_all(t.methods);
    }
    for (var e in module.extensions) {
        members.append_all(e.methods);
    }
    for (var m in members) {
        for (var attribute in m.attributes) {
            var name = attribute.name();
            if (name == _TEST_ATTRIBUTE or name == _SHOULD_PANIC_ATTRIBUTE) {
                return Optional<Diagnostic>.Value(
                    Diagnostic.error(
                        $"'{name}' applies only to a free function"
                    ).at(_attribute_name_location(attribute, m.loc.file))
                );
            }
        }
    }
    return Optional<Diagnostic>.Empty;
}

## `loc` as a diagnostic's location.
_at(loc: Loc): Location {
    return Location(loc.file as ulong, loc.span);
}
