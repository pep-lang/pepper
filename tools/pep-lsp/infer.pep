# Typing what the sema model leaves untyped, from the syntax alone: the
# body of a generic that nothing instantiates (sema checks only
# specializations), the names a `match` arm or an `is` test binds, and the
# members such code reaches. Hover and go-to-definition ask this when the
# model has no answer.
#
# A name's type comes from its declaration, else from sema's inferred type
# for it, else from its initializer: a constructor or call's return type, a
# field's type, a ternary's arm, an element of an array. A member is found
# in the declarations of every program file (the struct or enum, its
# extensions, the traits those add), with the owner's type arguments bound
# to the declaration's generic parameters.
#
# Expressions nest as deep as the parser allows, so the walk over a body
# (`SyntaxWalk`) keeps an explicit stack, and typing gives up past
# `_INFER_MAX_DEPTH` steps.

import compiler.ast;
import [
    Block,
    Declaration,
    DestructureBinding,
    EnumCase,
    Expression,
    FunctionDecl,
    GenericParam,
    Module,
    Pattern,
    PropertyDecl,
    Span,
    Statement,
    StructDecl,
    TypeName,
    VariableDecl
] from compiler.ast;
import compiler.link;
import compiler.sema;
import "scope";
import "symbols";

# How many steps typing one expression may take: names whose initializers
# name others, and members of members.
const _INFER_MAX_DEPTH: ulong = 48;

# Where another file's initializer is typed from: past every local.
const _INFER_ELSEWHERE: ulong = 0xFFFFFFFFFFFFFFFF;

# ── Types ────────────────────────────────────────────────────────────────

## A type as the typer tracks it: a name as written (no namespace or
## module qualifier) and its type arguments. `T[]` is `Array<T>` and `T?`
## is `Optional<T>`.
export struct Ty {
    ## The name.
    var name: String = "";
    ## The type arguments.
    var args: Ty[] = Array<Ty>();
    ## A tuple's element labels (`(line: int, column: int)`), else empty.
    var labels: String[] = Array<String>();

    ## Creates the type `name`, with no arguments.
    ##
    ## @param name the name
    construct(name: String) {
        this.name = name;
    }

    ## Returns the type `name<args>`.
    ##
    ## @param name the name
    ## @param args the type arguments
    ## @returns the type
    static of(name: String, args: Ty[]): Ty {
        var out = Ty(name);
        out.args = args;
        return out;
    }

    ## Returns `ty` as the typer spells it.
    ##
    ## @param ty the type as written
    ## @returns the type
    static from_ast(ty: TypeName): Ty {
        var name = ty.name;
        ulong arrays = 0;
        while (name.ends_with("[]")) {
            name = name.substr_bytes(0, name.size - 2);
            arrays += 1;
        }
        var out = Ty(_infer_plain(name));
        for (var argument in ty.generic_types) {
            out.args.append(Ty.from_ast(argument));
        }
        out.labels = ty.labels.clone();
        while (arrays > 0) {
            out = Ty.of("Array", [out]);
            arrays -= 1;
        }
        return out;
    }

    ## Returns a type rendered as text (a symbol's type, or sema's):
    ## `Box<int>`, `u8[]`, `int?`, `(int, String)`, `(T) => bool`.
    ##
    ## @param text the rendered type
    ## @returns the type; empty when `text` is not one
    static parse(text: String): Ty? {
        var parser = _TypeParser(text);
        var ty = parser.parse_type(0);
        if (ty.is_empty()) {
            return ty;
        }
        parser.space();
        if (parser.at != text.size) {
            return Optional<Ty>.Empty;
        }
        return ty;
    }

    ## Returns whether the type is unknown: inferred, `unknown` or empty.
    ##
    ## @returns true when unknown
    is_auto(): bool {
        return name == ast.AUTO_TYPE or name == "unknown" or name.is_empty;
    }

    ## Returns the type with each type parameter in `bindings` replaced by
    ## its argument.
    ##
    ## @param bindings type parameters and their arguments
    ## @returns the substituted type
    substitute(bindings: Array<(String, Ty)>): Ty {
        if (args.count == 0) {
            for (var (parameter, bound) in bindings) {
                if (parameter == name) {
                    return bound;
                }
            }
        }
        var out = Ty(name);
        for (var argument in args) {
            out.args.append(argument.substitute(bindings));
        }
        out.labels = labels;
        return out;
    }

    ## Returns the type as source writes it: `int[]`, `(line: int, column:
    ## int)`, `(T) => bool`, `Box<int>`.
    ##
    ## @returns the text
    to_string(): String {
        if (name == "Array" and args.count == 1) {
            return args[0].to_string() + "[]";
        }
        if (name == ast.TUPLE_TYPE) {
            var elements = Array<String>();
            ulong i = 0;
            while (i < args.count) {
                var element = args[i].to_string();
                if (i < labels.count and !labels[i].is_empty) {
                    element = labels[i] + ": " + element;
                }
                elements.append(element);
                i += 1;
            }
            return $"({", ".join(elements)})";
        }
        bool function = name == ast.FUNCTION_TYPE or name == ast.SHARED_FUNCTION_TYPE;
        if (function and args.count > 0) {
            var shared = name == ast.SHARED_FUNCTION_TYPE ? "shared " : "";
            var parameters = Array<String>();
            ulong i = 1;
            while (i < args.count) {
                parameters.append(args[i].to_string());
                i += 1;
            }
            return $"{shared}({", ".join(parameters)}) => {args[0].to_string()}";
        }
        if (args.count == 0) {
            return name;
        }
        return $"{name}<{_infer_listed(args)}>";
    }
}

# `types` rendered and separated by commas.
_infer_listed(types: Ty[]): String {
    var parts = Array<String>();
    for (var t in types) {
        parts.append(t.to_string());
    }
    return ", ".join(parts);
}

# A declared name as the source spells it: no namespace (`x@io/file`), no
# overload number, no module qualifier (`io.IoResult`).
_infer_plain(name: String): String {
    var demangled = link.demangle_name(name);
    var dot = demangled.rfind(".");
    if (dot < 0) {
        return demangled;
    }
    return demangled.substr_bytes(dot as ulong + 1, demangled.size - dot as ulong - 1);
}

# A parser for rendered types; nesting past `_INFER_MAX_DEPTH` fails.
struct _TypeParser {
    var text: String;
    var at: ulong;

    construct(text: String) {
        this.text = text;
        this.at = 0;
    }

    space() {
        while (at < text.size) {
            var b = text.byte_at(at);
            if (b != ' ' and b != '\t' and b != '\n' and b != '\r') {
                return;
            }
            at += 1;
        }
    }

    eat(token: String): bool {
        space();
        if (text.size - at < token.size or text.substr_bytes(at, token.size) != token) {
            return false;
        }
        at += token.size;
        return true;
    }

    parse_name(): String? {
        space();
        var start = at;
        while (at < text.size and _infer_is_name_part(text.byte_at(at))) {
            at += 1;
        }
        if (at == start) {
            return Optional<String>.Empty;
        }
        return Optional<String>.Value(text.substr_bytes(start, at - start));
    }

    # Types separated by `,` up to `close`, and their labels (`line:`),
    # empty when none has one.
    parse_list(close: String, depth: ulong): (Ty[], String[])? {
        var none = Optional<(Ty[], String[])>.Empty;
        var out = Array<Ty>();
        var labels = Array<String>();
        if (eat(close)) {
            return Optional<(Ty[], String[])>.Value((out, labels));
        }
        while (true) {
            var save = at;
            var label = parse_name();
            if (label.is_value() and eat(":")) {
                labels.append(label.value());
            } else {
                at = save;
                labels.append("");
            }
            var element = parse_type(depth + 1);
            if (element.is_empty()) {
                return none;
            }
            out.append(element.value());
            if (eat(close)) {
                if (_infer_all_empty(labels)) {
                    labels.clear();
                }
                return Optional<(Ty[], String[])>.Value((out, labels));
            }
            if (!eat(",")) {
                return none;
            }
        }
        return none;
    }

    parse_type(depth: ulong): Ty? {
        var none = Optional<Ty>.Empty;
        if (depth > _INFER_MAX_DEPTH) {
            return none;
        }
        var shared = eat("shared ");
        var out = Ty("");
        if (eat("(")) {
            var listed = parse_list(")", depth);
            if (listed.is_empty()) {
                return none;
            }
            var (elements, labels) = listed.value();
            if (eat("=>")) {
                var result = parse_type(depth + 1);
                if (result.is_empty()) {
                    return none;
                }
                var all = [result.value()];
                all.append_all(elements);
                out = Ty.of(shared ? ast.SHARED_FUNCTION_TYPE : ast.FUNCTION_TYPE, all);
            } else {
                out = Ty.of(ast.TUPLE_TYPE, elements);
                out.labels = labels;
            }
        } else {
            var name = parse_name();
            if (name.is_empty()) {
                return none;
            }
            var args = Array<Ty>();
            if (eat("<")) {
                var listed = parse_list(">", depth);
                if (listed.is_empty()) {
                    return none;
                }
                args = listed.value().0;
            }
            out = Ty.of(_infer_plain(name.value()), args);
        }
        while (true) {
            if (eat("[]")) {
                out = Ty.of("Array", [out]);
            } else if (eat("?")) {
                out = Ty.of("Optional", [out]);
            } else if (eat("*")) {
                out = Ty.of("__ptr", [out]);
            } else {
                return Optional<Ty>.Value(out);
            }
        }
        return none;
    }
}

# Whether `b` may be part of a rendered type's name.
_infer_is_name_part(b: u8): bool {
    if ((b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9')) {
        return true;
    }
    return b == '_' or b == '.' or b == '@' or b == '/' or b == '#' or b == '$';
}

# Whether every label is empty.
_infer_all_empty(labels: String[]): bool {
    for (var label in labels) {
        if (!label.is_empty) {
            return false;
        }
    }
    return true;
}

# Generic parameters bound to type arguments, in order.
_infer_bind(params: GenericParam[], args: Ty[]): Array<(String, Ty)> {
    var out = Array<(String, Ty)>();
    ulong i = 0;
    while (i < params.count and i < args.count) {
        out.append((params[i].name, args[i]));
        i += 1;
    }
    return out;
}

## The base name and type arguments of a member as written: `copy<T>` is
## `copy` with `T`.
##
## @param name the member as written
## @returns its base name and type arguments
export split_generics(name: String): (String, Ty[]) {
    var angle = name.find("<");
    if (angle < 0) {
        return (name, Array<Ty>());
    }
    var base = name.substr_bytes(0, angle as ulong);
    var rest = name.substr_bytes(angle as ulong + 1, name.size - angle as ulong - 1);
    var parsed = Ty.parse("_<" + rest);
    if (parsed is Value(t)) {
        return (base, t.args);
    }
    return (base, Array<Ty>());
}

# Whether two type names are the same type: as written, or the same number
# type under two names (`u8` and `byte`).
_infer_same_type(declared: String, name: String): bool {
    var plain = _infer_plain(declared);
    if (plain == name) {
        return true;
    }
    var key = _infer_number_key(plain);
    return key.is_value() and key == _infer_number_key(name);
}

# A number type's canonical spelling (`i32` for `int`), as sema files value
# types' methods; empty for any other type.
_infer_number_key(name: String): String? {
    match (name) {
        "int" => {
            return Optional<String>.Value("i32");
        }
        "uint" => {
            return Optional<String>.Value("u32");
        }
        "long" => {
            return Optional<String>.Value("i64");
        }
        "ulong" => {
            return Optional<String>.Value("u64");
        }
        "short" => {
            return Optional<String>.Value("i16");
        }
        "ushort" => {
            return Optional<String>.Value("u16");
        }
        "char" => {
            return Optional<String>.Value("i8");
        }
        "byte" => {
            return Optional<String>.Value("u8");
        }
        "float" => {
            return Optional<String>.Value("f32");
        }
        "double" => {
            return Optional<String>.Value("f64");
        }
        "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "f32", "f64", "bool" => {
            return Optional<String>.Value(name);
        }
        else => {
            return Optional<String>.Empty;
        }
    }
}

# Whether two spans are the same.
_infer_same_span(a: Span, b: Span): bool {
    return a.start == b.start and a.end == b.end;
}

# ── Walking a module ─────────────────────────────────────────────────────

## What a `SyntaxWalk` visits.
export enum SyntaxItem {
    ## A statement.
    Statement(statement: Statement),
    ## An expression.
    Expression(expression: Expression),
    ## The patterns of one `match` arm or `is` test, and the value matched.
    Patterns(patterns: Pattern[], subject: Expression),
    ## A declared variable: a local, a parameter (closures' included), a
    ## field, a module-scope variable, or a `for` or `with` binding.
    Variable(variable: VariableDecl),
}

# What the walk has still to visit.
enum _WalkNode {
    Block(block: Block),
    Statement(statement: Statement),
    Expression(expression: Expression),
    Function(function: FunctionDecl),
    Variable(variable: VariableDecl),
}

## Every statement, expression, pattern and variable of a module or a
## block, one at a time. It keeps an explicit stack, so no nesting depth
## overflows it.
export struct SyntaxWalk {
    var _stack: _WalkNode[] = Array<_WalkNode>();
    # Patterns visited while expanding a node, returned before the stack's
    # next node.
    var _pending: SyntaxItem[] = Array<SyntaxItem>();

    ## Creates a walk over nothing.
    construct() {}

    ## Returns a walk over every declaration of `module`.
    ##
    ## @param module the syntax tree
    ## @returns the walk
    static of_module(module: Module): SyntaxWalk {
        var out = SyntaxWalk();
        for (var d in module.declarations) {
            out._push_declaration(d);
        }
        return out;
    }

    ## Returns a walk over `block`.
    ##
    ## @param block the block
    ## @returns the walk
    static of_block(block: Block): SyntaxWalk {
        var out = SyntaxWalk();
        out._stack.append(_WalkNode.Block(block));
        return out;
    }

    _push_declaration(d: Declaration) {
        match (d) {
            Variable(v) => {
                _stack.append(_WalkNode.Variable(v));
            }
            Function(f) => {
                _stack.append(_WalkNode.Function(f));
            }
            Struct(s) => {
                for (var field in s.fields) {
                    _stack.append(_WalkNode.Variable(field));
                }
                for (var c in s.constructors) {
                    _stack.append(_WalkNode.Function(c));
                }
                for (var m in s.methods) {
                    _stack.append(_WalkNode.Function(m));
                }
                _push_accessors(s.properties);
                for (var property in s.properties) {
                    if (property.default_value is Value(e)) {
                        _stack.append(_WalkNode.Expression(e));
                    }
                }
                if (s.destructor is Value(destructor)) {
                    _stack.append(_WalkNode.Block(destructor));
                }
                if (s.enumeration is Value(body)) {
                    for (var case in body.cases) {
                        if (case.payload is Value(payload)) {
                            for (var v in payload) {
                                _stack.append(_WalkNode.Variable(v));
                            }
                        }
                        if (case.value is Value(e)) {
                            _stack.append(_WalkNode.Expression(e));
                        }
                    }
                }
            }
            Trait(t) => {
                for (var m in t.methods) {
                    _stack.append(_WalkNode.Function(m));
                }
            }
            Extend(e) => {
                for (var m in e.methods) {
                    _stack.append(_WalkNode.Function(m));
                }
                _push_accessors(e.properties);
            }
            TypeAlias(_) => {}
            Static(s) => {
                _stack.append(_WalkNode.Block(s.block));
            }
        }
    }

    _push_accessors(properties: PropertyDecl[]) {
        for (var property in properties) {
            if (property.getter is Value(getter)) {
                _stack.append(_WalkNode.Function(getter.function));
            }
            if (property.setter is Value(setter)) {
                _stack.append(_WalkNode.Function(setter.function));
            }
        }
    }

    ## Returns the next item.
    ##
    ## @returns the item; empty when the walk is done
    next(): SyntaxItem? {
        while (true) {
            if (_pending.count > 0) {
                return Optional<SyntaxItem>.Value(_pending.remove_at(0));
            }
            if (_stack.count == 0) {
                return Optional<SyntaxItem>.Empty;
            }
            var node = _stack.pop();
            match (node) {
                Function(f) => {
                    for (var p in f.parameters) {
                        _stack.append(_WalkNode.Variable(p));
                    }
                    if (f.body is Value(body)) {
                        _stack.append(_WalkNode.Block(body));
                    }
                }
                Variable(v) => {
                    if (v.default_value is Value(e)) {
                        _stack.append(_WalkNode.Expression(e));
                    }
                    return Optional<SyntaxItem>.Value(SyntaxItem.Variable(v));
                }
                Block(b) => {
                    for (var s in b.statements) {
                        _stack.append(_WalkNode.Statement(s));
                    }
                }
                Statement(s) => {
                    _expand_statement(s);
                    return Optional<SyntaxItem>.Value(SyntaxItem.Statement(s));
                }
                Expression(e) => {
                    _expand_expression(e);
                    return Optional<SyntaxItem>.Value(SyntaxItem.Expression(e));
                }
            }
        }
        return Optional<SyntaxItem>.Empty;
    }

    _push_expression(e: Expression) {
        _stack.append(_WalkNode.Expression(e));
    }

    _push_block(b: Block) {
        _stack.append(_WalkNode.Block(b));
    }

    _expand_statement(s: Statement) {
        match (s) {
            Expression(e) => {
                _push_expression(e);
            }
            Block(b) => {
                _push_block(b);
            }
            Declaration(d) => {
                if (d is Variable(v)) {
                    _stack.append(_WalkNode.Variable(v));
                } else if (d is Function(f)) {
                    _stack.append(_WalkNode.Function(f));
                }
            }
            Branch(condition, if_block, else_block, _) => {
                _push_expression(condition);
                _push_block(if_block);
                if (else_block is Value(otherwise)) {
                    _push_block(otherwise);
                }
            }
            While(condition, block, _) => {
                _push_expression(condition);
                _push_block(block);
            }
            For(binding, _, iterable, block, _) => {
                _stack.append(_WalkNode.Variable(binding));
                _push_expression(iterable);
                _push_block(block);
            }
            With(binding, scope, block, else_block, _) => {
                if (binding is Value(b)) {
                    _stack.append(_WalkNode.Variable(b));
                }
                _push_expression(scope);
                _push_block(block);
                if (else_block is Value(otherwise)) {
                    _push_block(otherwise);
                }
            }
            Return(value, _) => {
                if (value is Value(e)) {
                    _push_expression(e);
                }
            }
            Static(block) => {
                _push_block(block.block);
            }
            Destructure(_, value, _, _) => {
                _push_expression(value);
            }
            Match(m) => {
                _push_expression(m.value);
                for (var arm in m.arms) {
                    _pending.append(SyntaxItem.Patterns(arm.patterns, m.value));
                    if (arm.guard is Value(guard)) {
                        _push_expression(guard);
                    }
                    _push_block(arm.body);
                }
                if (m.else_block is Value(otherwise)) {
                    _push_block(otherwise);
                }
            }
            else => {}
        }
    }

    _expand_expression(e: Expression) {
        match (e) {
            Closure(c) => {
                for (var p in c.parameters) {
                    _stack.append(_WalkNode.Variable(p));
                }
                _push_block(c.body);
            }
            Match(m) => {
                _push_expression(m.value);
                for (var arm in m.arms) {
                    _pending.append(SyntaxItem.Patterns(arm.patterns, m.value));
                    if (arm.guard is Value(guard)) {
                        _push_expression(guard);
                    }
                    _push_expression(arm.value);
                }
                if (m.else_value is Value(otherwise)) {
                    _push_expression(otherwise);
                }
            }
            Is(value, pattern, _, _) => {
                _pending.append(SyntaxItem.Patterns([pattern], value));
                _push_expression(value);
            }
            else => {
                for (var child in children(e)) {
                    _push_expression(child);
                }
            }
        }
    }
}

# Each pattern of `patterns` and every pattern nested in them.
_infer_all_patterns(patterns: Pattern[]): Pattern[] {
    var out = Array<Pattern>();
    var stack = patterns.clone();
    while (stack.count > 0) {
        var p = stack.pop();
        out.append(p);
        if (p.elements is Value(elements)) {
            stack.append_all(elements);
        }
        if (p.bindings is Value(bindings)) {
            stack.append_all(bindings);
        }
    }
    return out;
}

# Whether destructuring `bindings` names a leaf at `span`.
_infer_declares(bindings: DestructureBinding[], span: Span): bool {
    var stack = bindings.clone();
    while (stack.count > 0) {
        var b = stack.pop();
        if (b.nested.count > 0) {
            stack.append_all(b.nested);
        } else if (_infer_same_span(b.name_span, span)) {
            return true;
        }
    }
    return false;
}

# One level of a destructuring pattern, and the type of the value it takes
# apart.
struct _DestructureLevel {
    var bindings: DestructureBinding[];
    var value: Ty?;

    construct(bindings: DestructureBinding[], value: Ty?) {
        this.bindings = bindings;
        this.value = value;
    }
}

# The `i`th element type of `value` when it is a tuple.
_infer_element_of(value: Ty?, i: ulong): Ty? {
    if (value is Value(t)) {
        if (t.name == ast.TUPLE_TYPE and i < t.args.count) {
            return Optional<Ty>.Value(t.args[i]);
        }
    }
    return Optional<Ty>.Empty;
}

# The type of the name destructuring binds at `span`, from a value of type
# `value`: its own type when written, else its element of the tuple.
_infer_destructured(bindings: DestructureBinding[], value: Ty?, span: Span): Ty? {
    var stack = [_DestructureLevel(bindings, value)];
    while (stack.count > 0) {
        var level = stack.pop();
        ulong i = 0;
        while (i < level.bindings.count) {
            var b = level.bindings[i];
            var element = _infer_element_of(level.value, i);
            i += 1;
            if (b.nested.count > 0) {
                stack.append(_DestructureLevel(b.nested, element));
                continue;
            }
            if (!_infer_same_span(b.name_span, span)) {
                continue;
            }
            if (b.type_name.name == ast.AUTO_TYPE) {
                return element;
            }
            return Optional<Ty>.Value(Ty.from_ast(b.type_name));
        }
    }
    return Optional<Ty>.Empty;
}

# ── Declarations ─────────────────────────────────────────────────────────

## A member of a type: what the declaration says, and where.
export enum MemberKind {
    ## A field.
    Field(variable: VariableDecl),
    ## A property.
    Property(property: PropertyDecl),
    ## A method.
    Method(function: FunctionDecl),
    ## An enum case.
    Case(case: EnumCase),
    ## A method every enum of plain values has (`name`, `from_value`): no
    ## file declares it, so it is placed at the enum's name.
    EnumMethod(owner: StructDecl, method: String),
    ## A labeled element of a tuple (`p.line`), with its type. The label
    ## has no declaration of its own.
    Element(label: String, ty: Ty),
}

## A member the typer found.
export struct TypedMember {
    ## The program file declaring it (0 is the document).
    var file: ulong;
    ## What it is.
    var kind: MemberKind;
    ## The name of the type it was found in, as written.
    var owner: String;
    ## The declaring type's generic parameters, bound to the owner's type
    ## arguments.
    var bindings: Array<(String, Ty)>;

    ## Creates one.
    ##
    ## @param file the program file declaring it
    ## @param kind what it is
    ## @param owner the type it was found in
    ## @param bindings the declaring type's parameters, bound
    construct(file: ulong, kind: MemberKind, owner: String, bindings: Array<(String, Ty)>) {
        this.file = file;
        this.kind = kind;
        this.owner = owner;
        this.bindings = bindings;
    }

    ## Returns the member's name where it is declared.
    ##
    ## @returns the span; empty for a tuple's element
    name_span(): Span? {
        match (kind) {
            Field(v) => {
                return Optional<Span>.Value(v.name_span);
            }
            Property(p) => {
                return Optional<Span>.Value(p.name_span);
            }
            Method(f) => {
                return Optional<Span>.Value(f.name_span);
            }
            Case(c) => {
                return Optional<Span>.Value(c.name_span);
            }
            EnumMethod(s, _) => {
                return Optional<Span>.Value(s.name_span);
            }
            Element(_, _) => {
                return Optional<Span>.Empty;
            }
        }
        return Optional<Span>.Empty;
    }

    ## Returns what hover shows: a field's type, a method's signature, or a
    ## case as `Shape.Circle(radius: int)`, with the owner's type arguments
    ## filled in.
    ##
    ## @returns the text
    describe(): String {
        match (kind) {
            Field(v) => {
                return Ty.from_ast(v.type_name).substitute(bindings).to_string();
            }
            Property(p) => {
                return Ty.from_ast(p.type_name).substitute(bindings).to_string();
            }
            Method(f) => {
                var parameters = Array<String>();
                for (var p in f.parameters) {
                    if (p.name != "this") {
                        parameters.append($"{p.name}: {Ty.from_ast(p.type_name).substitute(bindings).to_string()}");
                    }
                }
                var prefix = f.is_static ? "static " : "";
                var name = link.demangle_name(f.name);
                var generics = generics_string(f.generic_params);
                var result = Ty.from_ast(f.return_type).substitute(bindings).to_string();
                return $"{prefix}{name}{generics}({", ".join(parameters)}): {result}";
            }
            Case(c) => {
                if (c.payload is Value(payload)) {
                    var values = Array<String>();
                    for (var v in payload) {
                        values.append($"{v.name}: {Ty.from_ast(v.type_name).substitute(bindings).to_string()}");
                    }
                    return $"{owner}.{c.name}({", ".join(values)})";
                }
                return $"{owner}.{c.name}";
            }
            Element(_, ty) => {
                return ty.to_string();
            }
            EnumMethod(s, method) => {
                if (method != "from_value") {
                    return $"{method}(): String";
                }
                var representation = "int";
                if (s.enumeration is Value(body)) {
                    if (body.representation is Value(written)) {
                        representation = written.to_string();
                    }
                }
                return $"static from_value(value: {representation}): Result<{owner}>";
            }
        }
        return "";
    }
}

## What a pattern names at an offset.
export enum PatternHit {
    ## The case a pattern names.
    Case(found: TypedMember),
    ## A name the pattern binds, where it binds it, and its type when known.
    Binding(name: String, span: Span, ty: Ty?),
}

# The type of a member's value: a field's type, or an enum case's owner.
_infer_member_value(found: TypedMember, owner: Ty): Ty? {
    match (found.kind) {
        Field(v) => {
            return Optional<Ty>.Value(Ty.from_ast(v.type_name).substitute(found.bindings));
        }
        Property(p) => {
            return Optional<Ty>.Value(Ty.from_ast(p.type_name).substitute(found.bindings));
        }
        Element(_, ty) => {
            return Optional<Ty>.Value(ty);
        }
        Case(_) => {
            return Optional<Ty>.Value(owner);
        }
        else => {
            return Optional<Ty>.Empty;
        }
    }
}

# What a call of a value of function type `t` returns.
_infer_function_result(t: Ty): Ty? {
    if ((t.name == ast.FUNCTION_TYPE or t.name == ast.SHARED_FUNCTION_TYPE) and t.args.count > 0) {
        return Optional<Ty>.Value(t.args[0]);
    }
    return Optional<Ty>.Empty;
}

# Whether `d` declares a type: a struct, enum, trait or alias.
_infer_declares_type(d: Declaration): bool {
    match (d) {
        Struct(_) => {
            return true;
        }
        Trait(_) => {
            return true;
        }
        TypeAlias(_) => {
            return true;
        }
        else => {
            return false;
        }
    }
}

# Whether every case of `body` carries no values.
_infer_plain_values(body: ast.EnumBody): bool {
    for (var case in body.cases) {
        if (case.payload.is_value()) {
            return false;
        }
    }
    return true;
}

# The index of the parameter of closure `e` named at `span`.
_infer_closure_index(e: Expression, span: Span): ulong? {
    if (e is Closure(c)) {
        ulong i = 0;
        while (i < c.parameters.count) {
            if (_infer_same_span(c.parameters[i].name_span, span)) {
                return Optional<ulong>.Value(i);
            }
            i += 1;
        }
    }
    return Optional<ulong>.Empty;
}

# Where a local's type comes from.
enum _InferSite {
    Variable(variable: VariableDecl),
    For(iterable: Expression, span: Span),
    Bound(patterns: Pattern[], subject: Expression),
    Destructure(bindings: DestructureBinding[], value: Expression, span: Span),
    ForPattern(bindings: DestructureBinding[], iterable: Expression, span: Span),
    # A closure's parameter, by the function type the closure is given as:
    # what the callee's parameter or the variable says.
    ClosureParameter(index: ulong, ty: Ty),
}

# A pattern and the type of the value it matches, when known.
struct _PatternSubject {
    var pattern: Pattern;
    var subject: Ty?;

    construct(pattern: Pattern, subject: Ty?) {
        this.pattern = pattern;
        this.subject = subject;
    }
}

## Types names and finds members in the document (the fresh parse of
## `program.files[0]`) and the program's other files.
export struct Typer {
    ## The document's syntax tree.
    var document: Module;
    ## The program rooted at it, when it loaded.
    var program: link.Program?;
    ## The checked model, when the program passed sema.
    var model: sema.Module?;
    # The document, then each other program file, with its index.
    var _modules: Array<(ulong, Module)> = Array<(ulong, Module)>();
    # Every declaration of those, with its file.
    var _declarations: Array<(ulong, Declaration)> = Array<(ulong, Declaration)>();

    ## Creates a typer.
    ##
    ## @param document the document's syntax tree
    ## @param program the program rooted at it, if it loaded
    ## @param model the checked model, if the program passed sema
    construct(document: Module, program: link.Program?, model: sema.Module?) {
        this.document = document;
        this.program = program;
        this.model = model;
        ulong zero = 0;
        _modules.append((zero, document));
        if (program is Value(p)) {
            ulong file = 1;
            while (file < p.files.count) {
                _modules.append((file, p.files[file].module));
                file += 1;
            }
        }
        for (var (file, module) in _modules) {
            for (var d in module.declarations) {
                _declarations.append((file, d));
            }
        }
    }

    # Whether `name` names a type: a struct, enum, trait or alias some file
    # declares, a number type, or a type parameter in scope at `at`.
    _is_type(name: String, at: ulong): bool {
        if (sema.is_integral_name(name)) {
            return true;
        }
        for (var (_, d) in _declarations) {
            if (_infer_declares_type(d) and _infer_plain(d.declared_name()) == name) {
                return true;
            }
        }
        return generic_param_at(document, at, (p: GenericParam) => p.name == name).is_value();
    }

    # Whether `id` names a local or parameter in scope at `at`.
    _is_local(id: String, at: ulong): bool {
        for (var symbol in scope_locals(document, at)) {
            if (symbol.name == id) {
                return true;
            }
        }
        return false;
    }

    # `ty` with type aliases expanded.
    _resolve(ty: Ty): Ty {
        var out = ty;
        ulong steps = 0;
        while (steps < 8) {
            var alias = _alias_named(out.name);
            if (alias is Value(a)) {
                out = Ty.from_ast(a.target).substitute(_infer_bind(a.generic_params, out.args));
            } else {
                return out;
            }
            steps += 1;
        }
        return out;
    }

    _alias_named(name: String): ast.TypeAliasDecl? {
        for (var (_, d) in _declarations) {
            if (d is TypeAlias(a)) {
                if (_infer_plain(a.name) == name) {
                    return Optional<ast.TypeAliasDecl>.Value(a);
                }
            }
        }
        return Optional<ast.TypeAliasDecl>.Empty;
    }

    ## Returns the member `name` of a value (or, for a static call, the
    ## type) of type `owner`: a field, method or enum case its declaration,
    ## an extension of it, or a trait either adds declares.
    ##
    ## @param owner the owner's type
    ## @param name the member's name
    ## @param at where the owner is used: a type parameter there reaches
    ##   its bounds' members
    ## @returns the member; empty when none is found
    member(owner: Ty, name: String, at: ulong): TypedMember? {
        var resolved = _resolve(owner);
        # A weak reference or a pointer reaches its target's members.
        if ((resolved.name == "__weak" or resolved.name == "__ptr") and resolved.args.count == 1) {
            resolved = resolved.args[0];
        }
        # A tuple's labeled element.
        if (resolved.name == ast.TUPLE_TYPE) {
            var index = resolved.labels.find(name);
            if (index is Value(i)) {
                if (i >= resolved.args.count) {
                    return Optional<TypedMember>.Empty;
                }
                var kind = MemberKind.Element(name, resolved.args[i]);
                return Optional<TypedMember>.Value(TypedMember(0, kind, resolved.to_string(), Array<(String, Ty)>()));
            }
        }
        var found = _declared_member(resolved, name, 0);
        if (found.is_value()) {
            return found;
        }
        # A type parameter: its bounds' members.
        for (var bound in _generic_bounds(at, resolved.name)) {
            var through = _declared_member(Ty.from_ast(bound), name, 0);
            if (through.is_value()) {
                return through;
            }
        }
        return Optional<TypedMember>.Empty;
    }

    # The bounds of the type parameter `name` in scope at `at`.
    _generic_bounds(at: ulong, name: String): TypeName[] {
        var out = Array<TypeName>();
        for (var d in document.declarations) {
            match (d) {
                Function(f) => {
                    if (_infer_inside(f.span, at)) {
                        _infer_scan_bounds(f.generic_params, name, out);
                    }
                }
                Struct(s) => {
                    if (_infer_inside(s.span, at)) {
                        _infer_scan_bounds(s.generic_params, name, out);
                        _infer_scan_method_bounds(s.methods, at, name, out);
                    }
                }
                Trait(t) => {
                    if (_infer_inside(t.span, at)) {
                        _infer_scan_bounds(t.generic_params, name, out);
                        _infer_scan_method_bounds(t.methods, at, name, out);
                    }
                }
                Extend(e) => {
                    if (!_infer_inside(e.span, at)) {
                        continue;
                    }
                    _infer_scan_method_bounds(e.methods, at, name, out);
                    # `extend Box<T: Named>` bounds a parameter of the
                    # target.
                    ulong i = 0;
                    while (i < e.target.generic_types.count and i < e.target_bounds.count) {
                        if (e.target.generic_types[i].name == name) {
                            out.append_all(e.target_bounds[i]);
                        }
                        i += 1;
                    }
                }
                else => {}
            }
        }
        return out;
    }

    _declared_member(owner: Ty, name: String, depth: ulong): TypedMember? {
        var none = Optional<TypedMember>.Empty;
        if (depth > 4) {
            return none;
        }
        var traits = Array<Ty>();
        for (var (file, d) in _declarations) {
            match (d) {
                Struct(s) => {
                    if (!_infer_same_type(s.name, owner.name)) {
                        continue;
                    }
                    var found = _struct_member(file, s, owner, name);
                    if (found.is_value()) {
                        return found;
                    }
                }
                Trait(t) => {
                    if (!_infer_same_type(t.name, owner.name)) {
                        continue;
                    }
                    var bindings = _infer_bind(t.generic_params, owner.args);
                    for (var p in t.properties) {
                        if (p.name == name) {
                            return _infer_found(file, MemberKind.Property(p), t.name, bindings);
                        }
                    }
                    for (var m in t.methods) {
                        if (link.demangle_name(m.name) == name) {
                            return _infer_found(file, MemberKind.Method(m), t.name, bindings);
                        }
                    }
                }
                Extend(e) => {
                    if (!_infer_same_type(e.target.name, owner.name)) {
                        continue;
                    }
                    # `extend Box<T>` names its parameters in the target.
                    var bindings = Array<(String, Ty)>();
                    ulong i = 0;
                    while (i < e.target.generic_types.count and i < owner.args.count) {
                        bindings.append((e.target.generic_types[i].name, owner.args[i]));
                        i += 1;
                    }
                    for (var p in e.properties) {
                        if (p.name == name) {
                            return _infer_found(file, MemberKind.Property(p), e.target.name, bindings);
                        }
                    }
                    for (var m in e.methods) {
                        if (link.demangle_name(m.name) == name) {
                            return _infer_found(file, MemberKind.Method(m), e.target.name, bindings);
                        }
                    }
                    for (var t in e.traits) {
                        traits.append(Ty.from_ast(t).substitute(bindings));
                    }
                }
                else => {}
            }
        }
        for (var t in traits) {
            var found = _declared_member(t, name, depth + 1);
            if (found.is_value()) {
                return found;
            }
        }
        return none;
    }

    # The member `name` struct or enum `s` declares, for a value of type
    # `owner`.
    _struct_member(file: ulong, s: StructDecl, owner: Ty, name: String): TypedMember? {
        var bindings = _infer_bind(s.generic_params, owner.args);
        for (var v in s.fields) {
            if (v.name == name) {
                return _infer_found(file, MemberKind.Field(v), s.name, bindings);
            }
        }
        for (var p in s.properties) {
            if (p.name == name) {
                return _infer_found(file, MemberKind.Property(p), s.name, bindings);
            }
        }
        if (s.enumeration is Value(body)) {
            for (var c in body.cases) {
                if (c.name == name) {
                    return _infer_found(file, MemberKind.Case(c), s.name, bindings);
                }
            }
        }
        for (var m in s.methods) {
            if (link.demangle_name(m.name) == name) {
                return _infer_found(file, MemberKind.Method(m), s.name, bindings);
            }
        }
        if (s.enumeration is Value(body)) {
            if (_infer_plain_values(body) and sema.is_enum_built_in_method(name)) {
                return _infer_found(file, MemberKind.EnumMethod(s, name), s.name, bindings);
            }
        }
        return Optional<TypedMember>.Empty;
    }

    # ── Names ────────────────────────────────────────────────────────────

    ## Returns the type `this` has at `at`: the enclosing struct's, its
    ## generic parameters as arguments, or the type an extension extends.
    ##
    ## @param at the byte offset
    ## @returns the type; empty outside a struct, extension or trait
    this_type(at: ulong): Ty? {
        var around = body_at(document, at);
        if (around is Value(enclosing)) {
            if (enclosing.owner is Value(s)) {
                return Optional<Ty>.Value(Ty.of(s.name, _infer_parameter_types(s.generic_params)));
            }
        }
        for (var d in document.declarations) {
            match (d) {
                Extend(e) => {
                    if (_infer_inside(e.span, at)) {
                        return Optional<Ty>.Value(Ty.from_ast(e.target));
                    }
                }
                # A trait's default method: the trait's own members.
                Trait(t) => {
                    if (_infer_inside(t.span, at)) {
                        return Optional<Ty>.Value(Ty.of(t.name, _infer_parameter_types(t.generic_params)));
                    }
                }
                else => {}
            }
        }
        return Optional<Ty>.Empty;
    }

    ## Returns the type of the local or parameter `symbol` (from
    ## `scope_locals` or `declared_at`).
    ##
    ## @param symbol the local or parameter
    ## @returns its type; empty when unknown
    local_type_of(symbol: Symbol): Ty? {
        return _local_type(symbol, 0);
    }

    # The type of the local or parameter `symbol`, from its declaration.
    _local_type(symbol: Symbol, depth: ulong): Ty? {
        var written = Ty.parse(symbol.type_text);
        if (written is Value(w)) {
            if (!w.is_auto()) {
                return written;
            }
        }
        var inferred = _sema_local(symbol.name_span.start);
        if (inferred.is_empty()) {
            return _declared_type(symbol, depth);
        }
        # Sema's tuple types drop their labels; the syntax keeps them.
        if (inferred.value().name != ast.TUPLE_TYPE) {
            return inferred;
        }
        var declared = _declared_type(symbol, depth);
        if (declared is Value(d)) {
            if (d.name == ast.TUPLE_TYPE and d.labels.count > 0) {
                return declared;
            }
        }
        return inferred;
    }

    # The type sema inferred for the variable whose name starts at `start`
    # in the document.
    _sema_local(start: ulong): Ty? {
        if (model is Value(m)) {
            var ty = sema.local_type(m, 0, start);
            if (ty is Value(t)) {
                return Ty.parse(t.to_string());
            }
        }
        return Optional<Ty>.Empty;
    }

    # The type of the local or parameter `symbol` from its declaration: its
    # initializer, the value a pattern or destructuring takes apart, or what
    # a `for` loop iterates.
    _declared_type(symbol: Symbol, depth: ulong): Ty? {
        var none = Optional<Ty>.Empty;
        var span = symbol.name_span;
        # A constructor's `this.run = ...` parameter stores to the field.
        if (symbol.name.starts_with("this.")) {
            var field = symbol.name.substr_bytes(5, symbol.name.size - 5);
            var owner = this_type(span.start);
            if (owner.is_empty()) {
                return none;
            }
            var found = member(owner.value(), field, span.start);
            if (found.is_empty()) {
                return none;
            }
            return _infer_member_value(found.value(), owner.value());
        }
        var site = Optional<_InferSite>.Empty;
        var walk = SyntaxWalk.of_module(document);
        while (site.is_empty()) {
            var item = walk.next();
            if (item.is_empty()) {
                return none;
            }
            site = _site_of(item.value(), span, depth);
        }
        match (site.value()) {
            Variable(v) => {
                if (v.type_name.name != ast.AUTO_TYPE) {
                    return Optional<Ty>.Value(Ty.from_ast(v.type_name));
                }
                if (v.default_value is Value(initializer)) {
                    return _type_at(initializer, v.name_span.start, depth + 1);
                }
                return none;
            }
            For(iterable, for_span) => {
                var iterated = _type_at(iterable, for_span.start, depth + 1);
                if (iterated.is_empty()) {
                    return none;
                }
                return _element(iterated.value(), for_span.start);
            }
            ClosureParameter(index, ty) => {
                bool function = ty.name == ast.FUNCTION_TYPE
                    or ty.name == ast.SHARED_FUNCTION_TYPE
                    or ty.name == ast.EXTERN_FUNCTION_TYPE;
                if (function and index + 1 < ty.args.count) {
                    return Optional<Ty>.Value(ty.args[index + 1]);
                }
                return none;
            }
            Destructure(bindings, value, destructure_span) => {
                var taken = _type_at(value, destructure_span.start, depth + 1);
                return _infer_destructured(bindings, taken, span);
            }
            ForPattern(bindings, iterable, for_span) => {
                var iterated = _type_at(iterable, for_span.start, depth + 1);
                var element = Optional<Ty>.Empty;
                if (iterated is Value(t)) {
                    element = _element(t, for_span.start);
                }
                return _infer_destructured(bindings, element, span);
            }
            Bound(patterns, subject) => {
                var subject_type = _type_at(subject, subject.extent().start, depth + 1);
                for (var matched in _with_subjects(patterns, subject_type)) {
                    var p = matched.pattern;
                    if (p.is_bare_name() and _infer_same_span(p.case_span, span) and matched.subject.is_value()) {
                        return matched.subject;
                    }
                }
                return none;
            }
        }
        return none;
    }

    # Where the item declares the local named at `span`, if it does.
    _site_of(item: SyntaxItem, span: Span, depth: ulong): _InferSite? {
        var none = Optional<_InferSite>.Empty;
        match (item) {
            Statement(statement) => {
                if (statement is For(binding, pattern, iterable, _, for_span)) {
                    if (_infer_same_span(binding.name_span, span)) {
                        return Optional<_InferSite>.Value(_InferSite.For(iterable, for_span));
                    }
                    if (_infer_declares(pattern, span)) {
                        return Optional<_InferSite>.Value(_InferSite.ForPattern(pattern, iterable, for_span));
                    }
                } else if (statement is Destructure(bindings, value, _, destructure_span)) {
                    if (_infer_declares(bindings, span)) {
                        return Optional<_InferSite>.Value(_InferSite.Destructure(bindings, value, destructure_span));
                    }
                }
            }
            Variable(v) => {
                if (!_infer_same_span(v.name_span, span)) {
                    return none;
                }
                if (v.type_name.name == ast.AUTO_TYPE) {
                    var closure = _closure_parameter(span, depth + 1);
                    if (closure is Value(given)) {
                        var (index, ty) = given;
                        return Optional<_InferSite>.Value(_InferSite.ClosureParameter(index, ty));
                    }
                }
                return Optional<_InferSite>.Value(_InferSite.Variable(v));
            }
            Patterns(patterns, subject) => {
                for (var p in patterns) {
                    for (var label in p.bound_names()) {
                        if (_infer_same_span(label.span, span)) {
                            return Optional<_InferSite>.Value(_InferSite.Bound(patterns, subject));
                        }
                    }
                }
            }
            else => {}
        }
        return none;
    }

    # For the closure parameter named at `span`: its position, and the type
    # the closure is given as, from the callee's parameter it is passed to
    # or the variable it initializes.
    _closure_parameter(span: Span, depth: ulong): (ulong, Ty)? {
        var walk = SyntaxWalk.of_module(document);
        while (true) {
            var item = walk.next();
            if (item.is_empty()) {
                return Optional<(ulong, Ty)>.Empty;
            }
            match (item.value()) {
                Variable(v) => {
                    if (v.type_name.name == ast.AUTO_TYPE or v.default_value.is_empty()) {
                        continue;
                    }
                    var index = _infer_closure_index(v.default_value.value(), span);
                    if (index is Value(i)) {
                        return Optional<(ulong, Ty)>.Value((i, Ty.from_ast(v.type_name)));
                    }
                }
                Expression(e) => {
                    if (e is FunctionCall(function, arguments, _)) {
                        var given = _call_parameter(function, arguments, span, depth);
                        if (given.is_value()) {
                            return given;
                        }
                    }
                }
                else => {}
            }
        }
        return Optional<(ulong, Ty)>.Empty;
    }

    # For a call passing the closure whose parameter is named at `span`:
    # that parameter's position, and the type of the callee's parameter the
    # closure is passed to.
    _call_parameter(function: Expression, arguments: Expression[], span: Span, depth: ulong): (ulong, Ty)? {
        var none = Optional<(ulong, Ty)>.Empty;
        ulong argument = 0;
        var index = Optional<ulong>.Empty;
        while (argument < arguments.count) {
            index = _infer_closure_index(arguments[argument], span);
            if (index.is_value()) {
                break;
            }
            argument += 1;
        }
        if (index.is_empty()) {
            return none;
        }
        var parameter = Optional<Ty>.Empty;
        match (function) {
            SymbolRef(id, _) => {
                parameter = _function_parameter(id, argument);
            }
            MemberAccess(lhs, name, _, _) => {
                var found = _member_access_at(lhs, name, span.start, depth);
                if (found is Value(m)) {
                    parameter = _method_parameter(m, argument);
                }
            }
            else => {}
        }
        if (parameter is Value(t)) {
            return Optional<(ulong, Ty)>.Value((index.value(), t));
        }
        return none;
    }

    # The type of parameter `index` of the first top-level function `id`
    # that has one.
    _function_parameter(id: String, index: ulong): Ty? {
        for (var (_, d) in _declarations) {
            if (d is Function(f)) {
                if (_infer_plain(f.name) == id and index < f.parameters.count) {
                    return Optional<Ty>.Value(Ty.from_ast(f.parameters[index].type_name));
                }
            }
        }
        return Optional<Ty>.Empty;
    }

    # The type of parameter `index` (`this` left out) of method `found`.
    _method_parameter(found: TypedMember, index: ulong): Ty? {
        if (found.kind is Method(f)) {
            ulong seen = 0;
            for (var p in f.parameters) {
                if (p.name == "this") {
                    continue;
                }
                if (seen == index) {
                    return Optional<Ty>.Value(Ty.from_ast(p.type_name).substitute(found.bindings));
                }
                seen += 1;
            }
        }
        return Optional<Ty>.Empty;
    }

    # Each of `patterns` and the patterns nested in them, with the type of
    # the value it matches: a tuple's element, or a case's value.
    _with_subjects(patterns: Pattern[], subject: Ty?): _PatternSubject[] {
        var out = Array<_PatternSubject>();
        var stack = Array<_PatternSubject>();
        for (var p in patterns) {
            stack.append(_PatternSubject(p, subject));
        }
        while (stack.count > 0) {
            var top = stack.pop();
            var p = top.pattern;
            if (p.elements is Value(elements)) {
                ulong i = 0;
                while (i < elements.count) {
                    stack.append(_PatternSubject(elements[i], _infer_element_of(top.subject, i)));
                    i += 1;
                }
            }
            if (p.bindings is Value(subs)) {
                var found = case_of(p, top.subject);
                ulong i = 0;
                while (i < subs.count) {
                    stack.append(_PatternSubject(subs[i], _infer_case_value(found, i)));
                    i += 1;
                }
            }
            out.append(top);
        }
        return out;
    }

    ## Returns the case pattern `p` names, matching a value of type
    ## `subject`: of the enum it qualifies, else the value's, else the one
    ## enum declaring a case of that name that carries as many values.
    ##
    ## @param p the pattern
    ## @param subject the type of the value matched, if known
    ## @returns the case; empty when it names none, or two enums could be
    ##   meant
    case_of(p: Pattern, subject: Ty?): TypedMember? {
        var none = Optional<TypedMember>.Empty;
        if (p.literal.is_value() or p.elements.is_value()) {
            return none;
        }
        var owner = subject;
        if (p.qualifier is Value(qualifier)) {
            owner = Optional<Ty>.Value(Ty.from_ast(qualifier));
        }
        if (owner is Value(o)) {
            var found = _declared_member(_resolve(o), p.case_name, 0);
            if (found is Value(f)) {
                if (f.kind is Case(_)) {
                    return found;
                }
                return none;
            }
        }
        var first = Optional<TypedMember>.Empty;
        for (var (file, d) in _declarations) {
            var candidate = _infer_case_candidate(file, d, p);
            if (candidate.is_empty()) {
                continue;
            }
            if (first.is_empty()) {
                first = candidate;
                continue;
            }
            # Two enums could be meant: the document's own wins, else
            # neither.
            if (first.value().file != 0) {
                return none;
            }
            return first;
        }
        return first;
    }

    ## Returns what the pattern under `offset` names: a case, or a name it
    ## binds.
    ##
    ## @param offset the byte offset
    ## @returns what it names; empty when no pattern's name is there
    pattern_at(offset: ulong): PatternHit? {
        var none = Optional<PatternHit>.Empty;
        var hit = Optional<Pattern>.Empty;
        var hit_patterns = Array<Pattern>();
        var hit_subject = Optional<Expression>.Empty;
        var walk = SyntaxWalk.of_module(document);
        while (hit.is_empty()) {
            var item = walk.next();
            if (item.is_empty()) {
                return none;
            }
            if (item.value() is Patterns(patterns, subject)) {
                # `String.format`'s lowering binds its arguments by hidden
                # names at the arguments' own spans.
                for (var p in _infer_all_patterns(patterns)) {
                    if (p.case_name.starts_with("_pep_")) {
                        continue;
                    }
                    if (p.literal.is_empty() and p.elements.is_empty() and on_name(p.case_span, offset)) {
                        hit = Optional<Pattern>.Value(p);
                        hit_patterns = patterns;
                        hit_subject = Optional<Expression>.Value(subject);
                        break;
                    }
                }
            }
        }
        var p = hit.value();
        var subject = hit_subject.value();
        var subject_type = _type_at(subject, subject.extent().start, 0);
        var matched = Optional<Ty>.Empty;
        bool seen = false;
        for (var candidate in _with_subjects(hit_patterns, subject_type)) {
            if (candidate.pattern === p) {
                matched = candidate.subject;
                seen = true;
                break;
            }
        }
        if (!seen) {
            return none;
        }
        # A bare name in a tuple pattern or a case's values binds the value
        # unless it is a case.
        var found = case_of(p, matched);
        if (found is Value(f)) {
            return Optional<PatternHit>.Value(PatternHit.Case(f));
        }
        if (p.is_bare_name() and p.case_name != "_") {
            return Optional<PatternHit>.Value(PatternHit.Binding(p.case_name, p.case_span, matched));
        }
        return none;
    }

    ## Returns the type of the name `id` at `at`.
    ##
    ## @param id the name
    ## @param at the byte offset
    ## @returns its type; empty when unknown
    symbol_type(id: String, at: ulong): Ty? {
        return _name_type(id, at, 0);
    }

    _name_type(id: String, at: ulong, depth: ulong): Ty? {
        var none = Optional<Ty>.Empty;
        if (depth > _INFER_MAX_DEPTH) {
            return none;
        }
        if (id == "this") {
            return this_type(at);
        }
        var locals = scope_locals(document, at);
        ulong i = locals.count;
        while (i > 0) {
            i -= 1;
            if (locals[i].name == id) {
                return _local_type(locals[i], depth + 1);
            }
        }
        # A member of `this`, named bare.
        var owner = this_type(at);
        if (owner is Value(o)) {
            var found = member(o, id, at);
            if (found is Value(f)) {
                return _infer_member_value(f, o);
            }
        }
        # A module-scope variable, as declared or initialized.
        var plain = _infer_plain(id);
        for (var (file, d) in _declarations) {
            if (d is Variable(v)) {
                if (_infer_plain(v.name) != plain) {
                    continue;
                }
                if (v.type_name.name != ast.AUTO_TYPE) {
                    return Optional<Ty>.Value(Ty.from_ast(v.type_name));
                }
                if (v.default_value.is_empty()) {
                    return none;
                }
                # Another file's initializer names that file's
                # declarations; only a call of a type or function is typed
                # from here.
                var where = file == 0 ? v.name_span.start : _INFER_ELSEWHERE;
                return _type_at(v.default_value.value(), where, depth + 1);
            }
        }
        return none;
    }

    # The type a value of `owner` holds as elements: an array's element, or
    # what its iterator's `next()` returns.
    _element(owner: Ty, at: ulong): Ty? {
        var none = Optional<Ty>.Empty;
        var resolved = _resolve(owner);
        if (resolved.name == "Array" or resolved.name == "__ptr") {
            if (resolved.args.count == 0) {
                return none;
            }
            return Optional<Ty>.Value(resolved.args[0]);
        }
        # An iterator, or what `iterate()` returns.
        var no_args = Array<Ty>();
        var iterator = _method_result(resolved, "iterate", no_args, at).value_or(resolved);
        var next = _method_result(iterator, "next", no_args, at);
        if (next.is_empty()) {
            return none;
        }
        # `next()` returns an `Optional<T>`, or a `bool` with `current()`
        # the element.
        var result = next.value();
        if (result.name == "Optional") {
            if (result.args.count == 0) {
                return none;
            }
            return Optional<Ty>.Value(result.args[0]);
        }
        if (result.name == "bool") {
            return _method_result(iterator, "current", no_args, at);
        }
        return next;
    }

    # The type a call of `owner`'s method `name` returns.
    _method_result(owner: Ty, name: String, args: Ty[], at: ulong): Ty? {
        var none = Optional<Ty>.Empty;
        var found = member(owner, name, at);
        if (found.is_empty()) {
            return none;
        }
        var m = found.value();
        if (m.kind is Method(f)) {
            var bindings = m.bindings.clone();
            bindings.append_all(_infer_bind(f.generic_params, args));
            # A trait's `this` is the type it is called on.
            bindings.append(("this", owner));
            var result = Ty.from_ast(f.return_type).substitute(bindings);
            if (result.is_auto()) {
                return none;
            }
            return Optional<Ty>.Value(result);
        }
        return none;
    }

    ## Returns the type `expr` names when it names a type rather than a
    ## value: the owner of a static call (`Box<int>.make()`,
    ## `int.parse(...)`).
    ##
    ## @param expr the expression
    ## @param at where it is written
    ## @returns the type; empty when `expr` names a value
    named_type(expr: Expression, at: ulong): Ty? {
        match (expr) {
            TypeLiteral(t) => {
                if (_is_type(_infer_plain(t.name), at)) {
                    return Optional<Ty>.Value(Ty.from_ast(t));
                }
            }
            SymbolRef(id, _) => {
                if (!_is_local(id, at) and _is_type(id, at)) {
                    return Optional<Ty>.Value(Ty(id));
                }
            }
            else => {}
        }
        return Optional<Ty>.Empty;
    }

    ## Returns the type of `expr`, written at `at`.
    ##
    ## @param expr the expression
    ## @param at where it is written
    ## @returns its type; empty when unknown
    type_of(expr: Expression, at: ulong): Ty? {
        return _type_at(expr, at, 0);
    }

    _type_at(expr: Expression, at: ulong, depth: ulong): Ty? {
        if (depth > _INFER_MAX_DEPTH) {
            return Optional<Ty>.Empty;
        }
        var ty = _expression_type(expr, at, depth + 1);
        if (ty is Value(t)) {
            if (t.is_auto()) {
                return Optional<Ty>.Empty;
            }
        }
        return ty;
    }

    # The type of `expr`, unknown types not filtered out.
    _expression_type(expr: Expression, at: ulong, depth: ulong): Ty? {
        var none = Optional<Ty>.Empty;
        match (expr) {
            Literal(value, _) => {
                return Optional<Ty>.Value(Ty(literal_type(value)));
            }
            SymbolRef(id, _) => {
                return _name_type(id, at, depth);
            }
            SizeOf(_) => {
                return Optional<Ty>.Value(Ty("ulong"));
            }
            Unary(op, _, operand, _) => {
                if (op == "!") {
                    return Optional<Ty>.Value(Ty("bool"));
                }
                var inner = _type_at(operand, at, depth);
                if (op != "?" or inner.is_empty()) {
                    return inner;
                }
                # `r?`: the value a `Result` or an `Optional` holds.
                var held = _resolve(inner.value());
                if (held.args.count == 0) {
                    return none;
                }
                return Optional<Ty>.Value(held.args[0]);
            }
            Cast(_, type_name, _, _, _) => {
                return Optional<Ty>.Value(Ty.from_ast(type_name));
            }
            Binary(lhs, op, rhs, _) => {
                if (_infer_is_test(op)) {
                    return Optional<Ty>.Value(Ty("bool"));
                }
                var left = _type_at(lhs, at, depth);
                if (left.is_value()) {
                    return left;
                }
                return _type_at(rhs, at, depth);
            }
            Ternary(_, true_expr, false_expr, _) => {
                var first = _type_at(true_expr, at, depth);
                if (first.is_value()) {
                    return first;
                }
                return _type_at(false_expr, at, depth);
            }
            Index(lhs, _, _) => {
                var owner = _type_at(lhs, at, depth);
                if (owner.is_empty()) {
                    return none;
                }
                var element = _element(owner.value(), at);
                if (element.is_value()) {
                    return element;
                }
                # An indexer (`[](index): T`).
                var found = _declared_member(owner.value(), "__index_get", 0);
                if (found is Value(m)) {
                    if (m.kind is Method(f)) {
                        return Optional<Ty>.Value(Ty.from_ast(f.return_type).substitute(m.bindings));
                    }
                }
                return none;
            }
            MemberAccess(lhs, name, _, _) => {
                var owner = _owner_type(lhs, at, depth);
                if (owner.is_empty()) {
                    return none;
                }
                var (base, _) = split_generics(name);
                var found = member(owner.value(), base, at);
                if (found.is_empty()) {
                    return none;
                }
                return _infer_member_value(found.value(), owner.value());
            }
            FunctionCall(function, _, _) => {
                return _call_type(function, at, depth);
            }
            Tuple(elements, labels, _) => {
                var out = Ty(ast.TUPLE_TYPE);
                for (var element in elements) {
                    var typed = _type_at(element, at, depth);
                    if (typed.is_empty()) {
                        return none;
                    }
                    out.args.append(typed.value());
                }
                for (var label in labels) {
                    out.labels.append(label.name);
                }
                return Optional<Ty>.Value(out);
            }
            ArrayLiteral(elements, _) => {
                if (elements.count == 0) {
                    return none;
                }
                var element = _type_at(elements[0], at, depth);
                if (element.is_empty()) {
                    return none;
                }
                return Optional<Ty>.Value(Ty.of("Array", [element.value()]));
            }
            MapLiteral(entries, _) => {
                if (entries.count == 0) {
                    return none;
                }
                var key = _type_at(entries[0].key, at, depth);
                var value = _type_at(entries[0].value, at, depth);
                if (key.is_empty() or value.is_empty()) {
                    return none;
                }
                return Optional<Ty>.Value(Ty.of("HashMap", [key.value(), value.value()]));
            }
            Match(m) => {
                for (var arm in m.arms) {
                    var typed = _type_at(arm.value, at, depth);
                    if (typed.is_value()) {
                        return typed;
                    }
                }
                if (m.else_value is Value(otherwise)) {
                    return _type_at(otherwise, at, depth);
                }
                return none;
            }
            Is(_, _, _, _) => {
                return Optional<Ty>.Value(Ty("bool"));
            }
            NamedArgument(_, _, value, _) => {
                return _type_at(value, at, depth);
            }
            else => {
                return none;
            }
        }
    }

    # The type whose member `lhs.name` reaches: the type `lhs` names, else
    # the type of its value.
    _owner_type(lhs: Expression, at: ulong, depth: ulong): Ty? {
        var named = named_type(lhs, at);
        if (named.is_value()) {
            return named;
        }
        return _type_at(lhs, at, depth);
    }

    # The type a call of `function` returns.
    _call_type(function: Expression, at: ulong, depth: ulong): Ty? {
        var none = Optional<Ty>.Empty;
        match (function) {
            SymbolRef(id, _) => {
                if (_is_type(id, at) and !_is_local(id, at)) {
                    return Optional<Ty>.Value(Ty(id));
                }
                # A local or field holding a function.
                var held = _name_type(id, at, depth);
                if (held is Value(t)) {
                    return _infer_function_result(t);
                }
                # A method of `this`, called bare.
                var owner = this_type(at);
                if (owner is Value(o)) {
                    var result = _method_result(o, id, Array<Ty>(), at);
                    if (result.is_value()) {
                        return result;
                    }
                }
                return _function_result(id, Array<Ty>());
            }
            TypeLiteral(t) => {
                var args = Array<Ty>();
                for (var argument in t.generic_types) {
                    args.append(Ty.from_ast(argument));
                }
                if (t.name == "__weak_upgrade" or t.name == "unsafe_cast") {
                    if (args.count == 0) {
                        return none;
                    }
                    return Optional<Ty>.Value(args[0]);
                }
                if (t.name == "__weak_from") {
                    return Optional<Ty>.Value(Ty.of("__weak", args));
                }
                if (_is_type(_infer_plain(t.name), at)) {
                    return Optional<Ty>.Value(Ty.from_ast(t));
                }
                return _function_result(t.name, args);
            }
            MemberAccess(lhs, name, _, _) => {
                var owner = _owner_type(lhs, at, depth);
                if (owner.is_empty()) {
                    return none;
                }
                var (base, args) = split_generics(name);
                var found = member(owner.value(), base, at);
                if (found.is_empty()) {
                    return none;
                }
                match (found.value().kind) {
                    Method(_) => {
                        return _method_result(owner.value(), base, args, at);
                    }
                    EnumMethod(s, method) => {
                        if (method == "from_value") {
                            return Optional<Ty>.Value(Ty.of("Result", [Ty(_infer_plain(s.name))]));
                        }
                        return Optional<Ty>.Value(Ty("String"));
                    }
                    Case(_) => {
                        return Optional<Ty>.Value(_resolve(owner.value()));
                    }
                    else => {
                        var value = _infer_member_value(found.value(), owner.value());
                        if (value.is_empty()) {
                            return none;
                        }
                        return _infer_function_result(value.value());
                    }
                }
            }
            else => {}
        }
        return none;
    }

    # The type a call of the top-level function `name` returns.
    _function_result(name: String, args: Ty[]): Ty? {
        # Another file's initializer spells its own private names mangled.
        var plain = _infer_plain(name);
        for (var (_, d) in _declarations) {
            if (d is Function(f)) {
                if (_infer_plain(f.name) != plain) {
                    continue;
                }
                var result = Ty.from_ast(f.return_type).substitute(_infer_bind(f.generic_params, args));
                if (result.is_auto()) {
                    return Optional<Ty>.Empty;
                }
                return Optional<Ty>.Value(result);
            }
        }
        return Optional<Ty>.Empty;
    }

    ## Returns the member a member access (`x.name`, `x.name(...)`,
    ## `T.name(...)`) at `at` reaches.
    ##
    ## @param lhs the owner expression
    ## @param name the member as written
    ## @param at where the access is written
    ## @returns the member; empty when none is found
    member_access(lhs: Expression, name: String, at: ulong): TypedMember? {
        return _member_access_at(lhs, name, at, 0);
    }

    _member_access_at(lhs: Expression, name: String, at: ulong, depth: ulong): TypedMember? {
        var owner = _owner_type(lhs, at, depth);
        if (owner.is_empty()) {
            return Optional<TypedMember>.Empty;
        }
        var (base, _) = split_generics(name);
        return member(owner.value(), base, at);
    }

    ## Returns the type of the module-scope variable declared at
    ## `name_span` in program file `file`, from its initializer when it
    ## names no type.
    ##
    ## @param file the program file (0 is the document)
    ## @param name_span where the variable's name is written
    ## @returns its type; empty when unknown
    global_type(file: ulong, name_span: Span): Ty? {
        var none = Optional<Ty>.Empty;
        for (var (index, module) in _modules) {
            if (index != file) {
                continue;
            }
            for (var d in module.declarations) {
                if (d is Variable(v)) {
                    if (!_infer_same_span(v.name_span, name_span)) {
                        continue;
                    }
                    if (v.type_name.name != ast.AUTO_TYPE) {
                        return Optional<Ty>.Value(Ty.from_ast(v.type_name));
                    }
                    if (v.default_value.is_empty()) {
                        return none;
                    }
                    # Another file's initializer has no locals here.
                    var where = file == 0 ? v.name_span.start : _INFER_ELSEWHERE;
                    return _type_at(v.default_value.value(), where, 0);
                }
            }
            return none;
        }
        return none;
    }

    ## Returns the labels of the tuple a member access (`p.line`) reads.
    ##
    ## @param access the member access
    ## @param at where it is written
    ## @returns the labels; empty when the owner is no labeled tuple
    member_owner_labels(access: Expression, at: ulong): String[]? {
        var none = Optional<String[]>.Empty;
        if (access is MemberAccess(lhs, _, _, _)) {
            var owner = _type_at(lhs, at, 0);
            if (owner is Value(t)) {
                if (t.name == ast.TUPLE_TYPE and t.labels.count > 0) {
                    return Optional<String[]>.Value(t.labels);
                }
            }
        }
        return none;
    }

    ## Returns the member of `this` the bare name `id` at `at` reaches.
    ##
    ## @param id the name
    ## @param at where it is written
    ## @returns the member; empty outside a type or when it has none
    bare_member(id: String, at: ulong): TypedMember? {
        var owner = this_type(at);
        if (owner.is_empty()) {
            return Optional<TypedMember>.Empty;
        }
        return member(owner.value(), id, at);
    }

    ## Returns what a call `name(...)` at `at` may call: a method of
    ## `this`, else every free function named `name` and every constructor
    ## of the struct named `name`, in any program file.
    ##
    ## @param name the callee's name
    ## @param at where the call is written
    ## @returns the functions
    callees_named(name: String, at: ulong): FunctionDecl[] {
        var out = Array<FunctionDecl>();
        var bare = bare_member(name, at);
        if (bare is Value(found)) {
            if (found.kind is Method(f)) {
                out.append(f);
                return out;
            }
        }
        for (var (_, d) in _declarations) {
            match (d) {
                Function(f) => {
                    if (_infer_plain(f.name) == name) {
                        out.append(f);
                    }
                }
                Struct(s) => {
                    if (_infer_plain(s.name) == name) {
                        out.append_all(s.constructors);
                    }
                }
                else => {}
            }
        }
        return out;
    }
}

# A member found in program file `file`, declared by `owner_name`.
_infer_found(file: ulong, kind: MemberKind, owner_name: String, bindings: Array<(String, Ty)>): TypedMember? {
    return Optional<TypedMember>.Value(TypedMember(file, kind, _infer_plain(owner_name), bindings));
}

# Whether `span` holds `at`, its end left out.
_infer_inside(span: Span, at: ulong): bool {
    return span.start <= at and at < span.end;
}

# Generic parameters as types, to stand as their own arguments.
_infer_parameter_types(params: GenericParam[]): Ty[] {
    var out = Array<Ty>();
    for (var p in params) {
        out.append(Ty(p.name));
    }
    return out;
}

# Adds the bounds of the parameter `name` of `params` to `out`.
_infer_scan_bounds(params: GenericParam[], name: String, out: TypeName[]) {
    for (var p in params) {
        if (p.name == name) {
            out.append_all(p.bounds);
        }
    }
}

# Adds the bounds of the parameter `name` of each method around `at`.
_infer_scan_method_bounds(methods: FunctionDecl[], at: ulong, name: String, out: TypeName[]) {
    for (var m in methods) {
        if (_infer_inside(m.span, at)) {
            _infer_scan_bounds(m.generic_params, name, out);
        }
    }
}

# Whether binary operator `op` makes a `bool`.
_infer_is_test(op: String): bool {
    match (op) {
        "==", "!=", "===", "!==", "<", ">", "<=", ">=", "&&", "||", "and", "or" => {
            return true;
        }
        else => {
            return false;
        }
    }
}

# The type of value `i` of the case `found` names.
_infer_case_value(found: TypedMember?, i: ulong): Ty? {
    if (found is Value(f)) {
        if (f.kind is Case(case)) {
            if (case.payload is Value(payload)) {
                if (i < payload.count) {
                    return Optional<Ty>.Value(Ty.from_ast(payload[i].type_name).substitute(f.bindings));
                }
            }
        }
    }
    return Optional<Ty>.Empty;
}

# The case of enum declaration `d` of program file `file` that pattern `p`
# may name.
_infer_case_candidate(file: ulong, d: Declaration, p: Pattern): TypedMember? {
    if (d is Struct(s)) {
        if (s.enumeration is Value(body)) {
            var case = _infer_case_named(body, p);
            if (case is Value(c)) {
                return Optional<TypedMember>.Value(
                    TypedMember(file, MemberKind.Case(c), _infer_plain(s.name), Array<(String, Ty)>())
                );
            }
        }
    }
    return Optional<TypedMember>.Empty;
}

# The case of `body` pattern `p` names that carries as many values as `p`
# takes apart.
_infer_case_named(body: ast.EnumBody, p: Pattern): EnumCase? {
    for (var c in body.cases) {
        if (c.name != p.case_name) {
            continue;
        }
        if (p.bindings is Value(bindings)) {
            if (c.payload.is_empty() or c.payload.value().count != bindings.count) {
                continue;
            }
        }
        return Optional<EnumCase>.Value(c);
    }
    return Optional<EnumCase>.Empty;
}
