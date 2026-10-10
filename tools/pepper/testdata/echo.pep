# Prints its arguments joined by `|`, with an argument `cwd` replaced by
# the current folder, and exits with the number after an argument `exit`,
# or 0.

import process;

main(args: String[]): int {
    var shown = Array<String>();
    ulong index = 1;
    var code = 0;
    while (index < args.count) {
        if (args[index] == "cwd") {
            shown.append(process.working_directory().value().to_string());
        } else {
            shown.append(args[index]);
        }
        if (args[index] == "exit" and index + 1 < args.count) {
            code = int.parse(args[index + 1]).value();
        }
        index += 1;
    }
    print("|".join(shown));
    return code;
}
