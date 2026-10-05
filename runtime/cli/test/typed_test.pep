# The cli module's typed values: `option<T>` and the other generic
# declarations, the errors for a value of the wrong type, enum cases in
# kebab case, and the struct style's typed fields.

import cli;
import [Path] from io;

enum Speed {
    Fast,
    DebugInfo,
}

[Test]
reads_typed_values() {
    var parser = cli.Parser("build");
    var jobs = parser.option<int>("jobs", "j", "how many at once", default_value = "4");
    var ratio = parser.option<double>("ratio");
    var speed = parser.option<Speed>("speed", "s");
    var size = parser.option<byte>("size");
    var imports = parser.multiple<Path>("import-path", "I");
    var levels = parser.multiple<uint>("level");
    var source = parser.positional<Path>("source");
    var counts = parser.positionals<long>("counts");

    expect_false(parser.try_parse(["build", "main.pep"]).is_err());
    expect_equal(jobs.value(), 4);
    expect_false(jobs.is_set);
    expect_equal(ratio.value_or(0.5), 0.5);
    expect_true(speed.value_or(Speed.Fast) == Speed.Fast);
    expect_equal(source.value().to_string(), "main.pep");
    expect_equal(imports.values().count, 0 as ulong);

    var parsed = parser.try_parse(
        [
            "build",
            "-j12",
            "--ratio=2.5",
            "-s",
            "debug-info",
            "--size",
            "200",
            "-I",
            "a",
            "-I=b",
            "--level",
            "1",
            "--level=2",
            "src",
            "--",
            "-3",
            "40"
        ]
    );
    expect_false(parsed.is_err());
    expect_equal(jobs.value(), 12);
    expect_equal(ratio.value(), 2.5);
    expect_true(speed.value() == Speed.DebugInfo);
    expect_equal(size.value(), 200 as byte);
    var paths = imports.values();
    expect_equal(paths.count, 2 as ulong);
    expect_equal(paths[1].to_string(), "b");
    var given = levels.values();
    expect_equal(given[0] + given[1], 3 as uint);
    var numbers = counts.values();
    expect_equal(numbers.count, 2 as ulong);
    expect_equal(numbers[0] + numbers[1], 37 as long);
}

[Test]
rejects_a_value_of_the_wrong_type() {
    var parser = cli.Parser("build");
    parser.option<int>("jobs", "j");
    parser.option<ushort>("port");
    parser.option<uint>("level");
    parser.option<float>("ratio");
    parser.option<Speed>("speed");
    parser.positional<int>("count", required = false);
    expect_equal(
        parser.try_parse(["build", "--jobs", "x"]).error().message,
        "invalid value 'x' for '--jobs': expected an integer"
    );
    expect_equal(
        parser.try_parse(["build", "-jfour"]).error().message, "invalid value 'four' for '-j': expected an integer"
    );
    expect_equal(
        parser.try_parse(["build", "--port=70000"]).error().message,
        "invalid value '70000' for '--port': expected an integer from 0 to 65535"
    );
    expect_equal(
        parser.try_parse(["build", "--level", "-1"]).error().message,
        "invalid value '-1' for '--level': expected a non-negative integer"
    );
    expect_equal(
        parser.try_parse(["build", "--ratio", "fast"]).error().message,
        "invalid value 'fast' for '--ratio': expected a number"
    );
    expect_equal(
        parser.try_parse(["build", "--speed", "DebugInfo"]).error().message,
        "invalid value 'DebugInfo' for '--speed': expected 'fast' or 'debug-info'"
    );
    expect_equal(
        parser.try_parse(["build", "many"]).error().message, "invalid value 'many' for '<count>': expected an integer"
    );
}

[Test]
helps_with_defaults_and_choices() {
    var parser = cli.Parser("build");
    parser.option<int>("jobs", "j", "how many at once", default_value = "4");
    parser.option<Speed>("speed", help = "how to build");
    var expected = "usage: build [OPTIONS]\n\n"
        + "Options:\n"
        + "  -j, --jobs <JOBS>    how many at once [default: 4]\n"
        + "      --speed <SPEED>  how to build [possible values: fast, debug-info]\n"
        + "  -h, --help           show this help\n";
    expect_equal(parser.help(), expected);
}

struct TypedOptions {
    [cli.Option("j")]
    var jobs: int = 4;
    var speed: Speed;
    var ratio: double?;
    [cli.Option("I")]
    var import_path: Path[];
    var output: Path;
    [cli.Positional()]
    var count: int = 1;
    [cli.Positional()]
    var sizes: ushort[];
}

[Test]
declares_typed_fields() {
    var options = TypedOptions();
    var parser = cli.Parser("build");
    parser.add_options(options);
    var expected = "usage: build [OPTIONS] [count] [sizes]...\n\n"
        + "Arguments:\n"
        + "  <count>     [default: 1]\n"
        + "  <sizes>...\n\n"
        + "Options:\n"
        + "  -j, --jobs <JOBS>                [default: 4]\n"
        + "      --speed <SPEED>              [default: fast] [possible values: fast, debug-info]\n"
        + "      --ratio <RATIO>\n"
        + "  -I, --import-path <IMPORT_PATH>  [repeatable]\n"
        + "      --output <OUTPUT>\n"
        + "  -h, --help                       show this help\n";
    expect_equal(parser.help(), expected);

    expect_false(parser.try_parse(["build"]).is_err());
    expect_equal(options.jobs, 4);
    expect_true(options.speed == Speed.Fast);
    expect_false(options.ratio.is_value());
    expect_true(options.output === __null);
    expect_equal(options.count, 1);

    var parsed = parser.try_parse(
        ["build", "-j", "8", "--speed", "debug-info", "--ratio", "0.25", "-I", "a", "--output", "out", "3", "80", "443"]
    );
    expect_false(parsed.is_err());
    expect_equal(options.jobs, 8);
    expect_true(options.speed == Speed.DebugInfo);
    expect_equal(options.ratio.value(), 0.25);
    expect_equal(options.import_path.count, 1 as ulong);
    expect_equal(options.output.to_string(), "out");
    expect_equal(options.count, 3);
    expect_equal(options.sizes.count, 2 as ulong);
    expect_equal(options.sizes[1], 443 as ushort);

    # A bad value leaves the fields as they were.
    expect_equal(
        parser.try_parse(["build", "-j", "lots"]).error().message, "invalid value 'lots' for '-j': expected an integer"
    );
    expect_equal(options.jobs, 8);
}
