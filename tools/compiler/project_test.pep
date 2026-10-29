# The compiler's linker reads `pep.toml`: the manifest, its errors at the
# keys they are about, imports of a project's dependencies resolved in
# the project, and what `--locked` and `--offline` refuse to fetch.

import compiler.driver;
import io;
import [Directory, File, Path] from io;
import compiler.link;
import [TempFolder] from testing;

# What `text`'s problems say, each after the text it points at, one per
# line.
errors(text: String): String {
    var out = Array<String>();
    var parsed = link.parse_manifest(Path("pep.toml"), text);
    if (parsed.is_ok()) {
        return "";
    }
    for (var e in parsed.error()) {
        out.append($"{text.substr_bytes(e.span.start, e.span.end - e.span.start)}: {e.message}");
    }
    return "\n".join(out);
}

[Test]
reads_a_manifest() {
    var text = "[package]\nname = \"my_app\"\nversion = \"0.1.0\"\nauthors = [\"A\", \"B\"]\n\n[build]\nentry = \"src/main.pep\"\ninclude = [\"vendor\"]\nlink = [\"m\"]\n\n[dependencies]\ngeometry = { github = \"someone/geometry\", version = \"1.2\" }\njson = { gitlab = \"group/sub/pepper-json\", tag = \"v0.4.0\" }\nhttp = { codeberg = \"someone/http\", branch = \"main\" }\nlocal = { path = \"../local\" }\n";
    var parsed = link.parse_manifest(Path("/p/pep.toml"), text);
    expect_true(parsed.is_ok());
    var m = parsed.value();
    expect_equal(m.name, "my_app");
    expect_equal(m.entry_file.value(), "src/main.pep");
    expect_equal("\n".join(m.link), "m");
    expect_equal("\n".join(m.include), "vendor");
    var names = Array<String>();
    for (var d in m.dependencies) {
        names.append(d.name);
    }
    expect_equal(", ".join(names), "geometry, json, http, local");
    expect_true(m.dependencies[1].host.value() == link.Host.GitLab);
    expect_equal(m.dependencies[1].location, "group/sub/pepper-json");
    # Joined part by part, so the separators are the platform's (`\` on
    # Windows).
    var root = Path("/p");
    expect_equal(
        m.dependencies[0].directory(root, root).to_string(),
        root
            .join(Path(".pep"))
            .join(Path("deps"))
            .join(Path("github.com"))
            .join(Path("someone"))
            .join(Path("geometry"))
            .to_string()
    );
    expect_equal(m.dependencies[3].directory(root, root).to_string(), root.join(Path("../local")).to_string());
    # A vendored project's packages are in its vendor folder.
    expect_equal(
        m.dependencies[0].directory(root, root, "third_party").to_string(),
        root.join(Path("third_party")).join(Path("github.com")).join(Path("someone")).join(Path("geometry")).to_string()
    );
    var vendored = link.parse_manifest(
        Path("/p/pep.toml"), "[package]\nname = \"a\"\n[fetch]\nvendor = \"third_party\"\n"
    );
    expect_equal(vendored.value().vendor, "third_party");
    expect_equal(m.dependencies[0].locked_source().value(), "github:someone/geometry");
    expect_false(m.dependencies[3].locked_source().is_value());
}

[Test]
reports_problems_at_the_key() {
    expect_equal(
        errors(
            "[package]\nname = \"a\"\n[dependencies]\njson = { github = \"x/json\" }\njson = { github = \"y/json\" }\n"
        ),
        "json: duplicate key 'json'"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[dependencies]\nfast-json = { github = \"x/json\" }\n"),
        "fast-json: dependency name 'fast-json' is not an identifier; it is the name 'import' uses"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[dependencies]\njson = { github = \"x/json\", path = \"y\" }\n"),
        "path: 'path' is a second source; a dependency comes from one of 'github', 'gitlab', 'codeberg' or 'path'"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[dependencies]\njson = { github = \"json\" }\n"),
        "\"json\": 'github' must name a repository as 'owner/name', not 'json'"
    );
    expect_equal(
        errors(
            "[package]\nname = \"a\"\n[dependencies]\njson = { github = \"x/json\", tag = \"v1\", branch = \"b\" }\n"
        ),
        "branch: 'tag' and 'branch' both choose a revision; give one of 'version', 'branch', 'tag' or 'commit'"
    );
    expect_equal(errors("[package]\nversion = \"1\"\n"), "package: '[package]' needs a 'name'");
    expect_equal(errors("[package]\nname = \"a\"\ntoolchain = \"0.3\"\n"), "");
    expect_equal(
        errors("[package]\nname = \"a\"\ntoolchain = \"0.03\"\n"),
        "\"0.03\": toolchain '0.03' is not a version such as 0.3.0, 0.3 or latest"
    );
    expect_equal(errors("[package]\nname = \"a\"\nminimum_toolchain = \"0.11.0-dev\"\n"), "");
    expect_equal(
        errors("[package]\nname = \"a\"\nminimum_toolchain = \"0.11\"\n"),
        "\"0.11\": minimum_toolchain '0.11' is not a release such as 0.11.0 or 0.11.0-dev"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[bulid]\n"),
        "bulid: unknown table 'bulid'; a pep.toml has '[package]', '[build]', '[dependencies]', '[dev-dependencies]', '[build-dependencies]', '[native]', '[target]', '[features]', '[overrides]', '[fetch]', '[workspace]', '[retract]' and '[audit]'"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[fetch]\nhosts = [\"codeberg\", \"gitub\"]\n"),
        "\"gitub\": 'hosts' lists 'github', 'gitlab' or 'codeberg'"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[build]\nentyr = \"x\"\n"),
        "entyr: unknown key 'entyr' in '[build]'; expected one of 'entry', 'output', 'include', 'link', 'script'"
    );
    expect_equal(errors("[package]
name = \"a\"
[build]
script = \"tools/build.pep\"
"), "");
    expect_equal(
        errors("[package]
name = \"a\"
[build]
script = true
"), "true: 'script' must be a string, not a boolean"
    );
    expect_equal(errors("[package]\nname = \"a\"\n[fetch]\nhosts = [\"codeberg\", \"github\"]\n"), "");
    # `package` names a member of a repository's workspace.
    expect_equal(
        errors("[package]\nname = \"a\"\n[dependencies]\ngeo = { path = \"../geo\", package = \"geo\" }\n"),
        "package: 'package' names a member of a Git repository's workspace; a 'path' names the member's folder itself"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[dependencies]\ngeo = { github = \"x/kit\", package = \"geo-lib\" }\n"),
        "\"geo-lib\": 'package' names a workspace member by its package name, and 'geo-lib' is not one"
    );
    var member = link.parse_manifest(
        Path("/p/pep.toml"),
        "[package]\nname = \"a\"\n[dependencies]\ngeo = { github = \"x/kit\", package = \"geo\" }\n"
    );
    expect_equal(member.value().dependencies[0].locked_source().value(), "github:x/kit#geo");
    expect_equal(link.Host.GitHub.clone_url("x/kit#geo"), "https://github.com/x/kit.git");
    expect_equal(
        errors("[package]\nname = \"a\"\n[fetch]\nvendor = [\"x\"]\n"), "[: 'vendor' must be a string, not an array"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[retract]\n\"1.0.1\" = \"bad\"\n[audit]\nignore = [\"PEP-1\"]\n"), ""
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[retract]\n\"1.0.1\" = 1\n"), "1: '1.0.1' must be a string, not an integer"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[audit]\nignores = []\n"),
        "ignores: unknown key 'ignores' in '[audit]'; expected one of 'ignore'"
    );
}

[Test]
finds_line_and_column() {
    var (line, column) = link.line_column("ab\ncd", 4);
    expect_equal(line, 2);
    expect_equal(column, 2);
    var (first_line, first_column) = link.line_column("ab", 0);
    expect_equal(first_line, 1);
    expect_equal(first_column, 1);
}

[Test]
resolves_imports_of_a_projects_dependencies() {
    var folder = TempFolder("project_dependencies");
    var root = folder.path;
    Directory.create_all(root.join(Path("lib")).join(Path("geo")));
    File.write_text(
        root.join(Path("lib")).join(Path("geo")).join(Path("module.pep")),
        "export area(w: int, h: int): int {\n    return w * h;\n}\n"
    );
    File.write_text(
        root.join(Path("pep.toml")),
        "[package]\nname = \"p\"\n[dependencies]\ngeo = { path = \"lib/geo\" }\nnet = { github = \"nobody/net\" }\n"
    );
    File.write_text(root.join(Path("main.pep")), "import geo;\nmain(): int {\n    return geo.area(2, 3) - 6;\n}\n");
    var setup = link.Setup();
    setup.runtime = false;
    var program = link.load_program(root.join(Path("main.pep")), setup);
    expect_true(program.is_ok());
    expect_false(program.value().check().is_value());
    var found = false;
    for (var f in program.value().files) {
        if (f.name.ends_with("module.pep")) {
            found = true;
        }
    }
    expect_true(found);

    # A Git dependency not yet fetched.
    File.write_text(root.join(Path("main.pep")), "import net;\nmain(): int {\n    return 0;\n}\n");
    var missing = link.load_program(root.join(Path("main.pep")), setup);
    expect_true(missing.is_ok());
    var report = missing.value().check();
    expect_true(report.is_value());
    expect_true(report.value().contains("dependency 'net' is not fetched: no "));
}

[Test]
reports_an_unfetched_dependency_of_a_path_dependency() {
    var folder = TempFolder("path_dependency_dependencies");
    var lib = folder.path.join(Path("lib"));
    var app = folder.path.join(Path("app"));
    Directory.create_all(lib);
    Directory.create_all(app);
    # `lib` and `app` name each other: the walk stops at a folder seen.
    File.write_text(
        lib.join(Path("pep.toml")),
        "[package]\nname = \"lib\"\n[dependencies]\nterm = { github = \"nobody/term\" }\napp = { path = \"../app\" }\n"
    );
    File.write_text(
        lib.join(Path("module.pep")), "import term;\nexport reset(): String {\n    return term.RESET;\n}\n"
    );
    File.write_text(
        app.join(Path("pep.toml")),
        "[package]\nname = \"app\"\n[dependencies]\nlib = { path = \"../lib\" }\nnet = { github = \"nobody/net\" }\n"
    );
    File.write_text(app.join(Path("main.pep")), "import lib;\nmain(): int {\n    return lib.reset().size as int;\n}\n");

    # `pepper build` fetches the path dependency's Git dependencies too.
    var manifest = link.load_manifest(app.join(Path("pep.toml")), Array<Path>());
    expect_true(manifest.is_ok());
    var names = Array<String>();
    for (var d in manifest.value().git_dependencies()) {
        names.append(d.name);
    }
    expect_equal(names.count, 2);
    expect_equal(names[0], "net");
    expect_equal(names[1], "term");

    # Unfetched, the error is at the path dependency's import.
    var setup = link.Setup();
    setup.runtime = false;
    var program = link.load_program(app.join(Path("main.pep")), setup);
    expect_true(program.is_ok());
    var report = program.value().check();
    expect_true(report.is_value());
    expect_true(report.value().contains("module.pep:1:8: error: dependency 'term' is not fetched: no "));
    expect_true(report.value().contains("; run 'pepper package fetch'"));
}

[Test]
overrides_put_a_folder_in_place_of_a_package() {
    var folder = TempFolder("project_overrides");
    var root = folder.path;
    Directory.create_all(root.join(Path("geo")));
    File.write_text(
        root.join(Path("pep.toml")),
        "[package]\nname = \"p\"\n[dependencies]\ngeo = { github = \"x/geo\" }\n"
            + "[overrides]\n\"github:x/geo\" = { path = \"geo\" }\n"
            + "\"github:x/net\" = { github = \"me/net\", branch = \"fix\" }\n"
    );
    File.write_text(
        root.join(Path("geo")).join(Path("pep.toml")),
        "[package]\nname = \"geo\"\n[dependencies]\nterm = { github = \"nobody/term\" }\n"
    );
    File.write_text(root.join(Path("geo")).join(Path("module.pep")), "export area(): int {\n    return 0;\n}\n");
    File.write_text(root.join(Path("main.pep")), "import geo;\nmain(): int {\n    return geo.area();\n}\n");

    # The folder's Git dependencies are fetched, not the package it replaces.
    var manifest = link.load_manifest(root.join(Path("pep.toml")), Array<Path>());
    expect_true(manifest.is_ok());
    var names = Array<String>();
    for (var d in manifest.value().git_dependencies()) {
        names.append(d.name);
    }
    expect_equal(", ".join(names), "term");
    var setup = link.Setup();
    setup.runtime = false;
    var program = link.load_program(root.join(Path("main.pep")), setup);
    expect_true(program.is_ok());
    expect_false(program.value().check().is_value());

    # The lock clones a fork's commit from the fork, and a folder has
    # nothing to fetch.
    File.write_text(
        root.join(Path("pep.lock")),
        "version = 1\n\n[[package]]\nname = \"geo\"\nsource = \"github:x/geo\"\noverride = \"path:geo\"\n"
            + "\n[[package]]\nname = \"net\"\nsource = \"github:x/net\"\noverride = \"github:me/net\"\ncommit = \"abc\"\n"
    );
    var locked = link.read_lock(root.join(Path("pep.lock")));
    expect_true(locked.is_ok());
    expect_equal(locked.value().count, 1);
    expect_equal(locked.value()[0].clone_url(), link.Host.GitHub.clone_url("me/net"));

    expect_equal(
        errors("[package]\nname = \"a\"\n[overrides]\n\"x/geo\" = { path = \"geo\" }\n"),
        "x/geo: override 'x/geo' does not name a package's source, such as 'github:owner/name'"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[overrides]\n\"github:x/geo\" = { path = \"geo\", optional = true }\n"),
        "optional: an override takes a source and a revision, not 'optional'; set it on the dependency"
    );
}

[Test]
reads_dev_dependencies() {
    var parsed = link.parse_manifest(
        Path("/p/pep.toml"),
        "[package]\nname = \"p\"\n[dependencies]\ngeo = { path = \"geo\" }\n[dev-dependencies]\n"
            + "fixtures = { github = \"someone/fixtures\", version = \"1\" }\n"
    );
    expect_true(parsed.is_ok());
    var m = parsed.value();
    expect_equal(m.dependencies.count, 1);
    expect_equal(m.dev_dependencies.count, 1);
    expect_false(m.dependency("fixtures").is_value());
    expect_equal(m.dev_dependency("fixtures").value().locked_source().value(), "github:someone/fixtures");
    expect_equal(
        errors(
            "[package]\nname = \"a\"\n[dependencies]\njson = { github = \"x/json\" }\n[dev-dependencies]\njson = { github = \"x/json\" }\n"
        ),
        "json: 'json' is in both '[dependencies]' and '[dev-dependencies]'; keep it in one"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[dev-dependencies]\njson = { github = \"x/json\", tags = \"v1\" }\n"),
        "tags: unknown key 'tags' in '[dev-dependencies]'; expected one of 'github', 'gitlab', 'codeberg', 'path', 'package', 'version', 'branch', 'tag', 'commit', 'optional', 'features', 'default-features', 'workspace'"
    );
}

# What checking `file` reports, built as a test build when `test` is
# set; empty when it builds.
check_build(file: Path, test: bool): String {
    var setup = link.Setup();
    setup.runtime = false;
    if (test) {
        setup.target.build_options[link.TEST_BUILD_OPTION] = "1";
    }
    var program = link.load_program(file, setup);
    expect_true(program.is_ok());
    var report = program.value().check();
    return report.is_value() ? report.value() : "";
}

[Test]
only_tests_and_examples_see_dev_dependencies() {
    var folder = TempFolder("dev_dependencies");
    var lib = folder.path.join(Path("lib"));
    var app = folder.path.join(Path("app"));
    var fixtures = folder.path.join(Path("fixtures"));
    Directory.create_all(lib.join(Path("examples")));
    Directory.create_all(app);
    Directory.create_all(fixtures);
    File.write_text(fixtures.join(Path("module.pep")), "export answer(): int {\n    return 42;\n}\n");
    File.write_text(
        lib.join(Path("pep.toml")),
        "[package]\nname = \"lib\"\n[dev-dependencies]\nfixtures = { path = \"../fixtures\" }\n"
            + "term = { github = \"nobody/term\" }\n"
    );
    var uses = "import fixtures;\nmain(): int {\n    return fixtures.answer() - 42;\n}\n";
    File.write_text(lib.join(Path("main.pep")), uses);
    File.write_text(lib.join(Path("examples")).join(Path("demo.pep")), uses);
    File.write_text(lib.join(Path("module.pep")), "import fixtures;\nexport answer(): int {\n    return 1;\n}\n");

    # A test build and an example see them; any other build does not.
    expect_equal(check_build(lib.join(Path("main.pep")), true), "");
    expect_equal(check_build(lib.join(Path("examples")).join(Path("demo.pep")), false), "");
    expect_true(
        check_build(
            lib.join(Path("main.pep")),
            false
        ).contains(
            "main.pep:1:8: error: 'fixtures' is a dev-dependency, which only tests and the files in examples/ import; move it to '[dependencies]' to import it here"
        )
    );

    # A project that depends on lib neither fetches nor sees them, even in
    # its own test build.
    File.write_text(
        app.join(Path("pep.toml")), "[package]\nname = \"app\"\n[dependencies]\nlib = { path = \"../lib\" }\n"
    );
    File.write_text(app.join(Path("main.pep")), "import lib;\nmain(): int {\n    return lib.answer() - 1;\n}\n");
    expect_equal(link.load_manifest(lib.join(Path("pep.toml")), Array<Path>()).value().git_dependencies().count, 1);
    expect_equal(link.load_manifest(app.join(Path("pep.toml")), Array<Path>()).value().git_dependencies().count, 0);
    expect_true(
        check_build(
            app.join(Path("main.pep")),
            true
        ).contains(
            "module.pep:1:8: error: 'fixtures' is a dev-dependency of the package 'lib', which only its own tests and examples import"
        )
    );

    # A dev-dependency may not hide a runtime module either.
    var runtime = folder.path.join(Path("runtime"));
    Directory.create_all(runtime.join(Path("io")));
    File.write_text(runtime.join(Path("io")).join(Path("module.pep")), "");
    File.write_text(
        app.join(Path("pep.toml")), "[package]\nname = \"app\"\n[dev-dependencies]\nio = { path = \"../fixtures\" }\n"
    );
    var hidden = link.load_manifest(app.join(Path("pep.toml")), [runtime]);
    expect_true(hidden.is_err());
    expect_true(hidden.error().contains("dependency 'io' has the name of the runtime module 'io'"));
}

[Test]
reads_target_dependencies() {
    var parsed = link.parse_manifest(
        Path("/p/pep.toml"),
        "[package]\nname = \"p\"\n[dependencies]\ngeo = { path = \"geo\" }\n"
            + "[target.'OS(Windows)'.dependencies]\nwinapi = { github = \"someone/winapi\", version = \"1\" }\n"
            + "[target.'OS(Linux) && Arch(x64)'.dependencies]\nepoll = { github = \"someone/epoll\" }\n"
    );
    expect_true(parsed.is_ok());
    var m = parsed.value();
    expect_equal(m.dependencies.count, 3);
    expect_equal(m.dependency("geo").value().target, "");
    expect_equal(m.dependency("winapi").value().target, "OS(Windows)");
    var windows = link.Target.parse("x86_64-pc-windows-msvc").value();
    var linux = link.Target.parse("x86_64-unknown-linux-gnu").value();
    expect_true(m.dependency("geo").value().matches(linux));
    expect_true(m.dependency("winapi").value().matches(windows));
    expect_false(m.dependency("winapi").value().matches(linux));
    expect_true(m.dependency("epoll").value().matches(linux));
    expect_equal(m.git_dependencies().count, 2);
    expect_equal(m.git_dependencies(Optional<link.Target>.Value(linux))[0].name, "epoll");

    # `.build-dependencies`: the script's, for the host whatever the target.
    var scripted = link.parse_manifest(
        Path("/p/pep.toml"),
        "[package]\nname = \"p\"\n"
            + "[target.'OS(Windows) || OS(Linux) || OS(MacOS)'.build-dependencies]\nhere = { github = \"a/here\" }\n"
            + "[target.'OS(Wasi)'.build-dependencies]\nnever = { github = \"a/never\" }\n"
    );
    expect_true(scripted.is_ok());
    var s = scripted.value();
    expect_equal(s.dependencies.count, 0);
    expect_equal(s.build_dependencies.count, 2);
    expect_equal(s.build_dependency("never").value().table(), "target.'OS(Wasi)'.build-dependencies");
    var wasi = link.Target.parse("wasm32-wasip1").value();
    var for_wasi = s.git_dependencies(Optional<link.Target>.Value(wasi));
    expect_equal(for_wasi.count, 1);
    expect_equal(for_wasi[0].name, "here");

    expect_equal(
        errors("[package]\nname = \"a\"\n[target.'OS(Darwin)'.dependencies]\nx = { github = \"a/x\" }\n"),
        "OS(Darwin): unknown OS 'Darwin'; expected 'Windows', 'Mac', 'MacOS', 'Linux', 'Wasi', 'IOS' or 'Android'"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[target.'Windows)]'.dependencies]\nx = { github = \"a/x\" }\n"),
        "Windows)]: invalid target condition 'Windows)]'; expected what '[Target(...)]' takes, such as 'OS(Windows)'"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[target.'OS(Windows)'.dev-dependencies]\nx = { github = \"a/x\" }\n"),
        "dev-dependencies: unknown key 'dev-dependencies' in '[target.'OS(Windows)']'; expected one of 'dependencies', 'build-dependencies', 'native'"
    );
    expect_equal(
        errors(
            "[package]\nname = \"a\"\n[build-dependencies]\nx = { github = \"a/x\" }\n[target.'OS(Windows)'.build-dependencies]\nx = { github = \"a/x\" }\n"
        ),
        "x: 'x' is in both '[build-dependencies]' and '[target.'OS(Windows)'.build-dependencies]'; keep it in one"
    );
    expect_equal(
        errors(
            "[package]\nname = \"a\"\n[target.'OS(Windows)'.build-dependencies]\nx = { github = \"a/x\", optional = true }\n"
        ),
        "optional: build-dependency 'x' cannot be optional; only '[dependencies]' are"
    );
    expect_equal(
        errors(
            "[package]\nname = \"a\"\n[dependencies]\nx = { github = \"a/x\" }\n[target.'OS(Windows)'.dependencies]\nx = { github = \"a/x\" }\n"
        ),
        "x: 'x' is in both '[dependencies]' and '[target.'OS(Windows)'.dependencies]'; keep it in one"
    );
    expect_equal(
        errors(
            "[package]\nname = \"a\"\n[target.'OS(Windows)'.dependencies]\nx = { github = \"a/x\", tags = \"v1\" }\n"
        ),
        "tags: unknown key 'tags' in '[target.'OS(Windows)'.dependencies]'; expected one of 'github', 'gitlab', 'codeberg', 'path', 'package', 'version', 'branch', 'tag', 'commit', 'optional', 'features', 'default-features', 'workspace'"
    );
}

# `--no-build-scripts` passes only `[native]` flags that load no code and
# name no file: pepper-crypto's pass.
[Test]
no_build_scripts_allows_only_native_flags_that_load_no_code() {
    var allowed = [
        "-O3",
        "-Os",
        "-Oz",
        "-fno-strict-aliasing",
        "-fno-strict-overflow",
        "-fwrapv",
        "-Wno-pointer-sign",
        "-Wall",
        "-Werror=format",
        "-std=c11",
        "-std=c++17",
        "-mavx2",
        "-mno-sse4.2",
        "-march=x86-64-v3"
    ];
    var refused = [
        "-fplugin=x",
        "-fplugin",
        "-fpass-plugin=x.so",
        "-fprofile-use",
        "-fno-profile-generate",
        "-fmodules",
        "-fmodule-map-file=m",
        "-fsave-optimization-record",
        "-fno-integrated-as",
        "-fvisibility=hidden",
        "-Xclang",
        "-load",
        "-Wl,-rpath,x",
        "-Wa,x",
        "-Wp,-MD,x",
        "-mllvm",
        "-mmlir",
        "-fproc-stat-report",
        "-fexperimental-openacc-macro-override",
        "-mlink-bitcode-file",
        "-march=../x",
        "@file",
        "-include",
        "-Ifoo",
        "-DX",
        "--sysroot=x",
        "-O",
        "-O4",
        "-std=",
        "-W",
        "-f",
        "x.c",
        ""
    ];
    # Named, so a failure says which flag.
    var wrong = Array<String>();
    for (var flag in allowed) {
        if (!driver.native_flag_allowed(flag)) {
            wrong.append(flag);
        }
    }
    for (var flag in refused) {
        if (driver.native_flag_allowed(flag)) {
            wrong.append(flag);
        }
    }
    expect_equal(", ".join(wrong), "");
}

[Test]
reads_native_tables() {
    var parsed = link.parse_manifest(
        Path("/p/pep.toml"),
        "[package]\nname = \"p\"\n[native]\nsources = [\"c/*.c\"]\ninclude = [\"c/include\"]\n"
            + "defines = [\"FAST=1\"]\nflags = [\"-Wall\"]\nlink = [\"m\"]\npkg-config = [\"zlib\"]\n"
            + "[target.'OS(Windows)'.native]\nsources = [\"c/win.c\"]\nlink = [\"ws2_32\"]\n"
            + "[target.'OS(Wasi)'.native]\nlink = [\"never\"]\n"
    );
    expect_true(parsed.is_ok());
    var m = parsed.value();
    var windows = m.native_for(link.Target.parse("x86_64-pc-windows-msvc").value()).value();
    expect_equal(", ".join(windows.sources), "c/*.c, c/win.c");
    expect_equal(", ".join(windows.link), "m, ws2_32");
    expect_equal(", ".join(windows.include), "c/include");
    expect_equal(", ".join(windows.defines), "FAST=1");
    expect_equal(", ".join(windows.flags), "-Wall");
    expect_equal(", ".join(windows.pkg_config), "zlib");
    expect_equal(m.text.substr_bytes(windows.source_spans[1].start, 9), "\"c/win.c\"");
    expect_equal(m.text.substr_bytes(windows.flag_spans[0].start, 7), "\"-Wall\"");
    var linux = m.native_for(link.Target.parse("x86_64-unknown-linux-gnu").value()).value();
    expect_equal(", ".join(linux.sources), "c/*.c");
    expect_equal(", ".join(linux.link), "m");
    # No table holds: nothing to compile.
    var only_windows = link.parse_manifest(
        Path("/p/pep.toml"), "[package]\nname = \"p\"\n[target.'OS(Windows)'.native]\nsources = [\"w.c\"]\n"
    );
    expect_false(only_windows.value().native_for(link.Target.parse("x86_64-unknown-linux-gnu").value()).is_value());
    expect_equal(
        errors("[package]\nname = \"a\"\n[native]\nsource = [\"c/*.c\"]\n"),
        "source: unknown key 'source' in '[native]'; expected one of 'sources', 'include', 'defines', 'flags', 'link', 'pkg-config'"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[target.'OS(Linux)'.native]\nlinks = [\"m\"]\n"),
        "links: unknown key 'links' in '[target.'OS(Linux)'.native]'; expected one of 'sources', 'include', 'defines', 'flags', 'link', 'pkg-config'"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[native]\nsources = \"c/*.c\"\n"),
        "\"c/*.c\": 'sources' must be an array of strings, not a string"
    );
}

# What checking `file` for the target `triple` reports; empty when it
# builds.
check_for(file: Path, triple: String): String {
    var setup = link.Setup();
    setup.runtime = false;
    setup.target = link.Target.parse(triple).value();
    var program = link.load_program(file, setup);
    expect_true(program.is_ok());
    var report = program.value().check();
    return report.is_value() ? report.value() : "";
}

[Test]
a_build_sees_only_its_targets_dependencies() {
    var folder = TempFolder("target_dependencies");
    var app = folder.path.join(Path("app"));
    var win = folder.path.join(Path("win"));
    Directory.create_all(app);
    Directory.create_all(win);
    File.write_text(win.join(Path("module.pep")), "export answer(): int {\n    return 42;\n}\n");
    File.write_text(
        app.join(Path("pep.toml")),
        "[package]\nname = \"app\"\n[target.'OS(Windows)'.dependencies]\nwin = { path = \"../win\" }\n"
    );
    File.write_text(
        app.join(Path("main.pep")),
        "[Target(OS(Windows))]\nimport win;\nmain(): int {\n    return 0;\n}\n"
            + "[Target(OS(Windows))]\nanswer(): int {\n    return win.answer();\n}\n"
    );
    var main = app.join(Path("main.pep"));
    expect_equal(check_for(main, "x86_64-pc-windows-msvc"), "");
    expect_equal(check_for(main, "x86_64-unknown-linux-gnu"), "");

    # Imported where the condition does not hold, the error says so.
    File.write_text(main, "import win;\nmain(): int {\n    return win.answer() - 42;\n}\n");
    expect_equal(check_for(main, "x86_64-pc-windows-msvc"), "");
    expect_true(
        check_for(
            main,
            "aarch64-apple-darwin"
        ).contains(
            "main.pep:1:8: error: 'win' is a dependency only for targets where 'OS(Windows)' holds, which this build's does not; put '[Target(OS(Windows))]' on the import"
        )
    );
}

[Test]
a_build_fetches_only_its_targets_packages() {
    var folder = TempFolder("target_fetch");
    var root = folder.path;
    File.write_text(
        root.join(Path("pep.toml")),
        "[package]\nname = \"app\"\n[target.'OS(Windows)'.dependencies]\nnet = { github = \"nobody/net\" }\n"
    );
    File.write_text(root.join(Path("main.pep")), "main(): int {\n    return 0;\n}\n");
    File.write_text(
        root.join(Path("pep.lock")),
        "version = 1\n\n[[package]]\nname = \"net\"\nsource = \"github:nobody/net\"\n"
            + "commit = \"0123456789abcdef0123456789abcdef01234567\"\ntarget = \"OS(Windows)\"\n"
    );
    var entry = root.join(Path("main.pep"));
    var linux = link.Target.parse("x86_64-unknown-linux-gnu").value();
    var windows = link.Target.parse("x86_64-pc-windows-msvc").value();
    # Offline, a build fails only on what its target needs and neither
    # .pep/deps nor pep-package's download cache holds.
    expect_true(driver.fetch_dependencies(entry, offline = true, target = linux).is_ok());
    var missing = driver.fetch_dependencies(entry, offline = true, target = windows);
    expect_true(missing.is_err());
    expect_true(missing.error().contains("nor the package cache holds the commit 0123456789ab"));
    # Unlocked, it is stale for every target.
    File.remove(root.join(Path("pep.lock")));
    expect_true(driver.fetch_dependencies(entry, locked = true, target = linux).is_err());
    expect_true(driver.fetch_dependencies(entry, offline = true, target = linux).is_ok());
}

[Test]
locked_and_offline_builds_refuse_before_fetching() {
    var folder = TempFolder("project_locked_offline");
    var root = folder.path;
    File.write_text(
        root.join(Path("pep.toml")), "[package]\nname = \"app\"\n[dependencies]\nnet = { github = \"nobody/net\" }\n"
    );
    File.write_text(root.join(Path("main.pep")), "main(): int {\n    return 0;\n}\n");
    var entry = root.join(Path("main.pep"));

    # pep.toml names a dependency pep.lock does not list.
    var locked = driver.fetch_dependencies(entry, locked = true);
    expect_true(locked.is_err());
    expect_true(locked.error().contains("pep.lock is out of date: "));
    expect_true(
        locked.error().contains(
            "names github:nobody/net, which pep.lock does not list; run 'pepper package fetch' without --locked, and commit pep.lock"
        )
    );
    var offline = driver.fetch_dependencies(entry, offline = true);
    expect_true(offline.is_err());
    expect_true(
        offline.error().contains(
            "--offline, and choosing a revision of github:nobody/net reads which ones it offers over the network"
        )
    );
    # Already in .pep/deps, though unlocked: a build fetches nothing, so
    # --offline passes; --locked still fails.
    var net = root
        .join(Path(".pep"))
        .join(Path("deps"))
        .join(Path("github.com"))
        .join(Path("nobody"))
        .join(Path("net"));
    Directory.create_all(net);
    expect_true(driver.fetch_dependencies(entry, offline = true).is_ok());
    expect_true(driver.fetch_dependencies(entry, locked = true).is_err());
    Directory.remove_all(root.join(Path(".pep")));

    # A locked package not fetched yet, nor in the download cache: --offline
    # fails without fetching it.
    File.write_text(
        root.join(Path("pep.lock")),
        "version = 1\n\n[[package]]\nname = \"net\"\nsource = \"github:nobody/net\"\n"
            + "commit = \"0123456789abcdef0123456789abcdef01234567\"\n"
    );
    var missing = driver.fetch_dependencies(entry, offline = true);
    expect_true(missing.is_err());
    expect_true(missing.error().contains("--offline, and neither "));
    expect_true(
        missing.error().contains(
            "nor the package cache holds the commit 0123456789ab; run 'pepper package fetch' without --offline (or PEPPER_OFFLINE) first"
        )
    );
    expect_false(root.join(Path(".pep")).join(Path("deps")).exists());
}

[Test]
reads_features() {
    var parsed = link.parse_manifest(
        Path("/p/pep.toml"),
        "[package]\nname = \"http\"\n[dependencies]\n"
            + "zlib = { path = \"zlib\", optional = true, features = [\"simd\"], default-features = false }\n"
            + "[features]\ndefault = [\"gzip\"]\ngzip = [\"dep:zlib\", \"zlib/fast\"]\n"
    );
    expect_true(parsed.is_ok());
    var m = parsed.value();
    expect_equal(", ".join(m.feature("gzip").value().enables), "dep:zlib, zlib/fast");
    expect_equal(m.build_option("gzip"), "http_gzip");
    var zlib = m.dependency("zlib").value();
    expect_true(zlib.optional);
    expect_false(zlib.default_features);
    expect_equal(", ".join(zlib.features), "simd");

    expect_equal(
        errors("[package]\nname = \"a\"\n[features]\nx = [\"dep:y\"]\n"),
        "\"dep:y\": 'dep:y' names no dependency; 'dep:' turns on an optional dependency"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[dependencies]\ny = { path = \"y\" }\n[features]\nx = [\"dep:y\"]\n"),
        "\"dep:y\": dependency 'y' is not optional; give it 'optional = true' for 'dep:y' to turn it on"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[features]\nx = [\"z\"]\n"),
        "\"z\": no feature named 'z' in '[features]'; a feature turns on features, 'dep:name' or 'name/feature'"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[dev-dependencies]\ny = { path = \"y\", optional = true }\n"),
        "optional: dev-dependency 'y' cannot be optional; only '[dependencies]' are"
    );
    expect_equal(errors("[package]\nname = \"a\"\n[build-dependencies]\ny = { path = \"y\" }\n"), "");
    expect_equal(
        errors("[package]\nname = \"a\"\n[build-dependencies]\ny = { path = \"y\", optional = true }\n"),
        "optional: build-dependency 'y' cannot be optional; only '[dependencies]' are"
    );
}

[Test]
features_turn_on_build_options_and_optional_dependencies() {
    var folder = TempFolder("features");
    var app = folder.path.join(Path("app"));
    var http = folder.path.join(Path("http"));
    var zlib = folder.path.join(Path("zlib"));
    Directory.create_all(app);
    Directory.create_all(http);
    Directory.create_all(zlib);
    File.write_text(
        app.join(Path("pep.toml")),
        "[package]\nname = \"app\"\n[dependencies]\nhttp = { path = \"../http\" }\n[features]\nfast = [\"http/gzip\"]\n"
    );
    File.write_text(
        http.join(Path("pep.toml")),
        "[package]\nname = \"http\"\n[dependencies]\nzlib = { path = \"../zlib\", optional = true }\n"
            + "[features]\ndefault = [\"tls\"]\ntls = []\ngzip = [\"dep:zlib\"]\n"
    );
    File.write_text(
        http.join(Path("module.pep")),
        "[Target(BuildOption(http_gzip))]\nimport zlib;\nexport level(): int {\n    return 1;\n}\n"
    );
    File.write_text(zlib.join(Path("module.pep")), "export z(): int {\n    return 0;\n}\n");
    var main = app.join(Path("main.pep"));
    File.write_text(main, "import http;\nmain(): int {\n    return http.level() - 1;\n}\n");

    # A dependency's default features are on; the others only when asked.
    var plain = load_with(main, Array<String>());
    expect_true(plain.target.build_options.contains("http_tls"));
    expect_false(plain.target.build_options.contains("http_gzip"));
    expect_false(plain.check().is_value());
    var fast = load_with(main, ["fast"]);
    expect_true(fast.target.build_options.contains("app_fast"));
    expect_true(fast.target.build_options.contains("http_gzip"));
    expect_false(fast.check().is_value());
    var setup = link.Setup();
    setup.runtime = false;
    setup.target.features = ["nope"];
    var unknown = link.load_program(main, setup);
    expect_true(unknown.is_err());
    expect_equal(unknown.error(), "unknown feature 'nope' in '--features': package 'app' has 'fast'");

    # An optional dependency no feature turns on cannot be imported.
    File.write_text(
        http.join(Path("module.pep")), "import zlib;\nexport level(): int {\n    return 1 + zlib.z();\n}\n"
    );
    expect_true(load_with(main, Array<String>()).check().value().contains("'zlib' is an optional dependency"));
    expect_false(load_with(main, ["fast"]).check().is_value());

    # `default-features = false` leaves the dependency's default off, and a
    # feature it lacks is an error at the entry asking for it.
    File.write_text(
        app.join(Path("pep.toml")),
        "[package]\nname = \"app\"\n[dependencies]\nhttp = { path = \"../http\", default-features = false, features = [\"nope\"] }\n"
    );
    setup = link.Setup();
    setup.runtime = false;
    var missing = link.load_program(main, setup);
    expect_true(missing.is_err());
    expect_true(missing.error().contains("error: package 'http' has no feature 'nope'"));
    File.write_text(
        app.join(Path("pep.toml")),
        "[package]\nname = \"app\"\n[dependencies]\nhttp = { path = \"../http\", default-features = false }\n"
    );
    expect_false(load_with(main, Array<String>()).target.build_options.contains("http_tls"));

    # The project's own `default`, unless `--no-default-features`.
    File.write_text(
        app.join(Path("pep.toml")),
        "[package]\nname = \"app\"\n[dependencies]\nhttp = { path = \"../http\" }\n[features]\ndefault = [\"fast\"]\nfast = []\n"
    );
    expect_true(load_with(main, Array<String>()).target.build_options.contains("app_fast"));
    setup = link.Setup();
    setup.runtime = false;
    setup.target.default_features = false;
    var without = link.load_program(main, setup).value();
    expect_false(without.target.build_options.contains("app_fast"));
    expect_true(without.target.build_options.contains("http_tls"));
}

# `file`'s program, loaded with the project's `features` turned on.
load_with(file: Path, features: String[]): link.Program {
    var setup = link.Setup();
    setup.runtime = false;
    setup.target.features = features;
    var program = link.load_program(file, setup);
    expect_true(program.is_ok());
    return program.value();
}

[Test]
reads_a_workspace() {
    # A workspace's root needs no `[package]`.
    expect_equal(errors("[workspace]\nmembers = [\"a\", \"libs/*\"]\n"), "");
    expect_equal(
        errors("[workspace]\nmember = [\"a\"]\n"),
        "member: unknown key 'member' in '[workspace]'; expected one of 'members', 'dependencies'"
    );
    expect_equal(
        errors("[workspace]\nmembers = []\n[workspace.dependencies]\nn = { github = \"o/n\", optional = true }\n"),
        "optional: 'optional' is not for '[workspace.dependencies]', which gives a source and a revision; give it in the member's entry"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[dependencies]\nn = { workspace = true, github = \"o/n\" }\n"),
        "github: 'github' and 'workspace = true' both choose where 'n' comes from; keep one"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[dependencies]\nn = { workspace = false }\n"),
        "false: 'workspace' is true or absent; give dependency 'n' a source instead"
    );
    # A `path` takes a `version`, for `publish`, and nothing else.
    expect_equal(errors("[package]\nname = \"a\"\n[dependencies]\nn = { path = \"../n\", version = \"1\" }\n"), "");
    expect_equal(
        errors("[package]\nname = \"a\"\n[dependencies]\nn = { path = \"../n\", tag = \"v1\" }\n"),
        "tag: dependency 'n' is a 'path'; a folder has no branches, tags or commits, only a 'version' for 'publish'"
    );
}

[Test]
a_workspace_shares_its_root_and_unifies_features() {
    var folder = TempFolder("workspace");
    var root = folder.path;
    var app = root.join(Path("app"));
    var shapes = root.join(Path("libs")).join(Path("shapes"));
    Directory.create_all(app);
    Directory.create_all(shapes);
    File.write_text(
        root.join(Path("pep.toml")),
        "[workspace]\nmembers = [\"app\", \"libs/*\"]\n[workspace.dependencies]\n"
            + "net = { github = \"nobody/net\", version = \"1\" }\nshapes = { path = \"libs/shapes\" }\n"
    );
    File.write_text(shapes.join(Path("pep.toml")), "[package]\nname = \"shapes\"\n[features]\nround = []\n");
    File.write_text(shapes.join(Path("module.pep")), "export sides(): int {\n    return 4;\n}\n");
    File.write_text(
        app.join(Path("pep.toml")),
        "[package]\nname = \"app\"\n[dependencies]\nshapes = { workspace = true }\nnet = { workspace = true }\n"
    );
    var main = app.join(Path("main.pep"));
    File.write_text(main, "import shapes;\nmain(): int {\n    return shapes.sides() - 4;\n}\n");

    # A member's Git dependencies live in the root's `.pep/deps`, and a
    # `path` it inherits is relative to the root.
    var member = link.load_manifest(app.join(Path("pep.toml")), Array<Path>());
    expect_true(member.is_ok());
    var deps_root = member.value().deps_root();
    expect_equal(deps_root.to_string(), link.absolute(root).normalize().to_string());
    expect_equal(
        member.value().dependency("net").value().directory(deps_root, app).to_string(),
        link.package_directory(deps_root, link.Host.GitHub, "nobody/net").to_string()
    );
    var whole = link.load_manifest(root.join(Path("pep.toml")), Array<Path>());
    expect_true(whole.is_ok());
    expect_equal(whole.value().member_manifests.count, 2);
    expect_equal(whole.value().git_dependencies().count, 1);
    expect_false(load_with(main, Array<String>()).check().is_value());

    # The features of the members built together are unified: 'round' is
    # shapes', so only a build with shapes as a member turns it on.
    var setup = link.Setup();
    setup.runtime = false;
    setup.target.features = ["round"];
    expect_true(link.load_program(main, setup).is_err());
    setup.target.members = ["shapes"];
    var unified = link.load_program(main, setup);
    expect_true(unified.is_ok());
    expect_true(unified.value().target.build_options.contains("shapes_round"));

    # Problems at the member: listed twice, not a package, a workspace
    # itself, inheriting what the root lacks.
    Directory.create_all(root.join(Path("libs")).join(Path("inner")));
    File.write_text(root.join(Path("libs")).join(Path("inner")).join(Path("pep.toml")), "[workspace]\nmembers = []\n");
    File.write_text(root.join(Path("pep.toml")), "[workspace]\nmembers = [\"app\", \"app\", \"none\", \"libs/*\"]\n");
    var bad = link.load_manifest(app.join(Path("pep.toml")), Array<Path>());
    expect_true(bad.is_err());
    expect_true(bad.error().contains("pep.toml:2:19: error: workspace member 'app' is listed twice"));
    expect_true(bad.error().contains("pep.toml:2:26: error: workspace member 'none' is not a package: no "));
    expect_true(bad.error().contains("error: workspace member 'libs/*' is a workspace itself; workspaces do not nest"));
    expect_true(
        bad.error().contains("error: dependency 'shapes' has 'workspace = true', and '[workspace.dependencies]' of ")
    );

    # Outside a workspace, `workspace = true` has nothing to inherit.
    File.write_text(root.join(Path("pep.toml")), "[workspace]\nmembers = [\"libs/shapes\"]\n");
    var outside = link.load_manifest(app.join(Path("pep.toml")), Array<Path>());
    expect_true(outside.is_err());
    expect_true(
        outside.error().contains(
            "error: dependency 'shapes' has 'workspace = true', and no workspace lists this package; give it a source"
        )
    );
}
