# Prints its id, then replaces itself with a shell that prints its own id,
# a variable set for it and its folder, and exits with 9
# (programs_test.pep). POSIX only.

import io;
import process;

main(): int {
    print($"{process.id()}");
    var temporary = io.Path("/tmp");
    var error = process
        .Command("sh")
        .arguments(["-c", "echo $$; echo $PEP_EXEC; pwd; exit 9"])
        .environment("PEP_EXEC", "set")
        .working_directory(temporary)
        .exec();
    print($"exec returned: {error.message}");
    return 1;
}
