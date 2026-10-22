## `static (captures) { ... }` blocks, run at compile time.
## `expand` replaces each
## block in concrete code with what it emits, running its compile-time
## steps (a `for` over `reflect.properties<T>()`, a compile-time `if`) and
## filling in each emitted statement's placeholders; `expand_module_blocks`
## runs the module-scope blocks and gives their constants the values they
## computed; `check_attributes` checks every attribute against the
## `[Attribute]` struct it names. While the passes' state records them
## (`--emit-static`), each expansion is written back out as source too
## (`static_source.pep`).

import compiler.ast;
import [demangle, Diagnostic, Location] from compiler.diagnostic;
import [demangle_name, is_build_option_name, NAMESPACE_SEPARATOR] from compiler.link;
import [attribute_arguments, attribute_name] from "attributes";
import [getter_name, has_bare_attribute, INTERPOLATE, payload_field, REFLECT, TAG_FIELD] from "builder";
import [is_checked_function] from "checked";
import "common";
import "instantiation";
import [convert_string_literal] from "literals";
import [Loc] from "loc";
import [
    BinaryExpression,
    BinaryOp,
    Block,
    Branch,
    CastExpression,
    CastKind,
    Declaration,
    EnumCaseDef,
    EnumDef,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    LoopBreakKind,
    ModuleStaticBlock,
    MemberRefExpression,
    MethodCallExpression,
    Module,
    PropertyDef,
    RecordStaticConstant,
    Statement,
    StaticBlock,
    StaticConstant,
    StaticItem,
    StaticPass,
    StringLiteralExpression,
    StructDef,
    SymbolRefExpression,
    TypeName,
    UnaryOp
] from "model";
import [display_name] from "names";
import "overload_select";
import [display_float] from "program";
import [replace_statement_types] from "replace_types";
import [PassState] from "state";
import [
    escape_text,
    expression_source,
    Rendered,
    RenderedBranch,
    SourceEdit,
    SourcePiece,
    statement_source,
    StaticExpansion,
    string_literal,
    write_lines
] from "static_source";
import [is_integral_name, parse_type_string, replace_map] from "type_name";
import [Rewriter, rewrite_statement] from "walk";

## The attribute that makes a struct an attribute.
export const ATTRIBUTE_ATTRIBUTE = "Attribute";

## How many times a compile-time `while` may run before it is taken to be
## endless.
const _MAX_ITERATIONS: long = 100000;

## Whether the compiler gives attribute `name` a meaning. Any other
## attribute must name an `[Attribute]` struct.
_is_built_in_name(name: String): bool {
    match (name) {
        "Alias", "Attribute", "BuildOption", "Cold", "Deprecated", "Equatable", "Export", "Implicit", "Isolated", "Link", "LinkName", "Locked", "Move", "MoveSource", "NotCopyable", "Rename", "Sending", "Shared", "Target", "ThreadLocal", "Value", "__BuiltIn", "__Lazy", "__Reads" => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## Whether `block` holds a `static` block anywhere.
_has_static(block: Block): bool {
    for (var statement in block.items) {
        match (statement) {
            Static(_) => {
                return true;
            }
            Block(inner) => {
                if (_has_static(inner)) {
                    return true;
                }
            }
            Branch(branch) => {
                if (_has_static(branch.if_block)) {
                    return true;
                }
                if (branch.else_block.is_value() and _has_static(branch.else_block.value())) {
                    return true;
                }
            }
            While(loop) => {
                if (_has_static(loop.block)) {
                    return true;
                }
            }
            else => {}
        }
    }
    return false;
}

_body_has_static(function: FunctionDef): bool {
    return function.body.is_value() and _has_static(function.body.value());
}

## Expands every `static` block in concrete code: free functions that are
## not generic, and the methods, constructors and destructors of structs
## that are not. Errors go to `state`.
## `lowered` says the bodies have been through the passes that lower string
## literals, so a string a block emits is lowered too.
##
## @param module the model, changed in place
## @param state the passes' state
## @param lowered whether string literals are lowered by now
## @returns whether any block was expanded
export expand(module: Module, state: PassState, lowered: bool = false): bool {
    var sites = Array<FunctionDef>();
    for (var function in module.functions) {
        if (!function.is_generic_func and _body_has_static(function)) {
            sites.append(function);
        }
    }
    for (var st in module.structs) {
        if (_is_generic_base(st)) {
            continue;
        }
        for (var method in st.method_members) {
            if (_body_has_static(method)) {
                sites.append(method);
            }
        }
        for (var constructor in st.constructors) {
            if (_body_has_static(constructor)) {
                sites.append(constructor);
            }
        }
        if (_body_has_static(st.destructor)) {
            sites.append(st.destructor);
        }
    }
    if (sites.count == 0) {
        return false;
    }
    for (var function in sites) {
        var body = function.body.value();
        var expander = _Expander(module, state, _ExpansionContext.of(function, body));
        expander.lowered = lowered;
        expander.expand_in(body);
        state.notes.append_all(expander.notes);
    }
    return true;
}

## Empties the `static` blocks left in function bodies once the
## specializations are done: those of generic code, which only its
## specializations expand. A non-generic struct's generic methods keep
## theirs; they are the bases later specializations clone from.
##
## @param module the model, changed in place
export remove_from_generic_code(module: Module) {
    for (var function in module.functions) {
        _strip_static_body(function);
    }
    for (var st in module.structs) {
        for (var method in st.method_members) {
            _strip_static_body(method);
        }
        for (var constructor in st.constructors) {
            _strip_static_body(constructor);
        }
        if (st.generic_params.count > 0) {
            for (var method in st.generic_methods) {
                _strip_static_body(method);
            }
        }
        _strip_static_body(st.destructor);
    }
    for (var t in module.traits) {
        for (var method in t.methods) {
            _strip_static_body(method);
        }
    }
    for (var e in module.extensions) {
        for (var method in e.methods) {
            _strip_static_body(method);
        }
    }
}

_strip_static_body(function: FunctionDef) {
    if (_body_has_static(function)) {
        _strip_static(function.body.value());
    }
}

_strip_static(block: Block) {
    ulong i = 0;
    while (i < block.items.count) {
        match (block.items[i]) {
            Static(_) => {
                block.items[i] = Statement.Block(_block_of(Array<Statement>()));
            }
            Block(inner) => {
                _strip_static(inner);
            }
            Branch(branch) => {
                _strip_static(branch.if_block);
                if (branch.else_block.is_value()) {
                    _strip_static(branch.else_block.value());
                }
            }
            While(loop) => {
                _strip_static(loop.block);
            }
            else => {}
        }
        i += 1;
    }
}

## Runs the module-scope `static` blocks and gives each constant one
## declares the value the block computed, in place of the initializer the
## parser gave it.
##
## @param module the model, changed in place
## @param state the passes' state
export expand_module_blocks(module: Module, state: PassState) {
    var blocks = module.static_blocks;
    module.static_blocks = Array<ModuleStaticBlock>();
    var values = Array<(Loc, Expression)>();
    for (var block in blocks) {
        var context = _ExpansionContext("", "", block.block.loc, HashSet<String>());
        var expander = _Expander(module, state, context);
        var expanded = expander.expand(block.block);
        if (expanded.is_err()) {
            state.report(expanded.error());
            continue;
        }
        state.notes.append_all(expander.notes);
        for (var (name, loc) in block.constants) {
            var value = expander.scopes[0].try_get(name);
            if (!value.is_value()) {
                continue;
            }
            var written = ast.Expression.SymbolRef(name, loc.span);
            var emitted = expander.emitted(value.value(), written, loc);
            if (emitted.is_err()) {
                state.report(emitted.error());
            } else {
                values.append((loc, emitted.value()));
            }
        }
    }
    for (var (loc, value) in values) {
        for (var global in module.globals) {
            if (global.loc.same(loc)) {
                global.default = Optional<Expression>.Value(value);
                break;
            }
        }
    }
}

## The function a block is expanded in.
struct _ExpansionContext {
    # Its name as the user wrote it (`to_json<Point>`).
    var name: String;
    # Its name in the model, which `Module.spec_requests` is keyed by.
    var symbol: String;
    var loc: Loc;
    # Its parameters and locals: runtime values a block must capture.
    var runtime: HashSet<String>;

    construct(name: String, symbol: String, loc: Loc, runtime: HashSet<String>) {
        this.name = name;
        this.symbol = symbol;
        this.loc = loc;
        this.runtime = runtime;
    }

    static of(function: FunctionDef, body: Block): _ExpansionContext {
        var runtime = HashSet<String>();
        for (var p in function.parameters) {
            var name = p.name;
            while (name.starts_with("this.")) {
                name = name.substr_bytes(5, name.size - 5);
            }
            runtime.insert(name);
        }
        runtime.insert("this");
        _collect_locals(body, runtime);
        return _ExpansionContext(display_name(function.name), function.name, function.loc, runtime);
    }
}

_collect_locals(block: Block, out: HashSet<String>) {
    for (var statement in block.items) {
        match (statement) {
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    out.insert(variable.name);
                }
            }
            Block(inner) => {
                _collect_locals(inner, out);
            }
            Branch(branch) => {
                _collect_locals(branch.if_block, out);
                if (branch.else_block.is_value()) {
                    _collect_locals(branch.else_block.value(), out);
                }
            }
            While(loop) => {
                _collect_locals(loop.block, out);
            }
            else => {}
        }
    }
}

# ── Compile-time values ─────────────────────────────────────────────────────

## A field or property, from `reflect.properties<T>()` or `fields<T>()`.
struct _CtMember {
    var name: String;
    # The field `get` reads, when it is not `name`: a case's value.
    var field: String? = Optional<String>.Empty;
    var ty: TypeName;
    var index: ulong;
    var count: ulong;
    var is_const: bool;
    var is_property: bool;
    var attributes: ast.Attribute[];
    # The file the attributes are written in.
    var file: uint;
    # For a value a case carries, the enum.
    var enumeration: TypeName? = Optional<TypeName>.Empty;

    construct(
        name: String,
        ty: TypeName,
        index: ulong,
        count: ulong,
        is_const: bool,
        is_property: bool,
        attributes: ast.Attribute[],
        file: uint
    ) {
        this.name = name;
        this.ty = ty;
        this.index = index;
        this.count = count;
        this.is_const = is_const;
        this.is_property = is_property;
        this.attributes = attributes;
        this.file = file;
    }
}

## An enum case: from `reflect.cases<E>()`, or written as `E.Case`.
struct _CtCase {
    # The enum's type.
    var enumeration: TypeName;
    var name: String;
    # The case's value (a value enum), or its tag (a reference enum).
    var value: long;
    var index: ulong;
    var count: ulong;
    # A case of an enum with no values, which emitted code can name.
    var is_value: bool;
    # The values the case carries, as members whose `get` reads them.
    var values: _CtValue[] = Array<_CtValue>();
    var attributes: ast.Attribute[];
    var file: uint;

    construct(
        enumeration: TypeName,
        name: String,
        value: long,
        index: ulong,
        count: ulong,
        is_value: bool,
        attributes: ast.Attribute[],
        file: uint
    ) {
        this.enumeration = enumeration;
        this.name = name;
        this.value = value;
        this.index = index;
        this.count = count;
        this.is_value = is_value;
        this.attributes = attributes;
        this.file = file;
    }
}

## A function, from `reflect.functions_with<A>()`.
struct _CtFunction {
    # The function's name in the model, which a call uses.
    var symbol: String;
    var attributes: ast.Attribute[];
    var file: uint;

    construct(symbol: String, attributes: ast.Attribute[], file: uint) {
        this.symbol = symbol;
        this.attributes = attributes;
        this.file = file;
    }
}

## An attribute's values, from `attribute<A>()`.
struct _CtAttribute {
    # The attribute struct's name.
    var ty: String;
    var fields: Array<(String, _CtValue)>;

    construct(ty: String, fields: Array<(String, _CtValue)>) {
        this.ty = ty;
        this.fields = fields;
    }
}

## A value a `static` block computes.
enum _CtValue {
    Int(value: long),
    Float(value: double),
    Bool(value: bool),
    Text(value: String),
    Case(value: _CtCase),
    Member(value: _CtMember),
    Function(value: _CtFunction),
    List(items: _CtValue[]),
    Attribute(value: _CtAttribute),

    # The value as the debugger shows it, or none for a list.
    debug_constant(): StaticConstant? {
        match (this) {
            Int(value) => {
                return Optional<StaticConstant>.Value(StaticConstant.Int(value));
            }
            Float(value) => {
                return Optional<StaticConstant>.Value(StaticConstant.Float(value));
            }
            Bool(value) => {
                return Optional<StaticConstant>.Value(StaticConstant.Bool(value));
            }
            Text(value) => {
                return Optional<StaticConstant>.Value(StaticConstant.String(value));
            }
            Member(m) => {
                return Optional<StaticConstant>.Value(
                    _record(
                        "reflect.Member",
                        [
                            ("name", StaticConstant.String(m.name)),
                            ("type_name", StaticConstant.String(display_name(m.ty.display_stored()))),
                            ("index", StaticConstant.Int(m.index as long)),
                            ("is_last", StaticConstant.Bool(m.index + 1 == m.count)),
                            ("is_const", StaticConstant.Bool(m.is_const)),
                            ("is_property", StaticConstant.Bool(m.is_property))
                        ]
                    )
                );
            }
            Case(c) => {
                return Optional<StaticConstant>.Value(
                    _record(
                        "reflect.Case",
                        [
                            ("name", StaticConstant.String(c.name)),
                            ("value", StaticConstant.Int(c.value)),
                            ("index", StaticConstant.Int(c.index as long)),
                            ("is_last", StaticConstant.Bool(c.index + 1 == c.count))
                        ]
                    )
                );
            }
            Function(f) => {
                return Optional<StaticConstant>.Value(
                    _record("reflect.Function", [("name", StaticConstant.String(demangle_name(f.symbol)))])
                );
            }
            Attribute(a) => {
                var fields = Array<(String, StaticConstant)>();
                for (var (field, value) in a.fields) {
                    var constant = value.debug_constant();
                    if (constant.is_value()) {
                        fields.append((field, constant.value()));
                    }
                }
                return Optional<StaticConstant>.Value(
                    StaticConstant.Record(RecordStaticConstant(demangle_name(a.ty), fields))
                );
            }
            List(_) => {
                return Optional<StaticConstant>.Empty;
            }
        }
    }

    # What the value is, for messages.
    kind(): String {
        match (this) {
            Int(_) => {
                return "integer";
            }
            Float(_) => {
                return "floating-point number";
            }
            Bool(_) => {
                return "bool";
            }
            Text(_) => {
                return "string";
            }
            Case(_) => {
                return "enum case";
            }
            Member(_) => {
                return "member";
            }
            Function(_) => {
                return "function";
            }
            List(_) => {
                return "list";
            }
            Attribute(_) => {
                return "attribute";
            }
        }
    }

    # `kind` with its article: "an enum case".
    kind_with_article(): String {
        var k = kind();
        var first = k.substr_bytes(0, 1);
        var article = (first == "a" or first == "e" or first == "i" or first == "o" or first == "u") ? "an" : "a";
        return $"{article} {k}";
    }

    # The value as `reflect.print` and an interpolated string show it.
    display(): String {
        match (this) {
            Int(value) => {
                return $"{value}";
            }
            Float(value) => {
                return display_float(value);
            }
            Bool(value) => {
                return value ? "true" : "false";
            }
            Text(value) => {
                return value;
            }
            Case(c) => {
                return $"{display_name(c.enumeration.display())}.{c.name}";
            }
            Member(m) => {
                return m.name;
            }
            Function(f) => {
                return demangle_name(f.symbol);
            }
            List(items) => {
                var shown = Array<String>();
                for (var item in items) {
                    shown.append(item.display());
                }
                return $"[{", ".join(shown)}]";
            }
            Attribute(a) => {
                var fields = Array<String>();
                for (var (name, value) in a.fields) {
                    fields.append($"{name} = {value.quoted()}");
                }
                return $"{demangle_name(a.ty)}({", ".join(fields)})";
            }
        }
    }

    # The value as a literal in source, for `--emit-static`; none for what
    # emitted code cannot hold.
    source(): String? {
        match (this) {
            Int(value) => {
                return Optional<String>.Value($"{value}");
            }
            Float(value) => {
                var shown = display_float(value);
                if (!shown.contains(".") and !shown.contains("e") and !shown.contains("N") and !shown.contains("inf")) {
                    shown = shown + ".0";
                }
                return Optional<String>.Value(shown);
            }
            Bool(value) => {
                return Optional<String>.Value(value ? "true" : "false");
            }
            Text(value) => {
                return Optional<String>.Value(string_literal(value));
            }
            Case(c) => {
                if (c.is_value) {
                    return Optional<String>.Value($"{display_name(c.enumeration.display())}.{c.name}");
                }
                return Optional<String>.Empty;
            }
            else => {
                return Optional<String>.Empty;
            }
        }
    }

    # The value as the text of an interpolated string, where it prints the
    # same as its hole would.
    interpolated(): String? {
        match (this) {
            Int(value) => {
                return Optional<String>.Value($"{value}");
            }
            Bool(value) => {
                return Optional<String>.Value(value ? "true" : "false");
            }
            Text(value) => {
                return Optional<String>.Value(escape_text(value, true));
            }
            else => {
                return Optional<String>.Empty;
            }
        }
    }

    # `display`, with a string in quotes.
    quoted(): String {
        if (this is Text(value)) {
            return _debug_string(value);
        }
        return display();
    }

    # Whether this equals `other`, or none when they cannot be compared.
    equals(other: _CtValue): bool? {
        match (this) {
            Int(a) => {
                if (other is Int(b)) {
                    return Optional<bool>.Value(a == b);
                }
                if (other is Float(b)) {
                    return Optional<bool>.Value(a as double == b);
                }
            }
            Float(a) => {
                if (other is Float(b)) {
                    return Optional<bool>.Value(a == b);
                }
                if (other is Int(b)) {
                    return Optional<bool>.Value(b as double == a);
                }
            }
            Bool(a) => {
                if (other is Bool(b)) {
                    return Optional<bool>.Value(a == b);
                }
            }
            Text(a) => {
                if (other is Text(b)) {
                    return Optional<bool>.Value(a == b);
                }
            }
            Case(a) => {
                if (other is Case(b)) {
                    return Optional<bool>.Value(a.enumeration.name == b.enumeration.name and a.value == b.value);
                }
            }
            else => {}
        }
        return Optional<bool>.Empty;
    }

    # The attributes of a member, case or function, and their file.
    attributes(): (ast.Attribute[], uint)? {
        match (this) {
            Member(m) => {
                return Optional<(ast.Attribute[], uint)>.Value((m.attributes, m.file));
            }
            Case(c) => {
                return Optional<(ast.Attribute[], uint)>.Value((c.attributes, c.file));
            }
            Function(f) => {
                return Optional<(ast.Attribute[], uint)>.Value((f.attributes, f.file));
            }
            else => {
                return Optional<(ast.Attribute[], uint)>.Empty;
            }
        }
    }
}

_record(name: String, fields: Array<(String, StaticConstant)>): StaticConstant {
    return StaticConstant.Record(RecordStaticConstant(name, fields));
}

## `text` quoted for display: in double quotes, with quotes, backslashes
## and control characters escaped.
_debug_string(text: String): String {
    var out = StringBuilder();
    out.append("\"");
    ulong i = 0;
    while (i < text.size) {
        var b = text.byte_at(i);
        if (b == '"') {
            out.append("\\\"");
        } else if (b == '\\') {
            out.append("\\\\");
        } else if (b == '\n') {
            out.append("\\n");
        } else if (b == '\r') {
            out.append("\\r");
        } else if (b == '\t') {
            out.append("\\t");
        } else if (b == 0) {
            out.append("\\0");
        } else if (b < 32 or b == 127) {
            out.append("\\u{" + _hex(b as ulong) + "}");
        } else {
            out.append(text.substr_bytes(i, 1));
        }
        i += 1;
    }
    out.append("\"");
    return out.to_string();
}

_hex(value: ulong): String {
    var digits = "0123456789abcdef";
    if (value == 0) {
        return "0";
    }
    var out = "";
    var v = value;
    while (v > 0) {
        out = digits.substr_bytes(v % 16, 1) + out;
        v = v / 16;
    }
    return out;
}

## How many characters (not bytes) `text` holds.
_char_count(text: String): long {
    long count = 0;
    ulong i = 0;
    while (i < text.size) {
        if ((text.byte_at(i) & 0xC0) != 0x80) {
            count += 1;
        }
        i += 1;
    }
    return count;
}

_as_float(value: _CtValue): double {
    match (value) {
        Int(v) => {
            return v as double;
        }
        Float(v) => {
            return v;
        }
        else => {
            return 0.0;
        }
    }
}

## Orders locations by file, then by where they start.
_compare_locs(a: Loc, b: Loc): int {
    if (a.file != b.file) {
        return a.file < b.file ? -1 : 1;
    }
    if (a.span.start != b.span.start) {
        return a.span.start < b.span.start ? -1 : 1;
    }
    return 0;
}

_int_of(value: _CtValue): long? {
    if (value is Int(v)) {
        return Optional<long>.Value(v);
    }
    return Optional<long>.Empty;
}

_text_of(value: _CtValue): String? {
    if (value is Text(v)) {
        return Optional<String>.Value(v);
    }
    return Optional<String>.Empty;
}

## The assignment `statement` is, if it is one.
_assignment_of(statement: Statement): BinaryExpression? {
    if (statement is Expression(e)) {
        if (e is Binary(node)) {
            if (node.op is Assign) {
                return Optional<BinaryExpression>.Value(node);
            }
        }
    }
    return Optional<BinaryExpression>.Empty;
}

_is_number(value: _CtValue): bool {
    match (value) {
        Int(_), Float(_) => {
            return true;
        }
        else => {
            return false;
        }
    }
}

_case_of(def: EnumDef, index: ulong): _CtCase {
    var c = def.cases[index];
    return _CtCase(TypeName.named(def.name), c.name, c.value, index, def.cases.count, true, c.attributes, c.loc.file);
}

## A pass's statements after its `marker`, when it emits any.
_with_stop(marker: StaticPass, items: Statement[]): Statement[] {
    if (items.count == 0) {
        return items;
    }
    var out = [Statement.StaticPass(marker)];
    out.append_all(items);
    return out;
}

_marker(loc: Loc, values: Array<(String, StaticConstant)>, header: uint?, lines: Array<(Loc, uint)>): StaticPass {
    return StaticPass(loc, true, values, header, lines);
}

## The source a `get`, `set`, `call` or `matches` placeholder becomes, its
## arguments as written (see `_Expander.fill_member` for the code it
## becomes).
_member_source(receiver: _CtValue, method: String, arguments: ast.Span[]): SourcePiece[]? {
    var out = Array<SourcePiece>();
    match (receiver) {
        Member(m) => {
            if (method == "get" and m.field.is_value()) {
                # A case's value: only a `match` can read it in source.
                if (!m.enumeration.is_value() or arguments.count < 1) {
                    return Optional<SourcePiece[]>.Empty;
                }
                var enumeration = display_name(m.enumeration.value().display());
                var case = m.field.value().split(".")[0];
                var bindings = Array<String>();
                for (var i in 0..m.count) {
                    bindings.append(i == m.index ? "_pep_value" : "_");
                }
                out.append(SourcePiece.Text("match ("));
                out.append(SourcePiece.Argument(arguments[0]));
                out.append(
                    SourcePiece.Text(
                        $") {{ {enumeration}.{case}({", ".join(bindings)}) => _pep_value, else => __default<{display_name(m.ty.display())}>() }}"
                    )
                );
                return Optional<SourcePiece[]>.Value(out);
            }
            if (method == "get" and arguments.count >= 1) {
                out.append(SourcePiece.Argument(arguments[0]));
                out.append(SourcePiece.Text($".{m.name}"));
                return Optional<SourcePiece[]>.Value(out);
            }
            if (method == "set" and arguments.count >= 2) {
                out.append(SourcePiece.Argument(arguments[0]));
                out.append(SourcePiece.Text($".{m.name} = "));
                out.append(SourcePiece.Argument(arguments[1]));
                return Optional<SourcePiece[]>.Value(out);
            }
        }
        Function(f) => {
            if (method == "call") {
                out.append(SourcePiece.Text($"{demangle_name(f.symbol)}("));
                _append_arguments(out, arguments);
                out.append(SourcePiece.Text(")"));
                return Optional<SourcePiece[]>.Value(out);
            }
        }
        Case(c) => {
            var enumeration = display_name(c.enumeration.display());
            if (method == "get" and c.is_value) {
                out.append(SourcePiece.Text($"{enumeration}.{c.name}"));
                return Optional<SourcePiece[]>.Value(out);
            }
            if (method == "get") {
                out.append(SourcePiece.Text($"{enumeration}.{c.name}("));
                _append_arguments(out, arguments);
                out.append(SourcePiece.Text(")"));
                return Optional<SourcePiece[]>.Value(out);
            }
            if (method == "matches" and arguments.count >= 1) {
                var test = c.is_value ? "==" : "is";
                out.append(SourcePiece.Text("("));
                out.append(SourcePiece.Argument(arguments[0]));
                out.append(SourcePiece.Text($" {test} {enumeration}.{c.name})"));
                return Optional<SourcePiece[]>.Value(out);
            }
        }
        else => {}
    }
    return Optional<SourcePiece[]>.Empty;
}

## Appends `arguments`, separated by commas, to `out`.
_append_arguments(out: SourcePiece[], arguments: ast.Span[]) {
    for (var i in 0..arguments.count) {
        if (i > 0) {
            out.append(SourcePiece.Text(", "));
        }
        out.append(SourcePiece.Argument(arguments[i]));
    }
}

## The candidate declared in `file`, else the only one.
_prefer_file<T>(candidates: T[], file_of: (T) => uint, file: uint): T? {
    for (var c in candidates) {
        if (file_of(c) == file) {
            return Optional<T>.Value(c);
        }
    }
    if (candidates.count == 1) {
        return Optional<T>.Value(candidates[0]);
    }
    return Optional<T>.Empty;
}

# ── Expansion ───────────────────────────────────────────────────────────────

## A `for` or `while` pass being expanded: the loop's location, the pass's
## index and count, and its element.
struct _Pass {
    var loc: Loc;
    var index: ulong;
    var count: ulong;
    var element: String;

    construct(loc: Loc, index: ulong, count: ulong, element: String) {
        this.loc = loc;
        this.index = index;
        this.count = count;
        this.element = element;
    }
}

struct _Expander {
    var module: Module;
    var state: PassState;
    var context: _ExpansionContext;
    # The block's type arguments (`T` → `Point`).
    var type_map: Array<(String, TypeName)> = Array<(String, TypeName)>();
    # The file the block is written in.
    var file: uint = 0;
    # The compile-time variables, innermost scope last.
    var scopes: Array<HashMap<String, _CtValue>> = Array<HashMap<String, _CtValue>>();
    # The passes being expanded, outermost first.
    var passes: _Pass[] = Array<_Pass>();
    # What `reflect.print` wrote.
    var notes: Diagnostic[] = Array<Diagnostic>();
    # A compile-time `break` or `continue` that ran and has not yet reached
    # its loop: the statements after it are skipped.
    var jump: LoopBreakKind? = Optional<LoopBreakKind>.Empty;
    # Whether a string the block emits is lowered, as the bodies' are.
    var lowered: bool = false;
    # Writing each expansion back out as source too (`--emit-static`).
    var recording: bool = false;
    # The placeholders the statement being filled replaced, as source.
    var edits: SourceEdit[] = Array<SourceEdit>();
    # When recording, the statements emitted so far into each pass being
    # expanded, innermost last: what its `StaticPass.lines` holds.
    var lines: Array<Array<(Loc, uint)>> = Array<Array<(Loc, uint)>>();

    construct(module: Module, state: PassState, context: _ExpansionContext) {
        this.module = module;
        this.state = state;
        this.context = context;
        this.recording = state.static_recording.is_value();
    }

    # Replaces each `static` block in `block` with what it emits. An error
    # is reported, and the block emits nothing.
    expand_in(block: Block) {
        ulong i = 0;
        while (i < block.items.count) {
            match (block.items[i]) {
                Static(static_block) => {
                    var expanded = expand(static_block);
                    if (expanded.is_err()) {
                        state.report(expanded.error());
                        block.items[i] = Statement.Block(_block_of(Array<Statement>()));
                    } else {
                        block.items[i] = Statement.Block(expanded.value());
                    }
                }
                Block(inner) => {
                    expand_in(inner);
                }
                Branch(branch) => {
                    expand_in(branch.if_block);
                    if (branch.else_block.is_value()) {
                        expand_in(branch.else_block.value());
                    }
                }
                While(loop) => {
                    expand_in(loop.block);
                }
                else => {}
            }
            i += 1;
        }
    }

    expand(block: StaticBlock): Result<Block, Diagnostic> {
        type_map = block.type_map;
        file = block.loc.file;
        scopes = [HashMap<String, _CtValue>()];
        passes = Array<_Pass>();
        jump = Optional<LoopBreakKind>.Empty;
        lines = Array<Array<(Loc, uint)>>();
        var text = Array<Rendered>();
        lines.append(Array<(Loc, uint)>());
        var items = run_items(block.items, text);
        var emitted = lines.pop();
        if (items.is_err()) {
            var error = items.error();
            if (!context.name.is_empty) {
                error = error.with_note(
                    $"in the static block of '{context.name}'", Optional<Location>.Value(location_of(context.loc))
                );
                error = with_requests(error);
            }
            return Result<Block, Diagnostic>.Err(error);
        }
        # A module-scope block emits nothing: its constants hold what it
        # computed.
        if (recording and !context.symbol.is_empty and block.span.end > block.span.start) {
            var written = Array<String>();
            var positions = Array<(uint, ulong, ulong)>();
            write_lines([Rendered.Braced(text, Optional<uint>.Empty)], 0, written, positions);
            if (written.count == 0) {
                written.append("{}");
            }
            var type_arguments = Array<(String, String)>();
            for (var (param, ty) in block.type_map) {
                type_arguments.append((param, display_name(ty.display_stored())));
            }
            state.static_recording.value().expansions.append(
                StaticExpansion(block.loc, block.span, type_arguments, written, positions)
            );
        }
        # The statements emitted outside any pass, for the debugger.
        if (emitted.count == 0) {
            return Result<Block, Diagnostic>.Ok(_block_of(items.value()));
        }
        var marker = StaticPass(block.loc, false, Array<(String, StaticConstant)>(), Optional<uint>.Empty, emitted);
        return Result<Block, Diagnostic>.Ok(_block_of(_with_stop(marker, items.value())));
    }

    # A new id for a statement or header of the expansion, when recording.
    new_id(): uint? {
        if (!recording) {
            return Optional<uint>.Empty;
        }
        return Optional<uint>.Value(state.static_recording.value().next_id());
    }

    # Records that the statement written at `span` was emitted as `id`.
    emitted_as(span: ast.Span, id: uint?) {
        if (id.is_value() and lines.count > 0) {
            lines.last().append((at(span), id.value()));
        }
    }

    # When recording, the source at `span` (an emitted statement, or a
    # runtime `if`'s condition) with the placeholders just filled in
    # replaced and the types named; lines indented relative to the first.
    source_of(span: ast.Span, statement: bool): String[]? {
        if (!recording) {
            return Optional<String[]>.Empty;
        }
        var taken = edits;
        edits = Array<SourceEdit>();
        if (file as ulong >= state.sources.count) {
            return Optional<String[]>.Empty;
        }
        var source = state.sources[file as ulong].text;
        if (span.end > source.size) {
            return Optional<String[]>.Empty;
        }
        var names = Array<(String, String)>();
        for (var (spelled, ty) in member_types()) {
            names.append((spelled, display_name(ty.display_stored())));
        }
        for (var (param, ty) in type_map) {
            names.append((param, display_name(ty.display_stored())));
        }
        if (statement) {
            return Optional<String[]>.Value(statement_source(source, span, taken, names));
        }
        return Optional<String[]>.Value([expression_source(source, span, taken, names)]);
    }

    # `error` with a note for each specialization that led to the one being
    # expanded, back to the code that is not generic.
    with_requests(error: Diagnostic): Diagnostic {
        var out = error;
        var name = parse_type_string(context.symbol).to_string();
        var shown = Array<String>();
        while (true) {
            var request = module.spec_requests.try_get(name);
            if (!request.is_value()) {
                break;
            }
            var by = request.value().by;
            if (shown.contains(by) or shown.count >= _MAX_SPECIALIZATION_DEPTH) {
                break;
            }
            shown.append(by);
            out = out.with_note(
                $"'{demangle(name)}' is used by '{demangle(by)}' here",
                Optional<Location>.Value(location_of(request.value().loc))
            );
            name = by;
        }
        return out;
    }

    at(span: ast.Span): Loc {
        return Loc.at(file, span);
    }

    # The error `message` at `span`, with a note for each pass expanding.
    error(message: String, span: ast.Span): Diagnostic {
        return with_passes(error_at(message, at(span)));
    }

    with_passes(diagnostic: Diagnostic): Diagnostic {
        var out = diagnostic;
        ulong i = passes.count;
        while (i > 0) {
            i -= 1;
            var p = passes[i];
            var note = p.element.is_empty ?
                $"in iteration {p.index + 1} of the compile-time 'while'" :
                $"in pass {p.index + 1} of {p.count} ({p.element})";
            out = out.with_note(note, Optional<Location>.Value(location_of(p.loc)));
        }
        return out;
    }

    push_scope() {
        scopes.append(HashMap<String, _CtValue>());
    }

    pop_scope() {
        scopes.pop();
    }

    scoped_items(items: StaticItem[], text: Rendered[]): Result<Statement[], Diagnostic> {
        push_scope();
        var out = run_items(items, text);
        pop_scope();
        return out;
    }

    # Expands `items`, and when recording adds their source to `text`.
    run_items(items: StaticItem[], text: Rendered[]): Result<Statement[], Diagnostic> {
        var out = Array<Statement>();
        for (var item in items) {
            match (item) {
                For(node) => {
                    var iterable = evaluate(node.iterable);
                    if (iterable.is_err()) {
                        return Result<Statement[], Diagnostic>.Err(iterable.error());
                    }
                    var list = Array<_CtValue>();
                    match (iterable.value()) {
                        List(elements) => {
                            list = elements;
                        }
                        else => {
                            return Result<Statement[], Diagnostic>.Err(
                                error(
                                    $"a 'for' in a 'static' block needs a compile-time list, such as 'reflect.properties<T>()'; this is a {iterable.value().kind()}",
                                    node.iterable.span()
                                )
                            );
                        }
                    }
                    ulong index = 0;
                    while (index < list.count) {
                        var element = list[index];
                        passes.append(_Pass(node.loc, index, list.count, $"{element.kind()} '{element.display()}'"));
                        var pass_text = Array<Rendered>();
                        var header = new_id();
                        lines.append(Array<(Loc, uint)>());
                        push_scope();
                        scopes.last()[node.name] = element;
                        var values = debug_values();
                        var pass = run_items(node.body, pass_text);
                        pop_scope();
                        var pass_lines = lines.pop();
                        passes.pop();
                        if (pass.is_err()) {
                            return pass;
                        }
                        out.append(
                            Statement.Block(
                                _block_of(_with_stop(_marker(node.loc, values, header, pass_lines), pass.value()))
                            )
                        );
                        text.append(Rendered.Braced(pass_text, header));
                        var jumped = jump;
                        jump = Optional<LoopBreakKind>.Empty;
                        if (jumped.is_value() and jumped.value() is Break) {
                            break;
                        }
                        index += 1;
                    }
                }
                While(node) => {
                    long iteration = 0;
                    while (true) {
                        var condition = evaluate(node.condition);
                        if (condition.is_err()) {
                            return Result<Statement[], Diagnostic>.Err(condition.error());
                        }
                        bool keep_going = false;
                        match (condition.value()) {
                            Bool(value) => {
                                keep_going = value;
                            }
                            else => {
                                return Result<Statement[], Diagnostic>.Err(
                                    error(
                                        $"a compile-time condition must be a 'bool', not a {condition.value().kind()}",
                                        node.condition.span()
                                    )
                                );
                            }
                        }
                        if (!keep_going) {
                            break;
                        }
                        if (iteration == _MAX_ITERATIONS) {
                            return Result<Statement[], Diagnostic>.Err(
                                with_passes(
                                    error_at(
                                        $"a compile-time 'while' ran {_MAX_ITERATIONS} times; is its condition ever false?",
                                        node.loc
                                    )
                                )
                            );
                        }
                        passes.append(_Pass(node.loc, iteration as ulong, 0, ""));
                        var values = debug_values();
                        var pass_text = Array<Rendered>();
                        var header = new_id();
                        lines.append(Array<(Loc, uint)>());
                        var pass = scoped_items(node.body, pass_text);
                        var pass_lines = lines.pop();
                        passes.pop();
                        if (pass.is_err()) {
                            return pass;
                        }
                        if (pass.value().count > 0) {
                            out.append(
                                Statement.Block(
                                    _block_of(_with_stop(_marker(node.loc, values, header, pass_lines), pass.value()))
                                )
                            );
                            text.append(Rendered.Braced(pass_text, header));
                        }
                        iteration += 1;
                        var jumped = jump;
                        jump = Optional<LoopBreakKind>.Empty;
                        if (jumped.is_value() and jumped.value() is Break) {
                            break;
                        }
                    }
                }
                Jump(node) => {
                    jump = Optional<LoopBreakKind>.Value(node.kind);
                    return Result<Statement[], Diagnostic>.Ok(out);
                }
                If(node) => {
                    var condition = evaluate(node.condition);
                    if (condition.is_err()) {
                        return Result<Statement[], Diagnostic>.Err(condition.error());
                    }
                    bool taken = false;
                    match (condition.value()) {
                        Bool(value) => {
                            taken = value;
                        }
                        else => {
                            return Result<Statement[], Diagnostic>.Err(
                                error(
                                    $"a compile-time condition must be a 'bool', not a {condition.value().kind()}",
                                    node.condition.span()
                                )
                            );
                        }
                    }
                    var values = debug_values();
                    var branch_text = Array<Rendered>();
                    var header = new_id();
                    lines.append(Array<(Loc, uint)>());
                    var expanded = scoped_items(taken ? node.then_items : node.else_items, branch_text);
                    var branch_lines = lines.pop();
                    if (expanded.is_err()) {
                        return expanded;
                    }
                    out.append(
                        Statement.Block(
                            _block_of(_with_stop(_marker(node.loc, values, header, branch_lines), expanded.value()))
                        )
                    );
                    text.append(Rendered.Braced(branch_text, header));
                }
                EmitIf(node) => {
                    var condition = node.condition.copy();
                    var filled = fill_expression(condition);
                    if (filled.is_err()) {
                        return Result<Statement[], Diagnostic>.Err(filled.error());
                    }
                    var condition_text = source_of(node.span, false);
                    var id = new_id();
                    emitted_as(node.span, id);
                    var then_text = Array<Rendered>();
                    var else_text = Array<Rendered>();
                    var then_items = scoped_items(node.then_items, then_text);
                    if (then_items.is_err()) {
                        return then_items;
                    }
                    var else_block = Optional<Block>.Empty;
                    if (node.else_items.count > 0) {
                        var else_items = scoped_items(node.else_items, else_text);
                        if (else_items.is_err()) {
                            return else_items;
                        }
                        else_block = Optional<Block>.Value(_block_of(else_items.value()));
                    }
                    out.append(Statement.Branch(Branch(filled.value(), _block_of(then_items.value()), else_block)));
                    if (condition_text.is_value()) {
                        var else_rendered = node.else_items.count > 0 ?
                            Optional<Rendered[]>.Value(else_text) :
                            Optional<Rendered[]>.Empty;
                        text.append(
                            Rendered.Conditional(
                                RenderedBranch("\n".join(condition_text.value()), then_text, else_rendered, id)
                            )
                        );
                    }
                }
                Block(inner) => {
                    var inner_text = Array<Rendered>();
                    var expanded = scoped_items(inner, inner_text);
                    if (expanded.is_err()) {
                        return expanded;
                    }
                    out.append(Statement.Block(_block_of(expanded.value())));
                    text.append(Rendered.Braced(inner_text, Optional<uint>.Empty));
                }
                Var(node) => {
                    var value = evaluate(node.value);
                    if (value.is_err()) {
                        return Result<Statement[], Diagnostic>.Err(value.error());
                    }
                    scopes.last()[node.name] = value.value();
                }
                Evaluate(e) => {
                    var value = evaluate(e);
                    if (value.is_err()) {
                        return Result<Statement[], Diagnostic>.Err(value.error());
                    }
                }
                Emit(statement, span) => {
                    var filled = fill_statement(statement.copy());
                    if (filled.is_err()) {
                        return Result<Statement[], Diagnostic>.Err(filled.error());
                    }
                    out.append(filled.value());
                    var id = new_id();
                    emitted_as(span, id);
                    var written = source_of(span, true);
                    if (written.is_value()) {
                        text.append(Rendered.Code(written.value(), id));
                    }
                }
            }
            if (jump.is_value()) {
                break;
            }
        }
        return Result<Statement[], Diagnostic>.Ok(out);
    }

    # The compile-time variables in scope and their values, as the debugger
    # shows them, sorted by name.
    debug_values(): Array<(String, StaticConstant)> {
        # An inner scope's name hides an outer one's, even when it has
        # nothing to show (a list).
        var seen = HashSet<String>();
        var values = Array<(String, StaticConstant)>();
        ulong s = scopes.count;
        while (s > 0) {
            s -= 1;
            for (var (name, value) in scopes[s]) {
                if (!seen.contains(name)) {
                    seen.insert(name);
                    var constant = value.debug_constant();
                    if (constant.is_value()) {
                        values.append((name, constant.value()));
                    }
                }
            }
        }
        values.sort((a: (String, StaticConstant), b: (String, StaticConstant)) => {
            var (x, _) = a;
            var (y, _) = b;
            return _compare_bytes(x, y) as int;
        });
        return values;
    }

    # The `x.Type` types of the members in scope.
    member_types(): Array<(String, TypeName)> {
        var types = Array<(String, TypeName)>();
        for (var scope in scopes) {
            for (var (name, value) in scope) {
                if (value is Member(member)) {
                    var spelled = $"{name}.Type";
                    var kept = Array<(String, TypeName)>();
                    for (var (s, t) in types) {
                        if (s != spelled) {
                            kept.append((s, t));
                        }
                    }
                    kept.append((spelled, member.ty.copy()));
                    types = kept;
                }
            }
        }
        return types;
    }

    # Fills in an emitted statement: the members' types, then the
    # placeholders.
    fill_statement(statement: Statement): Result<Statement, Diagnostic> {
        edits = Array<SourceEdit>();
        var types = member_types();
        if (types.count > 0) {
            replace_statement_types(statement, types);
        }
        var filler = _Filler(this);
        var out = rewrite_statement(statement, filler);
        if (filler.error.is_value()) {
            return Result<Statement, Diagnostic>.Err(filler.error.value());
        }
        return Result<Statement, Diagnostic>.Ok(out);
    }

    fill_expression(e: Expression): Result<Expression, Diagnostic> {
        var filled = fill_statement(Statement.Expression(e));
        if (filled.is_err()) {
            return Result<Expression, Diagnostic>.Err(filled.error());
        }
        if (filled.value() is Expression(value)) {
            return Result<Expression, Diagnostic>.Ok(value);
        }
        return Result<Expression, Diagnostic>.Ok(e);
    }

    # What replaces a placeholder: `e` itself when it is not one.
    fill(e: Expression): Result<Expression, Diagnostic> {
        match (e) {
            StaticValue(placeholder) => {
                var value = evaluate(placeholder.expr);
                if (value.is_err()) {
                    return Result<Expression, Diagnostic>.Err(value.error());
                }
                if (recording) {
                    var written = value.value().source();
                    if (written.is_value()) {
                        edits.append(
                            SourceEdit(
                                placeholder.expr.extent(),
                                [SourcePiece.Text(written.value())],
                                value.value().interpolated()
                            )
                        );
                    }
                }
                return emitted(value.value(), placeholder.expr, placeholder.loc);
            }
            StaticMember(placeholder) => {
                var evaluated = evaluate(placeholder.member);
                if (evaluated.is_err()) {
                    return Result<Expression, Diagnostic>.Err(evaluated.error());
                }
                if (recording) {
                    var pieces = _member_source(evaluated.value(), placeholder.method, placeholder.argument_spans);
                    if (pieces.is_value()) {
                        edits.append(SourceEdit(placeholder.span, pieces.value()));
                    }
                }
                return fill_member(evaluated.value(), placeholder.method, placeholder.args, placeholder.loc);
            }
            else => {
                return Result<Expression, Diagnostic>.Ok(e);
            }
        }
    }

    arity_error(method: String, want: ulong, have: ulong, span: ast.Span): Diagnostic {
        var s = want == 1 ? "" : "s";
        return error($"'{method}' takes {want} argument{s}, have {have}", span);
    }

    # `receiver.method(args)` in emitted code, a placeholder filled in.
    fill_member(receiver: _CtValue, method: String, args: Expression[], loc: Loc): Result<Expression, Diagnostic> {
        var span = loc.span;
        match (receiver) {
            Member(m) => {
                if (method == "get") {
                    if (args.count != 1) {
                        return Result<Expression, Diagnostic>.Err(arity_error(method, 1, args.count, span));
                    }
                    var field = m.field.is_value() ? m.field.value() : m.name;
                    return Result<Expression, Diagnostic>.Ok(
                        Expression.MemberRef(MemberRefExpression(args[0], field, loc))
                    );
                }
                if (method == "set" and m.field.is_value()) {
                    return Result<Expression, Diagnostic>.Err(
                        error($"'set' cannot change value '{m.name}': a case's values are fixed once made", span)
                    );
                }
                if (method == "set") {
                    if (args.count != 2) {
                        return Result<Expression, Diagnostic>.Err(arity_error(method, 2, args.count, span));
                    }
                    var target = Expression.MemberRef(MemberRefExpression(args[0], m.name, loc));
                    return Result<Expression, Diagnostic>.Ok(
                        Expression.Binary(BinaryExpression(target, args[1], BinaryOp.Assign, loc))
                    );
                }
            }
            Function(f) => {
                if (method == "call") {
                    return Result<Expression, Diagnostic>.Ok(
                        Expression.FunctionCall(FunctionCallExpression(f.symbol, args, loc))
                    );
                }
            }
            Case(c) => {
                if (method == "get" and c.is_value) {
                    if (args.count != 0) {
                        return Result<Expression, Diagnostic>.Err(arity_error(method, 0, args.count, span));
                    }
                    return Result<Expression, Diagnostic>.Ok(_case_value(c));
                }
                if (method == "matches") {
                    if (args.count != 1) {
                        return Result<Expression, Diagnostic>.Err(arity_error(method, 1, args.count, span));
                    }
                    var subject = args[0];
                    Expression test = c.is_value ? _case_value(c) : Expression.IntLiteral(c.value);
                    Expression lhs = c.is_value ?
                        subject :
                        Expression.MemberRef(MemberRefExpression(subject, TAG_FIELD, loc));
                    return Result<Expression, Diagnostic>.Ok(
                        Expression.Binary(BinaryExpression(lhs, test, BinaryOp.Equal, loc))
                    );
                }
                if (method == "get") {
                    # `Shape.Circle(r)`: the case's static method makes it.
                    if (args.count != c.values.count) {
                        var s = c.values.count == 1 ? "" : "s";
                        return Result<Expression, Diagnostic>.Err(
                            error($"'get' of case '{c.name}' takes {c.values.count} value{s}, have {args.count}", span)
                        );
                    }
                    var this_value = Expression.SymbolRef(
                        SymbolRefExpression(c.enumeration.to_string(), c.enumeration.copy(), loc)
                    );
                    return Result<Expression, Diagnostic>.Ok(
                        Expression.MethodCall(MethodCallExpression(this_value, c.name, args, loc))
                    );
                }
            }
            else => {}
        }
        return Result<Expression, Diagnostic>.Err(
            error($"no method named '{method}' on a compile-time {receiver.kind()}", span)
        );
    }

    # `value` as an expression in emitted code.
    emitted(value: _CtValue, written: ast.Expression, loc: Loc): Result<Expression, Diagnostic> {
        match (value) {
            Int(v) => {
                return Result<Expression, Diagnostic>.Ok(Expression.IntLiteral(v));
            }
            Float(v) => {
                return Result<Expression, Diagnostic>.Ok(Expression.FloatLiteral(v));
            }
            Bool(v) => {
                return Result<Expression, Diagnostic>.Ok(Expression.BoolLiteral(v));
            }
            Text(v) => {
                var literal = Expression.StringLiteral(StringLiteralExpression(v, false, loc));
                if (lowered) {
                    literal = convert_string_literal(literal);
                }
                return Result<Expression, Diagnostic>.Ok(literal);
            }
            Case(c) => {
                if (c.is_value) {
                    return Result<Expression, Diagnostic>.Ok(_case_value(c));
                }
            }
            else => {}
        }
        return Result<Expression, Diagnostic>.Err(
            error(
                $"'{written.to_string()}' is a compile-time {value.kind()}, which emitted code cannot use; emitted code can use numbers, 'bool', strings and enum cases",
                written.span()
            )
        );
    }

    # ── Evaluation ──────────────────────────────────────────────────────────

    lookup(name: String): _CtValue? {
        ulong s = scopes.count;
        while (s > 0) {
            s -= 1;
            var found = scopes[s].try_get(name);
            if (found.is_value()) {
                return found;
            }
        }
        return Optional<_CtValue>.Empty;
    }

    ok(value: _CtValue): Result<_CtValue, Diagnostic> {
        return Result<_CtValue, Diagnostic>.Ok(value);
    }

    fail(message: String, span: ast.Span): Result<_CtValue, Diagnostic> {
        return Result<_CtValue, Diagnostic>.Err(error(message, span));
    }

    evaluate(e: ast.Expression): Result<_CtValue, Diagnostic> {
        match (e) {
            Literal(literal, span) => {
                match (literal) {
                    Integer(v) => {
                        return ok(_CtValue.Int(v));
                    }
                    Float(v) => {
                        return ok(_CtValue.Float(v));
                    }
                    Bool(v) => {
                        return ok(_CtValue.Bool(v));
                    }
                    String(v) => {
                        return ok(_CtValue.Text(v));
                    }
                    Char(v) => {
                        return ok(_CtValue.Int(v as long));
                    }
                    Null => {
                        return fail("'__null' has no compile-time value", span);
                    }
                }
            }
            SymbolRef(id, span) => {
                var found = lookup(id);
                if (found.is_value()) {
                    return ok(found.value());
                }
                if (id == REFLECT) {
                    return fail("'reflect' is used through its functions, such as 'reflect.properties<T>()'", span);
                }
                if (context.runtime.contains(id)) {
                    return fail($"'{id}' is a runtime value; add it to the static block's capture list", span);
                }
                return fail($"'{display_name(id)}' has no compile-time value", span);
            }
            Unary(op, _, operand, span) => {
                var value = evaluate(operand);
                if (value.is_err()) {
                    return value;
                }
                match (value.value()) {
                    Bool(v) => {
                        if (op == "!") {
                            return ok(_CtValue.Bool(!v));
                        }
                    }
                    Int(v) => {
                        if (op == "-") {
                            return ok(_CtValue.Int(-v));
                        }
                    }
                    Float(v) => {
                        if (op == "-") {
                            return ok(_CtValue.Float(-v));
                        }
                    }
                    else => {}
                }
                return fail($"operator '{op}' cannot be applied to a compile-time {value.value().kind()}", span);
            }
            Binary(lhs, op, rhs, span) => {
                return binary(lhs, op, rhs, span);
            }
            Ternary(condition, true_expr, false_expr, span) => {
                var tested = evaluate(condition);
                if (tested.is_err()) {
                    return tested;
                }
                match (tested.value()) {
                    Bool(v) => {
                        return evaluate(v ? true_expr : false_expr);
                    }
                    else => {
                        return fail($"a compile-time condition must be a 'bool', not a {tested.value().kind()}", span);
                    }
                }
            }
            Index(lhs, rhs, span) => {
                var list = evaluate(lhs);
                if (list.is_err()) {
                    return list;
                }
                var index = evaluate(rhs);
                if (index.is_err()) {
                    return index;
                }
                if (list.value() is List(items)) {
                    if (index.value() is Int(i)) {
                        if (i >= 0 and (i as ulong) < items.count) {
                            return ok(items[i as ulong]);
                        }
                        return fail($"index {i} is out of range for a list of {items.count}", span);
                    }
                }
                return fail(
                    $"a compile-time {list.value().kind()} cannot be indexed by a {index.value().kind()}", span
                );
            }
            MemberAccess(lhs, name, name_span, _) => {
                if (lhs is SymbolRef(id, _)) {
                    if (!lookup(id).is_value()) {
                        var c = enum_case(id, name);
                        if (c.is_value()) {
                            return ok(c.value());
                        }
                    }
                }
                var value = evaluate(lhs);
                if (value.is_err()) {
                    return value;
                }
                return member(value.value(), name, name_span);
            }
            FunctionCall(function, arguments, _) => {
                return call(function, arguments);
            }
            TypeLiteral(ty) => {
                return fail($"'{ty.to_string()}' is missing '()'", ty.span);
            }
            else => {
                return fail("this expression cannot be evaluated at compile time", e.span());
            }
        }
    }

    # `E.Case` for a value enum `E`.
    enum_case(enumeration: String, name: String): _CtValue? {
        var def = find_enum(enumeration);
        if (!def.is_value()) {
            return Optional<_CtValue>.Empty;
        }
        ulong i = 0;
        while (i < def.value().cases.count) {
            if (def.value().cases[i].name == name) {
                return Optional<_CtValue>.Value(_CtValue.Case(_case_of(def.value(), i)));
            }
            i += 1;
        }
        return Optional<_CtValue>.Empty;
    }

    find_enum(name: String): EnumDef? {
        return _find_enum(module, name, file);
    }

    condition(e: ast.Expression): Result<bool, Diagnostic> {
        var value = evaluate(e);
        if (value.is_err()) {
            return Result<bool, Diagnostic>.Err(value.error());
        }
        if (value.value() is Bool(v)) {
            return Result<bool, Diagnostic>.Ok(v);
        }
        return Result<bool, Diagnostic>.Err(
            error($"a compile-time condition must be a 'bool', not a {value.value().kind()}", e.span())
        );
    }

    binary(lhs: ast.Expression, op: String, rhs: ast.Expression, span: ast.Span): Result<_CtValue, Diagnostic> {
        if (op == "=" or op == "+=" or op == "-=" or op == "*=" or op == "/=" or op == "%=") {
            var arithmetic = op.substr_bytes(0, op.size - 1);
            var id = "";
            match (lhs) {
                SymbolRef(name, _) => {
                    id = name;
                }
                else => {
                    return fail("only a compile-time variable can be assigned in a 'static' block", lhs.span());
                }
            }
            if (!lookup(id).is_value()) {
                return evaluate(lhs);
            }
            var value = arithmetic.is_empty ? evaluate(rhs) : binary(lhs, arithmetic, rhs, span);
            if (value.is_err()) {
                return value;
            }
            ulong s = scopes.count;
            while (s > 0) {
                s -= 1;
                if (scopes[s].contains(id)) {
                    scopes[s][id] = value.value();
                    break;
                }
            }
            return value;
        }
        if (op == "&&" or op == "||" or op == "and" or op == "or") {
            var left = condition(lhs);
            if (left.is_err()) {
                return Result<_CtValue, Diagnostic>.Err(left.error());
            }
            if (left.value() == (op == "||" or op == "or")) {
                return ok(_CtValue.Bool(left.value()));
            }
            var right = condition(rhs);
            if (right.is_err()) {
                return Result<_CtValue, Diagnostic>.Err(right.error());
            }
            return ok(_CtValue.Bool(right.value()));
        }
        var evaluated_left = evaluate(lhs);
        if (evaluated_left.is_err()) {
            return evaluated_left;
        }
        var evaluated_right = evaluate(rhs);
        if (evaluated_right.is_err()) {
            return evaluated_right;
        }
        var left = evaluated_left.value();
        var right = evaluated_right.value();
        var mismatch = $"operator '{op}' cannot be applied to a compile-time {left.kind()} and {right.kind()}";
        if (op == "==" or op == "!=") {
            var same = left.equals(right);
            if (!same.is_value()) {
                return fail(mismatch, span);
            }
            return ok(_CtValue.Bool(same.value() == (op == "==")));
        }
        if (op == "<" or op == "<=" or op == ">" or op == ">=") {
            long ordering = 0;
            var left_int = _int_of(left);
            var right_int = _int_of(right);
            var left_text = _text_of(left);
            var right_text = _text_of(right);
            if (left_int.is_value() and right_int.is_value()) {
                var a = left_int.value();
                var b = right_int.value();
                ordering = a < b ? -1 : (a > b ? 1 : 0);
            } else if (left_text.is_value() and right_text.is_value()) {
                ordering = _compare_bytes(left_text.value(), right_text.value());
            } else if (_is_number(left) and _is_number(right)) {
                var a = _as_float(left);
                var b = _as_float(right);
                ordering = a < b ? -1 : (a > b ? 1 : 0);
            } else {
                return fail(mismatch, span);
            }
            bool result = false;
            match (op) {
                "<" => {
                    result = ordering < 0;
                }
                "<=" => {
                    result = ordering <= 0;
                }
                ">" => {
                    result = ordering > 0;
                }
                else => {
                    result = ordering >= 0;
                }
            }
            return ok(_CtValue.Bool(result));
        }
        if (op == "+" or op == "-" or op == "*" or op == "/" or op == "%") {
            var left_text = _text_of(left);
            var right_text = _text_of(right);
            if (op == "+" and left_text.is_value() and right_text.is_value()) {
                return ok(_CtValue.Text(left_text.value() + right_text.value()));
            }
            var left_int = _int_of(left);
            var right_int = _int_of(right);
            if (left_int.is_value() and right_int.is_value()) {
                var a = left_int.value();
                var b = right_int.value();
                var result = Optional<long>.Empty;
                match (op) {
                    "+" => {
                        result = a.checked_add(b);
                    }
                    "-" => {
                        result = a.checked_sub(b);
                    }
                    "*" => {
                        result = a.checked_mul(b);
                    }
                    "/" => {
                        if (b != 0 and !(a == -9223372036854775807 - 1 and b == -1)) {
                            result = Optional<long>.Value(a / b);
                        }
                    }
                    else => {
                        if (b != 0 and !(a == -9223372036854775807 - 1 and b == -1)) {
                            result = Optional<long>.Value(a % b);
                        }
                    }
                }
                if (result.is_value()) {
                    return ok(_CtValue.Int(result.value()));
                }
                if (b == 0 and (op == "/" or op == "%")) {
                    return fail("division by zero in a 'static' block", span);
                }
                return fail("integer overflow in a 'static' block", span);
            }
            if (_is_number(left) and _is_number(right)) {
                var a = _as_float(left);
                var b = _as_float(right);
                double result = 0.0;
                match (op) {
                    "+" => {
                        result = a + b;
                    }
                    "-" => {
                        result = a - b;
                    }
                    "*" => {
                        result = a * b;
                    }
                    "/" => {
                        result = a / b;
                    }
                    else => {
                        result = _fmod(a, b);
                    }
                }
                return ok(_CtValue.Float(result));
            }
            return fail(mismatch, span);
        }
        return fail($"operator '{op}' is not supported in a 'static' block", span);
    }

    # `value.name`.
    member(value: _CtValue, name: String, span: ast.Span): Result<_CtValue, Diagnostic> {
        var found = Optional<_CtValue>.Empty;
        match (value) {
            Member(m) => {
                match (name) {
                    "name" => {
                        found = Optional<_CtValue>.Value(_CtValue.Text(m.name));
                    }
                    "index" => {
                        found = Optional<_CtValue>.Value(_CtValue.Int(m.index as long));
                    }
                    "is_last" => {
                        found = Optional<_CtValue>.Value(_CtValue.Bool(m.index + 1 == m.count));
                    }
                    "type_name" => {
                        found = Optional<_CtValue>.Value(_CtValue.Text(display_name(m.ty.display_stored())));
                    }
                    "is_const" => {
                        found = Optional<_CtValue>.Value(_CtValue.Bool(m.is_const));
                    }
                    "is_property" => {
                        found = Optional<_CtValue>.Value(_CtValue.Bool(m.is_property));
                    }
                    else => {}
                }
            }
            Case(c) => {
                match (name) {
                    "name" => {
                        found = Optional<_CtValue>.Value(_CtValue.Text(c.name));
                    }
                    "value" => {
                        found = Optional<_CtValue>.Value(_CtValue.Int(c.value));
                    }
                    "index" => {
                        found = Optional<_CtValue>.Value(_CtValue.Int(c.index as long));
                    }
                    "is_last" => {
                        found = Optional<_CtValue>.Value(_CtValue.Bool(c.index + 1 == c.count));
                    }
                    "values" => {
                        found = Optional<_CtValue>.Value(_CtValue.List(c.values.copy()));
                    }
                    else => {}
                }
            }
            Function(f) => {
                if (name == "name") {
                    found = Optional<_CtValue>.Value(_CtValue.Text(demangle_name(f.symbol)));
                }
            }
            List(items) => {
                if (name == "count") {
                    found = Optional<_CtValue>.Value(_CtValue.Int(items.count as long));
                } else if (name == "is_empty") {
                    found = Optional<_CtValue>.Value(_CtValue.Bool(items.count == 0));
                }
            }
            Text(s) => {
                if (name == "length") {
                    found = Optional<_CtValue>.Value(_CtValue.Int(_char_count(s)));
                } else if (name == "is_empty") {
                    found = Optional<_CtValue>.Value(_CtValue.Bool(s.is_empty));
                }
            }
            Attribute(a) => {
                for (var (field, v) in a.fields) {
                    if (field == name) {
                        found = Optional<_CtValue>.Value(v);
                        break;
                    }
                }
            }
            else => {}
        }
        if (found.is_value()) {
            return ok(found.value());
        }
        var what = $"compile-time {value.kind()}";
        if (value is Attribute(a)) {
            what = $"attribute '{demangle_name(a.ty)}'";
        }
        return fail($"no member named '{name}' in {what}", span);
    }

    # The type `ty` names in the block: its type arguments substituted,
    # `field.Type` resolved, `T[]` spelled `Array<T>`.
    resolve_type(ty: TypeName): TypeName {
        if (ty.name.ends_with("[]")) {
            var element = ty.copy();
            element.name = ty.name.substr_bytes(0, ty.name.size - 2);
            return TypeName.with_args("Array", [resolve_type(element)]);
        }
        if (ty.name.ends_with(".Type")) {
            var variable = ty.name.substr_bytes(0, ty.name.size - 5);
            var found = lookup(variable);
            if (found.is_value()) {
                if (found.value() is Member(member)) {
                    return member.ty.copy();
                }
            }
        }
        var resolved = ty.copy();
        var args = Array<TypeName>();
        for (var t in ty.sub_types) {
            args.append(resolve_type(t));
        }
        resolved.sub_types = args;
        if (resolved.sub_types.count == 0) {
            replace_map(resolved, type_map);
        } else {
            for (var (param, arg) in type_map) {
                if (resolved.name == param) {
                    var kept = resolved.sub_types;
                    resolved = arg.copy();
                    resolved.sub_types.append_all(kept);
                }
            }
        }
        return resolved;
    }

    from_ast(ty: ast.TypeName): TypeName {
        var args = Array<TypeName>();
        for (var t in ty.generic_types) {
            args.append(from_ast(t));
        }
        return resolve_type(args.count == 0 ? TypeName.named(ty.name) : TypeName.with_args(ty.name, args));
    }

    # A call in a `static` block: a `reflect` function, a method of a
    # compile-time value, or `$"..."`'s conversion.
    call(function: ast.Expression, arguments: ast.Expression[]): Result<_CtValue, Diagnostic> {
        bool reflect_in_scope = !lookup(REFLECT).is_value();
        match (function) {
            SymbolRef(id, _) => {
                if (id == INTERPOLATE and arguments.count == 1) {
                    var value = evaluate(arguments[0]);
                    if (value.is_err()) {
                        return value;
                    }
                    return ok(_CtValue.Text(value.value().display()));
                }
            }
            MemberAccess(lhs, name, name_span, _) => {
                var spelled = ast.parse_type_text(name, name_span);
                var type_args = Array<TypeName>();
                for (var t in spelled.generic_types) {
                    type_args.append(from_ast(t));
                }
                if (lhs is SymbolRef(id, _)) {
                    if (reflect_in_scope and id == REFLECT) {
                        return reflect(spelled.name, type_args, arguments, name_span);
                    }
                }
                var receiver = evaluate(lhs);
                if (receiver.is_err()) {
                    return receiver;
                }
                return method(receiver.value(), spelled.name, type_args, arguments, name_span);
            }
            TypeLiteral(ty) => {
                var dot = ty.name.find(".");
                if (dot >= 0) {
                    var root = ty.name.substr_bytes(0, dot as ulong);
                    var name = ty.name.substr_bytes(dot as ulong + 1, ty.name.size - dot as ulong - 1);
                    var type_args = Array<TypeName>();
                    for (var t in ty.generic_types) {
                        type_args.append(from_ast(t));
                    }
                    var start = ty.span.start + root.size + 1;
                    var name_span = ast.Span(start, start + name.size);
                    if (root == REFLECT and reflect_in_scope) {
                        return reflect(name, type_args, arguments, name_span);
                    }
                    var receiver = lookup(root);
                    if (!receiver.is_value()) {
                        return fail($"'{root}' has no compile-time value", ty.span);
                    }
                    return method(receiver.value(), name, type_args, arguments, name_span);
                }
            }
            else => {}
        }
        var name = "";
        match (function) {
            SymbolRef(id, _) => {
                name = display_name(id);
            }
            TypeLiteral(ty) => {
                name = ty.to_string();
            }
            else => {
                name = function.to_string();
            }
        }
        return Result<_CtValue, Diagnostic>.Err(
            error(
                $"'{name}' cannot be called at compile time",
                function.span()
            ).with_note(
                "a 'static' block can call the 'reflect' functions and the methods of what they return; calling other functions at compile time is not supported yet",
                Optional<Location>.Empty
            )
        );
    }

    # The build option `argument` names: a compile-time string holding a
    # valid name.
    build_option_name(argument: ast.Expression): Result<String, Diagnostic> {
        var value = evaluate(argument);
        if (value.is_err()) {
            return Result<String, Diagnostic>.Err(value.error());
        }
        if (value.value() is Text(name)) {
            if (is_build_option_name(name)) {
                return Result<String, Diagnostic>.Ok(name);
            }
            return Result<String, Diagnostic>.Err(
                error(
                    $"invalid build option name '{name}'; a name is a letter or '_' followed by letters, digits and '_'",
                    argument.span()
                )
            );
        }
        return Result<String, Diagnostic>.Err(
            error($"a build option's name must be a 'String', not a {value.value().kind()}", argument.span())
        );
    }

    expect_arguments(name: String, arguments: ast.Expression[], want: ulong, span: ast.Span): Diagnostic? {
        if (arguments.count != want) {
            var s = want == 1 ? "" : "s";
            return Optional<Diagnostic>.Value(
                error($"'{name}' takes {want} argument{s}, have {arguments.count}", span)
            );
        }
        return Optional<Diagnostic>.Empty;
    }

    expect_types(name: String, type_args: TypeName[], want: ulong, span: ast.Span): Diagnostic? {
        if (type_args.count != want) {
            var names = want == 0 ? "" : (want == 1 ? "T" : "T, A");
            var s = want == 1 ? "" : "s";
            return Optional<Diagnostic>.Value(
                error($"'{name}' takes {want} type argument{s}: 'reflect.{name}<{names}>()'", span)
            );
        }
        return Optional<Diagnostic>.Empty;
    }

    # The first of the two checks that fails.
    _checks(types: Diagnostic?, arguments: Diagnostic?): Result<_CtValue, Diagnostic>? {
        if (types.is_value()) {
            return Optional<Result<_CtValue, Diagnostic>>.Value(Result<_CtValue, Diagnostic>.Err(types.value()));
        }
        if (arguments.is_value()) {
            return Optional<Result<_CtValue, Diagnostic>>.Value(Result<_CtValue, Diagnostic>.Err(arguments.value()));
        }
        return Optional<Result<_CtValue, Diagnostic>>.Empty;
    }

    # `reflect.name<type_args>(arguments)`.
    reflect(
        name: String, type_args: TypeName[], arguments: ast.Expression[], span: ast.Span
    ): Result<_CtValue, Diagnostic> {
        match (name) {
            "name" => {
                var failed = _checks(
                    expect_types(name, type_args, 1, span), expect_arguments(name, arguments, 0, span)
                );
                if (failed.is_value()) {
                    return failed.value();
                }
                return ok(_CtValue.Text(display_name(type_args[0].display_stored())));
            }
            "properties", "fields" => {
                var failed = _checks(
                    expect_types(name, type_args, 1, span), expect_arguments(name, arguments, 0, span)
                );
                if (failed.is_value()) {
                    return failed.value();
                }
                return members(type_args[0], name == "fields", span);
            }
            "cases" => {
                var failed = _checks(
                    expect_types(name, type_args, 1, span), expect_arguments(name, arguments, 0, span)
                );
                if (failed.is_value()) {
                    return failed.value();
                }
                return cases(type_args[0], span);
            }
            "functions_with" => {
                var failed = _checks(
                    expect_types(name, type_args, 1, span), expect_arguments(name, arguments, 0, span)
                );
                if (failed.is_value()) {
                    return failed.value();
                }
                var attribute = attribute_struct_named(type_args[0], span);
                if (attribute.is_err()) {
                    return Result<_CtValue, Diagnostic>.Err(attribute.error());
                }
                var functions = Array<FunctionDef>();
                for (var f in module.functions) {
                    if (f.is_generic_func) {
                        continue;
                    }
                    for (var a in f.attributes) {
                        if (names_attribute(a, f.loc.file, attribute.value())) {
                            functions.append(f);
                            break;
                        }
                    }
                }
                functions.sort((a: FunctionDef, b: FunctionDef) => _compare_locs(a.loc, b.loc));
                var out = Array<_CtValue>();
                for (var f in functions) {
                    out.append(_CtValue.Function(_CtFunction(f.name, f.attributes, f.loc.file)));
                }
                return ok(_CtValue.List(out));
            }
            "is_struct", "is_enum", "is_trait" => {
                var failed = _checks(
                    expect_types(name, type_args, 1, span), expect_arguments(name, arguments, 0, span)
                );
                if (failed.is_value()) {
                    return failed.value();
                }
                var ty = type_args[0];
                var found = find_struct(ty);
                bool is_enum = find_enum(ty.name).is_value();
                if (!is_enum and found.is_value()) {
                    var (st, _) = found.value();
                    is_enum = st.enum_cases.is_value();
                }
                if (name == "is_enum") {
                    return ok(_CtValue.Bool(is_enum));
                }
                if (name == "is_struct") {
                    return ok(_CtValue.Bool(!is_enum and found.is_value()));
                }
                for (var t in module.traits) {
                    if (t.name == ty.name) {
                        return ok(_CtValue.Bool(true));
                    }
                }
                return ok(_CtValue.Bool(false));
            }
            "is_reference" => {
                var failed = _checks(
                    expect_types(name, type_args, 1, span), expect_arguments(name, arguments, 0, span)
                );
                if (failed.is_value()) {
                    return failed.value();
                }
                var found = find_struct(type_args[0]);
                if (!found.is_value()) {
                    return ok(_CtValue.Bool(false));
                }
                var (st, _) = found.value();
                return ok(_CtValue.Bool(!has_bare_attribute(st.attributes, "Value")));
            }
            "is_same" => {
                var failed = _checks(
                    expect_types(name, type_args, 2, span), expect_arguments(name, arguments, 0, span)
                );
                if (failed.is_value()) {
                    return failed.value();
                }
                return ok(_CtValue.Bool(_canonical(type_args[0]) == _canonical(type_args[1])));
            }
            "has_attribute", "attribute" => {
                var failed = _checks(
                    expect_types(name, type_args, 2, span), expect_arguments(name, arguments, 0, span)
                );
                if (failed.is_value()) {
                    return failed.value();
                }
                var ty = type_args[0];
                var shown = display_name(ty.display());
                var found = find_struct(ty);
                if (found.is_value()) {
                    var (st, _) = found.value();
                    return attribute_of(
                        st.attributes, st.loc.file, type_args[1], name == "attribute", $"'{shown}'", span
                    );
                }
                var e = find_enum(ty.name);
                if (e.is_value()) {
                    return attribute_of(
                        e.value().attributes, e.value().loc.file, type_args[1], name == "attribute", $"'{shown}'", span
                    );
                }
                return fail($"'{shown}' is not a struct or an enum", span);
            }
            "has_build_option" => {
                var failed = _checks(
                    expect_types(name, type_args, 0, span), expect_arguments(name, arguments, 1, span)
                );
                if (failed.is_value()) {
                    return failed.value();
                }
                var option = build_option_name(arguments[0]);
                if (option.is_err()) {
                    return Result<_CtValue, Diagnostic>.Err(option.error());
                }
                return ok(_CtValue.Bool(state.target.build_options.contains(option.value())));
            }
            "build_option" => {
                var failed = expect_types(name, type_args, 0, span);
                if (failed.is_value()) {
                    return Result<_CtValue, Diagnostic>.Err(failed.value());
                }
                if (arguments.count < 1 or arguments.count > 2) {
                    return fail($"'build_option' takes 1 or 2 arguments, have {arguments.count}", span);
                }
                var option = build_option_name(arguments[0]);
                if (option.is_err()) {
                    return Result<_CtValue, Diagnostic>.Err(option.error());
                }
                var value = state.target.build_options.try_get(option.value());
                if (value.is_value()) {
                    return ok(_CtValue.Text(value.value()));
                }
                if (arguments.count == 2) {
                    var default = evaluate(arguments[1]);
                    if (default.is_err()) {
                        return default;
                    }
                    if (default.value() is Text(text)) {
                        return ok(_CtValue.Text(text));
                    }
                    return fail(
                        $"the default of a build option must be a 'String', not a {default.value().kind()}",
                        arguments[1].span()
                    );
                }
                var o = option.value();
                return Result<_CtValue, Diagnostic>.Err(
                    error(
                        $"build option '{o}' is not defined",
                        span
                    ).with_note(
                        $"define it with '-D {o}=<value>', test it with 'reflect.has_build_option', or give a default: 'reflect.build_option(\"{o}\", \"\")'",
                        Optional<Location>.Empty
                    )
                );
            }
            "print" => {
                var failed = expect_arguments(name, arguments, 1, span);
                if (failed.is_value()) {
                    return Result<_CtValue, Diagnostic>.Err(failed.value());
                }
                var value = evaluate(arguments[0]);
                if (value.is_err()) {
                    return value;
                }
                notes.append(
                    with_passes(Diagnostic.warning($"static print: {value.value().quoted()}").at(location_of(at(span))))
                );
                return ok(_CtValue.Bool(true));
            }
            "error" => {
                var failed = expect_arguments(name, arguments, 1, span);
                if (failed.is_value()) {
                    return Result<_CtValue, Diagnostic>.Err(failed.value());
                }
                var message = evaluate(arguments[0]);
                if (message.is_err()) {
                    return message;
                }
                return fail(message.value().display(), span);
            }
            "assert" => {
                var failed = expect_arguments(name, arguments, 2, span);
                if (failed.is_value()) {
                    return Result<_CtValue, Diagnostic>.Err(failed.value());
                }
                var holds = condition(arguments[0]);
                if (holds.is_err()) {
                    return Result<_CtValue, Diagnostic>.Err(holds.error());
                }
                if (holds.value()) {
                    return ok(_CtValue.Bool(true));
                }
                var message = evaluate(arguments[1]);
                if (message.is_err()) {
                    return message;
                }
                return fail(message.value().display(), arguments[0].span());
            }
            else => {
                return fail($"no function named '{name}' in 'reflect'", span);
            }
        }
    }

    # `value.name<type_args>(arguments)` on a compile-time value.
    method(
        value: _CtValue, name: String, type_args: TypeName[], arguments: ast.Expression[], span: ast.Span
    ): Result<_CtValue, Diagnostic> {
        var attributes = value.attributes();
        if ((name == "has_attribute" or name == "attribute") and attributes.is_value()) {
            if (type_args.count != 1) {
                return fail($"'{name}' takes one type argument: '{name}<A>()'", span);
            }
            var failed = expect_arguments(name, arguments, 0, span);
            if (failed.is_value()) {
                return Result<_CtValue, Diagnostic>.Err(failed.value());
            }
            var (list, file) = attributes.value();
            return attribute_of(
                list, file, type_args[0], name == "attribute", $"{value.kind()} '{value.display()}'", span
            );
        }
        var text_value = _text_of(value);
        if ((name == "starts_with" or name == "ends_with" or name == "contains") and text_value.is_value()) {
            var text = text_value.value();
            var failed = expect_arguments(name, arguments, 1, span);
            if (failed.is_value()) {
                return Result<_CtValue, Diagnostic>.Err(failed.value());
            }
            var part = evaluate(arguments[0]);
            if (part.is_err()) {
                return part;
            }
            if (part.value() is Text(p)) {
                if (name == "starts_with") {
                    return ok(_CtValue.Bool(text.starts_with(p)));
                }
                if (name == "ends_with") {
                    return ok(_CtValue.Bool(text.ends_with(p)));
                }
                return ok(_CtValue.Bool(text.contains(p)));
            }
            return fail($"'{name}' takes a string", arguments[0].span());
        }
        # At module scope, where nothing is emitted, a case's `get()` is the
        # case itself.
        if (name == "get" and arguments.count == 0) {
            if (value is Case(c)) {
                if (c.is_value) {
                    return ok(value);
                }
            }
        }
        if ((name == "get" or name == "set" or name == "call") and attributes.is_value()) {
            return fail($"'{name}' emits code, so it can be used only in a statement that uses a captured value", span);
        }
        return fail($"no method named '{name}' on a compile-time {value.kind()}", span);
    }

    # ── Reflection ──────────────────────────────────────────────────────────

    # The struct `ty` names, with the type arguments to substitute in its
    # fields when only its generic base exists yet.
    find_struct(ty: TypeName): (StructDef, Array<(String, TypeName)>)? {
        var spelled = ty.to_string();
        for (var st in module.structs) {
            if (st.name == spelled) {
                return Optional<(StructDef, Array<(String, TypeName)>)>.Value((st, Array<(String, TypeName)>()));
            }
        }
        var base = Optional<StructDef>.Empty;
        for (var st in module.structs) {
            if (st.name == ty.name and st.generic_params.count > 0) {
                base = Optional<StructDef>.Value(st);
                break;
            }
        }
        if (!base.is_value() and ty.sub_types.count == 0) {
            var candidates = Array<StructDef>();
            for (var st in module.structs) {
                if (st.generic_params.count == 0 and demangle_name(st.name) == ty.name) {
                    candidates.append(st);
                }
            }
            base = _prefer_file(candidates, (s) => s.loc.file, file);
        }
        if (!base.is_value()) {
            return Optional<(StructDef, Array<(String, TypeName)>)>.Empty;
        }
        var map = Array<(String, TypeName)>();
        ulong i = 0;
        while (i < base.value().generic_params.count and i < ty.sub_types.count) {
            map.append((base.value().generic_params[i].name, ty.sub_types[i].copy()));
            i += 1;
        }
        return Optional<(StructDef, Array<(String, TypeName)>)>.Value((base.value(), map));
    }

    members(ty: TypeName, all: bool, span: ast.Span): Result<_CtValue, Diagnostic> {
        var shown = display_name(ty.display());
        var found_struct = find_struct(ty);
        if (!found_struct.is_value()) {
            if (find_enum(ty.name).is_value()) {
                return fail($"'{shown}' is an enum; use 'reflect.cases<{shown}>()'", span);
            }
            return fail($"'{shown}' is not a struct", span);
        }
        var (st, map) = found_struct.value();
        if (st.enum_cases.is_value()) {
            return fail($"'{shown}' is an enum; use 'reflect.cases<{shown}>()'", span);
        }
        if (all and st.loc.file != file) {
            return Result<_CtValue, Diagnostic>.Err(
                error(
                    $"'fields' of '{shown}' is only available in the file that declares '{shown}'; use 'properties'",
                    span
                ).with_note($"'{shown}' declared here", Optional<Location>.Value(location_of(st.loc)))
            );
        }
        module.field_lists_read.insert(st.name);
        var found = Array<_Found>();
        var owner = demangle_name(st.ty.name);
        var properties = Array<PropertyDef>();
        for (var p in module.properties) {
            if (!p.in_trait
                and (p.owner == st.ty.name or demangle_name(p.owner) == owner)
                and p.loc.file == st.loc.file) {
                properties.append(p);
            }
        }
        for (var field in st.field_members) {
            bool synthesized = field.name.starts_with("__") and !(all and field.name.starts_with("__field_"));
            if (field.hidden or synthesized or field.name.contains(".") or (!all and field.name.starts_with("_"))) {
                continue;
            }
            var t = field.ty.copy();
            replace_map(t, map);
            bool is_property = false;
            for (var p in properties) {
                if (p.storage.is_value() and p.storage.value() == field.name and p.name == field.name) {
                    is_property = true;
                }
            }
            found.append(_Found(field.loc, field.name, t, field.is_const, is_property, field.attributes));
        }
        if (!all) {
            for (var property in properties) {
                bool known = false;
                for (var f in found) {
                    if (f.name == property.name) {
                        known = true;
                    }
                }
                if (property.name.starts_with("_") or known) {
                    continue;
                }
                var getter = Optional<FunctionDef>.Empty;
                for (var m in st.method_members) {
                    if (m.name == getter_name(property.name)) {
                        getter = Optional<FunctionDef>.Value(m);
                        break;
                    }
                }
                var t = getter.is_value() ? getter.value().ty.copy() : TypeName.auto();
                replace_map(t, map);
                var attributes = getter.is_value() ? getter.value().attributes : Array<ast.Attribute>();
                found.append(_Found(property.loc, property.name, t, !property.set.is_value(), true, attributes));
            }
        }
        found.sort((a: _Found, b: _Found) => _compare_locs(a.loc, b.loc));
        var out = Array<_CtValue>();
        ulong index = 0;
        while (index < found.count) {
            var f = found[index];
            out.append(
                _CtValue.Member(
                    _CtMember(f.name, f.ty, index, found.count, f.is_const, f.is_property, f.attributes, f.loc.file)
                )
            );
            index += 1;
        }
        return ok(_CtValue.List(out));
    }

    cases(ty: TypeName, span: ast.Span): Result<_CtValue, Diagnostic> {
        var def = find_enum(ty.name);
        if (def.is_value()) {
            var out = Array<_CtValue>();
            ulong i = 0;
            while (i < def.value().cases.count) {
                out.append(_CtValue.Case(_case_of(def.value(), i)));
                i += 1;
            }
            return ok(_CtValue.List(out));
        }
        var found = find_struct(ty);
        if (found.is_value()) {
            var (st, map) = found.value();
            if (st.enum_cases.is_value()) {
                var cases = st.enum_cases.value();
                var out = Array<_CtValue>();
                ulong index = 0;
                while (index < cases.count) {
                    var c = cases[index];
                    var made = _CtCase(ty.copy(), c.name, c.value, index, cases.count, false, c.attributes, c.loc.file);
                    ulong v = 0;
                    while (v < c.payload.count) {
                        var (value_name, value_loc) = c.payload[v];
                        var field = payload_field(c.name, value_name);
                        var t = TypeName.auto();
                        for (var f in st.field_members) {
                            if (f.name == field) {
                                t = f.ty.copy();
                                break;
                            }
                        }
                        replace_map(t, map);
                        var m = _CtMember(
                            value_name, t, v, c.payload.count, true, false, Array<ast.Attribute>(), value_loc.file
                        );
                        m.field = Optional<String>.Value(field);
                        m.enumeration = Optional<TypeName>.Value(ty.copy());
                        made.values.append(_CtValue.Member(m));
                        v += 1;
                    }
                    out.append(_CtValue.Case(made));
                    index += 1;
                }
                return ok(_CtValue.List(out));
            }
        }
        return fail($"'{display_name(ty.display())}' is not an enum", span);
    }

    # The `[Attribute]` struct `ty` names, or the name of a built-in
    # attribute.
    attribute_struct_named(ty: TypeName, span: ast.Span): Result<_AttributeName, Diagnostic> {
        var found = _find_attribute_struct(module, ty.name, file);
        if (found.is_value() and !_is_built_in(found.value())) {
            return Result<_AttributeName, Diagnostic>.Ok(_AttributeName(found.value().name, false, false));
        }
        var base = ty.name;
        var dot = ty.name.rfind(".");
        if (dot >= 0) {
            base = ty.name.substr_bytes(dot as ulong + 1, ty.name.size - dot as ulong - 1);
        }
        if (_is_built_in_name(base)) {
            return Result<_AttributeName, Diagnostic>.Ok(_AttributeName(base, true, found.is_value()));
        }
        return Result<_AttributeName, Diagnostic>.Err(
            error(
                $"'{display_name(ty.display())}' is not an attribute; an attribute is a struct marked '[Attribute]'",
                span
            )
        );
    }

    # Whether `attribute`, written in `file`, is an `A`.
    names_attribute(attribute: ast.Attribute, in_file: uint, wanted: _AttributeName): bool {
        var name = attribute_name(attribute);
        if (!name.is_value()) {
            return false;
        }
        var found = _find_attribute_struct(module, name.value(), in_file);
        if (wanted.built_in) {
            return name.value() == wanted.name and (!found.is_value() or _is_built_in(found.value()));
        }
        return found.is_value() and found.value().name == wanted.name;
    }

    # `has_attribute<A>()` or `attribute<A>()` over `attributes`, written in
    # `in_file`.
    attribute_of(
        attributes: ast.Attribute[], in_file: uint, attribute: TypeName, value: bool, what: String, span: ast.Span
    ): Result<_CtValue, Diagnostic> {
        var wanted = attribute_struct_named(attribute, span);
        if (wanted.is_err()) {
            return Result<_CtValue, Diagnostic>.Err(wanted.error());
        }
        var found = Optional<ast.Attribute>.Empty;
        for (var a in attributes) {
            if (names_attribute(a, in_file, wanted.value())) {
                found = Optional<ast.Attribute>.Value(a);
                break;
            }
        }
        if (!value) {
            return ok(_CtValue.Bool(found.is_value()));
        }
        var shown = display_name(attribute.display());
        if (!found.is_value()) {
            return fail($"{what} has no attribute '{shown}'; test it with 'has_attribute<{shown}>()' first", span);
        }
        var w = wanted.value();
        Result<_CtValue, Diagnostic> made = Result<_CtValue, Diagnostic>.Ok(_CtValue.Bool(false));
        if (!w.built_in) {
            made = _attribute_value(module, found.value(), in_file);
        } else if (w.declared) {
            made = _built_in_value(module, w.name, found.value(), in_file);
        } else {
            return fail($"built-in attribute '{w.name}' is not declared in the runtime, so it has no value", span);
        }
        if (made.is_err()) {
            return Result<_CtValue, Diagnostic>.Err(with_passes(made.error()));
        }
        return made;
    }
}

## What a `_Filler` does at each expression of an emitted statement.
struct _Filler {
    var expander: _Expander;
    var error: Diagnostic? = Optional<Diagnostic>.Empty;

    construct(expander: _Expander) {
        this.expander = expander;
    }

    rewrite(e: Expression): Expression {
        if (error.is_value()) {
            return e;
        }
        var filled = expander.fill(e);
        if (filled.is_err()) {
            error = Optional<Diagnostic>.Value(filled.error());
            return e;
        }
        return filled.value();
    }
}

extend _Filler with Rewriter;

## A member `reflect.properties` or `fields` finds, before it is numbered.
struct _Found {
    var loc: Loc;
    var name: String;
    var ty: TypeName;
    var is_const: bool;
    var is_property: bool;
    var attributes: ast.Attribute[];

    construct(loc: Loc, name: String, ty: TypeName, is_const: bool, is_property: bool, attributes: ast.Attribute[]) {
        this.loc = loc;
        this.name = name;
        this.ty = ty;
        this.is_const = is_const;
        this.is_property = is_property;
        this.attributes = attributes;
    }
}

## An `[Attribute]` struct, by its name in the model, or a built-in
## attribute and whether the runtime declares it (which gives it a value).
struct _AttributeName {
    var name: String;
    var built_in: bool;
    var declared: bool;

    construct(name: String, built_in: bool, declared: bool) {
        this.name = name;
        this.built_in = built_in;
        this.declared = declared;
    }
}

_case_value(c: _CtCase): Expression {
    return Expression.Cast(
        CastExpression(Expression.IntLiteral(c.value), c.enumeration.copy(), Loc.none(), CastKind.Synthesized)
    );
}

_fmod(a: double, b: double): double {
    return a % b;
}

_find_enum(module: Module, name: String, file: uint): EnumDef? {
    for (var e in module.enums) {
        if (e.name == name) {
            return Optional<EnumDef>.Value(e);
        }
    }
    var candidates = Array<EnumDef>();
    for (var e in module.enums) {
        if (demangle_name(e.name) == name) {
            candidates.append(e);
        }
    }
    return _prefer_file(candidates, (e) => e.loc.file, file);
}

# ── Attributes ──────────────────────────────────────────────────────────────

## `st` declares a built-in attribute: an `[Attribute]` struct named like
## one, as `runtime/attributes.pep` declares them.
_is_built_in(st: StructDef): bool {
    return _is_built_in_name(demangle_name(st.name));
}

_is_attribute_struct(st: StructDef): bool {
    return st.generic_params.count == 0 and has_bare_attribute(st.attributes, ATTRIBUTE_ATTRIBUTE);
}

## The `[Attribute]` struct an attribute named `name`, written in `file`,
## refers to.
_find_attribute_struct(module: Module, name: String, file: uint): StructDef? {
    for (var st in module.structs) {
        if (_is_attribute_struct(st) and st.name == name) {
            return Optional<StructDef>.Value(st);
        }
    }
    # `serialize.Name`: the module's export, whatever file of the module
    # declares it (`Name@serialize/module`).
    var module_name = Optional<String>.Empty;
    var base = name;
    var dot = name.rfind(".");
    if (dot >= 0) {
        module_name = Optional<String>.Value(name.substr_bytes(0, dot as ulong));
        base = name.substr_bytes(dot as ulong + 1, name.size - dot as ulong - 1);
    }
    var candidates = Array<StructDef>();
    for (var st in module.structs) {
        if (!_is_attribute_struct(st) or demangle_name(st.name) != base) {
            continue;
        }
        if (module_name.is_value()) {
            var at = st.name.find(NAMESPACE_SEPARATOR);
            if (at < 0) {
                continue;
            }
            var ns = st.name.substr_bytes(at as ulong + 1, st.name.size - at as ulong - 1);
            var slash = ns.find("/");
            var first = slash < 0 ? ns : ns.substr_bytes(0, slash as ulong);
            if (ns != module_name.value() and first != module_name.value()) {
                continue;
            }
        }
        candidates.append(st);
    }
    return _prefer_file(candidates, (s) => s.loc.file, file);
}

## The value of a literal in the model: a parameter's default or a field's
## initializer.
_model_constant(module: Module, e: Expression): _CtValue? {
    match (e) {
        IntLiteral(v) => {
            return Optional<_CtValue>.Value(_CtValue.Int(v));
        }
        FloatLiteral(v) => {
            return Optional<_CtValue>.Value(_CtValue.Float(v));
        }
        BoolLiteral(v) => {
            return Optional<_CtValue>.Value(_CtValue.Bool(v));
        }
        StringLiteral(node) => {
            return Optional<_CtValue>.Value(_CtValue.Text(node.value));
        }
        FunctionCall(node) => {
            # A lowered string literal: `String(raw, size, length)`.
            if (node.function == "String" and node.args.count == 3) {
                return _model_constant(module, node.args[0]);
            }
        }
        # Text joined with `+`, as an attribute argument may be: before
        # `resolve_injected`, and the `String` `+` call it makes.
        Binary(node) => {
            if (node.op == BinaryOp.Add) {
                return _joined_constant(module, node.lhs, node.rhs);
            }
        }
        MethodCall(node) => {
            if (node.method == "+" and node.args.count == 1) {
                return _joined_constant(module, node.this_value, node.args[0]);
            }
        }
        Unary(node) => {
            if (node.op is Neg) {
                var inner = _model_constant(module, node.operand);
                if (inner.is_value()) {
                    if (inner.value() is Int(v)) {
                        return Optional<_CtValue>.Value(_CtValue.Int(-v));
                    }
                    if (inner.value() is Float(v)) {
                        return Optional<_CtValue>.Value(_CtValue.Float(-v));
                    }
                }
            }
        }
        Cast(node) => {
            if (node.expr is IntLiteral(v)) {
                for (var def in module.enums) {
                    if (def.name != node.ty.name) {
                        continue;
                    }
                    ulong i = 0;
                    while (i < def.cases.count) {
                        if (def.cases[i].value == v) {
                            return Optional<_CtValue>.Value(_CtValue.Case(_case_of(def, i)));
                        }
                        i += 1;
                    }
                    return Optional<_CtValue>.Empty;
                }
                return Optional<_CtValue>.Value(_CtValue.Int(v));
            }
        }
        MemberRef(node) => {
            if (node.lhs is SymbolRef(symbol)) {
                for (var def in module.enums) {
                    if (def.name != symbol.id) {
                        continue;
                    }
                    ulong i = 0;
                    while (i < def.cases.count) {
                        if (def.cases[i].name == node.name) {
                            return Optional<_CtValue>.Value(_CtValue.Case(_case_of(def, i)));
                        }
                        i += 1;
                    }
                    return Optional<_CtValue>.Empty;
                }
            }
        }
        else => {}
    }
    return Optional<_CtValue>.Empty;
}

## The text of `lhs + rhs` when both are constant text.
_joined_constant(module: Module, lhs: Expression, rhs: Expression): _CtValue? {
    var a = _model_constant(module, lhs);
    var b = _model_constant(module, rhs);
    if (a.is_value() and b.is_value()) {
        var x = _text_of(a.value());
        var y = _text_of(b.value());
        if (x.is_value() and y.is_value()) {
            return Optional<_CtValue>.Value(_CtValue.Text(x.value() + y.value()));
        }
    }
    return Optional<_CtValue>.Empty;
}

## The value a field of type `ty` holds when nothing sets it.
_zero(module: Module, ty: TypeName): _CtValue? {
    var name = ty.name;
    if (name == "bool") {
        return Optional<_CtValue>.Value(_CtValue.Bool(false));
    }
    if (name == "String") {
        return Optional<_CtValue>.Value(_CtValue.Text(""));
    }
    if (name == "float" or name == "double" or name == "f32" or name == "f64") {
        return Optional<_CtValue>.Value(_CtValue.Float(0.0));
    }
    for (var def in module.enums) {
        if (def.name != name) {
            continue;
        }
        long default = 0;
        bool has_zero = false;
        for (var c in def.cases) {
            if (c.value == 0) {
                has_zero = true;
            }
        }
        if (!has_zero and def.cases.count > 0) {
            default = def.cases[0].value;
        }
        ulong i = 0;
        while (i < def.cases.count) {
            if (def.cases[i].value == default) {
                return Optional<_CtValue>.Value(_CtValue.Case(_case_of(def, i)));
            }
            i += 1;
        }
        return Optional<_CtValue>.Empty;
    }
    bool is_enum = false;
    for (var def in module.enums) {
        if (def.name == name) {
            is_enum = true;
        }
    }
    if (is_integral_name(name) or is_enum or name == "char" or name == "byte") {
        return Optional<_CtValue>.Value(_CtValue.Int(0));
    }
    return Optional<_CtValue>.Empty;
}

## Evaluates an argument of an attribute: a literal, `-` a number, an enum
## case, or a `+` of strings.
_attribute_argument(module: Module, e: ast.Expression, file: uint): Result<_CtValue, Diagnostic> {
    var not_constant = Result<_CtValue, Diagnostic>.Err(
        error_at(
            "an attribute argument must be a constant: a number, 'bool', character, string or enum case",
            Loc.at(file, e.span())
        )
    );
    match (e) {
        Literal(literal, _) => {
            match (literal) {
                Integer(v) => {
                    return Result<_CtValue, Diagnostic>.Ok(_CtValue.Int(v));
                }
                Float(v) => {
                    return Result<_CtValue, Diagnostic>.Ok(_CtValue.Float(v));
                }
                Bool(v) => {
                    return Result<_CtValue, Diagnostic>.Ok(_CtValue.Bool(v));
                }
                String(v) => {
                    return Result<_CtValue, Diagnostic>.Ok(_CtValue.Text(v));
                }
                Char(v) => {
                    return Result<_CtValue, Diagnostic>.Ok(_CtValue.Int(v as long));
                }
                Null => {
                    return not_constant;
                }
            }
        }
        Unary(op, _, operand, _) => {
            if (op == "-") {
                var inner = _attribute_argument(module, operand, file);
                if (inner.is_err()) {
                    return inner;
                }
                if (inner.value() is Int(v)) {
                    return Result<_CtValue, Diagnostic>.Ok(_CtValue.Int(-v));
                }
                if (inner.value() is Float(v)) {
                    return Result<_CtValue, Diagnostic>.Ok(_CtValue.Float(-v));
                }
            }
            return not_constant;
        }
        Binary(lhs, op, rhs, _) => {
            if (op == "+") {
                var a = _attribute_argument(module, lhs, file);
                if (a.is_err()) {
                    return a;
                }
                var b = _attribute_argument(module, rhs, file);
                if (b.is_err()) {
                    return b;
                }
                var x = _text_of(a.value());
                var y = _text_of(b.value());
                if (x.is_value() and y.is_value()) {
                    return Result<_CtValue, Diagnostic>.Ok(_CtValue.Text(x.value() + y.value()));
                }
            }
            return not_constant;
        }
        MemberAccess(lhs, name, _, _) => {
            if (lhs is SymbolRef(id, _)) {
                var def = _find_enum(module, id, file);
                if (!def.is_value()) {
                    return not_constant;
                }
                ulong i = 0;
                while (i < def.value().cases.count) {
                    if (def.value().cases[i].name == name) {
                        return Result<_CtValue, Diagnostic>.Ok(_CtValue.Case(_case_of(def.value(), i)));
                    }
                    i += 1;
                }
                return Result<_CtValue, Diagnostic>.Err(
                    error_at($"no case named '{name}' in '{display_name(def.value().name)}'", Loc.at(file, e.span()))
                );
            }
            return not_constant;
        }
        else => {
            return not_constant;
        }
    }
}

## Whether `value` fits a field of type `ty`.
_fits(module: Module, value: _CtValue, ty: TypeName): bool {
    var zero = _zero(module, ty);
    if (!zero.is_value()) {
        return false;
    }
    match (zero.value()) {
        Int(_) => {
            return value is Int(_);
        }
        Bool(_) => {
            return value is Bool(_);
        }
        Text(_) => {
            return value is Text(_);
        }
        Float(_) => {
            return _is_number(value);
        }
        Case(a) => {
            if (value is Case(b)) {
                return a.enumeration.name == b.enumeration.name;
            }
            return false;
        }
        else => {
            return false;
        }
    }
}

## One value an attribute takes: the field it sets, and its default.
struct _Slot {
    var name: String;
    var field: String;
    var default: _CtValue?;

    construct(name: String, field: String, default: _CtValue?) {
        this.name = name;
        this.field = field;
        this.default = default;
    }
}

_default_constant(module: Module, default: Expression?): _CtValue? {
    if (!default.is_value()) {
        return Optional<_CtValue>.Empty;
    }
    return _model_constant(module, default.value());
}

## What an attribute struct's arguments set: with a constructor that takes
## parameters, each parameter (a `this.field` one, or one the body assigns
## to a field); without one, each field, in order.
_slots(module: Module, st: StructDef): Result<_Slot[], Diagnostic> {
    var shown = demangle_name(st.name);
    var constructor = Optional<FunctionDef>.Empty;
    for (var c in st.constructors) {
        for (var p in c.parameters) {
            if (!p.hidden) {
                constructor = Optional<FunctionDef>.Value(c);
                break;
            }
        }
        if (constructor.is_value()) {
            break;
        }
    }
    if (!constructor.is_value()) {
        var out = Array<_Slot>();
        for (var f in st.field_members) {
            if (!f.hidden and !f.name.starts_with("__")) {
                out.append(_Slot(f.name, f.name, _default_constant(module, f.default)));
            }
        }
        return Result<_Slot[], Diagnostic>.Ok(out);
    }
    var ctor = constructor.value();
    # `this.name = name;` in the body: parameter → field.
    var assigned = Array<(String, String)>();
    if (ctor.body.is_value()) {
        for (var statement in ctor.body.value().items) {
            var target = Optional<(String, String)>.Empty;
            var assignment = _assignment_of(statement);
            if (assignment.is_value()) {
                var node = assignment.value();
                if (node.rhs is SymbolRef(rhs)) {
                    match (node.lhs) {
                        MemberRef(member) => {
                            bool on_this = member.lhs is ThisRef;
                            if (member.lhs is SymbolRef(receiver)) {
                                on_this = on_this or receiver.id == "this";
                            }
                            if (on_this) {
                                target = Optional<(String, String)>.Value((rhs.id, member.name));
                            }
                        }
                        SymbolRef(field) => {
                            target = Optional<(String, String)>.Value((rhs.id, field.id));
                        }
                        else => {}
                    }
                }
            }
            # What `synthesize` made (allocation, field initializers).
            bool synthesized = false;
            match (statement) {
                Declaration(declaration) => {
                    if (declaration is Variable(variable)) {
                        synthesized = variable.hidden or variable.loc.is_none();
                    }
                }
                Expression(e) => {
                    synthesized = _expression_loc(e).is_none();
                }
                Return(r) => {
                    synthesized = r.loc.is_none();
                }
                else => {}
            }
            if (target.is_value()) {
                assigned.append(target.value());
            } else if (!synthesized) {
                return Result<_Slot[], Diagnostic>.Err(
                    error_at(
                        $"the constructor of attribute '{shown}' may only assign its parameters to fields", ctor.loc
                    )
                );
            }
        }
    }
    var out = Array<_Slot>();
    for (var parameter in ctor.parameters) {
        if (parameter.hidden) {
            continue;
        }
        var name = parameter.name;
        while (name.starts_with("this.")) {
            name = name.substr_bytes(5, name.size - 5);
        }
        var field = name;
        if (!parameter.name.starts_with("this.")) {
            var found = Optional<String>.Empty;
            for (var (p, f) in assigned) {
                if (p == name) {
                    found = Optional<String>.Value(f);
                    break;
                }
            }
            if (!found.is_value()) {
                return Result<_Slot[], Diagnostic>.Err(
                    error_at($"parameter '{name}' of attribute '{shown}' must set a field", parameter.loc)
                );
            }
            field = found.value();
        }
        out.append(_Slot(name, field, _default_constant(module, parameter.default)));
    }
    return Result<_Slot[], Diagnostic>.Ok(out);
}

## The string field `field` of `attribute` (written in `file`), an
## `[Attribute]` struct's value, read as `reflect.attribute<A>()` would.
##
## @param module the model
## @param attribute the attribute
## @param file the file it is written in
## @param field the field's name
## @returns the field's text, or none
export attribute_string(module: Module, attribute: ast.Attribute, file: uint, field: String): String? {
    var value = _attribute_value(module, attribute, file);
    if (value.is_err()) {
        return Optional<String>.Empty;
    }
    if (value.value() is Attribute(made)) {
        for (var (name, field_value) in made.fields) {
            if (name == field) {
                if (field_value is Text(text)) {
                    return Optional<String>.Value(text);
                }
            }
        }
    }
    return Optional<String>.Empty;
}

## The value of `attribute` (written in `file`), an `[Attribute]` struct:
## its arguments bound to the struct's slots, then the other fields'
## initializers and zero values.
_attribute_value(module: Module, attribute: ast.Attribute, file: uint): Result<_CtValue, Diagnostic> {
    var spelled = attribute_name(attribute);
    var name = spelled.is_value() ? spelled.value() : "";
    var found = _find_attribute_struct(module, name, file);
    if (!found.is_value()) {
        var name_span = attribute.body.span();
        if (attribute.body is FunctionCall(function, _, _)) {
            name_span = function.span();
        }
        return Result<_CtValue, Diagnostic>.Err(error_at($"unknown attribute '{name}'", Loc.at(file, name_span)));
    }
    var st = found.value();
    var shown = demangle_name(st.name);
    var slots = _slots(module, st);
    if (slots.is_err()) {
        return Result<_CtValue, Diagnostic>.Err(slots.error());
    }
    var arguments = attribute_arguments(attribute);
    var values = Array<(String, _CtValue)>();
    var bound = Array<bool>();
    for (var _ in slots.value()) {
        bound.append(false);
    }
    ulong positional = 0;
    for (var argument in arguments) {
        ulong index = 0;
        if (argument.name.is_value()) {
            var (label, span) = argument.name.value();
            bool known = false;
            ulong i = 0;
            while (i < slots.value().count) {
                if (slots.value()[i].name == label) {
                    index = i;
                    known = true;
                    break;
                }
                i += 1;
            }
            if (!known) {
                return Result<_CtValue, Diagnostic>.Err(
                    error_at($"no parameter named '{label}' in attribute '{shown}'", Loc.at(file, span))
                );
            }
        } else {
            positional += 1;
            if (positional > slots.value().count) {
                return Result<_CtValue, Diagnostic>.Err(
                    error_at(
                        $"too many arguments to attribute '{shown}': expected {slots.value().count}, have {arguments.count}",
                        Loc.at(file, argument.value.span())
                    )
                );
            }
            index = positional - 1;
        }
        if (bound[index]) {
            return Result<_CtValue, Diagnostic>.Err(
                error_at(
                    $"'{slots.value()[index].name}' of attribute '{shown}' is given twice",
                    Loc.at(file, argument.value.span())
                )
            );
        }
        bound[index] = true;
        var value = _attribute_argument(module, argument.value, file);
        if (value.is_err()) {
            return value;
        }
        var set = _set_field(
            module, st, shown, slots.value()[index].field, value.value(), Loc.at(file, argument.value.span()), values
        );
        if (set.is_value()) {
            return Result<_CtValue, Diagnostic>.Err(set.value());
        }
    }
    ulong index = 0;
    while (index < slots.value().count) {
        var slot = slots.value()[index];
        if (!bound[index]) {
            if (!slot.default.is_value()) {
                return Result<_CtValue, Diagnostic>.Err(
                    error_at(
                        $"too few arguments to attribute '{shown}': missing '{slot.name}'", Loc.at(file, attribute.span)
                    )
                );
            }
            var set = _set_field(
                module, st, shown, slot.field, slot.default.value(), Loc.at(file, attribute.span), values
            );
            if (set.is_value()) {
                return Result<_CtValue, Diagnostic>.Err(set.value());
            }
        }
        index += 1;
    }
    var fields = Array<(String, _CtValue)>();
    for (var field in st.field_members) {
        if (field.hidden or field.name.starts_with("__")) {
            continue;
        }
        var value = Optional<_CtValue>.Empty;
        for (var (n, v) in values) {
            if (n == field.name) {
                value = Optional<_CtValue>.Value(v);
            }
        }
        if (!value.is_value()) {
            value = _default_constant(module, field.default);
        }
        if (!value.is_value()) {
            value = _zero(module, field.ty);
        }
        fields.append((field.name, value.is_value() ? value.value() : _CtValue.Int(0)));
    }
    return Result<_CtValue, Diagnostic>.Ok(_CtValue.Attribute(_CtAttribute(st.name, fields)));
}

## Sets `field` of the attribute's `values` to `value`, or returns the error.
_set_field(
    module: Module,
    st: StructDef,
    shown: String,
    field: String,
    value: _CtValue,
    at: Loc,
    values: Array<(String, _CtValue)>
): Diagnostic? {
    var declared = Optional<TypeName>.Empty;
    for (var f in st.field_members) {
        if (f.name == field) {
            declared = Optional<TypeName>.Value(f.ty);
            break;
        }
    }
    if (!declared.is_value()) {
        return Optional<Diagnostic>.Value(error_at($"no field named '{field}' in attribute '{shown}'", at));
    }
    if (!_fits(module, value, declared.value())) {
        return Optional<Diagnostic>.Value(
            error_at(
                $"cannot use {value.kind_with_article()} for '{field}' of attribute '{shown}', which is a '{display_name(declared.value().display())}'",
                at
            )
        );
    }
    ulong i = 0;
    while (i < values.count) {
        var (n, _) = values[i];
        if (n == field) {
            values.remove_at(i);
        } else {
            i += 1;
        }
    }
    values.append((field, value));
    return Optional<Diagnostic>.Empty;
}

## The value of built-in attribute `name` as written, as the struct the
## runtime declares for it: `[Target(...)]` holds its condition as written
## and `[BuildOption(...)]` its option's name; the others take their
## arguments as an `[Attribute]` struct of the user's does.
_built_in_value(module: Module, name: String, attribute: ast.Attribute, file: uint): Result<_CtValue, Diagnostic> {
    var field = "";
    if (name == "Target") {
        field = "condition";
    } else if (name == "BuildOption") {
        field = "name";
    } else {
        return _attribute_value(module, attribute, file);
    }
    var st = _find_attribute_struct(module, name, file);
    var written = Array<String>();
    for (var argument in attribute_arguments(attribute)) {
        # `[BuildOption("X")]` names `X`, as `BuildOption(X)` does.
        var text = Optional<String>.Empty;
        if (argument.value is Literal(literal, _)) {
            if (literal is String(value)) {
                text = Optional<String>.Value(value);
            }
        }
        if (name == "BuildOption" and text.is_value()) {
            written.append(text.value());
        } else {
            written.append(argument.value.to_string());
        }
    }
    var fields = [(field, _CtValue.Text(", ".join(written)))];
    return Result<_CtValue, Diagnostic>.Ok(_CtValue.Attribute(_CtAttribute(st.value().name, fields)));
}

# ── Checking attributes ─────────────────────────────────────────────────────

## Whether a field of type `ty` can be part of an attribute: a number,
## `bool`, `char`, a `String`, or an enum whose cases carry no values.
_is_attribute_field_type(module: Module, ty: TypeName): bool {
    return _zero(module, ty).is_value();
}

## Reports an attribute that names neither a built-in attribute nor an
## `[Attribute]` struct, an argument an attribute struct cannot take, and an
## `[Attribute]` struct that cannot be one.
##
## @param module the model
## @param state the passes' state, which keeps the first error
export check_attributes(module: Module, state: PassState) {
    for (var st in module.structs) {
        if (!has_bare_attribute(st.attributes, ATTRIBUTE_ATTRIBUTE) or st.generic_params.count > 0) {
            continue;
        }
        for (var field in st.field_members) {
            if (field.hidden or field.name.starts_with("__")) {
                continue;
            }
            if (!_is_attribute_field_type(module, field.ty)) {
                state.report(
                    error_at(
                        $"field '{field.name}' of attribute '{demangle_name(st.name)}' must be a number, 'bool', 'char', 'String' or an enum, not '{display_name(field.ty.display())}'",
                        field.type_loc.is_none() ? field.loc : field.type_loc
                    )
                );
                return;
            }
        }
    }
    var check = (attributes: ast.Attribute[], file: uint) => {
        for (var attribute in attributes) {
            var name = attribute_name(attribute);
            if (!name.is_value()) {
                continue;
            }
            # The compiler checks a built-in attribute's arguments itself.
            var found = _find_attribute_struct(module, name.value(), file);
            if ((!found.is_value() or _is_built_in(found.value())) and _is_built_in_name(name.value())) {
                continue;
            }
            var value = _attribute_value(module, attribute, file);
            if (value.is_err()) {
                state.report(value.error());
                return;
            }
        }
    };
    var function = (f: FunctionDef) => {
        check(f.attributes, f.loc.file);
        for (var p in f.parameters) {
            check(p.attributes, f.loc.file);
        }
    };
    for (var st in module.structs) {
        if (st.name != st.ty.name and st.generic_params.count > 0) {
            continue;
        }
        # A checked unit's attributes were checked with it.
        if (module.checked.structs.contains(st.name)) {
            continue;
        }
        check(st.attributes, st.loc.file);
        for (var field in st.field_members) {
            check(field.attributes, st.loc.file);
        }
        for (var method in st.method_members) {
            function(method);
        }
        for (var constructor in st.constructors) {
            function(constructor);
        }
        for (var method in st.generic_methods) {
            function(method);
        }
        if (st.enum_cases.is_value()) {
            for (var c in st.enum_cases.value()) {
                check(c.attributes, c.loc.file);
            }
        }
    }
    for (var f in module.functions) {
        if (!is_checked_function(module, f)) {
            function(f);
        }
    }
    for (var e in module.enums) {
        check(e.attributes, e.loc.file);
        for (var c in e.cases) {
            check(c.attributes, c.loc.file);
        }
    }
    for (var g in module.globals) {
        if (!module.checked.globals.contains(g.name)) {
            check(g.attributes, g.loc.file);
        }
    }
    for (var t in module.traits) {
        check(t.attributes, t.loc.file);
    }
}
