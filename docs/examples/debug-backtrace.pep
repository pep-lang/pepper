# Capturing the call stack and resolving it to functions and lines.
import debug;

struct Parser {
    var depth: int;

    construct() {
        depth = 0;
    }

    # Records where it was called from, as an error report might.
    where(): debug.Backtrace {
        return debug.capture();
    }
}

main(): int {
    var parser = Parser();
    var trace = parser.where();
    var frames = trace.frames();
    for (var frame in frames) {
        print(frame.to_string());
    }
    # The outermost frame is main. (With -O, `where` is inlined into main
    # and has no frame of its own; WebAssembly cannot walk its stack, so
    # there a backtrace is empty.)
    if (frames.count > 0) {
        assert(frames[frames.count - 1].function == "main", "the outermost call");
    }
    debug.output("done");
    return 0;
}
