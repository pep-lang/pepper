# Golden tests of pep-fmt's style: each formats a snippet with
# `format_source` and compares the text.

import "format";

# Checks that `source` formats to exactly `expected`.
expect_formats(source: String, expected: String) {
    var formatted = format_source(source);
    if (formatted.is_err()) {
        panic("pep-fmt failed: " + formatted.error().message);
    }
    expect_equal(formatted.value(), expected);
}

[Test]
places_braces_attributes_and_declarations() {
    expect_formats(
        "[Test] [Target(OS(Linux))] export int add(int a, int b = 2)\n"
            + "{\n"
            + "  return a+b;\n"
            + "}\n"
            + "struct Point { int x; var y: int = 0; construct(int x = 0) { this.x = x; }\n"
            + " bool ==(Point other) { return x == other.x; }\n"
            + "int [](ulong i) { return x; }\n"
            + "static Point origin() { return Point(); } }\n",
        "[Test]\n"
            + "[Target(OS(Linux))]\n"
            + "export add(a: int, b: int = 2): int {\n"
            + "    return a + b;\n"
            + "}\n"
            + "\n"
            + "struct Point {\n"
            + "    int x;\n"
            + "    var y: int = 0;\n"
            + "    construct(x: int = 0) {\n"
            + "        this.x = x;\n"
            + "    }\n"
            + "    ==(other: Point): bool { return x == other.x; }\n"
            + "    [](i: ulong): int { return x; }\n"
            + "    static origin(): Point { return Point(); }\n"
            + "}\n"
    );
}

[Test]
places_private_after_the_attributes() {
    expect_formats(
        "[Inline] private int twice(int x) { return x*2; }\nprivate   const LIMIT = 3;\nprivate struct Shelf { var count: int; }\n",
        "[Inline]\n"
            + "private twice(x: int): int { return x * 2; }\n"
            + "\n"
            + "private const LIMIT = 3;\n"
            + "\n"
            + "private struct Shelf {\n"
            + "    var count: int;\n"
            + "}\n"
    );
}

[Test]
writes_an_empty_extension_body_as_a_semicolon() {
    # After a `with` clause an empty body becomes `;`, and one-line
    # extensions sit together; a body with a comment, or with no `with`
    # clause, stays.
    expect_formats(
        "extend A with Shape {}\n"
            + "extend B with Shape, Named { }  # both\n"
            + "extend C with Shape;\n"
            + "extend D with Shape {\n"
            + "    # later\n"
            + "}\n"
            + "extend E {}\n",
        "extend A with Shape;\n"
            + "extend B with Shape, Named;  # both\n"
            + "extend C with Shape;\n"
            + "\n"
            + "extend D with Shape {\n"
            + "    # later\n"
            + "}\n"
            + "\n"
            + "extend E {}\n"
    );
}

[Test]
keeps_one_line_bodies_and_else_as_written() {
    expect_formats(
        "main(): int {\n"
            + "    for (var x in xs) { if x > 1 { continue; } else if x < 0 { break; }\n"
            + "    else { print(x); } }\n"
            + "    return 0;\n"
            + "}\n",
        "main(): int {\n"
            + "    for (var x in xs) {\n"
            + "        if x > 1 { continue; } else if x < 0 { break; } else {\n"
            + "            print(x);\n"
            + "        }\n"
            + "    }\n"
            + "    return 0;\n"
            + "}\n"
    );
}

[Test]
wraps_long_lines_after_commas_and_before_operators() {
    expect_formats(
        "main(): int {\n"
            + "    call(argument_number_one, argument_number_two, argument_number_three, argument_number_four, argument_number_five_xy);\n"
            + "    call(argument_number_one, argument_number_two, argument_number_three, argument_number_four, argument_number_five_is_long, x);\n"
            + "    if (first_condition_is_long(argument_value) and second_condition_is_long(argument_value) or third_condition(value)) { return 1; }\n"
            + "    return 0;\n"
            + "}\n",
        "main(): int {\n"
            + "    call(\n"
            + "        argument_number_one, argument_number_two, argument_number_three, argument_number_four, argument_number_five_xy\n"
            + "    );\n"
            + "    call(\n"
            + "        argument_number_one,\n"
            + "        argument_number_two,\n"
            + "        argument_number_three,\n"
            + "        argument_number_four,\n"
            + "        argument_number_five_is_long,\n"
            + "        x\n"
            + "    );\n"
            + "    if (first_condition_is_long(argument_value) and second_condition_is_long(argument_value)\n"
            + "        or third_condition(value)) { return 1; }\n"
            + "    return 0;\n"
            + "}\n"
    );
}

[Test]
breaks_before_operators_and_dots() {
    # Line breaks never end a statement, so a long expression breaks before
    # each operator, and a chain of three calls or more before each `.`.
    expect_formats(
        "main(): int {\n"
            + "    total = first_value_that_is_long_enough + second_value_that_is_long_enough + third_value_that_is_long_and_longer_still;\n"
            + "    var n = words.iterate().filter((w) => w.length() > 4).map((w) => w.length() * 2).collect_all_the_things_right_now_x();\n"
            + "    File.stderr().write_string(\"a message that is long enough to need its own line, and then some more words to be sure\");\n"
            + "    return 0;\n"
            + "}\n",
        "main(): int {\n"
            + "    total = first_value_that_is_long_enough\n"
            + "        + second_value_that_is_long_enough\n"
            + "        + third_value_that_is_long_and_longer_still;\n"
            + "    var n = words\n"
            + "        .iterate()\n"
            + "        .filter((w) => w.length() > 4)\n"
            + "        .map((w) => w.length() * 2)\n"
            + "        .collect_all_the_things_right_now_x();\n"
            + "    File.stderr().write_string(\n"
            + "        \"a message that is long enough to need its own line, and then some more words to be sure\"\n"
            + "    );\n"
            + "    return 0;\n"
            + "}\n"
    );
}

[Test]
keeps_a_dotted_import_together() {
    expect_formats(
        "import  geo.solids   as s;\n" + "import http.client;\n", "import http.client;\n" + "import geo.solids as s;\n"
    );
}

[Test]
sorts_imports_and_aligns_trailing_comments() {
    expect_formats(
        "import \"zeta\";\n"
            + "import \"alpha\"; # a file\n"
            + "import io;\n"
            + "\n"
            + "const A = 1; # one\n"
            + "const LONGER = 2;   # two\n",
        "import io;\n"
            + "import \"alpha\";  # a file\n"
            + "import \"zeta\";\n"
            + "\n"
            + "const A = 1;       # one\n"
            + "const LONGER = 2;  # two\n"
    );
}

[Test]
keeps_the_blank_line_after_a_file_comment_when_sorting_imports() {
    expect_formats(
        "# A file.\n"
            + "\n"
            + "import \"types\";\n"
            + "import \"path\";\n"
            + "import \"file\";\n"
            + "\n"
            + "const A = 1;\n",
        "# A file.\n"
            + "\n"
            + "import \"file\";\n"
            + "import \"path\";\n"
            + "import \"types\";\n"
            + "\n"
            + "const A = 1;\n"
    );
}

[Test]
leaves_out_a_void_return_type() {
    expect_formats(
        "void run(int n) { go(n); }\n" + "stop(): void { go(0); }\n" + "trait T { void tick(); }\n",
        "run(n: int) {\n"
            + "    go(n);\n"
            + "}\n"
            + "\n"
            + "stop() {\n"
            + "    go(0);\n"
            + "}\n"
            + "\n"
            + "trait T {\n"
            + "    tick(): void;\n"
            + "}\n"
    );
}

[Test]
leaves_format_off_regions_as_written() {
    expect_formats(
        "# The grid.\n"
            + "# format: off\n"
            + "const GRID = add(1, 0,\n"
            + "                 0, 1);\n"
            + "# format: on\n"
            + "var  x=1;\n"
            + "\n"
            + "main(): int {\n"
            + "  var a=1;\n"
            + "    # format: off\n"
            + "    var   b   = 2;   # aligned\n"
            + "    if (a) { f(); }\n"
            + "    # format: on\n"
            + "  var c=3;\n"
            + "  return 0;\n"
            + "}\n",
        "# The grid.\n"
            + "# format: off\n"
            + "const GRID = add(1, 0,\n"
            + "                 0, 1);\n"
            + "# format: on\n"
            + "var x = 1;\n"
            + "\n"
            + "main(): int {\n"
            + "    var a = 1;\n"
            + "    # format: off\n"
            + "    var   b   = 2;   # aligned\n"
            + "    if (a) { f(); }\n"
            + "    # format: on\n"
            + "    var c = 3;\n"
            + "    return 0;\n"
            + "}\n"
    );
}

[Test]
runs_format_off_to_the_end_without_format_on() {
    expect_formats(
        "main() {\n" + "  f(  1 );\n" + "  # format: off\n" + "  g(  2 );\n" + "  h(  3 );\n" + "}\n" + "var  y=1;\n",
        "main() {\n"
            + "    f(1);\n"
            + "    # format: off\n"
            + "  g(  2 );\n"
            + "  h(  3 );\n"
            + "}\n"
            + "\n"
            + "var y = 1;\n"
    );
}

[Test]
keeps_crlf_in_format_off_regions() {
    expect_formats(
        "var  a=1;\r\n" + "# format: off\r\n" + "var   b=2;\r\n" + "# format: on\r\n" + "var  c=3;\r\n",
        "var a = 1;\r\n" + "# format: off\r\n" + "var   b=2;\r\n" + "# format: on\r\n" + "var c = 3;\r\n"
    );
}

[Test]
keeps_parameter_attributes_inline() {
    expect_formats(
        "struct Box<T> {\n" + "    send([Move] value: T, [Move] [Sending] other: T) { take(value); }\n" + "}\n",
        "struct Box<T> {\n"
            + "    send([Move] value: T, [Move] [Sending] other: T) {\n"
            + "        take(value);\n"
            + "    }\n"
            + "}\n"
    );
}

[Test]
puts_branch_hints_above_their_branch() {
    expect_formats(
        "f(n: int): int {\n"
            + "    [Unlikely] if (n < 0) { return -1; } else\n"
            + "    [Likely]\n"
            + "    if (n > 0) { return 1; }\n"
            + "    match (n) {\n"
            + "        [Likely] 0 => { return 0; }\n"
            + "        [Unlikely] else => { return 2; }\n"
            + "    }\n"
            + "}\n",
        "f(n: int): int {\n"
            + "    [Unlikely]\n"
            + "    if (n < 0) { return -1; } else [Likely] if (n > 0) { return 1; }\n"
            + "    match (n) {\n"
            + "        [Likely]\n"
            + "        0 => { return 0; }\n"
            + "        [Unlikely]\n"
            + "        else => { return 2; }\n"
            + "    }\n"
            + "}\n"
    );
}

[Test]
spaces_export_from_and_keeps_its_order() {
    expect_formats(
        "import \"b\";\n"
            + "import \"a\";\n"
            + "export   *   from \"zeta\";\n"
            + "[Target(OS(Linux))] export  [ x as y,z ]  from   \"alpha\";\n"
            + "export * from io;\n",
        "import \"a\";\n"
            + "import \"b\";\n"
            + "export * from \"zeta\";\n"
            + "[Target(OS(Linux))]\n"
            + "export [x as y, z] from \"alpha\";\n"
            + "export * from io;\n"
    );
}

[Test]
keeps_comments_blank_lines_and_line_endings() {
    expect_formats(
        "# header\n"
            + "\n"
            + "\n"
            + "\n"
            + "## Doc.\n"
            + "f(): int {\n"
            + "    # before\n"
            + "\n"
            + "\n"
            + "    return 0;\n"
            + "    # after\n"
            + "}\n"
            + "# end\n",
        "# header\n"
            + "\n"
            + "## Doc.\n"
            + "f(): int {\n"
            + "    # before\n"
            + "\n"
            + "    return 0;\n"
            + "    # after\n"
            + "}\n"
            + "# end\n"
    );
    expect_formats(
        "main(): int {\r\n" + "  return 0;\r\n" + "}\r\n", "main(): int {\r\n" + "    return 0;\r\n" + "}\r\n"
    );
}

[Test]
keeps_character_literals_as_written() {
    expect_formats(
        "main(): int {\n"
            + "    var q='\"';\n"
            + "    if (q=='#' or q=='\\'' or q=='\\x7F') { return 1; }\n"
            + "    return 0;\n"
            + "}\n",
        "main(): int {\n"
            + "    var q = '\"';\n"
            + "    if (q == '#' or q == '\\'' or q == '\\x7F') { return 1; }\n"
            + "    return 0;\n"
            + "}\n"
    );
}

[Test]
keeps_interpolated_strings_as_written() {
    expect_formats(
        "main(): int {\n"
            + "    var n=1;\n"
            + "    print($\"n = {n}, {{literal}} \\\"q\\\"\"+$\"\");\n"
            + "    return 0;\n"
            + "}\n",
        "main(): int {\n"
            + "    var n = 1;\n"
            + "    print($\"n = {n}, {{literal}} \\\"q\\\"\" + $\"\");\n"
            + "    return 0;\n"
            + "}\n"
    );
}

[Test]
keeps_interpolated_expressions_as_written() {
    # The braces' expressions, strings and braces in them included, stay
    # inside the one string token.
    expect_formats(
        "main(): int {\n"
            + "    print($\"{a+b} {f(\"}\")} {c?\"x\":'}'} {$\"<{n}>\"} {{\"+x);\n"
            + "    return 0;\n"
            + "}\n",
        "main(): int {\n"
            + "    print($\"{a+b} {f(\"}\")} {c?\"x\":'}'} {$\"<{n}>\"} {{\" + x);\n"
            + "    return 0;\n"
            + "}\n"
    );
}

[Test]
keeps_format_specifications_as_written() {
    # A specification stays inside its string token; String.format is an
    # ordinary call to the formatter.
    expect_formats(
        "main(): int {\n"
            + "    print($\"{n:>8} {n:08x} {c?a:b:-^5}\"+String.format( \"{1}{0:x}\",a,b ));\n"
            + "    return 0;\n"
            + "}\n",
        "main(): int {\n"
            + "    print($\"{n:>8} {n:08x} {c?a:b:-^5}\" + String.format(\"{1}{0:x}\", a, b));\n"
            + "    return 0;\n"
            + "}\n"
    );
}

[Test]
spaces_tuples_and_destructuring() {
    expect_formats(
        "pair():(int,(String,long)) {\n"
            + "    return (1,(\"x\",2));\n"
            + "}\n"
            + "\n"
            + "main(): int {\n"
            + "    var (a,b:(String,long))=pair();\n"
            + "    const (_ ,c)=( b.1 ,a );\n"
            + "    (a,c)=(c,a);\n"
            + "    return pair().1.1+b.1;\n"
            + "}\n",
        "pair(): (int, (String, long)) {\n"
            + "    return (1, (\"x\", 2));\n"
            + "}\n"
            + "\n"
            + "main(): int {\n"
            + "    var (a, b: (String, long)) = pair();\n"
            + "    const (_, c) = (b.1, a);\n"
            + "    (a, c) = (c, a);\n"
            + "    return pair().1.1 + b.1;\n"
            + "}\n"
    );
}

[Test]
reads_optional_tuples() {
    expect_formats(
        "find():(int,String)? {\n" + "    var p:(line:int,column:int)?=q;\n" + "    return r;\n" + "}\n",
        "find(): (int, String)? {\n" + "    var p: (line: int, column: int)? = q;\n" + "    return r;\n" + "}\n"
    );
}

[Test]
reads_tuple_arrays() {
    expect_formats(
        "find():(int,String)[] {\n" + "    var p:(line:int,column:int)[][]?=q;\n" + "    return r;\n" + "}\n",
        "find(): (int, String)[] {\n" + "    var p: (line: int, column: int)[][]? = q;\n" + "    return r;\n" + "}\n"
    );
}

[Test]
formats_labeled_tuple_literals() {
    expect_formats(
        "f():(line:int,column:int) {\n"
            + "    var p=(line:3,column:a?b:c);\n"
            + "    return (line:p.line,column:( x:1,y:2 ).x);\n"
            + "}\n",
        "f(): (line: int, column: int) {\n"
            + "    var p = (line: 3, column: a ? b : c);\n"
            + "    return (line: p.line, column: (x: 1, y: 2).x);\n"
            + "}\n"
    );
}

[Test]
reads_optional_types_and_keeps_ternaries() {
    expect_formats(
        "struct S {\n"
            + "    Token?  leaf;\n"
            + "}\n"
            + "f(x:int?):Array<int?> {\n"
            + "    Node? a=x;\n"
            + "    c ? d : e;\n"
            + "    var g=h?i:j;\n"
            + "    return k;\n"
            + "}\n",
        "struct S {\n"
            + "    Token? leaf;\n"
            + "}\n"
            + "\n"
            + "f(x: int?): Array<int?> {\n"
            + "    Node? a = x;\n"
            + "    c ? d : e;\n"
            + "    var g = h ? i : j;\n"
            + "    return k;\n"
            + "}\n"
    );
}

[Test]
formats_tuple_patterns() {
    expect_formats(
        "f(a:Shape,n:int):int {\n"
            + "    match ((a,n)) {\n"
            + "        (Circle,0),(Line,_)=>{ return 1; }\n"
            + "        (Text(t,_),( x,\"y\" ))=>{ return 2; }\n"
            + "        else=>{ return 3; }\n"
            + "    }\n"
            + "    if ((a,n) is (Circle,k)) { return k; }\n"
            + "    return 0;\n"
            + "}\n",
        "f(a: Shape, n: int): int {\n"
            + "    match ((a, n)) {\n"
            + "        (Circle, 0), (Line, _) => { return 1; }\n"
            + "        (Text(t, _), (x, \"y\")) => { return 2; }\n"
            + "        else => { return 3; }\n"
            + "    }\n"
            + "    if ((a, n) is (Circle, k)) { return k; }\n"
            + "    return 0;\n"
            + "}\n"
    );
}

[Test]
formats_match_expressions_is_tests_and_literal_patterns() {
    expect_formats(
        "f(d:Doc):int {\n"
            + "    var w=match(d){Text(t,u)=>t.length(),Line=>1,else=>0};\n"
            + "    match (n) {\n"
            + "        -1,2=>{ return 1; }\n"
            + "        \"a\"=>{ return 2; }\n"
            + "        else=>{ return 3; }\n"
            + "    }\n"
            + "    if (d is Text(a,_)) { return 1; }\n"
            + "    return w;\n"
            + "}\n",
        "f(d: Doc): int {\n"
            + "    var w = match (d) {\n"
            + "        Text(t, u) => t.length(),\n"
            + "        Line => 1,\n"
            + "        else => 0\n"
            + "    };\n"
            + "    match (n) {\n"
            + "        -1, 2 => { return 1; }\n"
            + "        \"a\" => { return 2; }\n"
            + "        else => { return 3; }\n"
            + "    }\n"
            + "    if (d is Text(a, _)) { return 1; }\n"
            + "    return w;\n"
            + "}\n"
    );
}

[Test]
formats_guards() {
    expect_formats(
        "f(s:Shape):int {\n"
            + "    var w=match(s){Circle(r)if r>10=>1,else=>0};\n"
            + "    match (s) {\n"
            + "        Rect(a,b)  if  a==b=>{ return 1; }\n"
            + "        else=>{ return w; }\n"
            + "    }\n"
            + "}\n",
        "f(s: Shape): int {\n"
            + "    var w = match (s) {\n"
            + "        Circle(r) if r > 10 => 1,\n"
            + "        else => 0\n"
            + "    };\n"
            + "    match (s) {\n"
            + "        Rect(a, b) if a == b => { return 1; }\n"
            + "        else => { return w; }\n"
            + "    }\n"
            + "}\n"
    );
}

[Test]
formats_range_and_constant_patterns() {
    expect_formats(
        "f(n:int):int {\n"
            + "    return match(n){1 .. 9=>1,MIN..> limits.MAX=>2,LIMIT=>3,-5..-1=>4,else=>0};\n"
            + "}\n",
        "f(n: int): int {\n"
            + "    return match (n) {\n"
            + "        1..9 => 1,\n"
            + "        MIN..>limits.MAX => 2,\n"
            + "        LIMIT => 3,\n"
            + "        -5..-1 => 4,\n"
            + "        else => 0\n"
            + "    };\n"
            + "}\n"
    );
}

[Test]
formats_enum_properties() {
    expect_formats(
        "enum Size {\n"
            + "    Small,\n"
            + "    Large,\n"
            + "\n"
            + "    var ounces:int { get { return 8; } }\n"
            + "    double():int { return ounces*2; }\n"
            + "}\n",
        "enum Size {\n"
            + "    Small,\n"
            + "    Large,\n"
            + "\n"
            + "    var ounces: int {\n"
            + "        get { return 8; }\n"
            + "    }\n"
            + "    double(): int { return ounces * 2; }\n"
            + "}\n"
    );
}

[Test]
spaces_collection_literals() {
    expect_formats(
        "main(): int {\n"
            + "    var a = [1,2 , 3];\n"
            + "    var m = [\"a\" :1, \"b\":[2]];\n"
            + "    HashMap<String, int> e = [ : ];\n"
            + "    return 0;\n"
            + "}\n",
        "main(): int {\n"
            + "    var a = [1, 2, 3];\n"
            + "    var m = [\"a\": 1, \"b\": [2]];\n"
            + "    HashMap<String, int> e = [:];\n"
            + "    return 0;\n"
            + "}\n"
    );
}

[Test]
keeps_a_lane_count_type_argument() {
    expect_formats("var v = simd.Vector<byte,16>( 1 as byte );\n", "var v = simd.Vector<byte, 16>(1 as byte);\n");
}
