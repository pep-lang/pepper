<!-- Generated from runtime/cli/module.pep by `pep-doc reference`. Do not edit. -->

# The cli module

Command-line parsing: declare a program's options and arguments, then
parse them, with the help, version and error messages generated from
the declarations.

Bring it in with `import cli`. The raw arguments stay where they are,
in `main(args: String[])` and `process.arguments()`.

- [Parser](cli-parser.md): `Parser`, and the handles its declarations
  return: `Flag`, `Argument`, `ArgumentList`; and `closest`, which
  picks the name a misspelled one most likely meant
- [Completions](cli-completions.md): `Shell`, the shells
  `Parser.completions` writes a completion script for
- [Options](cli-options.md): `Option` and `Positional`, the attributes
  that shape what `Parser.add_options` declares from a struct's fields

**Example**
```pepper
import cli;

main(args: String[]): int {
    var parser = cli.Parser("greet", "Greets someone");
    var loud = parser.flag("loud", "l", "shout the greeting");
    var name = parser.positional("name", "who to greet", required = false, default_value = "world");
    if (!parser.parse(args)) {
        return 2;
    }
    var greeting = $"hello, {name.value()}";
    print(loud.is_set ? greeting.upper() : greeting);
    return 0;
}
```

Source: `runtime/cli/module.pep`
