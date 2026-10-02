## Starting a program: `Command` names it and its arguments, environment,
## working directory and standard streams; `spawn()` starts it and `run()`
## also waits for it and collects what it wrote.

import async;
import io;
import os;
import "child";
import "sys_posix";
import "sys_windows";

## Where a child's standard input, output or error goes (see
## `Command.stdin`, `Command.stdout` and `Command.stderr`).
export enum Stream {
    ## The child shares the parent's stream: it reads the parent's input,
    ## or writes where the parent writes.
    Inherit,
    ## A pipe connects the stream to the parent, which reaches it through
    ## `Child.stdin()`, `Child.stdout()` or `Child.stderr()`.
    Pipe,
    ## The stream is the null device: reading it finds the end at once, and
    ## what is written to it is thrown away.
    Null,
}

## What a program `Command.run()` waited for left behind: how it ended and
## what it wrote.
export struct Output {
    ## How the program ended.
    var status: ExitStatus;
    ## Everything the program wrote to standard output, decoded as UTF-8
    ## (each byte sequence that is not valid UTF-8 becomes U+FFFD); empty
    ## when standard output was not piped.
    var stdout: String;
    ## Everything the program wrote to standard error, decoded the same
    ## way; empty when standard error was not piped.
    var stderr: String;

    ## Creates an Output from its parts.
    ##
    ## @param status how the program ended
    ## @param stdout what it wrote to standard output
    ## @param stderr what it wrote to standard error
    construct(status: ExitStatus, stdout: String, stderr: String) {
        this.status = status;
        this.stdout = stdout;
        this.stderr = stderr;
    }
}

## Describes a program to start: the program, its arguments, its
## environment, its working directory, and where its standard streams go.
##
## A builder in the style of Rust's `std::process::Command`: each setter
## stores its value and returns this same Command, so calls chain, and one
## Command can start the program any number of times.
##
## The program is found the way a shell finds it: a name with no path
## separator is searched for on the `PATH` (on Windows, also in the
## directory of the running program and the system directories, and `.exe`
## is added when the name has no extension); anything else is a path,
## relative to the parent's current directory.
##
## The child inherits the parent's environment, changed by `environment`,
## `remove_environment` and `clear_environment`. By default it also
## inherits the parent's current directory and its three standard streams;
## `run()` instead pipes standard output and error, and gives standard
## input the null device, unless they were set.
##
## @example
##     import process;
##
##     main(): int {
##         var output = process.Command("clang").arguments(["--version"]).run().value();
##         if (!output.status.success()) {
##             print(output.stderr);
##             return 1;
##         }
##         return 0;
##     }
export struct Command {
    ## The program to start, as given to the constructor.
    var program: String;
    # The arguments after the program.
    var _arguments: Array<String>;
    # Environment changes in order: a value to set, or none to remove.
    var _environment_names: Array<String>;
    var _environment_values: Array<String?>;
    # Whether the child starts from an empty environment.
    var _clear_environment: bool;
    var _working_directory: io.Path?;
    # Where each standard stream goes, when it was set.
    var _stdin: Stream?;
    var _stdout: Stream?;
    var _stderr: Stream?;

    ## Creates a Command that starts `program` with no arguments, the
    ## parent's environment and current directory, and inherited streams.
    ##
    ## @param program the program: a name to search for on the `PATH`, or a
    ##   path
    construct(program: String) {
        this.program = program;
        this._arguments = Array<String>();
        this._environment_names = Array<String>();
        this._environment_values = Array<String?>();
    }

    ## Adds one argument after those already added. It reaches the program
    ## as one element of its arguments, whatever it holds: no shell splits
    ## or expands it. On Windows, where a program receives one command line,
    ## it is quoted so that the C runtime splits it back out as it was.
    ##
    ## @param value the argument
    ## @returns this Command
    argument(value: String): Command {
        _arguments.append(value);
        return this;
    }

    ## Adds each of `values` as an argument, in order.
    ##
    ## @param values the arguments
    ## @returns this Command
    arguments(values: Array<String>): Command {
        for (var value in values) {
            _arguments.append(value);
        }
        return this;
    }

    ## Sets the environment variable `name` to `value` for the child,
    ## replacing any value it would inherit. On Windows, names are compared
    ## without regard to case.
    ##
    ## @param name the variable's name
    ## @param value its value
    ## @returns this Command
    environment(name: String, value: String): Command {
        _environment_names.append(name);
        _environment_values.append(Optional<String>.some(value));
        return this;
    }

    ## Leaves the environment variable `name` out of the child's
    ## environment, including a value an earlier `environment` set.
    ##
    ## @param name the variable's name
    ## @returns this Command
    remove_environment(name: String): Command {
        _environment_names.append(name);
        _environment_values.append(Optional<String>.none());
        return this;
    }

    ## Starts the child with an empty environment, dropping every variable
    ## the parent has and every change made so far; later calls to
    ## `environment` add to it.
    ##
    ## @returns this Command
    clear_environment(): Command {
        _clear_environment = true;
        _environment_names = Array<String>();
        _environment_values = Array<String?>();
        return this;
    }

    ## Starts the child in `path` instead of the parent's current directory.
    ## A relative program path is still resolved against the parent's
    ## current directory.
    ##
    ## @param path the child's current directory
    ## @returns this Command
    working_directory(path: io.Path): Command {
        _working_directory = Optional<io.Path>.some(path);
        return this;
    }

    ## Sets where the child's standard input comes from.
    ##
    ## @param stream `Stream.Inherit`, `Stream.Pipe` or `Stream.Null`
    ## @returns this Command
    stdin(stream: Stream): Command {
        _stdin = Optional<Stream>.some(stream);
        return this;
    }

    ## Sets where the child's standard output goes.
    ##
    ## @param stream `Stream.Inherit`, `Stream.Pipe` or `Stream.Null`
    ## @returns this Command
    stdout(stream: Stream): Command {
        _stdout = Optional<Stream>.some(stream);
        return this;
    }

    ## Sets where the child's standard error goes.
    ##
    ## @param stream `Stream.Inherit`, `Stream.Pipe` or `Stream.Null`
    ## @returns this Command
    stderr(stream: Stream): Command {
        _stderr = Optional<Stream>.some(stream);
        return this;
    }

    ## Starts the program and returns at once, without waiting for it.
    ##
    ## Each stream that was not set is inherited. A piped stream is reached
    ## through the Child; close a piped standard input when done writing, or
    ## a child that reads to the end never finishes. Wait for the child with
    ## `Child.wait()`: a child that is never waited for stays in the process
    ## table until the parent ends.
    ##
    ## @returns the running child; an error when the program cannot be
    ##   started: `is_not_found()` when it is not found, `is_permission_denied()`
    ##   when it is not executable, or another platform error
    ## @example
    ##     var child = process.Command("sort").stdin(process.Stream.Pipe).stdout(process.Stream.Pipe).spawn().value();
    ##     child.stdin().write_all("pear\napple\n");
    ##     child.stdin().close();
    ##     var sorted = child.stdout().read_string().value();   # "apple\npear\n"
    ##     child.wait();
    spawn(): io.IoResult<Child> {
        return _process_sys_spawn(this, _stream_or(_stdin), _stream_or(_stdout), _stream_or(_stderr));
    }

    ## Starts the program, waits for it to end, and returns how it ended
    ## with what it wrote.
    ##
    ## Standard output and error are piped and collected unless they were
    ## set, and standard input is the null device unless it was set. Both
    ## outputs are read at once, so a child that fills one pipe while the
    ## parent reads the other does not stall. In a task, the reads and the
    ## wait park the task rather than blocking its worker.
    ##
    ## @returns the exit status and output; an error when the program cannot
    ##   be started (as for `spawn()`) or its output cannot be read
    ## @example
    ##     var output = process.Command("echo").argument("hello").run().value();
    ##     assert(output.status.success(), "echo succeeds");
    ##     assert(output.stdout == "hello\n", "and prints its argument");
    run(): io.IoResult<Output> {
        var stdin = _stdin.is_some() ? _stdin.value() : Stream.Null;
        var stdout = _stdout.is_some() ? _stdout.value() : Stream.Pipe;
        var stderr = _stderr.is_some() ? _stderr.value() : Stream.Pipe;
        var spawned = _process_sys_spawn(this, stdin, stdout, stderr);
        if (spawned.is_err()) {
            return io.IoResult<Output>.err(spawned.error());
        }
        var child = spawned.value();
        var collected = child._collect();
        var status = child.wait();
        if (status.is_err()) {
            return io.IoResult<Output>.err(status.error());
        }
        if (collected.is_err()) {
            return io.IoResult<Output>.err(collected.error());
        }
        var output = collected.value();
        output.status = status.value();
        return io.IoResult<Output>.ok(output);
    }

    # The child's environment as `NAME=VALUE` entries: the parent's, or none
    # after `clear_environment`, with the changes applied.
    _environment_entries(): Array<String> {
        var entries = Array<String>();
        if (!_clear_environment) {
            entries = os._os_environment_entries();
        }
        var index: ulong = 0;
        while (index < _environment_names.count) {
            var name = _environment_names[index];
            var kept = Array<String>();
            for (var entry in entries) {
                if (!_process_entry_names(entry, name)) {
                    kept.append(entry);
                }
            }
            var value = _environment_values[index];
            if (value.is_some()) {
                kept.append(name + "=" + value.value());
            }
            entries = kept;
            index = index + 1;
        }
        return entries;
    }

    # Whether the child's environment differs from the parent's.
    _changes_environment(): bool {
        return _clear_environment || _environment_names.count > 0;
    }
}

# `stream`, or `Stream.Inherit` when it was not set.
_stream_or(stream: Stream?): Stream {
    if (stream.is_some()) {
        return stream.value();
    }
    return Stream.Inherit;
}

# Whether the environment entry `entry` (`NAME=VALUE`) is for `name`. On
# Windows a leading '=' belongs to the name (such as `=C:`), and names are
# compared without regard to case.
_process_entry_names(entry: String, name: String): bool {
    if (entry.size <= name.size || entry.byte_at(name.size) != 61) {
        return false;
    }
    var own = entry.substr_bytes(0, name.size);
    if (_process_sys_names_ignore_case()) {
        return own.lower() == name.lower();
    }
    return own == name;
}
