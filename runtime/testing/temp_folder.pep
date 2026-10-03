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

    ## Makes the folder, removing what a crashed run left at its path.
    ##
    ## @param name a name for the folder, such as the test's
    ## @panics if the folder cannot be made
    construct(name: String) {
        path = io.Directory.temp().join($"pepper_test_{name}_{process.id()}");
        io.Directory.remove_all(path);
        var made = io.Directory.create_all(path);
        if (made.is_err()) {
            panic($"cannot make the test folder '{path}': {made.error().message}");
        }
    }

    destruct {
        io.Directory.remove_all(path);
    }
}
