<!-- Generated from runtime/process.pep by `pep-doc reference`. Do not edit. -->

# Arguments and exit (deprecated)

The running program's arguments and exit, kept for the deprecated
prelude `arguments()` and `exit()`; the `process` module has them now.

Source: `runtime/process.pep`

## arguments

```pepper
[Deprecated("use 'process.arguments' instead (import process)")] arguments(): Array<String>
```

Deprecated: use `process.arguments` instead.

Returns the program's command-line arguments, as `process.arguments()`
does.

**Returns**
- the program name followed by its arguments

## exit

```pepper
[Deprecated("use 'process.exit' instead (import process)")] exit(code: int)
```

Deprecated: use `process.exit` instead.

Ends the program at once with status `code`, as `process.exit(code)`
does: C's `atexit` handlers run and the C output streams are flushed.

**Parameters**
- `code` — the exit status: 0 for success, anything else for failure
