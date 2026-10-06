## `TempFolder`, a test fixture: a fresh folder that is removed with
## everything in it when the fixture is released.

import io;
import process;

## A fresh, empty folder under the system's temporary folder, for a test
## that writes files. The folder and everything in it are removed when the
## last reference to the fixture is released, so a test that holds it in a
## local cleans up when it returns.
##
## Its name joins the name the test gives with the process id, so tests
## running at once, each in a process of its own, never share a folder.
## When a folder of that name is left from an earlier run (whose process
## had the same id) and cannot be removed, a number is added to the name,
## so the folder is always new and empty.
##
## @example
##     [Test]
##     writes_a_file() {
##         var folder = TempFolder("writes_a_file");
##         var path = folder.path.join("notes.txt");
##         io.File.write_text(path, "hello");
##         expect_equal(io.File.read_to_string(path).value(), "hello");
##     }
export struct TempFolder {
    ## The folder's path.
    const path: io.Path;

    ## Makes the folder, removing what a crashed run left at its path, or
    ## taking a numbered name when that cannot be removed.
    ##
    ## @param name a name for the folder, such as the test's
    ## @panics if the folder cannot be made
    construct(name: String) {
        var base = $"pepper_test_{name}_{process.id()}";
        var fresh = io.Directory.temp().join(base);
        # A run that crashed, or whose cleanup failed, left it; a folder
        # already holding files would break the test that gets it (#724).
        io.Directory.remove_all(fresh);
        ulong number = 1;
        while (fresh.exists()) {
            fresh = io.Directory.temp().join($"{base}_{number}");
            io.Directory.remove_all(fresh);
            number += 1;
        }
        var made = io.Directory.create_all(fresh);
        if (made.is_err()) {
            panic($"cannot make the test folder '{fresh}': {made.error().message}");
        }
        path = fresh;
    }

    destruct {
        io.Directory.remove_all(path);
    }
}
