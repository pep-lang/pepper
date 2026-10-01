# Both modules export `Length`, `parse` and `unit`; each keeps its own.
import "metric" as metric;
import "imperial" as imp;
import [unit as imperial_unit] from "imperial";

main(): int {
    var a: metric.Length = metric.parse("abc");
    var b: imp.Length = imp.parse("abc");
    assert(a.metres == 3.0, "metric.parse");
    assert(b.feet == 9.0, "imperial.parse");
    assert(metric.unit() == "m", "qualified by the alias");
    assert(imperial_unit() == "ft", "renamed by the import list");
    return 0;
}
