<!-- Generated from runtime/os/module.pep by `pep-doc reference`. Do not edit. -->

# The os module

What the operating system provides beyond the running process:
environment variables, clocks and time, and the machine and user.

`os` is a module: bring it in with `import os` (and write
`os.environment("HOME")`) or import names directly with
`import [Instant, Duration] from os`.

- [Environment](os-environment.md): `environment(name)`,
  `environment_variables()`, `set_environment(name, value)` and
  `remove_environment(name)`
- [Time](os-time.md): `Duration`, `Instant` (a monotonic clock, for
  measuring) and `SystemTime` (the wall clock)
- [Machine](os-machine.md): `system_os()`, `system_name()`, `system_version()`,
  `architecture()`, `hostname()`, processor counts, `total_memory()`,
  `page_size()`
- [User](os-user.md): `user_name()`, `home_directory()`,
  `temp_directory()`, `is_elevated()`

**Example**
```pepper
import os;

main(): int {
    var start = os.Instant.now();
    var runtime = os.environment("PEPPER_RUNTIME").value_or("runtime");
    print($"runtime at {runtime} on {os.hostname()}");
    print($"took {os.Instant.now() - start}");
    return 0;
}
```

Source: `runtime/os/module.pep`
