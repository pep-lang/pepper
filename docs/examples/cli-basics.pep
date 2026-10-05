# Command-line parsing: declare options and arguments, then parse.
import cli;

main(args: String[]): int {
    var parser = cli.Parser("greet", "Greets someone", version = "1.0");
    var greeting = parser.option("greeting", "g", "what to say", default_value = "hello");
    var loud = parser.flag("loud", "l", "shout it");
    var times = parser.option<int>("times", "n", "how many times to say it", value_name = "COUNT", default_value = "1");
    var names = parser.positionals("names", "who to greet");

    # `parse` prints --help and --version and exits; on a mistake it writes
    # the error and the usage to standard error and returns false.
    if (!parser.parse(args)) {
        return 2;
    }

    var people = names.is_set ? names.values() : ["world"];
    for (var person in people) {
        var line = $"{greeting.value()}, {person}";
        for (var _ in 0..times.value()) {
            print(loud.is_set ? line.upper() : line);
        }
    }
    return 0;
}
