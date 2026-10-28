# `pep-new` and `pep-init` end to end: the tools scripts/pepper-tests.sh
# built (beside the test program or on the PATH) scaffold projects into
# temporary folders, which `pepper build` and `pepper test` then build and
# test as a user would.

import [Path] from io;
import os;
import process;
import [TempFolder] from testing;
import [expect_contains, expect_exit, expect_starts_with, read_file, run, tool, write_file] from tool_testing;

# Runs the tool `name` (`pep-new`, `pep-init`, `pepper`) in `folder`.
in_folder(folder: Path, name: String, arguments: String[]): process.Output {
    return run(process.Command(tool(name).to_string()).arguments(arguments).working_directory(folder));
}

[Test]
a_new_program_builds_runs_and_passes_its_test() {
    var folder = TempFolder("pep_new_program");
    var made = in_folder(folder.path, "pep-new", ["hello"]);
    expect_exit(made, 0);
    expect_equal(made.stdout, $"Created program 'hello' in hello\n");
    var project = folder.path.join("hello");
    expect_equal(read_file(project.join("pep.toml")), "[package]\nname = \"hello\"\nversion = \"0.1.0\"\n");
    expect_contains(read_file(project.join(".gitignore")), "/.pep/\n");
    expect_starts_with(read_file(project.join("README.md")), "# hello\n");

    expect_exit(in_folder(project, "pepper", ["build"]), 0);
    var suffix = os.system_os() == os.OperatingSystem.Windows ? ".exe" : "";
    var ran = run(process.Command(project.join("hello" + suffix).to_string()));
    expect_exit(ran, 0);
    expect_equal(ran.stdout, "Hello, world!\n");
    var tested = in_folder(project, "pepper", ["test"]);
    expect_exit(tested, 0);
    expect_contains(tested.stdout, "1 passed, 0 failed");
}

# `--lib` writes pep-lang/pepper-package-template's files, named for the
# package, and its tests pass with the package on the import path under
# its name, as the template's `tests/run.sh` puts it (that script needs a
# POSIX shell; the template's CI runs it).
[Test]
a_new_package_passes_its_tests() {
    var folder = TempFolder("pep_new_package");
    var packages = folder.path.join("packages");
    var project = packages.join("geometry");
    expect_exit(in_folder(folder.path, "pep-new", [project.to_string(), "--lib", "--license", "MIT"]), 0);
    var manifest = read_file(project.join("pep.toml"));
    expect_starts_with(manifest, "[package]\nname = \"geometry\"\nversion = \"0.1.0\"\n");
    expect_contains(manifest, "license = \"MIT\"\n");
    expect_starts_with(read_file(project.join("LICENSE")), "MIT License\n\nCopyright (c) The geometry authors\n");
    expect_contains(read_file(project.join("README.md")), "\n## License\n\nMIT; see [LICENSE](LICENSE).\n");
    expect_contains(read_file(project.join("tests").join("greet_test.pep")), "import geometry;\n");
    expect_contains(read_file(project.join("add.pep")), "extern int geometry_add(int a, int b);\n");
    expect_contains(read_file(project.join(".github").join("workflows").join("ci.yml")), "bash tests/run.sh");

    # Its `[native]` table links native/add.c, which tests/add_test.pep calls.
    var tested = in_folder(project, "pepper", ["test", "-I", packages.to_string(), "tests"]);
    expect_exit(tested, 0);
    expect_contains(tested.stdout, "2 passed, 0 failed");
    # Its CI publishes its reference, which needs every public declaration documented.
    expect_exit(in_folder(project, "pep-doc", ["package", "--check"]), 0);
}

# `pep-init` names the project after the current folder, and without
# `--license` names no license.
[Test]
init_starts_a_package_in_the_current_folder() {
    var folder = TempFolder("pep_init");
    var project = folder.path.join("shapes");
    write_file(project.join("notes.txt"), "kept");
    var made = in_folder(project, "pep-init", ["--lib"]);
    expect_exit(made, 0);
    expect_equal(made.stdout, "Created package 'shapes' in .\n");
    var manifest = read_file(project.join("pep.toml"));
    expect_contains(manifest, "name = \"shapes\"\n");
    expect_false(manifest.contains("license"));
    expect_false(read_file(project.join("README.md")).contains("## License"));
    expect_false(project.join("LICENSE").exists());
    expect_equal(read_file(project.join("notes.txt")), "kept");
}

# Any file there already stops the whole scaffold, and is named.
[Test]
refuses_to_overwrite_and_writes_nothing() {
    var folder = TempFolder("pep_new_refuses");
    write_file(folder.path.join("README.md"), "mine");
    write_file(folder.path.join("main.pep"), "mine");
    var refused = in_folder(folder.path, "pep-init", Array<String>());
    expect_exit(refused, 1);
    expect_equal(
        refused.stderr,
        $"pep-init: error: nothing written: these files are there already\n  {Path(".").join("main.pep")}\n  {Path(".").join("README.md")}\n"
    );
    expect_false(folder.path.join("pep.toml").exists());
    expect_equal(read_file(folder.path.join("README.md")), "mine");
}

[Test]
checks_the_name_as_pep_toml_does_and_suggests_one() {
    var folder = TempFolder("pep_new_names");
    var bad = in_folder(folder.path, "pep-new", ["my-app"]);
    expect_exit(bad, 1);
    expect_equal(
        bad.stderr,
        "pep-new: error: package name 'my-app' is not an identifier: use letters, digits and '_', not starting with a digit; try '--name my_app'\n"
    );
    expect_false(folder.path.join("my-app").exists());
    expect_contains(in_folder(folder.path, "pep-new", ["x", "--name", "2d"]).stderr, "; try '--name _2d'\n");
    expect_equal(
        in_folder(folder.path, "pep-new", ["match", "--lib"]).stderr,
        "pep-new: error: package name 'match' is a reserved word, which 'import' cannot name; try '--name match_'\n"
    );
    expect_exit(in_folder(folder.path, "pep-new", ["my-app", "--name", "my_app"]), 0);
    expect_contains(read_file(folder.path.join("my-app").join("pep.toml")), "name = \"my_app\"\n");

    var license = in_folder(folder.path, "pep-new", ["y", "--license", "GPL-3.0"]);
    expect_exit(license, 1);
    expect_equal(license.stderr, "pep-new: error: no license text for 'GPL-3.0': --license takes MIT or Apache-2.0\n");
    expect_exit(in_folder(folder.path, "pep-new", Array<String>()), 2);
}
