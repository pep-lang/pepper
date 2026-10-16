# The program pep-run's tests run: prints its arguments, then the file
# `data.txt` in the folder it runs in, and exits with the status its first
# argument names.
import [File] from io;

main(args: String[]): int {
    ulong index = 1;
    while (index < args.count) {
        print($"argument {args[index]}");
        index += 1;
    }
    var data = File.read_to_string("data.txt");
    print(data.is_ok() ? $"data {data.value()}" : "no data");
    if (args.count > 1) {
        return int.parse(args[1]).value_or(0);
    }
    return 0;
}
