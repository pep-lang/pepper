# Named arguments: `name = value` after the positional arguments.
window(title: String, width: int = 800, height: int = 600, resizable: bool = true): String {
    return $"{title} {width}x{height} resizable={resizable}";
}

struct Point {
    var x: int;
    var y: int;

    construct(this.x = 0, this.y = 0) {}

    moved(dx: int = 0, dy: int = 0): Point {
        return Point(x + dx, y + dy);
    }
}

# 'size = ...' works as well as 'count = ...'; 'n = ...' still works, with a
# deprecation warning.
[Alias("size", "count")]
[Rename("n", "count")]
repeat(text: String, count: int = 1): String {
    var result = "";
    for (var i in 0..count) {
        result = result + text;
    }
    return result;
}

main(): int {
    assert(window("Editor") == "Editor 800x600 resizable=true", "all defaults");
    # Skip width and height.
    assert(window("Editor", resizable = false) == "Editor 800x600 resizable=false", "skip");
    # Named arguments in any order.
    assert(window("Editor", height = 400, width = 1200) == "Editor 1200x400 resizable=true", "any order");
    # Every argument may be named.
    assert(window(title = "Editor", width = 1024) == "Editor 1024x600 resizable=true", "all named");

    # Constructors and methods take them too.
    var p = Point(y = 5);
    assert(p.moved(dy = 2).y == 7, "method");

    assert(repeat("ab", size = 3) == "ababab", "alias");
    return 0;
}
