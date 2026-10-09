# TempFolder: always a new, empty folder, removed with the fixture.

import io;
import process;
import "../runner";
import "../temp_folder";

[Test]
starts_empty_when_an_earlier_run_left_its_folder() {
    # What a crashed run with this process id would have left (#724).
    var stale = io.Directory.temp().join($"pepper_test_left_behind_{process.id()}");
    io.Directory.create_all(stale.join("modes").join("bin"));
    io.File.write_text(stale.join("modes").join("bin").join("run.sh"), "old");
    {
        var folder = TempFolder("left_behind");
        expect_false(folder.path.join("modes").exists());
        expect_true(folder.path.is_directory());
    }
    io.Directory.remove_all(stale);
}

[Test]
is_removed_with_the_fixture() {
    var path = io.Path("");
    {
        var folder = TempFolder("removed_with_the_fixture");
        path = folder.path;
        io.File.write_text(path.join("notes.txt"), "notes");
    }
    expect_false(path.exists());
}
