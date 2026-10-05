# Command-line parsing: declare the options as a struct's fields.
import cli;

struct Options {
    [cli.Option("g", "what to say")]
    var greeting: String = "hello";
    [cli.Option("l", "shout it")]
    var loud: bool;
    [cli.Option("n", "how many times to say it", value_name = "COUNT")]
    var times: int = 1;
    [cli.Positional("who to greet")]
    var names: String[];
}

main(args: String[]): int {
    var options = Options();
    var parser = cli.Parser("greet", "Greets someone", version = "1.0");
    parser.add_options(options);
    if (!parser.parse(args)) {
        return 2;
    }

    var people = options.names.is_empty ? ["world"] : options.names;
    for (var person in people) {
        var line = $"{options.greeting}, {person}";
        for (var _ in 0..options.times) {
            print(options.loud ? line.upper() : line);
        }
    }
    return 0;
}
