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
        "bulid: unknown table 'bulid'; a pep.toml has '[package]', '[build]', '[dependencies]', '[dev-dependencies]' and '[fetch]'"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[fetch]\nhosts = [\"codeberg\", \"gitub\"]\n"),
        "\"gitub\": 'hosts' lists 'github', 'gitlab' or 'codeberg'"
    );
    expect_equal(
        errors("[package]\nname = \"a\"\n[build]\nentyr = \"x\"\n"),
        "entyr: unknown key 'entyr' in '[build]'; expected one of 'entry', 'output', 'include', 'link'"
    );
    expect_equal(errors("[package]\nname = \"a\"\n[fetch]\nhosts = [\"codeberg\", \"github\"]\n"), "");
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
        "tags: unknown key 'tags' in '[dev-dependencies]'; expected one of 'github', 'gitlab', 'codeberg', 'path', 'version', 'branch', 'tag', 'commit'"
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
        offline.error().contains("lacks github:nobody/net; run 'pepper package fetch' without --offline first")
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

    # A locked package not fetched yet: --offline fails without fetching it.
    File.write_text(
        root.join(Path("pep.lock")),
        "version = 1\n\n[[package]]\nname = \"net\"\nsource = \"github:nobody/net\"\n"
            + "commit = \"0123456789abcdef0123456789abcdef01234567\"\n"
    );
    var missing = driver.fetch_dependencies(entry, offline = true);
    expect_true(missing.is_err());
    expect_true(missing.error().starts_with("--offline, and "));
    expect_true(
        missing.error().contains(
            "lacks github:nobody/net 0123456789ab; run 'pepper package fetch' without --offline first"
        )
    );
    expect_false(root.join(Path(".pep")).join(Path("deps")).exists());
}
