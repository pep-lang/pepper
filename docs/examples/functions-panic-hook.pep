# A panic hook: code that runs before a panic prints its message.

import [File] from io;

# A full-screen program draws on the terminal's alternate screen, and must
# leave it before a panic's message prints, or the message goes with it.
leave_alternate_screen() {
    File.stdout().write_all("\x1B[?1049l");
}

main(): int {
    File.stdout().write_all("\x1B[?1049h");
    # Chain the hook installed before (none here) after this program's own.
    var previous = take_panic_hook();
    set_panic_hook((message, location) => {
        leave_alternate_screen();
        previous(message, location);
    });

    # ... draw, until the user quits; a panic here leaves the screen first.

    leave_alternate_screen();
    take_panic_hook();
    return 0;
}
