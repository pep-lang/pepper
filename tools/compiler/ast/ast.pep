## The syntax tree the compiler works on: one `Module` per source file,
## built by `parse` from Pepper source. `to_json` writes it as
## `pep-build --emit-ast=json` prints it.

import json;
import [JsonValue] from json;
import syntax;
import [Comment, Token] from syntax;

## A byte range of one source file: `start` inclusive, `end` exclusive.
[Value]
export struct Span {
    ## The byte offset of the first byte.
    var start: ulong;
    ## The byte offset just past the last byte.
    var end: ulong;

    ## Creates a span.
    ##
    ## @param start the offset of the first byte
    ## @param end the offset just past the last byte
    construct(this.start = 0, this.end = 0) {}

    ## Returns the span from this one's start to `other`'s end.
    ##
    ## @param other the span that ends the result
    ## @returns the joined span
    to(other: Span): Span {
        return Span(start, other.end);
    }

    ## Returns the span as JSON: `{"start":..,"end":..}`.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["start"] = JsonValue.Integer(start as long);
        out["end"] = JsonValue.Integer(end as long);
        return out;
    }
}

## The internal name of a type sema infers (`var x = 1;`).
export const AUTO_TYPE = "__auto";
## The internal name of a function type: `(P1, P2) => R` is
## `__function<R, P1, P2>`.
export const FUNCTION_TYPE = "__function";
## The internal name of a tuple type: `(A, B)` is `__tuple<A, B>`.
export const TUPLE_TYPE = "__tuple";
## The internal name of a thread-safe function type.
export const SHARED_FUNCTION_TYPE = "__shared_function";
## The internal name of a C function pointer type.
export const EXTERN_FUNCTION_TYPE = "__extern_function";
## The runtime type `T?` stands for.
export const OPTIONAL_TYPE = "Optional";
## The raw pointer type: `__ptr<T>`, which the parser also makes of C's
## `T*`.
export const POINTER_TYPE = "__ptr";

## A literal value.
## The printable ASCII characters, from the space on.
const _PRINTABLE = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
## The hexadecimal digits, upper case.
const _HEX_DIGITS = "0123456789ABCDEF";

export enum Literal {
    ## A string literal's text, escapes decoded.
    ##
    ## @param text the text
    String(text: String),
    ## An integer literal.
    ##
    ## @param value the value
    Integer(value: long),
    ## A decimal integer literal above `long`'s range: a `ulong`.
    ##
    ## @param value the value
    Unsigned(value: ulong),
    ## A floating-point literal.
    ##
    ## @param value the value
    Float(value: double),
    ## `true` or `false`.
    ##
    ## @param value the value
    Bool(value: bool),
    ## A character literal: the character's byte.
    ##
    ## @param value the byte
    Char(value: u8),
    ## `null`.
    Null,

    ## Returns the literal as source writes it: `"a\n"`, `'x'`, `42`.
    ##
    ## @returns the text
    to_string(): String {
        match (this) {
            String(text) => {
                var out = StringBuilder();
                out.append("\"");
                # A String's `length` is 0 when its bytes are not UTF-8 (the
                # `\x80` to `\xFF` of a `StringConstant`): each byte is an escape.
                if (text.size > 0 and text.length == 0) {
                    for (var i in 0..text.size) {
                        out.append($"\\x{text.byte_at(i) as int:02X}");
                    }
                    out.append("\"");
                    return out.to_string();
                }
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
            Integer(value) => {
                return $"{value}";
            }
            Unsigned(value) => {
                return $"{value}";
            }
            Float(value) => {
                return $"{value}";
            }
            Bool(value) => {
                return value ? "true" : "false";
            }
            Char(value) => {
                match (value) {
                    10 => {
                        return "'\\n'";
                    }
                    9 => {
                        return "'\\t'";
                    }
                    13 => {
                        return "'\\r'";
                    }
                    0 => {
                        return "'\\0'";
                    }
                    92 => {
                        return "'\\\\'";
                    }
                    39 => {
                        return "'\\''";
                    }
                    else => {}
                }
                if (value >= 32 and value <= 126) {
                    return $"'{_PRINTABLE.substr_bytes((value - 32) as ulong, 1)}'";
                }
                var high = _HEX_DIGITS.substr_bytes((value >> 4) as ulong, 1);
                var low = _HEX_DIGITS.substr_bytes((value & 15) as ulong, 1);
                return $"'\\x{high}{low}'";
            }
            Null => {
                return "__null";
            }
        }
        return "";
    }

    ## Returns the literal as JSON, externally tagged (`{"Case": value}`).
    ##
    ## @returns the JSON value
    to_json(): JsonValue {
        match (this) {
            String(text) => {
                # Bytes that are not UTF-8 (`length` 0) go as their escapes:
                # JSON text is UTF-8.
                if (text.size > 0 and text.length == 0) {
                    return tagged("Bytes", JsonValue.String(this.to_string()));
                }
                return tagged("String", JsonValue.String(text));
            }
            Integer(value) => {
                return tagged("Integer", JsonValue.Integer(value));
            }
            Unsigned(value) => {
                return tagged("Unsigned", JsonValue.String($"{value}"));
            }
            Float(value) => {
                return tagged("Float", JsonValue.Number(value));
            }
            Bool(value) => {
                return tagged("Bool", JsonValue.Bool(value));
            }
            Char(value) => {
                return tagged("Char", JsonValue.Integer(value as long));
            }
            Null => {
                return JsonValue.String("Null");
            }
        }
        return JsonValue.Null;
    }
}

## A type as written: a name with type arguments.
export struct TypeName {
    ## The name: `int`, `Array`, `io.Path`, or an internal name such as
    ## `__function`.
    var name: String = "";
    ## The type arguments.
    var generic_types: TypeName[] = Array<TypeName>();
    ## The whole type as written.
    var span: Span;
    ## A tuple type's element labels, one per element (empty when the
    ## element has none); empty when no element is labeled.
    var labels: String[] = Array<String>();
    ## Whether this `__ptr<T>` was written in C's syntax, `T*`, which only
    ## `extern` declarations may use.
    var c_pointer: bool = false;

    ## Creates a type name.
    ##
    ## @param name the name
    ## @param span where it is written
    construct(this.name = "", this.span = Span()) {}

    ## Returns the type sema infers, `auto`.
    ##
    ## @returns a new `__auto` type name
    static auto(): TypeName {
        return TypeName(AUTO_TYPE);
    }

    ## Returns a deep copy, so linking can rename one without the other.
    ##
    ## @returns the copy
    copy(): TypeName {
        var out = TypeName(name, span);
        for (var argument in generic_types) {
            out.generic_types.append(argument.copy());
        }
        out.labels = labels.copy();
        out.c_pointer = c_pointer;
        return out;
    }

    ## Returns the type as source writes it: `Box<int>`, `(int) => bool`,
    ## `(x: int, y: int)`.
    ##
    ## @returns the text
    to_string(): String {
        return _text(false);
    }

    ## Returns the type with each pointer written in C's syntax spelled
    ## that way (`int*` rather than `__ptr<int>`), for a message about
    ## that syntax.
    ##
    ## @returns the text
    as_written(): String {
        return _text(true);
    }

    # The type as text, with C pointers as stars when `stars` is set.
    _text(stars: bool): String {
        if (stars and c_pointer and generic_types.count == 1) {
            return generic_types[0]._text(true) + "*";
        }
        # `(int, String)[]` and `Box<int>[]` keep `[]` in the name.
        if (name.ends_with("[]") and generic_types.count > 0) {
            var element = copy();
            element.name = name.substr_bytes(0, name.size - 2);
            return element._text(stars) + "[]";
        }
        bool function = name == FUNCTION_TYPE or name == SHARED_FUNCTION_TYPE or name == EXTERN_FUNCTION_TYPE;
        if (function and generic_types.count > 0) {
            var prefix = "";
            if (name == SHARED_FUNCTION_TYPE) {
                prefix = "shared ";
            } else if (name == EXTERN_FUNCTION_TYPE) {
                prefix = "extern ";
            }
            var parameters = Array<String>();
            ulong i = 1;
            while (i < generic_types.count) {
                parameters.append(generic_types[i]._text(stars));
                i += 1;
            }
            return $"{prefix}({", ".join(parameters)}) => {generic_types[0]._text(stars)}";
        }
        if (name == TUPLE_TYPE and generic_types.count > 0) {
            var elements = Array<String>();
            ulong i = 0;
            while (i < generic_types.count) {
                var element = generic_types[i]._text(stars);
                if (i < labels.count and !labels[i].is_empty) {
                    element = labels[i] + ": " + element;
                }
                elements.append(element);
                i += 1;
            }
            return $"({", ".join(elements)})";
        }
        if (generic_types.count == 0) {
            return name;
        }
        var arguments = Array<String>();
        for (var argument in generic_types) {
            arguments.append(argument._text(stars));
        }
        return $"{name}<{", ".join(arguments)}>";
    }

    ## Returns the type name as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(name);
        out["generic_types"] = types_json(generic_types);
        out["span"] = span.to_json();
        out["labels"] = strings_json(labels);
        return out;
    }
}

## Returns the type `text` spells as `TypeName.to_string` writes it
## (`Box<(a: int, b: int)>`, `(int) => bool`, `(int, String)[]`), every
## part at `span`. The parser keeps a generic method's type arguments that
## way in the member's name (`pass<(a: int, b: int)>`).
##
## @param text the type's text
## @param span where every part is
## @returns the type; `to_string` spells it back as `text` only when
##     `text` is a type so spelled
export parse_type_text(text: String, span: Span): TypeName {
    var reader = _TypeText(text, span);
    return reader.read();
}

# Reads a type from its `TypeName.to_string` spelling.
struct _TypeText {
    var text: String;
    var span: Span;
    var at: ulong = 0;

    construct(text: String, span: Span) {
        this.text = text;
        this.span = span;
    }

    read(): TypeName {
        var function = FUNCTION_TYPE;
        if (_skip("shared (")) {
            function = SHARED_FUNCTION_TYPE;
            at -= 1;
        } else if (_skip("extern (")) {
            function = EXTERN_FUNCTION_TYPE;
            at -= 1;
        }
        if (_skip("(")) {
            var elements = Array<TypeName>();
            var labels = Array<String>();
            bool labeled = false;
            while (at < text.size and !_skip(")")) {
                var label = _label();
                labeled = labeled or !label.is_empty;
                labels.append(label);
                elements.append(read());
                _skip(", ");
            }
            if (_skip(" => ")) {
                var out = TypeName(function, span);
                out.generic_types.append(read());
                out.generic_types.append_all(elements);
                return out;
            }
            var tuple = TypeName(TUPLE_TYPE, span);
            tuple.generic_types = elements;
            if (labeled) {
                tuple.labels = labels;
            }
            return _arrays(tuple);
        }
        ulong start = at;
        while (at < text.size) {
            var b = text.byte_at(at);
            if (b == '<' or b == '>' or b == ',' or b == '(' or b == ')' or b == ' ') {
                break;
            }
            at += 1;
        }
        if (at == start and at < text.size) {
            # A byte no spelling puts here: taken, so every loop moves on,
            # and the result does not spell back as `text`.
            at += 1;
        }
        var out = TypeName(text.substr_bytes(start, at - start), span);
        if (_skip("<")) {
            while (at < text.size and !_skip(">")) {
                out.generic_types.append(read());
                _skip(", ");
            }
            return _arrays(out);
        }
        return out;
    }

    # `label: ` at the reader, taken; empty when there is none.
    _label(): String {
        ulong end = at;
        while (end < text.size) {
            var b = text.byte_at(end);
            if (!((b >= 'a' and b <= 'z')
                or (b >= 'A' and b <= 'Z')
                or (b >= '0' and b <= '9')
                or b == '_'
                or b >= 128)) {
                break;
            }
            end += 1;
        }
        if (end == at or !text.substr_bytes(end, text.size - end).starts_with(": ")) {
            return "";
        }
        var label = text.substr_bytes(at, end - at);
        at = end + 2;
        return label;
    }

    # `[]` suffixes after `out`'s `>` or `)`, which extend its name.
    _arrays(out: TypeName): TypeName {
        while (_skip("[]")) {
            out.name = out.name + "[]";
        }
        return out;
    }

    # Takes `word` when the reader is at it.
    _skip(word: String): bool {
        if (!text.substr_bytes(at, text.size - at).starts_with(word)) {
            return false;
        }
        at += word.size;
        return true;
    }
}

## The attribute that declares a compiler built-in in the runtime
## (`[__BuiltIn]`): the compiler ignores the declaration.
export const BUILT_IN_ATTRIBUTE = "__BuiltIn";

## Returns whether `attributes` mark a declaration `[__BuiltIn]`.
##
## @param attributes the declaration's attributes
## @returns true when one of them is `[__BuiltIn]`
export is_built_in(attributes: Attribute[]): bool {
    for (var attribute in attributes) {
        if (attribute.name() == BUILT_IN_ATTRIBUTE) {
            return true;
        }
    }
    return false;
}

## Returns whether `attributes` include one named `name`, bare or called.
##
## @param attributes the attributes
## @param name the attribute's name
## @returns true when one of them is named `name`
export has_attribute(attributes: Attribute[], name: String): bool {
    for (var attribute in attributes) {
        if (attribute.name() == name) {
            return true;
        }
    }
    return false;
}

## One attribute, `[body]`.
export struct Attribute {
    ## The attribute: a name (`Export`) or a call (`Link("m")`).
    var body: Expression;
    ## The whole bracket group.
    var span: Span;

    ## Creates an attribute.
    ##
    ## @param body the attribute's expression
    ## @param span the bracket group
    construct(body: Expression, span: Span) {
        this.body = body;
        this.span = span;
    }

    ## Returns the attribute's name: `Link` in `[Link("m")]` and in `[Link]`.
    ##
    ## @returns the name, or an empty String for any other expression
    name(): String {
        match (body) {
            SymbolRef(id, _) => {
                return id;
            }
            FunctionCall(function, _, _) => {
                if (function is SymbolRef(id, _)) {
                    return id;
                }
            }
            else => {}
        }
        return "";
    }

    ## Returns the attribute as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["body"] = body.to_json();
        out["span"] = span.to_json();
        return out;
    }
}

## A label of a tuple literal's element, with the span of its name.
export struct Label {
    ## The label.
    var name: String = "";
    ## Where the label is written.
    var span: Span;

    ## Creates a label.
    ##
    ## @param name the label
    ## @param span where it is written
    construct(name: String, span: Span) {
        this.name = name;
        this.span = span;
    }

    ## Returns the label as JSON: `[name, span]`, a tuple as an array.
    ##
    ## @returns the JSON array
    to_json(): JsonValue {
        return JsonValue.array([JsonValue.String(name), span.to_json()]);
    }
}

## One entry of a map literal, `key: value`.
export struct MapEntry {
    ## The key.
    var key: Expression;
    ## The value.
    var value: Expression;

    ## Creates an entry.
    ##
    ## @param key the key
    ## @param value the value
    construct(key: Expression, value: Expression) {
        this.key = key;
        this.value = value;
    }
}

## A format specification after the `:` of an interpolated string's hole
## or a format string's argument: `[[fill]align][+][0][width][.precision][type]`.
export struct FormatSpec {
    ## The fill character, a space when not written.
    var fill: String = " ";
    ## The alignment when `has_align`: 1 for `<`, 2 for `^`, 3 for `>`.
    var align: long;
    ## An alignment is written.
    var has_align: bool;
    ## The `+` sign flag, when written.
    var plus: Span?;
    ## The `0` padding flag, when written.
    var zero: Span?;
    ## The minimum width, 0 when not written.
    var width: long;
    ## The digits after the `.`.
    var precision: long;
    ## The `.` before the precision, when written.
    var point: Span?;
    ## The type, `d`, `x`, `X`, `b` or `o`; empty when not written.
    var kind: String = "";
    ## Where the type is written.
    var kind_span: Span;

    ## Creates a specification that writes nothing.
    construct() {}

    ## Returns the specification as source writes it: `>8.2`.
    ##
    ## @returns the text after the `:`
    to_string(): String {
        var out = StringBuilder();
        if (has_align) {
            if (fill != " ") {
                out.append(fill);
            }
            out.append(align == 1 ? "<" : (align == 2 ? "^" : ">"));
        }
        if (plus.is_value()) {
            out.append("+");
        }
        if (zero.is_value()) {
            out.append("0");
        }
        if (width > 0) {
            out.append($"{width}");
        }
        if (point.is_value()) {
            out.append($".{precision}");
        }
        out.append(kind);
        return out.to_string();
    }

    ## Returns the specification as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["fill"] = JsonValue.String(fill);
        out["align"] = has_align ? JsonValue.Integer(align) : JsonValue.Null;
        out["plus"] = optional_span_json(plus);
        out["zero"] = optional_span_json(zero);
        out["width"] = JsonValue.Integer(width);
        out["precision"] = point.is_value() ? JsonValue.Integer(precision) : JsonValue.Null;
        out["point"] = optional_span_json(point);
        out["kind"] = JsonValue.String(kind);
        out["kind_span"] = kind_span.to_json();
        return out;
    }
}

## One part of an interpolated string (`$"..."`) or of the format string
## that `print` and `String.format` take, as the source writes it.
export enum StringPart {
    ## Text between the braces, with its escapes and `{{` `}}` decoded.
    ##
    ## @param text the text
    ## @param span where it is written
    Text(text: String, span: Span),
    ## `{value}` or `{value:spec}` of an interpolated string.
    ##
    ## @param value the value converted to text
    ## @param braces the braces
    ## @param spec the format specification, when written
    Hole(value: Expression, braces: Span, spec: FormatSpec?),
    ## `{0}` or `{0:spec}` of a format string: the argument after the
    ## format that it stands for.
    ##
    ## @param index the argument's index, 0 for the first after the format
    ## @param index_span where the index is written
    ## @param braces the braces
    ## @param spec the format specification, when written
    Argument(index: ulong, index_span: Span, braces: Span, spec: FormatSpec?),

    ## Returns the part as source writes it inside the quotes.
    ##
    ## @returns the text
    to_string(): String {
        match (this) {
            Text(text, _) => {
                var quoted = Literal.String(text).to_string();
                return quoted.substr_bytes(1, quoted.size - 2).replace("{", "{{").replace("}", "}}");
            }
            Hole(value, _, spec) => {
                return spec.is_value() ?
                    $"{{{value.to_string()}:{spec.value().to_string()}}}" :
                    $"{{{value.to_string()}}}";
            }
            Argument(index, _, _, spec) => {
                return spec.is_value() ? $"{{{index}:{spec.value().to_string()}}}" : $"{{{index}}}";
            }
        }
        return "";
    }

    ## Returns the part as JSON, externally tagged (`{"Case": value}`).
    ##
    ## @returns the JSON value
    to_json(): JsonValue {
        match (this) {
            Text(text, span) => {
                var out = JsonValue.object();
                out["text"] = JsonValue.String(text);
                out["span"] = span.to_json();
                return tagged("Text", out);
            }
            Hole(value, braces, spec) => {
                var out = JsonValue.object();
                out["value"] = value.to_json();
                out["braces"] = braces.to_json();
                out["spec"] = spec.is_value() ? spec.value().to_json() : JsonValue.Null;
                return tagged("Hole", out);
            }
            Argument(index, index_span, braces, spec) => {
                var out = JsonValue.object();
                out["index"] = JsonValue.Integer(index as long);
                out["index_span"] = index_span.to_json();
                out["braces"] = braces.to_json();
                out["spec"] = spec.is_value() ? spec.value().to_json() : JsonValue.Null;
                return tagged("Argument", out);
            }
        }
        return JsonValue.Null;
    }
}

## An expression.
export enum Expression {
    ## A literal.
    ##
    ## @param value the literal
    ## @param span where it is written
    Literal(value: Literal, span: Span),
    ## A name.
    ##
    ## @param id the name
    ## @param span where it is written
    SymbolRef(id: String, span: Span),
    ## A generic type in expression position: `Array<int>` in
    ## `Array<int>()`.
    ##
    ## @param type_name the type
    TypeLiteral(type_name: TypeName),
    ## `sizeof<T>()`.
    ##
    ## @param type_name the type measured
    SizeOf(type_name: TypeName),
    ## `op operand` or, not `prefix`, `operand op`.
    ##
    ## @param op the operator
    ## @param prefix whether the operator comes first
    ## @param operand the operand
    ## @param span the operator
    Unary(op: String, prefix: bool, operand: Expression, span: Span),
    ## `expr as Type`, or `expr as? Type` when `optional`.
    ##
    ## @param expr the value cast
    ## @param type_name the type cast to
    ## @param span the cast
    ## @param keyword_span the `as` keyword
    ## @param optional written `as?`
    Cast(expr: Expression, type_name: TypeName, span: Span, keyword_span: Span, optional: bool),
    ## `lhs op rhs`.
    ##
    ## @param lhs the left operand
    ## @param op the operator
    ## @param rhs the right operand
    ## @param span the operator
    Binary(lhs: Expression, op: String, rhs: Expression, span: Span),
    ## `condition ? true_expr : false_expr`.
    ##
    ## @param condition the condition
    ## @param true_expr the value when it holds
    ## @param false_expr the value when it does not
    ## @param span the `?`
    Ternary(condition: Expression, true_expr: Expression, false_expr: Expression, span: Span),
    ## `lhs[rhs]`.
    ##
    ## @param lhs the value indexed
    ## @param rhs the index
    ## @param span the brackets
    Index(lhs: Expression, rhs: Expression, span: Span),
    ## `lhs.name`.
    ##
    ## @param lhs the value
    ## @param name the member's name
    ## @param name_span where the name is written
    ## @param span the access
    MemberAccess(lhs: Expression, name: String, name_span: Span, span: Span),
    ## `function(arguments...)`.
    ##
    ## @param function the function called
    ## @param arguments the arguments
    ## @param span the call
    FunctionCall(function: Expression, arguments: Expression[], span: Span),
    ## `name = value` among a call's arguments.
    ##
    ## @param name the parameter's name
    ## @param name_span where the name is written
    ## @param value the argument
    ## @param span the argument
    NamedArgument(name: String, name_span: Span, value: Expression, span: Span),
    ## A closure literal.
    ##
    ## @param closure the closure
    Closure(closure: ClosureLiteral),
    ## `(a, b, ...)`, with every element labeled or none.
    ##
    ## @param elements the elements
    ## @param labels the labels, or none
    ## @param span the tuple
    Tuple(elements: Expression[], labels: Label[], span: Span),
    ## `[a, b, ...]`.
    ##
    ## @param elements the elements
    ## @param span the literal
    ArrayLiteral(elements: Expression[], span: Span),
    ## `[k: v, ...]`, or `[:]`.
    ##
    ## @param entries the entries
    ## @param span the literal
    MapLiteral(entries: MapEntry[], span: Span),
    ## A `match` that produces a value.
    ##
    ## @param expression the match
    Match(expression: MatchExpression),
    ## `value is pattern`.
    ##
    ## @param value the value tested
    ## @param pattern the pattern
    ## @param keyword_span the `is` keyword
    ## @param span the test
    Is(value: Expression, pattern: Pattern, keyword_span: Span, span: Span),
    ## `$"text {value} text"` as written: `parse.parse_written` keeps it,
    ## and `desugar` turns it into the calls that convert each hole and
    ## the concatenation of the results.
    ##
    ## @param parts the text and holes, in order
    ## @param span the literal
    Interpolated(parts: StringPart[], span: Span),
    ## The string literal format that `print` and `String.format` take
    ## first, `"{0} and {1}"`, followed by at least one argument for
    ## `print`. It is only ever the first argument of such a call, which
    ## `desugar` turns into the format's text.
    ##
    ## @param parts the text and arguments, in order
    ## @param span the literal
    ## @param paren where the call's `(` starts
    ## @param argument_spans the arguments after the format, each from its
    ##   first token to its last
    FormatString(parts: StringPart[], span: Span, paren: ulong, argument_spans: Span[]),
    ## `(value)` as written: `parse.parse_written` keeps the parentheses
    ## for tools that print the source back, and `desugar` (like
    ## `parse.parse`) leaves the value alone in their place.
    ##
    ## @param value the expression inside
    ## @param span the parentheses and what is between them
    Parenthesized(value: Expression, span: Span),

    ## Returns where a diagnostic about the expression points.
    ##
    ## @returns the span
    span(): Span {
        match (this) {
            Literal(_, span) => {
                return span;
            }
            SymbolRef(_, span) => {
                return span;
            }
            TypeLiteral(type_name) => {
                return type_name.span;
            }
            SizeOf(type_name) => {
                return type_name.span;
            }
            Unary(_, _, _, span) => {
                return span;
            }
            Cast(_, _, span, _, _) => {
                return span;
            }
            Binary(_, _, _, span) => {
                return span;
            }
            Ternary(_, _, _, span) => {
                return span;
            }
            Index(_, _, span) => {
                return span;
            }
            MemberAccess(_, _, _, span) => {
                return span;
            }
            FunctionCall(_, _, span) => {
                return span;
            }
            NamedArgument(_, _, _, span) => {
                return span;
            }
            Closure(closure) => {
                return closure.span;
            }
            Tuple(_, _, span) => {
                return span;
            }
            ArrayLiteral(_, span) => {
                return span;
            }
            MapLiteral(_, span) => {
                return span;
            }
            Match(expression) => {
                return expression.span;
            }
            Is(_, _, _, span) => {
                return span;
            }
            Interpolated(_, span) => {
                return span;
            }
            FormatString(_, span, _, _) => {
                return span;
            }
            Parenthesized(_, span) => {
                return span;
            }
        }
        return Span();
    }

    ## Returns the span from the expression's first byte to its last: a
    ## binary's operands, a call's callee and arguments, and so on, which
    ## `span()` leaves out.
    ##
    ## @returns the span
    extent(): Span {
        match (this) {
            Unary(_, _, operand, span) => {
                return _union(span, operand.extent());
            }
            Cast(expr, type_name, span, _, _) => {
                return _union(_union(span, expr.extent()), type_name.span);
            }
            Binary(lhs, _, rhs, span) => {
                return _union(_union(span, lhs.extent()), rhs.extent());
            }
            Index(lhs, rhs, span) => {
                return _union(_union(span, lhs.extent()), rhs.extent());
            }
            Ternary(condition, true_expr, false_expr, span) => {
                return _union(_union(_union(span, condition.extent()), true_expr.extent()), false_expr.extent());
            }
            MemberAccess(lhs, _, _, span) => {
                return _union(span, lhs.extent());
            }
            FunctionCall(function, arguments, span) => {
                var out = _union(span, function.extent());
                for (var argument in arguments) {
                    out = _union(out, argument.extent());
                }
                return out;
            }
            NamedArgument(_, _, value, span) => {
                return _union(span, value.extent());
            }
            Is(value, _, _, span) => {
                return _union(span, value.extent());
            }
            else => {
                return span();
            }
        }
    }

    ## Returns the expression as source writes it, every binary in
    ## parentheses: `(a + 1)`, `f(x, "y")`. A closure's block body and a
    ## `match` print in short.
    ##
    ## @returns the text
    to_string(): String {
        match (this) {
            Literal(value, _) => {
                return value.to_string();
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
                return prefix ? op + operand.to_string() : operand.to_string() + op;
            }
            Binary(lhs, op, rhs, _) => {
                return $"({lhs.to_string()} {op} {rhs.to_string()})";
            }
            Cast(expr, type_name, _, _, optional) => {
                var mark = optional ? "?" : "";
                return $"({expr.to_string()} as{mark} {type_name.to_string()})";
            }
            Ternary(condition, true_expr, false_expr, _) => {
                return $"({condition.to_string()} ? {true_expr.to_string()} : {false_expr.to_string()})";
            }
            Index(lhs, rhs, _) => {
                return $"{lhs.to_string()}[{rhs.to_string()}]";
            }
            MemberAccess(lhs, name, _, _) => {
                return $"{lhs.to_string()}.{name}";
            }
            FunctionCall(function, arguments, _) => {
                return $"{function.to_string()}({_joined(arguments)})";
            }
            NamedArgument(name, _, value, _) => {
                return $"{name} = {value.to_string()}";
            }
            Closure(closure) => {
                var params = Array<String>();
                for (var p in closure.parameters) {
                    params.append(p.type_name.name == AUTO_TYPE ? p.name : $"{p.name}: {p.type_name.to_string()}");
                }
                var returns = closure.return_type.name == AUTO_TYPE ? "" : $": {closure.return_type.to_string()}";
                return $"({", ".join(params)}){returns} => {{ ... }}";
            }
            Tuple(elements, labels, _) => {
                if (labels.count == 0) {
                    return $"({_joined(elements)})";
                }
                var parts = Array<String>();
                ulong i = 0;
                while (i < elements.count and i < labels.count) {
                    parts.append($"{labels[i].name}: {elements[i].to_string()}");
                    i += 1;
                }
                return $"({", ".join(parts)})";
            }
            ArrayLiteral(elements, _) => {
                return $"[{_joined(elements)}]";
            }
            MapLiteral(entries, _) => {
                if (entries.count == 0) {
                    return "[:]";
                }
                var parts = Array<String>();
                for (var entry in entries) {
                    parts.append($"{entry.key.to_string()}: {entry.value.to_string()}");
                }
                return $"[{", ".join(parts)}]";
            }
            Match(expression) => {
                return $"match ({expression.value.to_string()}) {{ ... }}";
            }
            Is(value, pattern, _, _) => {
                return $"({value.to_string()} is {pattern.to_string()})";
            }
            Interpolated(parts, _) => {
                return "$\"" + _parts_text(parts) + "\"";
            }
            FormatString(parts, _, _, _) => {
                return "\"" + _parts_text(parts) + "\"";
            }
            Parenthesized(value, _) => {
                return $"({value.to_string()})";
            }
        }
        return "";
    }

    ## Returns the expression as JSON, externally tagged (`{"Case": value}`).
    ##
    ## @returns the JSON value
    to_json(): JsonValue {
        match (this) {
            Literal(value, span) => {
                var out = JsonValue.object();
                out["value"] = value.to_json();
                out["span"] = span.to_json();
                return tagged("Literal", out);
            }
            SymbolRef(id, span) => {
                var out = JsonValue.object();
                out["id"] = JsonValue.String(id);
                out["span"] = span.to_json();
                return tagged("SymbolRef", out);
            }
            TypeLiteral(type_name) => {
                return tagged("TypeLiteral", type_name.to_json());
            }
            SizeOf(type_name) => {
                return tagged("SizeOf", type_name.to_json());
            }
            Unary(op, prefix, operand, span) => {
                var out = JsonValue.object();
                out["op"] = JsonValue.String(op);
                out["prefix"] = JsonValue.Bool(prefix);
                out["operand"] = operand.to_json();
                out["span"] = span.to_json();
                return tagged("Unary", out);
            }
            Cast(expr, type_name, span, keyword_span, optional) => {
                var out = JsonValue.object();
                out["expr"] = expr.to_json();
                out["ty"] = type_name.to_json();
                out["span"] = span.to_json();
                out["keyword_span"] = keyword_span.to_json();
                out["optional"] = JsonValue.Bool(optional);
                return tagged("Cast", out);
            }
            Binary(lhs, op, rhs, span) => {
                var out = JsonValue.object();
                out["lhs"] = lhs.to_json();
                out["op"] = JsonValue.String(op);
                out["rhs"] = rhs.to_json();
                out["span"] = span.to_json();
                return tagged("Binary", out);
            }
            Ternary(condition, true_expr, false_expr, span) => {
                var out = JsonValue.object();
                out["condition"] = condition.to_json();
                out["true_expr"] = true_expr.to_json();
                out["false_expr"] = false_expr.to_json();
                out["span"] = span.to_json();
                return tagged("Ternary", out);
            }
            Index(lhs, rhs, span) => {
                var out = JsonValue.object();
                out["lhs"] = lhs.to_json();
                out["rhs"] = rhs.to_json();
                out["span"] = span.to_json();
                return tagged("Index", out);
            }
            MemberAccess(lhs, name, name_span, span) => {
                var out = JsonValue.object();
                out["lhs"] = lhs.to_json();
                out["name"] = JsonValue.String(name);
                out["name_span"] = name_span.to_json();
                out["span"] = span.to_json();
                return tagged("MemberAccess", out);
            }
            FunctionCall(function, arguments, span) => {
                var out = JsonValue.object();
                out["function"] = function.to_json();
                out["arguments"] = expressions_json(arguments);
                out["span"] = span.to_json();
                return tagged("FunctionCall", out);
            }
            NamedArgument(name, name_span, value, span) => {
                var out = JsonValue.object();
                out["name"] = JsonValue.String(name);
                out["name_span"] = name_span.to_json();
                out["value"] = value.to_json();
                out["span"] = span.to_json();
                return tagged("NamedArgument", out);
            }
            Closure(closure) => {
                return tagged("Closure", closure.to_json());
            }
            Tuple(elements, labels, span) => {
                var out = JsonValue.object();
                out["elements"] = expressions_json(elements);
                var label_list = JsonValue.array();
                for (var label in labels) {
                    label_list.append(label.to_json());
                }
                out["labels"] = label_list;
                out["span"] = span.to_json();
                return tagged("Tuple", out);
            }
            ArrayLiteral(elements, span) => {
                var out = JsonValue.object();
                out["elements"] = expressions_json(elements);
                out["span"] = span.to_json();
                return tagged("ArrayLiteral", out);
            }
            MapLiteral(entries, span) => {
                var out = JsonValue.object();
                var list = JsonValue.array();
                for (var entry in entries) {
                    list.append(JsonValue.array([entry.key.to_json(), entry.value.to_json()]));
                }
                out["entries"] = list;
                out["span"] = span.to_json();
                return tagged("MapLiteral", out);
            }
            Match(inner) => {
                return tagged("Match", inner.to_json());
            }
            Is(value, pattern, keyword_span, span) => {
                var out = JsonValue.object();
                out["value"] = value.to_json();
                out["pattern"] = pattern.to_json();
                out["keyword_span"] = keyword_span.to_json();
                out["span"] = span.to_json();
                return tagged("Is", out);
            }
            Interpolated(parts, span) => {
                var out = JsonValue.object();
                out["parts"] = parts_json(parts);
                out["span"] = span.to_json();
                return tagged("Interpolated", out);
            }
            FormatString(parts, span, paren, argument_spans) => {
                var out = JsonValue.object();
                out["parts"] = parts_json(parts);
                out["span"] = span.to_json();
                out["paren"] = JsonValue.Integer(paren as long);
                var spans = JsonValue.array();
                for (var argument_span in argument_spans) {
                    spans.append(argument_span.to_json());
                }
                out["argument_spans"] = spans;
                return tagged("FormatString", out);
            }
            Parenthesized(value, span) => {
                var out = JsonValue.object();
                out["value"] = value.to_json();
                out["span"] = span.to_json();
                return tagged("Parenthesized", out);
            }
        }
        return JsonValue.Null;
    }
}

## A `match` in expression position.
export struct MatchExpression {
    ## The value matched.
    var value: Expression;
    ## The arms, in order.
    var arms: MatchValueArm[] = Array<MatchValueArm>();
    ## The `else` arm's value, when there is one.
    var else_value: Expression?;
    ## The `else` keyword, when there is an `else` arm.
    var else_span: Span;
    ## The `match` keyword.
    var keyword_span: Span;
    ## The whole match.
    var span: Span;

    ## Creates a match expression.
    ##
    ## @param value the value matched
    construct(value: Expression) {
        this.value = value;
    }

    ## Returns the match as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["value"] = value.to_json();
        var list = JsonValue.array();
        for (var arm in arms) {
            list.append(arm.to_json());
        }
        out["arms"] = list;
        out["else_arm"] = else_value.is_value() ?
            JsonValue.array([else_span.to_json(), else_value.value().to_json()]) :
            JsonValue.Null;
        out["keyword_span"] = keyword_span.to_json();
        out["span"] = span.to_json();
        return out;
    }
}

## One arm of a `match` expression.
export struct MatchValueArm {
    ## The patterns.
    var patterns: Pattern[] = Array<Pattern>();
    ## The guard, `if condition`.
    var guard: Expression?;
    ## The value the arm selects.
    var value: Expression;
    ## The arm.
    var span: Span;

    ## Creates an arm.
    construct() {}

    ## Returns the arm as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["patterns"] = patterns_json(patterns);
        out["guard"] = optional_expression_json(guard);
        out["value"] = value.to_json();
        out["span"] = span.to_json();
        return out;
    }
}

## A closure literal.
export struct ClosureLiteral {
    ## The parameters; a parameter written without a type is `auto`.
    var parameters: VariableDecl[] = Array<VariableDecl>();
    ## The return type, else `auto`.
    var return_type: TypeName = TypeName.auto();
    ## The body; an expression body is a block holding `return expr;`.
    var body: Block;
    ## The body was written as an expression.
    var expression_body: bool;
    ## The closure.
    var span: Span;

    ## Creates a closure literal.
    construct() {}

    ## Returns the closure as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["parameters"] = variables_json(parameters);
        out["return_type"] = return_type.to_json();
        out["body"] = body.to_json();
        out["expression_body"] = JsonValue.Bool(expression_body);
        out["span"] = span.to_json();
        return out;
    }
}

## A variable, field, parameter or binding.
export struct VariableDecl {
    ## The attributes before it.
    var attributes: Attribute[] = Array<Attribute>();
    ## The name.
    var name: String = "";
    ## Where the name is written.
    var name_span: Span;
    ## The type, `auto` when not written.
    var type_name: TypeName = TypeName.auto();
    ## The initializer or default value.
    var default_value: Expression?;
    ## Declared `const`.
    var is_const: bool;
    ## From the first token to the last.
    var span: Span;
    ## Declared `export`.
    var is_exported: bool;
    ## Declared `private`: visible only in its own file.
    var is_private: bool;

    ## Creates a declaration.
    ##
    ## @param name the name
    construct(this.name = "") {}

    ## Returns the declaration as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["attributes"] = attributes_json(attributes);
        out["name"] = JsonValue.String(name);
        out["name_span"] = name_span.to_json();
        out["type_name"] = type_name.to_json();
        out["default_value"] = optional_expression_json(default_value);
        out["is_const"] = JsonValue.Bool(is_const);
        out["span"] = span.to_json();
        out["is_exported"] = JsonValue.Bool(is_exported);
        out["is_private"] = JsonValue.Bool(is_private);
        return out;
    }
}

## A property: `var name: T { get; set { ... } } = init;`.
export struct PropertyDecl {
    ## The attributes before it.
    var attributes: Attribute[] = Array<Attribute>();
    ## The name.
    var name: String = "";
    ## Where the name is written.
    var name_span: Span;
    ## The type.
    var type_name: TypeName;
    ## The initializer of the implied storage.
    var default_value: Expression?;
    ## The `get` accessor.
    var getter: Accessor?;
    ## The `set` accessor.
    var setter: Accessor?;
    ## From the first token to the last.
    var span: Span;

    ## Creates a property.
    construct() {}

    ## Returns the property as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["attributes"] = attributes_json(attributes);
        out["name"] = JsonValue.String(name);
        out["name_span"] = name_span.to_json();
        out["type_name"] = type_name.to_json();
        out["default_value"] = optional_expression_json(default_value);
        out["get"] = getter.is_value() ? getter.value().to_json() : JsonValue.Null;
        out["set"] = setter.is_value() ? setter.value().to_json() : JsonValue.Null;
        out["span"] = span.to_json();
        return out;
    }
}

## One accessor of a property: `get;`, `set { ... }`.
export struct Accessor {
    ## The `get` or `set` keyword.
    var span: Span;
    ## The accessor as the method it compiles to, `__get_P(): T` or
    ## `__set_P(value: T)`; its body is empty for `get;` and `set;`.
    var function: FunctionDecl;

    ## Creates an accessor.
    ##
    ## @param span the keyword
    ## @param function the method
    construct(span: Span, function: FunctionDecl) {
        this.span = span;
        this.function = function;
    }

    ## Returns the accessor as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["span"] = span.to_json();
        out["function"] = function.to_json();
        return out;
    }
}

## A function, method, constructor or extern.
export struct FunctionDecl {
    ## The name.
    var name: String = "";
    ## Where the name is written.
    var name_span: Span;
    ## The generic parameters.
    var generic_params: GenericParam[] = Array<GenericParam>();
    ## The return type.
    var return_type: TypeName;
    ## The parameters.
    var parameters: VariableDecl[] = Array<VariableDecl>();
    ## Declared `extern`.
    var external: bool;
    ## The body; none for an extern or a trait method without one.
    var body: Block?;
    ## Declared `static`.
    var is_static: bool;
    ## An indexer, `T [](params)`.
    var is_indexer: bool;
    ## An extern ending in `...`.
    var is_variadic: bool;
    ## The whole function.
    var span: Span;
    ## The attributes before it.
    var attributes: Attribute[] = Array<Attribute>();
    ## Declared `export`.
    var is_exported: bool;
    ## Declared `private`: visible only in its own file.
    var is_private: bool;

    ## Creates a function.
    ##
    ## @param name the name
    construct(this.name = "") {}

    ## Returns the function as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(name);
        out["name_span"] = name_span.to_json();
        var generics = JsonValue.array();
        for (var param in generic_params) {
            generics.append(param.to_json());
        }
        out["generic_params"] = generics;
        out["return_type"] = return_type.to_json();
        out["parameters"] = variables_json(parameters);
        out["external"] = JsonValue.Bool(external);
        out["body"] = body.is_value() ? body.value().to_json() : JsonValue.Null;
        out["is_static"] = JsonValue.Bool(is_static);
        out["is_indexer"] = JsonValue.Bool(is_indexer);
        out["is_variadic"] = JsonValue.Bool(is_variadic);
        out["span"] = span.to_json();
        out["attributes"] = attributes_json(attributes);
        out["is_exported"] = JsonValue.Bool(is_exported);
        out["is_private"] = JsonValue.Bool(is_private);
        return out;
    }
}

## A generic parameter: `T`, `T: Shape & Named`, `TError = Error`.
export struct GenericParam {
    ## The name.
    var name: String = "";
    ## Where the name is written.
    var name_span: Span;
    ## The traits an argument must conform to.
    var bounds: TypeName[] = Array<TypeName>();
    ## The default type.
    var default: TypeName?;
    ## Set by module linking: the name is a type argument.
    var is_argument: bool;

    ## Creates a generic parameter.
    ##
    ## @param name the name
    ## @param name_span where it is written
    construct(name: String, name_span: Span) {
        this.name = name;
        this.name_span = name_span;
    }

    ## Returns the parameter as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(name);
        out["name_span"] = name_span.to_json();
        out["bounds"] = types_json(bounds);
        out["default"] = default.is_value() ? default.value().to_json() : JsonValue.Null;
        out["is_argument"] = JsonValue.Bool(is_argument);
        return out;
    }
}

## A struct or enum declaration.
export struct StructDecl {
    ## The name.
    var name: String = "";
    ## Where the name is written.
    var name_span: Span;
    ## The generic parameters.
    var generic_params: GenericParam[] = Array<GenericParam>();
    ## The fields.
    var fields: VariableDecl[] = Array<VariableDecl>();
    ## The properties.
    var properties: PropertyDecl[] = Array<PropertyDecl>();
    ## The methods.
    var methods: FunctionDecl[] = Array<FunctionDecl>();
    ## The constructors.
    var constructors: FunctionDecl[] = Array<FunctionDecl>();
    ## The destructor's body.
    var destructor: Block?;
    ## The `destruct` keyword.
    var destruct_span: Span?;
    ## The whole declaration.
    var span: Span;
    ## The attributes before it.
    var attributes: Attribute[] = Array<Attribute>();
    ## Declared `export`.
    var is_exported: bool;
    ## Declared `private`: visible only in its own file.
    var is_private: bool;
    ## The cases, for an `enum`.
    var enumeration: EnumBody?;

    ## Creates a struct declaration.
    construct() {}

    ## Returns the declaration as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(name);
        out["name_span"] = name_span.to_json();
        out["generic_params"] = generic_params_json(generic_params);
        out["fields"] = variables_json(fields);
        out["properties"] = properties_json(properties);
        out["methods"] = functions_json(methods);
        out["constructors"] = functions_json(constructors);
        out["destructor"] = destructor.is_value() ? destructor.value().to_json() : JsonValue.Null;
        out["destruct_span"] = destruct_span.is_value() ? destruct_span.value().to_json() : JsonValue.Null;
        out["span"] = span.to_json();
        out["attributes"] = attributes_json(attributes);
        out["is_exported"] = JsonValue.Bool(is_exported);
        out["is_private"] = JsonValue.Bool(is_private);
        out["enumeration"] = enumeration.is_value() ? enumeration.value().to_json() : JsonValue.Null;
        return out;
    }
}

## What an `enum` adds to its `StructDecl`.
export struct EnumBody {
    ## The integer type after `:`.
    var representation: TypeName?;
    ## The cases.
    var cases: EnumCase[] = Array<EnumCase>();

    ## Creates an enum body.
    construct() {}

    ## Returns the body as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["representation"] = representation.is_value() ? representation.value().to_json() : JsonValue.Null;
        var list = JsonValue.array();
        for (var item in cases) {
            list.append(item.to_json());
        }
        out["cases"] = list;
        return out;
    }
}

## One case of an enum.
export struct EnumCase {
    ## The name.
    var name: String = "";
    ## Where the name is written.
    var name_span: Span;
    ## The explicit value after `=`.
    var value: Expression?;
    ## The values the case carries, when written with parentheses.
    var payload: VariableDecl[]?;
    ## The attributes before it.
    var attributes: Attribute[] = Array<Attribute>();
    ## The whole case.
    var span: Span;

    ## Creates a case.
    construct() {}

    ## Returns the case as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(name);
        out["name_span"] = name_span.to_json();
        out["value"] = optional_expression_json(value);
        out["payload"] = payload.is_value() ? variables_json(payload.value()) : JsonValue.Null;
        out["attributes"] = attributes_json(attributes);
        out["span"] = span.to_json();
        return out;
    }
}

## A trait declaration.
export struct TraitDecl {
    ## The attributes before it.
    var attributes: Attribute[] = Array<Attribute>();
    ## The name.
    var name: String = "";
    ## Where the name is written.
    var name_span: Span;
    ## The generic parameters.
    var generic_params: GenericParam[] = Array<GenericParam>();
    ## The methods.
    var methods: FunctionDecl[] = Array<FunctionDecl>();
    ## The properties the trait requires.
    var properties: PropertyDecl[] = Array<PropertyDecl>();
    ## The whole declaration.
    var span: Span;
    ## Declared `export`.
    var is_exported: bool;
    ## Declared `private`: visible only in its own file.
    var is_private: bool;

    ## Creates a trait declaration.
    construct() {}

    ## Returns the declaration as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["attributes"] = attributes_json(attributes);
        out["name"] = JsonValue.String(name);
        out["name_span"] = name_span.to_json();
        out["generic_params"] = generic_params_json(generic_params);
        out["methods"] = functions_json(methods);
        out["properties"] = properties_json(properties);
        out["span"] = span.to_json();
        out["is_exported"] = JsonValue.Bool(is_exported);
        out["is_private"] = JsonValue.Bool(is_private);
        return out;
    }
}

## A type alias: `type Name<P> = Target;`.
export struct TypeAliasDecl {
    ## The attributes before it.
    var attributes: Attribute[] = Array<Attribute>();
    ## The name.
    var name: String = "";
    ## Where the name is written.
    var name_span: Span;
    ## The generic parameters.
    var generic_params: GenericParam[] = Array<GenericParam>();
    ## The type aliased.
    var target: TypeName;
    ## The whole declaration.
    var span: Span;
    ## Declared `export`.
    var is_exported: bool;
    ## Declared `private`: visible only in its own file.
    var is_private: bool;

    ## Creates a type alias.
    construct() {}

    ## Returns the declaration as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["attributes"] = attributes_json(attributes);
        out["name"] = JsonValue.String(name);
        out["name_span"] = name_span.to_json();
        out["generic_params"] = generic_params_json(generic_params);
        out["target"] = target.to_json();
        out["span"] = span.to_json();
        out["is_exported"] = JsonValue.Bool(is_exported);
        out["is_private"] = JsonValue.Bool(is_private);
        return out;
    }
}

## An extension: `extend Target with Traits { ... }`.
export struct ExtendDecl {
    ## The attributes before it.
    var attributes: Attribute[] = Array<Attribute>();
    ## The type extended.
    var target: TypeName;
    ## Constraints restated on the target's parameters, per argument.
    var target_bounds: TypeName[][] = Array<TypeName[]>();
    ## The traits implemented.
    var traits: TypeName[] = Array<TypeName>();
    ## The methods.
    var methods: FunctionDecl[] = Array<FunctionDecl>();
    ## The computed properties.
    var properties: PropertyDecl[] = Array<PropertyDecl>();
    ## The whole declaration.
    var span: Span;
    ## Declared `export`.
    var is_exported: bool;
    ## Declared `private`: visible only in its own file.
    var is_private: bool;

    ## Creates an extension.
    construct() {}

    ## Returns the declaration as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["attributes"] = attributes_json(attributes);
        out["target"] = target.to_json();
        var bounds = JsonValue.array();
        for (var list in target_bounds) {
            bounds.append(types_json(list));
        }
        out["target_bounds"] = bounds;
        out["traits"] = types_json(traits);
        out["methods"] = functions_json(methods);
        out["properties"] = properties_json(properties);
        out["span"] = span.to_json();
        out["is_exported"] = JsonValue.Bool(is_exported);
        out["is_private"] = JsonValue.Bool(is_private);
        return out;
    }
}

## A declaration at module scope or in a block.
export enum Declaration {
    ## A variable.
    ##
    ## @param decl the variable
    Variable(decl: VariableDecl),
    ## A function.
    ##
    ## @param decl the function
    Function(decl: FunctionDecl),
    ## A struct or enum.
    ##
    ## @param decl the struct
    Struct(decl: StructDecl),
    ## A trait.
    ##
    ## @param decl the trait
    Trait(decl: TraitDecl),
    ## An extension.
    ##
    ## @param decl the extension
    Extend(decl: ExtendDecl),
    ## A type alias.
    ##
    ## @param decl the alias
    TypeAlias(decl: TypeAliasDecl),
    ## A module-scope `static { ... }` block.
    ##
    ## @param block the block
    Static(block: StaticBlock),

    ## Returns the attributes written before the declaration.
    ##
    ## @returns the attributes
    attributes(): Attribute[] {
        match (this) {
            Variable(decl) => {
                return decl.attributes;
            }
            Function(decl) => {
                return decl.attributes;
            }
            Struct(decl) => {
                return decl.attributes;
            }
            Trait(decl) => {
                return decl.attributes;
            }
            Extend(decl) => {
                return decl.attributes;
            }
            TypeAlias(decl) => {
                return decl.attributes;
            }
            Static(block) => {
                return block.attributes;
            }
        }
        return Array<Attribute>();
    }

    ## Returns whether the declaration is marked `export`.
    ##
    ## @returns true when importers can use it
    is_exported(): bool {
        match (this) {
            Variable(decl) => {
                return decl.is_exported;
            }
            Function(decl) => {
                return decl.is_exported;
            }
            Struct(decl) => {
                return decl.is_exported;
            }
            Trait(decl) => {
                return decl.is_exported;
            }
            Extend(decl) => {
                return decl.is_exported;
            }
            TypeAlias(decl) => {
                return decl.is_exported;
            }
            Static(block) => {
                return block.is_exported;
            }
        }
        return false;
    }

    ## Returns whether the declaration is marked `private`.
    ##
    ## @returns true when only its own file can use it
    is_private(): bool {
        match (this) {
            Variable(decl) => {
                return decl.is_private;
            }
            Function(decl) => {
                return decl.is_private;
            }
            Struct(decl) => {
                return decl.is_private;
            }
            Trait(decl) => {
                return decl.is_private;
            }
            Extend(decl) => {
                return decl.is_private;
            }
            TypeAlias(decl) => {
                return decl.is_private;
            }
            Static(block) => {
                return block.is_private;
            }
        }
        return false;
    }

    ## Returns the declared name: an extension's target's name, and empty
    ## for a `static` block.
    ##
    ## @returns the name
    declared_name(): String {
        match (this) {
            Variable(decl) => {
                return decl.name;
            }
            Function(decl) => {
                return decl.name;
            }
            Struct(decl) => {
                return decl.name;
            }
            Trait(decl) => {
                return decl.name;
            }
            Extend(decl) => {
                return decl.target.name;
            }
            TypeAlias(decl) => {
                return decl.name;
            }
            Static(_) => {
                return "";
            }
        }
        return "";
    }

    ## Gives the declaration the name `name`; an extension or a `static`
    ## block keeps what it has.
    ##
    ## @param name the new name
    rename(name: String) {
        match (this) {
            Variable(decl) => {
                decl.name = name;
            }
            Function(decl) => {
                decl.name = name;
            }
            Struct(decl) => {
                decl.name = name;
            }
            Trait(decl) => {
                decl.name = name;
            }
            TypeAlias(decl) => {
                decl.name = name;
            }
            else => {}
        }
    }

    ## Returns the whole declaration's span.
    ##
    ## @returns the span
    span(): Span {
        match (this) {
            Variable(decl) => {
                return decl.span;
            }
            Function(decl) => {
                return decl.span;
            }
            Struct(decl) => {
                return decl.span;
            }
            Trait(decl) => {
                return decl.span;
            }
            Extend(decl) => {
                return decl.span;
            }
            TypeAlias(decl) => {
                return decl.span;
            }
            Static(block) => {
                return block.span;
            }
        }
        return Span();
    }

    ## Returns where the declared name is written: an extension's target
    ## type, a `static` block's keyword.
    ##
    ## @returns the span
    name_span(): Span {
        match (this) {
            Variable(decl) => {
                return decl.name_span;
            }
            Function(decl) => {
                return decl.name_span;
            }
            Struct(decl) => {
                return decl.name_span;
            }
            Trait(decl) => {
                return decl.name_span;
            }
            Extend(decl) => {
                return decl.target.span;
            }
            TypeAlias(decl) => {
                return decl.name_span;
            }
            Static(block) => {
                return block.keyword_span;
            }
        }
        return Span();
    }

    ## Returns the declaration as JSON, externally tagged (`{"Case": value}`).
    ##
    ## @returns the JSON value
    to_json(): JsonValue {
        match (this) {
            Variable(decl) => {
                return tagged("Variable", decl.to_json());
            }
            Function(decl) => {
                return tagged("Function", decl.to_json());
            }
            Struct(decl) => {
                return tagged("Struct", decl.to_json());
            }
            Trait(decl) => {
                return tagged("Trait", decl.to_json());
            }
            Extend(decl) => {
                return tagged("Extend", decl.to_json());
            }
            TypeAlias(decl) => {
                return tagged("TypeAlias", decl.to_json());
            }
            Static(block) => {
                return tagged("Static", block.to_json());
            }
        }
        return JsonValue.Null;
    }
}

## `{ statement... }`.
export struct Block {
    ## The statements.
    var statements: Statement[] = Array<Statement>();
    ## The braces, widened to the first attribute.
    var span: Span;
    ## The attributes before it.
    var attributes: Attribute[] = Array<Attribute>();

    ## Creates a block.
    ##
    ## @param span the braces
    construct(this.span = Span()) {}

    ## Returns the block as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        var list = JsonValue.array();
        for (var statement in statements) {
            list.append(statement.to_json());
        }
        out["statements"] = list;
        out["span"] = span.to_json();
        out["attributes"] = attributes_json(attributes);
        return out;
    }
}

## One binding of a destructuring pattern: a name, or a nested pattern.
export struct DestructureBinding {
    ## The name, `_` to skip; empty for a nested pattern.
    var name: String = "";
    ## Where the name is written.
    var name_span: Span;
    ## The type, `auto` when not written.
    var type_name: TypeName = TypeName.auto();
    ## A nested pattern's bindings.
    var nested: DestructureBinding[] = Array<DestructureBinding>();

    ## Creates a binding.
    construct() {}

    ## Returns the binding as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(name);
        out["name_span"] = name_span.to_json();
        out["type_name"] = type_name.to_json();
        out["nested"] = bindings_json(nested);
        return out;
    }
}

## `match (value) { pattern => { ... } else => { ... } }` as a statement.
export struct Match {
    ## The value matched.
    var value: Expression;
    ## The arms.
    var arms: MatchArm[] = Array<MatchArm>();
    ## The `else` arm's block.
    var else_block: Block?;
    ## The `else` keyword.
    var else_span: Span;
    ## The `match` keyword.
    var keyword_span: Span;
    ## The whole match.
    var span: Span;

    ## Creates a match.
    ##
    ## @param value the value matched
    construct(value: Expression) {
        this.value = value;
    }

    ## Returns the match as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["value"] = value.to_json();
        var list = JsonValue.array();
        for (var arm in arms) {
            list.append(arm.to_json());
        }
        out["arms"] = list;
        out["else_arm"] = else_block.is_value() ?
            JsonValue.array([else_span.to_json(), else_block.value().to_json()]) :
            JsonValue.Null;
        out["keyword_span"] = keyword_span.to_json();
        out["span"] = span.to_json();
        return out;
    }
}

## One arm of a `match` statement.
export struct MatchArm {
    ## The patterns.
    var patterns: Pattern[] = Array<Pattern>();
    ## The guard.
    var guard: Expression?;
    ## The block.
    var body: Block;
    ## The arm.
    var span: Span;

    ## Creates an arm.
    construct() {}

    ## Returns the arm as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["patterns"] = patterns_json(patterns);
        out["guard"] = optional_expression_json(guard);
        out["body"] = body.to_json();
        out["span"] = span.to_json();
        return out;
    }
}

## Returns the smallest span holding both `a` and `b`.
_union(a: Span, b: Span): Span {
    return Span(a.start < b.start ? a.start : b.start, a.end > b.end ? a.end : b.end);
}

## Returns `expressions` as source writes them, separated by commas.
_joined(expressions: Expression[]): String {
    var parts = Array<String>();
    for (var e in expressions) {
        parts.append(e.to_string());
    }
    return ", ".join(parts);
}

## Returns string parts as source writes them inside the quotes.
_parts_text(parts: StringPart[]): String {
    var out = StringBuilder();
    for (var part in parts) {
        out.append(part.to_string());
    }
    return out.to_string();
}

## Returns `patterns` as source writes them, separated by commas.
_patterns_text(patterns: Pattern[]): String {
    var parts = Array<String>();
    for (var p in patterns) {
        parts.append(p.to_string());
    }
    return ", ".join(parts);
}

## A pattern: a case (`Circle(r)`), a literal, a range, or a tuple.
export struct Pattern {
    ## A literal pattern's literal, or a range's start.
    var literal: Expression?;
    ## A tuple pattern's elements.
    var elements: Pattern[]?;
    ## The enum named before the case.
    var qualifier: TypeName?;
    ## The case's name; empty for a literal or tuple pattern.
    var case_name: String = "";
    ## Where the case is written.
    var case_span: Span;
    ## The patterns of the case's values, when written with parentheses.
    var bindings: Pattern[]?;
    ## A range pattern's end, when `literal` is its start.
    var range_end: Expression?;
    ## The range includes its end (`..>`).
    var range_inclusive: bool;
    ## Set by module linking when the name is a module-scope constant.
    var constant: String?;
    ## The case's name read as a type.
    var type_name: TypeName?;
    ## The whole pattern.
    var span: Span;

    ## Creates a pattern.
    construct() {}

    ## Returns whether this is a bare name: no literal, elements, enum,
    ## values or constant.
    ##
    ## @returns true for a bare name
    is_bare_name(): bool {
        return literal.is_empty()
            and elements.is_empty()
            and qualifier.is_empty()
            and bindings.is_empty()
            and constant.is_empty();
    }

    ## Returns the pattern as source writes it: `Shape.Circle(r)`, `1..>9`,
    ## `(a, _)`.
    ##
    ## @returns the text
    to_string(): String {
        if (literal.is_value()) {
            if (range_end.is_value()) {
                var dots = range_inclusive ? "..>" : "..";
                return $"{literal.value().to_string()}{dots}{range_end.value().to_string()}";
            }
            return literal.value().to_string();
        }
        if (elements.is_value()) {
            return $"({_patterns_text(elements.value())})";
        }
        var out = "";
        if (qualifier.is_value()) {
            out = qualifier.value().to_string() + ".";
        }
        out = out + case_name;
        if (type_name.is_value() and type_name.value().generic_types.count > 0) {
            var arguments = Array<String>();
            for (var t in type_name.value().generic_types) {
                arguments.append(t.to_string());
            }
            out = $"{out}<{", ".join(arguments)}>";
        }
        if (bindings.is_value()) {
            out = $"{out}({_patterns_text(bindings.value())})";
        }
        return out;
    }

    ## Returns the names the pattern may bind, `_` left out: each bare name
    ## inside a tuple pattern or a case's parentheses.
    ##
    ## @returns the names with where each is written
    bound_names(): Label[] {
        var out = Array<Label>();
        _collect_names(false, out);
        return out;
    }

    _collect_names(in_tuple: bool, out: Label[]) {
        if (elements.is_value()) {
            for (var element in elements.value()) {
                element._collect_names(true, out);
            }
            return;
        }
        if (in_tuple and is_bare_name() and case_name != "_") {
            out.append(Label(case_name, case_span));
        }
        if (bindings.is_value()) {
            for (var binding in bindings.value()) {
                binding._collect_names(true, out);
            }
        }
    }

    ## Returns the pattern as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["literal"] = optional_expression_json(literal);
        out["elements"] = elements.is_value() ? patterns_json(elements.value()) : JsonValue.Null;
        out["qualifier"] = qualifier.is_value() ? qualifier.value().to_json() : JsonValue.Null;
        out["case"] = JsonValue.String(case_name);
        out["case_span"] = case_span.to_json();
        out["bindings"] = bindings.is_value() ? patterns_json(bindings.value()) : JsonValue.Null;
        if (range_end.is_value()) {
            var range = JsonValue.object();
            range["end"] = range_end.value().to_json();
            range["inclusive"] = JsonValue.Bool(range_inclusive);
            out["range"] = range;
        } else {
            out["range"] = JsonValue.Null;
        }
        out["constant"] = constant.is_value() ? JsonValue.String(constant.value()) : JsonValue.Null;
        out["ty"] = type_name.is_value() ? type_name.value().to_json() : JsonValue.Null;
        out["span"] = span.to_json();
        return out;
    }
}

## `static (captures) { ... }`: compile-time work.
export struct StaticBlock {
    ## The runtime values the block may emit code against.
    var captures: Label[] = Array<Label>();
    ## From `parse_written` only: every capture as written, which `captures`
    ## keeps only when it is a name; empty without captures.
    var written_captures: Expression[] = Array<Expression>();
    ## The block.
    var block: Block;
    ## The `static` keyword.
    var keyword_span: Span;
    ## The whole block.
    var span: Span;
    ## At module scope: the attributes before it.
    var attributes: Attribute[] = Array<Attribute>();
    ## At module scope: written `export static`.
    var is_exported: bool;
    ## At module scope: written `private static`.
    var is_private: bool;

    ## Creates a static block.
    construct() {}

    ## Returns the block as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        var list = JsonValue.array();
        for (var capture in captures) {
            list.append(capture.to_json());
        }
        out["captures"] = list;
        if (!written_captures.is_empty) {
            var written = JsonValue.array();
            for (var capture in written_captures) {
                written.append(capture.to_json());
            }
            out["written_captures"] = written;
        }
        out["block"] = block.to_json();
        out["keyword_span"] = keyword_span.to_json();
        out["span"] = span.to_json();
        out["attributes"] = attributes_json(attributes);
        out["is_exported"] = JsonValue.Bool(is_exported);
        out["is_private"] = JsonValue.Bool(is_private);
        return out;
    }
}

## A statement.
export enum Statement {
    ## An expression statement.
    ##
    ## @param expression the expression
    Expression(expression: Expression),
    ## A nested block.
    ##
    ## @param block the block
    Block(block: Block),
    ## A declaration.
    ##
    ## @param declaration the declaration
    Declaration(declaration: Declaration),
    ## `if (condition) { ... } else { ... }`.
    ##
    ## @param condition the condition
    ## @param if_block the block run when it holds
    ## @param else_block the block run when it does not
    ## @param span the statement
    Branch(condition: Expression, if_block: Block, else_block: Block?, span: Span),
    ## `while (condition) { ... }`.
    ##
    ## @param condition the condition
    ## @param block the body
    ## @param span the statement
    While(condition: Expression, block: Block, span: Span),
    ## `for (var x in iterable) { ... }`.
    ##
    ## @param binding the loop variable; empty-named with a pattern
    ## @param pattern the tuple pattern each element is destructured into
    ## @param iterable the value iterated
    ## @param block the body
    ## @param span the statement
    For(binding: VariableDecl, pattern: DestructureBinding[], iterable: Expression, block: Block, span: Span),
    ## `with (var x = scope) { ... } else { ... }`.
    ##
    ## @param binding the variable, if any
    ## @param scope the scope entered
    ## @param block the body
    ## @param else_block the block run when entering gives null
    ## @param span the statement
    With(binding: VariableDecl?, scope: Expression, block: Block, else_block: Block?, span: Span),
    ## `return value;`.
    ##
    ## @param value the value, if any
    ## @param span the statement
    Return(value: Expression?, span: Span),
    ## `break;` or, `is_continue`, `continue;`, with the label of the loop it
    ## leaves (`break outer;`), or none for the innermost.
    ##
    ## @param is_continue whether it is `continue`
    ## @param label the loop's label, or empty
    ## @param label_span the label, or the keyword when there is none
    ## @param span the statement
    LoopBreak(is_continue: bool, label: String, label_span: Span, span: Span),
    ## `label: while (...) { ... }` or `label: for (...) { ... }`: a loop that
    ## `break label;` and `continue label;` name.
    ##
    ## @param label the label
    ## @param label_span the label
    ## @param loop the `While` or `For` it names
    ## @param span the statement, label included
    Labeled(label: String, label_span: Span, loop: Statement, span: Span),
    ## `var (a, b) = value;`.
    ##
    ## @param bindings the bindings
    ## @param value the tuple
    ## @param is_const declared `const`
    ## @param span the statement
    Destructure(bindings: DestructureBinding[], value: Expression, is_const: bool, span: Span),
    ## A `match` statement.
    ##
    ## @param statement the match
    Match(statement: Match),
    ## A `static` block.
    ##
    ## @param block the block
    Static(block: StaticBlock),

    ## Returns where the statement is written.
    ##
    ## @returns the span
    span(): Span {
        match (this) {
            Expression(expression) => {
                return expression.span();
            }
            Block(block) => {
                return block.span;
            }
            Declaration(declaration) => {
                return declaration.span();
            }
            Branch(_, _, _, span) => {
                return span;
            }
            While(_, _, span) => {
                return span;
            }
            For(_, _, _, _, span) => {
                return span;
            }
            With(_, _, _, _, span) => {
                return span;
            }
            Return(_, span) => {
                return span;
            }
            LoopBreak(_, _, _, span) => {
                return span;
            }
            Labeled(_, _, _, span) => {
                return span;
            }
            Destructure(_, _, _, span) => {
                return span;
            }
            Match(statement) => {
                return statement.span;
            }
            Static(block) => {
                return block.span;
            }
        }
        return Span();
    }

    ## Returns the statement as JSON, externally tagged (`{"Case": value}`).
    ##
    ## @returns the JSON value
    to_json(): JsonValue {
        match (this) {
            Expression(expression) => {
                return tagged("Expression", expression.to_json());
            }
            Block(block) => {
                return tagged("Block", block.to_json());
            }
            Declaration(declaration) => {
                return tagged("Declaration", declaration.to_json());
            }
            Branch(condition, if_block, else_block, span) => {
                var out = JsonValue.object();
                out["condition"] = condition.to_json();
                out["if_block"] = if_block.to_json();
                out["else_block"] = else_block.is_value() ? else_block.value().to_json() : JsonValue.Null;
                out["span"] = span.to_json();
                return tagged("Branch", out);
            }
            While(condition, block, span) => {
                var out = JsonValue.object();
                out["condition"] = condition.to_json();
                out["block"] = block.to_json();
                out["span"] = span.to_json();
                return tagged("While", out);
            }
            For(binding, pattern, iterable, block, span) => {
                var out = JsonValue.object();
                out["binding"] = binding.to_json();
                out["pattern"] = bindings_json(pattern);
                out["iterable"] = iterable.to_json();
                out["block"] = block.to_json();
                out["span"] = span.to_json();
                return tagged("For", out);
            }
            With(binding, scope, block, else_block, span) => {
                var out = JsonValue.object();
                out["binding"] = binding.is_value() ? binding.value().to_json() : JsonValue.Null;
                out["scope"] = scope.to_json();
                out["block"] = block.to_json();
                out["else_block"] = else_block.is_value() ? else_block.value().to_json() : JsonValue.Null;
                out["span"] = span.to_json();
                return tagged("With", out);
            }
            Return(value, span) => {
                var out = JsonValue.object();
                out["expr"] = optional_expression_json(value);
                out["span"] = span.to_json();
                return tagged("Return", out);
            }
            LoopBreak(is_continue, label, _, span) => {
                var out = JsonValue.object();
                out["kind"] = JsonValue.String(is_continue ? "Continue" : "Break");
                out["label"] = JsonValue.String(label);
                out["span"] = span.to_json();
                return tagged("LoopBreak", out);
            }
            Labeled(label, label_span, loop, span) => {
                var out = JsonValue.object();
                out["label"] = JsonValue.String(label);
                out["label_span"] = label_span.to_json();
                out["loop"] = loop.to_json();
                out["span"] = span.to_json();
                return tagged("Labeled", out);
            }
            Destructure(bindings, value, is_const, span) => {
                var out = JsonValue.object();
                out["bindings"] = bindings_json(bindings);
                out["value"] = value.to_json();
                out["is_const"] = JsonValue.Bool(is_const);
                out["span"] = span.to_json();
                return tagged("Destructure", out);
            }
            Match(inner) => {
                return tagged("Match", inner.to_json());
            }
            Static(block) => {
                return tagged("Static", block.to_json());
            }
        }
        return JsonValue.Null;
    }
}

## One `symbol` or `symbol as name` of `import [...] from source`.
export struct ImportedSymbol {
    ## The symbol's name.
    var name: String = "";
    ## Where the name is written.
    var name_span: Span;
    ## The local name, if renamed.
    var alias: String?;
    ## The entry.
    var span: Span;

    ## Creates an entry.
    construct() {}

    ## Returns the name the symbol is bound to in the importing file.
    ##
    ## @returns the alias, else the name
    local_name(): String {
        return alias.is_value() ? alias.value() : name;
    }

    ## Returns the entry as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(name);
        out["name_span"] = name_span.to_json();
        out["alias"] = optional_string_json(alias);
        out["span"] = span.to_json();
        return out;
    }
}

## An import, or a re-export of a source (`export * from "shapes"`).
export struct Import {
    ## The module name, or the file path as written.
    var name: String = "";
    ## Where the name is written.
    var name_span: Span;
    ## The qualifier after `as`.
    var alias: String?;
    ## A quoted local import.
    var is_local: bool;
    ## The symbols listed in `[...]`.
    var symbols: ImportedSymbol[]?;
    ## A re-export.
    var reexport: bool;
    ## The attributes before it.
    var attributes: Attribute[] = Array<Attribute>();
    ## The whole import.
    var span: Span;

    ## Creates an import.
    construct() {}

    ## Returns the name without a trailing `.pep`.
    ##
    ## @returns the stem
    stem(): String {
        return name.ends_with(".pep") ? name.substr_bytes(0, name.size - 4) : name;
    }

    ## Returns how diagnostics name the import's source: `"util.pep"`, or
    ## `module 'm'`.
    ##
    ## @returns the description
    describe(): String {
        if (is_local) {
            return $"\"{stem()}.pep\"";
        }
        return $"module '{name}'";
    }

    ## Returns how diagnostics name the source of a local import that
    ## resolved to a module folder: `the module folder "vec"`.
    ##
    ## @param folder the import resolved to a module folder
    ## @returns the description
    describe_as(folder: bool): String {
        if (is_local and folder) {
            return $"the module folder \"{stem()}\"";
        }
        return describe();
    }

    ## Returns the qualifier the import binds (`m` in `m.sqrt`): the alias,
    ## or a module import's last name part.
    ##
    ## @returns the qualifier, or none for an import list, a re-export or an
    ##   unaliased local import
    qualifier(): String? {
        if (symbols.is_value() or reexport) {
            return Optional<String>.Empty;
        }
        if (alias.is_value()) {
            return alias;
        }
        if (is_local) {
            return Optional<String>.Empty;
        }
        var parts = name.split(".");
        return Optional<String>.Value(parts[parts.count - 1]);
    }

    ## Returns the import as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["name"] = JsonValue.String(name);
        out["name_span"] = name_span.to_json();
        out["alias"] = optional_string_json(alias);
        out["is_local"] = JsonValue.Bool(is_local);
        if (symbols.is_value()) {
            var list = JsonValue.array();
            for (var symbol in symbols.value()) {
                list.append(symbol.to_json());
            }
            out["symbols"] = list;
        } else {
            out["symbols"] = JsonValue.Null;
        }
        out["reexport"] = JsonValue.Bool(reexport);
        out["attributes"] = attributes_json(attributes);
        out["span"] = span.to_json();
        return out;
    }
}

## `export symbol as name;`.
export struct ExportAlias {
    ## The symbol as written, possibly qualified.
    var symbol: String = "";
    ## Where the symbol is written.
    var symbol_span: Span;
    ## The name importers see, if renamed.
    var alias: String?;
    ## The attributes before it.
    var attributes: Attribute[] = Array<Attribute>();
    ## The whole re-export.
    var span: Span;

    ## Creates a re-export.
    construct() {}

    ## Returns the name importers see: the alias, else the symbol's last
    ## part.
    ##
    ## @returns the exported name
    exported_name(): String {
        if (alias.is_value()) {
            return alias.value();
        }
        var parts = symbol.split(".");
        return parts[parts.count - 1];
    }

    ## Returns the re-export as JSON.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        out["symbol"] = JsonValue.String(symbol);
        out["symbol_span"] = symbol_span.to_json();
        out["alias"] = optional_string_json(alias);
        out["attributes"] = attributes_json(attributes);
        out["span"] = span.to_json();
        return out;
    }
}

## Deprecated syntax the parser accepted: how the source spells it, what
## replaces it, and the text that migrates it.
export struct SyntaxWarning {
    ## Where it is.
    var span: Span;
    ## How the source spells it, quoted: "`new`".
    var what: String = "";
    ## What replaces it.
    var instead: String = "";
    ## The text that replaces it.
    var replacement: String = "";
    ## A warning that is not a deprecation: its whole message, which
    ## `what`, `instead` and `replacement` then do not make.
    var message: String = "";

    ## Creates a warning.
    ##
    ## @param span where it is
    ## @param what how the source spells it
    ## @param instead what replaces it
    ## @param replacement the text that replaces it
    construct(span: Span, what: String, instead: String, replacement: String) {
        this.span = span;
        this.what = what;
        this.instead = instead;
        this.replacement = replacement;
    }
}

## Every token of one source file, with the comments and line breaks
## around it: what `parse.parse_written` keeps beside the tree for tools
## that print the source back (pep-fmt) or read its comments.
##
## Each comment belongs to exactly one token, as the lexer attached it: a
## comment after a token on the same line is that token's trailing comment,
## and every other comment is a leading comment of the token after it (the
## `End` token for the file's last comments). A node's comments are those of
## its tokens, which its spans locate: `leading` and `trailing` read the
## ones before and after a node.
export struct SourceTokens {
    ## The text the tokens point into.
    var source: String;
    ## Every token in source order, as the parser read them (a `>` joined
    ## with the `>` or `=` after it into one `>>`, `>=` or `>>=`), ending
    ## with the `End` token.
    var tokens: Token[];

    ## Creates the tokens of a source file.
    ##
    ## @param source the text the tokens point into
    ## @param tokens every token in source order, ending with `End`
    construct(source: String, tokens: Token[]) {
        this.source = source;
        this.tokens = tokens;
    }

    ## Returns the index of the first token that starts at or after
    ## `offset`: the `End` token's when none does.
    ##
    ## @param offset a byte offset in the source
    ## @returns the token's index
    next_index(offset: ulong): ulong {
        ulong low = 0;
        ulong high = tokens.count - 1;
        while (low < high) {
            var middle = low + (high - low) / 2;
            if (tokens[middle].offset < offset) {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        return low;
    }

    ## Returns the index of the token that starts at `offset`, or -1 when
    ## none does.
    ##
    ## @param offset a byte offset in the source
    ## @returns the token's index, or -1
    index_at(offset: ulong): long {
        var index = next_index(offset);
        if (tokens[index].offset != offset) {
            return -1;
        }
        return index as long;
    }

    ## Returns the text of the token at `index`, exactly as written.
    ##
    ## @param index the token's index
    ## @returns its text
    text(index: ulong): String {
        return tokens[index].text(source);
    }

    ## Returns the comments on their own lines before the node at `span`:
    ## the leading comments of its first token.
    ##
    ## @param span a node's span, starting at its first token
    ## @returns the comments, in order
    leading(span: Span): Comment[] {
        return tokens[next_index(span.start)].leading_comments;
    }

    ## Returns the comment after the node at `span` on its last line: the
    ## trailing comment of its last token, or an empty String.
    ##
    ## @param span a node's span, ending after its last token
    ## @returns the comment, or an empty String
    trailing(span: Span): String {
        var after = next_index(span.end);
        if (after == 0) {
            return "";
        }
        return tokens[after - 1].trailing_comment;
    }

    ## Returns whether a blank line comes before the node at `span`,
    ## counting from the first comment above it.
    ##
    ## @param span a node's span, starting at its first token
    ## @returns true when two or more line breaks come first
    blank_before(span: Span): bool {
        var first = tokens[next_index(span.start)];
        if (first.has_leading_comments()) {
            return first.leading_comments[0].newlines_before >= 2;
        }
        return first.newlines_before >= 2;
    }
}

## One parsed source file.
export struct Module {
    ## The imports and re-exports of sources.
    var imports: Import[] = Array<Import>();
    ## The re-exports of single symbols.
    var exports: ExportAlias[] = Array<ExportAlias>();
    ## The declarations.
    var declarations: Declaration[] = Array<Declaration>();
    ## Every attribute that tests a build option, in source order.
    var build_option_tests: Attribute[] = Array<Attribute>();
    ## Deprecated syntax, in source order. Not part of the JSON.
    var warnings: SyntaxWarning[] = Array<SyntaxWarning>();
    ## Every token, with its comments and line breaks: kept by
    ## `parse.parse_written`, not by `parse.parse`. Not part of the JSON.
    var tokens: SourceTokens?;

    ## Creates an empty module.
    construct() {}

    ## Returns the module as JSON, as `pep-build --emit-ast=json` writes it.
    ##
    ## @returns the JSON object
    to_json(): JsonValue {
        var out = JsonValue.object();
        var import_list = JsonValue.array();
        for (var item in imports) {
            import_list.append(item.to_json());
        }
        out["imports"] = import_list;
        var export_list = JsonValue.array();
        for (var item in exports) {
            export_list.append(item.to_json());
        }
        out["exports"] = export_list;
        var declaration_list = JsonValue.array();
        for (var item in declarations) {
            declaration_list.append(item.to_json());
        }
        out["declarations"] = declaration_list;
        out["build_option_tests"] = attributes_json(build_option_tests);
        return out;
    }
}

# The externally tagged form of an enum case: `{"Case": value}`.
tagged(name: String, value: JsonValue): JsonValue {
    var out = JsonValue.object();
    out[name] = value;
    return out;
}

types_json(types: TypeName[]): JsonValue {
    var out = JsonValue.array();
    for (var item in types) {
        out.append(item.to_json());
    }
    return out;
}

strings_json(strings: String[]): JsonValue {
    var out = JsonValue.array();
    for (var item in strings) {
        out.append(JsonValue.String(item));
    }
    return out;
}

expressions_json(expressions: Expression[]): JsonValue {
    var out = JsonValue.array();
    for (var item in expressions) {
        out.append(item.to_json());
    }
    return out;
}

optional_expression_json(expression: Expression?): JsonValue {
    return expression.is_value() ? expression.value().to_json() : JsonValue.Null;
}

optional_string_json(text: String?): JsonValue {
    return text.is_value() ? JsonValue.String(text.value()) : JsonValue.Null;
}

attributes_json(attributes: Attribute[]): JsonValue {
    var out = JsonValue.array();
    for (var item in attributes) {
        out.append(item.to_json());
    }
    return out;
}

variables_json(variables: VariableDecl[]): JsonValue {
    var out = JsonValue.array();
    for (var item in variables) {
        out.append(item.to_json());
    }
    return out;
}

functions_json(functions: FunctionDecl[]): JsonValue {
    var out = JsonValue.array();
    for (var item in functions) {
        out.append(item.to_json());
    }
    return out;
}

properties_json(properties: PropertyDecl[]): JsonValue {
    var out = JsonValue.array();
    for (var item in properties) {
        out.append(item.to_json());
    }
    return out;
}

generic_params_json(params: GenericParam[]): JsonValue {
    var out = JsonValue.array();
    for (var item in params) {
        out.append(item.to_json());
    }
    return out;
}

patterns_json(patterns: Pattern[]): JsonValue {
    var out = JsonValue.array();
    for (var item in patterns) {
        out.append(item.to_json());
    }
    return out;
}

bindings_json(bindings: DestructureBinding[]): JsonValue {
    var out = JsonValue.array();
    for (var item in bindings) {
        out.append(item.to_json());
    }
    return out;
}

optional_span_json(span: Span?): JsonValue {
    return span.is_value() ? span.value().to_json() : JsonValue.Null;
}

parts_json(parts: StringPart[]): JsonValue {
    var out = JsonValue.array();
    for (var part in parts) {
        out.append(part.to_json());
    }
    return out;
}
