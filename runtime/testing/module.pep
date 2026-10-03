## The test program `pep-build --test` builds: a `main` that lists the
## entry file's `[Test]` functions or runs one of them.
##
## A test build loads `testing` into every file, as `--import testing`
## would, and adds to the entry file a `main` (marked `[TestMain]`, which
## replaces the file's own) that registers each `[Test]` function with a
## `TestRunner` and calls `run`. Test files do not import it themselves:
## the checks they call, such as `expect_equal`, are in the prelude, and
## the fixture `TempFolder` (a scratch folder removed when released) is
## here.
##
## `pep-test` (`pepper test`) drives the program: it lists the tests with
## `--list` and runs each in a child process of its own with `--run NAME`
## (see the testing chapter).

# This file only gathers the module's public API from its other files.

import "runner";
import "temp_folder";

export TestMain;
export TestRunner;
export TempFolder;
export keep_for_the_program;
