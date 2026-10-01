## What the operating system provides beyond the running process:
## environment variables, clocks and time, and the machine and user.
##
## `os` is a module: bring it in with `import os` (and write
## `os.environment("HOME")`) or import names directly with
## `import [Instant, Duration] from os`.
##
## - [Environment](os-environment.md): `environment(name)` and
##   `environment_variables()`, read-only
## - [Time](os-time.md): `Duration`, `Instant` (a monotonic clock, for
##   measuring) and `SystemTime` (the wall clock)
## - [Machine](os-machine.md): `system_os()`, `system_name()`, `system_version()`,
##   `architecture()`, `hostname()`, processor counts, `total_memory()`,
##   `page_size()`
## - [User](os-user.md): `user_name()`, `home_directory()`,
##   `temp_directory()`
##
## @example
##     import os;
##
##     main(): int {
##         var start = os.Instant.now();
##         var runtime = os.environment("PEPPER_RUNTIME").value_or("runtime");
##         print($"runtime at {runtime} on {os.hostname()}");
##         print($"took {os.Instant.now() - start}");
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "environment";
import "machine";
import "sys_posix";
import "sys_windows";
import "time";
import "user";

export environment;
export environment_variables;
export Duration;
export Instant;
export SystemTime;
export OperatingSystem;
export system_os;
export system_name;
export system_version;
export architecture;
export hostname;
export logical_cpus;
export physical_cpus;
export total_memory;
export page_size;
export user_name;
export home_directory;
export temp_directory;

# For the process module only: the environment a child inherits.
export _os_environment_entries;
[Target(!OS(Windows))]
export _os_environ;
