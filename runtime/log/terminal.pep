# Whether standard error is a terminal that shows ANSI colors. Every
# platform declares `_log_stderr_shows_color` with the same signature.

[Target(OS(Linux) || OS(Mac))]
extern int isatty(int fd);
[Target(OS(Windows))]
extern void* GetStdHandle(uint which);
[Target(OS(Windows))]
extern int GetConsoleMode(void* console, uint* mode);

[Target(OS(Linux) || OS(Mac))]
_log_stderr_shows_color(): bool {
    return isatty(2) != 0;
}

# Windows: only a console already in virtual terminal mode (Windows
# Terminal, VS Code) reads ANSI escapes; the mode is left as it is.
[Target(OS(Windows))]
_log_stderr_shows_color(): bool {
    var mode = _pep_malloc(4) as __ptr<uint>;
    mode[0] = 0;
    # STD_ERROR_HANDLE is (DWORD)-12.
    var ok = GetConsoleMode(GetStdHandle(4294967284 as uint), mode);
    var shows = ok != 0 && (mode[0] & 4) != 0;
    _pep_free(mode);
    return shows;
}

[Target(!OS(Linux) && !OS(Mac) && !OS(Windows))]
_log_stderr_shows_color(): bool {
    return false;
}
