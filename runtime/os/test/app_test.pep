# os.app_directories: none on a desktop; Foundation's folders on iOS; on
# Android, the folders pepper_set_app_directories gives. The prototype apps
# (docs/examples/mobile/) check them inside a real app.

import io;
import os;

[Test]
[Target(!OS(IOS) && !OS(Android))]
a_desktop_has_no_app_directories() {
    expect_false(os.app_directories().is_value());
}

[Test]
[Target(OS(IOS))]
ios_gives_the_containers_folders() {
    var folders = os.app_directories().value();
    expect_true(folders.documents.to_string().ends_with("/Documents"));
    expect_true(folders.cache.to_string().ends_with("/Library/Caches"));
    expect_false(folders.temp.to_string().ends_with("/"));
    var file = folders.temp.join("pepper-app-test.txt");
    expect_true(io.File.write_text(file, "scratch").is_ok());
    expect_equal(io.File.read_to_string(file).value(), "scratch");
    io.File.remove(file);
}

[Test]
[Target(OS(Android))]
android_keeps_the_folders_the_app_gives() {
    var temp = io.Directory.temp();
    var files = temp.join("pepper-app-files");
    io.Directory.create_all(files);
    # The temporary folder by another name, so that other tests' paths
    # still lead there.
    var cache = $"{temp}/.";
    pepper_set_app_directories(files.to_string(), cache);
    var folders = os.app_directories().value();
    expect_equal(folders.documents.to_string(), files.to_string());
    expect_equal(folders.cache.to_string(), cache);
    expect_equal(folders.temp.to_string(), cache);
    # `adb shell` sets TMPDIR, which comes first; an app has none.
    if (!os.environment("TMPDIR").is_value()) {
        expect_equal(io.Directory.temp().to_string(), cache);
    }
    var file = folders.documents.join("note.txt");
    expect_true(io.File.write_text(file, "kept").is_ok());
    expect_equal(io.File.read_to_string(file).value(), "kept");
    io.Directory.remove_all(files);
}
