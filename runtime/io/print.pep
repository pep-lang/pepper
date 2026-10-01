## `Print`: `print` and `print_line` for anything that writes bytes, such as
## a `File`, a `TcpStream` or a `UnixStream`.

import "file";
import "socket";
import "types";
import "unix";

## A byte stream that values can be printed to, as the global `print` prints
## to standard output.
##
## A type has the trait by providing `write_all(data: u8[])`; it then gets
## `print` and `print_line`, which write the text `to_string` makes of a
## value (the text `$"{value}"` would hold). `File`, `TcpStream` and
## `UnixStream` have it.
##
## @example
##     import io;
##
##     main(): int {
##         var path = io.Directory.temp().join("report.txt");
##         var file = io.File.create(path).value();
##         file.print("total: ");
##         file.print_line(42);
##         file.close();
##         assert(io.File.read_to_string(path).value() == "total: 42\n", "printed");
##         io.File.remove(path);
##         return 0;
##     }
export trait Print {
    ## Writes all of `data`.
    ##
    ## @param data the bytes to write
    ## @returns an Ok result once every byte is written; an error when the
    ##   stream fails
    write_all(data: u8[]): IoResult<void>;

    ## Writes the text of `value`, with no line break after it: a String as
    ## it is, anything else through `to_string`.
    ##
    ## @typeParam T the type of `value`
    ## @param value the value to print
    ## @returns an Ok result once the text is written; an error as for
    ##   `write_all`
    ## @example
    ##     file.print("n = ");
    ##     file.print(3);   # the file now holds "n = 3"
    print<T>(value: T): IoResult<void> {
        return write_all(to_string(value).bytes());
    }

    ## Writes the text of `value` and a line break (`\n`), as the global
    ## `print` does on standard output.
    ##
    ## @typeParam T the type of `value`
    ## @param value the value to print
    ## @returns an Ok result once the line is written; an error as for
    ##   `write_all`
    ## @example
    ##     file.print_line($"total: {total}");
    ##     file.print_line((1, "two"));   # (1, two)
    print_line<T>(value: T): IoResult<void> {
        return write_all((to_string(value) + "\n").bytes());
    }
}

extend File with Print {}

extend TcpStream with Print {}

extend UnixStream with Print {}
