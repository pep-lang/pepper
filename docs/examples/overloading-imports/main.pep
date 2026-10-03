import "numbers";
import "flags";

# The file's own `describe` joins the two modules' sets.
describe(text: String): String {
    return "some text";
}

main(): int {
    assert(describe(3) == "a number", "numbers' member");
    assert(describe(true) == "a flag", "flags' member");
    assert(describe("hi") == "some text", "this file's member");
    return 0;
}
