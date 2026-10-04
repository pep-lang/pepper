# debug.capture() resolves each frame to the function it is in, from the
# symbol table alone (a test build has no debug info to rely on).

import debug;

struct Point {
    var x: int;
    construct(x: int) {
        this.x = x;
    }
    trace(): Array<debug.StackFrame> {
        return debug.capture().frames();
    }
}

helper<T>(value: T): Array<debug.StackFrame> {
    var p = Point(1);
    return p.trace();
}

# A method of a struct, called from a generic function, captures the stack:
# the frames start at the method, then its callers.
[Test]
capture_names_functions_without_debug_info() {
    var frames = helper<int>(3);
    expect_true(frames.count >= 3);
    expect_equal(frames[0].function, "Point.trace");
    expect_equal(frames[1].function, "helper<int>");
    expect_equal(frames[2].function, "capture_names_functions_without_debug_info");
}
