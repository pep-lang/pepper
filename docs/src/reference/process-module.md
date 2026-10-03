<!-- Generated from runtime/process/module.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# The process module

Child processes, and what belongs to the running one, modeled on Rust's
`std::process`.

`process` is a module: bring it in with `import process` (and write
`process.Command`) or import names directly with
`import [Command, Stream] from process`. `arguments()` and `exit()` stay
in the prelude, and the module passes them on as well.

- [Command](process-command.md): `Command` describes a program to start;
  `run()` waits for it and collects its output, `spawn()` starts it and
  returns a `Child`, and `exec()` runs it in place of the running program
- [Child](process-child.md): a running child process, its piped streams,
  and its `ExitStatus`
- [The running process](process-current.md): `id()` and
  `executable_path()`

**Example**
```pepper
import process;

main(): int {
    var output = process.Command("git").argument("--version").run();
    if (output.is_err()) {
        print("git is not installed");
        return 1;
    }
    print(output.value().stdout);
    return 0;
}
```

Source: `runtime/process/module.pep`
