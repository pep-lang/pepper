# The geometry module: what this file exports is the module's interface.
import "shapes";
import "solids" as solids;

export struct Point {
    var x: int;
    var y: int;
}

export make(x: int, y: int): Point {
    var p = Point();
    p.x = x;
    p.y = y;
    return p;
}

reset_count(): int {
    return 0;
}

export area as rect_area;           # shapes.pep's area, renamed
export Box;                         # shapes.pep's Box, under its own name
export reset_count as reset;        # a private function, exported as reset
export solids.volume as box_volume; # from the nested module
