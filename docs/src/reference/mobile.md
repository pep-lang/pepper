<!-- Generated from runtime/mobile.pep by `pep-doc reference`. Do not edit. -->

# iOS and Android

What the runtime does only on iOS and Android: sending an app's standard
output and error to the platform's log, and, on Android, taking the
app's folders from the app (see
[iOS and Android](../language/mobile.md)).

Source: `runtime/mobile.pep`

## pepper_set_app_directories

```pepper
[Target(OS(Android))] [Export] pepper_set_app_directories(files: String, cache: String)
```

Tells the Pepper runtime where the app's folders are, as Android gives
native code no way to find them: call it once, early (in the
`Application`'s or first activity's `onCreate`), before Pepper code uses
them. The C library exports it as `pepper_set_app_directories`, and the
Java bindings (`--bindings java`, `--lib aar`) as
`pepperSetAppDirectories` on the library's class:

    Greeter.pepperSetAppDirectories(getFilesDir().getPath(), getCacheDir().getPath());

Then `os.app_directories()` returns them, and `io.Directory.temp()` is
the cache folder (unless `TMPDIR` is set). A later call replaces them.

**Parameters**
- `files` — the app's files folder, `Context.getFilesDir()`
- `cache` — the app's cache folder, `Context.getCacheDir()`
