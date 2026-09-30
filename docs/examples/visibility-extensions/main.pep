import "point";
import "measure";                      # brings Point's manhattan() into scope

main(): int {
    var p = Point();
    p.x = 3;
    p.y = -4;
    assert(p.manhattan() == 7, "an extension from an imported file");
    return 0;
}
