
using Antlr4.Runtime;

namespace Pepper.UnitTests {
    public class StructTests {
        [Test]
        public void Basic() {
            var source = """
                struct Test {
                    int x = 1;
                };
                int main() {
                    Test t = Test();
                    return t.x;
                }
                """;
            Utils.CompileAndRun("HelloWorld", source);
        }
    }
}