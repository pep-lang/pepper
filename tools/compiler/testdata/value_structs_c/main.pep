# Value structs of each shape C passes differently, to and from C by value
# (#384): main calls C, and C calls the exports back.

[Value]
struct Point {
    var x: int;
    var y: int;
    construct(this.x = 0, this.y = 0) {}
}

[Value]
struct Size3 {
    var a: int;
    var b: int;
    var c: int;
    construct(this.a = 0, this.b = 0, this.c = 0) {}
}

[Value]
struct Vec2 {
    var x: float;
    var y: float;
    construct(this.x = 0.0, this.y = 0.0) {}
}

[Value]
struct Vec3d {
    var x: double;
    var y: double;
    var z: double;
    construct(this.x = 0.0, this.y = 0.0, this.z = 0.0) {}
}

[Value]
struct Mixed {
    var d: double;
    var i: int;
    construct(this.d = 0.0, this.i = 0) {}
}

[Value]
struct Big {
    var a: long;
    var b: long;
    var c: long;
    var d: long;
    construct(this.a = 0, this.b = 0, this.c = 0, this.d = 0) {}
}

[Value]
struct Nested {
    var p: Point;
    var w: float;
    construct(this.p = Point(), this.w = 0.0) {}
}

[Value]
struct Small {
    var a: u8;
    var b: u8;
    construct(this.a = 0, this.b = 0) {}
}

extern Point c_point_add(Point a, Point b);
extern Size3 c_size3_twice(Size3 s);
extern Vec2 c_vec2_scale(Vec2 v, float k);
extern Vec3d c_vec3_cross(Vec3d a, Vec3d b);
extern Mixed c_mixed(Mixed m);
extern Big c_big(Big b, long add);
extern Nested c_nested(Nested n);
extern Small c_small(Small s);
extern int c_seven(Point a, Point b, Point c, Point d, Point e, Point f, Point g);
extern double c_regs(double d1, long i1, Vec3d v, Mixed m, int i2);
extern long c_callbacks();

[Export]
pep_point_add(a: Point, b: Point): Point {
    return Point(a.x + b.x, a.y + b.y);
}

[Export]
pep_vec3_scale(v: Vec3d, k: double): Vec3d {
    return Vec3d(v.x * k, v.y * k, v.z * k);
}

[Export]
pep_big(b: Big): Big {
    return Big(b.d, b.c, b.b, b.a * 100);
}

[Export]
pep_size3(s: Size3): Size3 {
    return Size3(s.c, s.b, s.a + 1000);
}

[Export]
pep_vec2(v: Vec2): Vec2 {
    return Vec2(v.y, v.x);
}

[Export]
pep_mixed(m: Mixed): Mixed {
    return Mixed(m.d + 1.0, m.i * 3);
}

[Export]
pep_small(s: Small): Small {
    return Small(s.b, s.a);
}

main(): int {
    var p = c_point_add(Point(1, 2), Point(30, 40));
    print($"point {p.x} {p.y}");
    var s = c_size3_twice(Size3(1, 2, 3));
    print($"size3 {s.a} {s.b} {s.c}");
    var v = c_vec2_scale(Vec2(1.5, -2.0), 2.0);
    print($"vec2 {v.x} {v.y}");
    var c = c_vec3_cross(Vec3d(1.0, 0.0, 0.0), Vec3d(0.0, 1.0, 0.0));
    print($"vec3 {c.x} {c.y} {c.z}");
    var m = c_mixed(Mixed(1.25, 41));
    print($"mixed {m.d} {m.i}");
    var b = c_big(Big(1, 2, 3, 4), 100);
    print($"big {b.a} {b.b} {b.c} {b.d}");
    var n = c_nested(Nested(Point(5, 6), 1.5));
    print($"nested {n.p.x} {n.p.y} {n.w}");
    var sm = c_small(Small(7, 9));
    print($"small {sm.a} {sm.b}");
    var seven = c_seven(Point(1, 1), Point(2, 1), Point(3, 1), Point(4, 1), Point(5, 1), Point(6, 1), Point(7, 1));
    print($"seven {seven}");
    print($"regs {c_regs(0.5, 2, Vec3d(1.0, 2.0, 3.0), Mixed(0.25, 4), 5)}");
    print($"callbacks {c_callbacks()}");
    return 0;
}
