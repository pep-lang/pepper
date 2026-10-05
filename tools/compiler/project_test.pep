# The compiler's linker reads `pep.toml` as the Rust compiler does
# (`crates/pepper-files/src/project.rs`): the same manifest, the same
# errors at the same keys, and imports of a project's dependencies
# resolved in the project.

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
    expect_equal(
        errors("[package]\nname = \"a\"\n[bulid]\n"),
        "bulid: unknown table 'bulid'; a pep.toml has '[package]', '[build]', '[dependencies]' and '[fetch]'"
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
