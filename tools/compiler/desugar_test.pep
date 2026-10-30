# `parse.parse_written` keeps interpolated strings, `print` and
# `String.format` formats and module-scope `static` blocks as the source
# writes them; `parse.parse` returns them desugared by `compiler.desugar`.

import compiler.ast;
import [Declaration, Expression, Statement, StringPart] from compiler.ast;
import compiler.desugar;
import compiler.parse;

# The first statement of the first function of `source`, as an expression:
# an expression statement's, or a variable's initializer.
first_expression(module: ast.Module): Expression {
    if (module.declarations[0] is Function(function)) {
        var statement = function.body.value().statements[0];
        if (statement is Expression(e)) {
            return e;
        }
        if (statement is Declaration(local)) {
            if (local is Variable(variable)) {
                return variable.default_value.value();
            }
        }
    }
    return Expression.SymbolRef("", ast.Span());
}

# The name a call calls, or empty.
callee_name(e: Expression): String {
    if (e is FunctionCall(function, _, _)) {
        if (function is SymbolRef(id, _)) {
            return id;
        }
    }
    return "";
}

[Test]
parse_written_keeps_an_interpolated_string() {
    var module = parse.parse_written("f() { var s = $\"a{x:>8.2}b\"; }").value();
    var e = first_expression(module);
    expect_true(e is Interpolated(_, _), "an interpolated string stays one node");
    if (e is Interpolated(parts, span)) {
        expect_equal(parts.count, 3 as ulong);
        expect_true(parts[1] is Hole(_, _, _), "the value in braces is a hole");
        expect_equal(span.start, 14 as ulong);
    }
    expect_equal(e.to_string(), "$\"a{x:>8.2}b\"");
}

[Test]
parse_desugars_an_interpolated_string() {
    var e = first_expression(parse.parse("f() { var s = $\"a{x}\"; }").value());
    expect_true(e is Binary(_, _, _, _), "the text and the converted value are concatenated");
    if (e is Binary(_, _, rhs, _)) {
        expect_equal(callee_name(rhs), "_pep_interpolate");
    }
}

[Test]
parse_written_keeps_a_format_as_the_first_argument() {
    var e = first_expression(parse.parse_written("f() { print(\"{1} {0}\", x, y); }").value());
    expect_equal(callee_name(e), "print");
    if (e is FunctionCall(_, arguments, _)) {
        expect_equal(arguments.count, 3 as ulong);
        expect_true(arguments[0] is FormatString(_, _, _, _), "the format comes first");
        if (arguments[0] is FormatString(parts, _, paren, argument_spans)) {
            expect_equal(parts.count, 3 as ulong);
            expect_true(parts[0] is Argument(_, _, _, _), "`{1}` names an argument");
            expect_equal(paren, 11 as ulong);
            expect_equal(argument_spans.count, 2 as ulong);
        }
    }
}

[Test]
parse_desugars_a_format() {
    var e = first_expression(parse.parse("f() { print(\"{1} {0}\", x, y); }").value());
    expect_equal(callee_name(e), "print");
    if (e is FunctionCall(_, arguments, _)) {
        expect_equal(arguments.count, 1 as ulong);
        expect_true(arguments[0] is Match(_), "arguments out of order are bound in a match");
    }
    var formatted = first_expression(parse.parse("f() { var s = String.format(\"{0}!\", x); }").value());
    expect_true(formatted is Binary(_, _, _, _), "String.format is the formatted text");
}

[Test]
desugar_reports_a_format_that_does_not_match_its_arguments() {
    var source = "f() { print(\"{1}\", x); }";
    expect_true(parse.parse_written(source).is_ok(), "the faithful tree does not check the format");
    var parsed = parse.parse(source);
    expect_true(parsed.is_err(), "parse checks the format");
    if (parsed.is_err()) {
        expect_equal(parsed.error().message, "argument index 1 is out of range for 1 argument");
        expect_equal(parsed.error().span.start, 14 as ulong);
    }
}

[Test]
parse_adds_the_constants_of_a_static_block() {
    var source = "static { const N = 1; }";
    expect_equal(parse.parse_written(source).value().declarations.count, 1 as ulong);
    var declarations = parse.parse(source).value().declarations;
    expect_equal(declarations.count, 2 as ulong);
    if (declarations[1] is Variable(constant)) {
        expect_equal(constant.name, "N");
        expect_true(constant.is_const, "the constant is const");
    } else {
        expect_true(false, "the constant follows the block");
    }
}

[Test]
desugar_of_the_written_tree_is_what_parse_returns() {
    var source = "static { const N = 1; }\nf(x: int) { print(\"{1}{0}\", x, $\"{x:>4}\"); var s = String.format(\"{0}\", $\"a{x}\"); }";
    var written = parse.parse_written(source).value();
    var rewritten = desugar.desugar(written);
    expect_true(rewritten.is_ok(), "the formats match their arguments");
    expect_equal(rewritten.value().to_json().to_string(), parse.parse(source).value().to_json().to_string());
}

# The text of `e`'s first string literal or text part: a plain literal's,
# an interpolated string's, or the format's of a call; empty for any
# other expression.
first_text(e: Expression): String {
    var parts = Array<StringPart>();
    if (e is Literal(literal, _)) {
        if (literal is String(text)) {
            return text;
        }
    } else if (e is Interpolated(interpolated, _)) {
        parts = interpolated;
    } else if (e is FunctionCall(_, arguments, _)) {
        if (arguments[0] is FormatString(format, _, _, _)) {
            parts = format;
        }
    }
    if (!parts.is_empty) {
        if (parts[0] is Text(text, _)) {
            return text;
        }
    }
    return "";
}

# A line break in a string literal reads as `\n` when the file ends its
# lines `\r\n`, as a Windows checkout does, so a literal means the same on
# every system.
[Test]
parse_reads_a_crlf_line_break_in_a_string_as_a_newline() {
    for (var literal in ["\"a\r\nb\"", "$\"a\r\nb{x}\"", "print(\"a\r\nb{0}\", x)"]) {
        var source = "f() {\r\n    var s = " + literal + ";\r\n}\r\n";
        var e = first_expression(parse.parse_written(source).value());
        expect_equal(first_text(e), "a\nb");
    }
}
