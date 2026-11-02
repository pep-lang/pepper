#include <stdint.h>
typedef struct { int32_t x, y; } Point;
typedef struct { int32_t a, b, c; } Size3;
typedef struct { float x, y; } Vec2;
typedef struct { double x, y, z; } Vec3d;
typedef struct { double d; int32_t i; } Mixed;
typedef struct { int64_t a, b, c, d; } Big;
typedef struct { Point p; float w; } Nested;
typedef struct { uint8_t a, b; } Small;
typedef struct { double d; float f; } Padded;

Point c_point_add(Point a, Point b) { Point r = { a.x + b.x, a.y + b.y }; return r; }
Size3 c_size3_twice(Size3 s) { Size3 r = { 2 * s.a, 2 * s.b, 2 * s.c }; return r; }
Vec2 c_vec2_scale(Vec2 v, float k) { Vec2 r = { v.x * k, v.y * k }; return r; }
Vec3d c_vec3_cross(Vec3d a, Vec3d b) {
    Vec3d r = { a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x };
    return r;
}
Mixed c_mixed(Mixed m) { Mixed r = { m.d * 2, m.i + 1 }; return r; }
Big c_big(Big b, int64_t add) { Big r = { b.a + add, b.b + add, b.c + add, b.d + add }; return r; }
Nested c_nested(Nested n) { Nested r = { { n.p.y, n.p.x }, n.w * 3 }; return r; }
Small c_small(Small s) { Small r = { s.b, s.a }; return r; }
Padded c_padded(Padded p) { Padded r = { p.d + 1, p.f * 2 }; return r; }
int32_t c_seven(Point a, Point b, Point c, Point d, Point e, Point f, Point g) {
    return a.x + b.x + c.x + d.x + e.x + f.x + g.x + 10 * (a.y + b.y + c.y + d.y + e.y + f.y + g.y);
}
double c_regs(double d1, int64_t i1, Vec3d v, Mixed m, int32_t i2) { return d1 + i1 + v.x + v.y + v.z + m.d + m.i + i2; }

Point pep_point_add(Point a, Point b);
Vec3d pep_vec3_scale(Vec3d v, double k);
Big pep_big(Big b);
Size3 pep_size3(Size3 s);
Vec2 pep_vec2(Vec2 v);
Mixed pep_mixed(Mixed m);
Small pep_small(Small s);

int64_t c_callbacks(void) {
    Point p = pep_point_add((Point){1, 2}, (Point){10, 20});
    Vec3d v = pep_vec3_scale((Vec3d){1, 2, 3}, 2);
    Big b = pep_big((Big){1, 2, 3, 4});
    Size3 s = pep_size3((Size3){5, 6, 7});
    Vec2 w = pep_vec2((Vec2){1.5f, 2.5f});
    Mixed m = pep_mixed((Mixed){0.5, 7});
    Small sm = pep_small((Small){3, 4});
    return p.x + p.y + (int64_t)(v.x + v.y + v.z) + b.a + b.b + b.c + b.d + s.a + s.b + s.c
        + (int64_t)(w.x * 10 + w.y * 10) + (int64_t)(m.d * 10) + m.i + sm.a * 100 + sm.b;
}
