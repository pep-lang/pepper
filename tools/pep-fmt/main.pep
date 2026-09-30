# pep-fmt: formats Pepper source in the standard style, like gofmt.
#
# Reads a source file on standard input and writes it, formatted, to standard
# output. On a syntax error it writes a clang-style diagnostic to standard
# error, writes nothing to standard output, and exits with status 1.
#
# Build it from the repository root with the tools folder on the import path:
#
#     pepper -I tools tools/pep-fmt/main.pep -o pep-fmt
#     pep-fmt < file.pep > formatted.pep

import [File] from io;
import syntax;
import "format";

main(): int {
    var input = File.stdin().read_string();
    if (input.is_err()) {
        File.stderr().write_string("pep-fmt: error: cannot read standard input: " + input.Error.Message + "\n");
        return 1;
    }
    var source = input.value();
    var formatted = format_source(source);
    if (formatted.is_err()) {
        var error = formatted.Error;
        var line = syntax.line_of(source, error.offset);
        var column = syntax.column_of(source, error.offset);
        File.stderr().write_string(
            "<stdin>:" + number_text(line) + ":" + number_text(column) + ": error: " + error.message + "\n"
        );
        return 1;
    }
    File.stdout().write_string(formatted.value());
    return 0;
}

# The decimal digits of `value`. The runtime has no number formatting yet.
number_text(value: ulong): String {
    if (value == 0) {
        return "0";
    }
    var digits = Array<String>();
    var remaining = value;
    while (remaining > 0) {
        var digit = remaining % 10;
        digits.append("0123456789".substr(digit, 1));
        remaining = remaining / 10;
    }
    var result = "";
    while (!digits.empty()) {
        result += digits.pop();
    }
    return result;
}
