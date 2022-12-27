
using Antlr4.Runtime;

namespace Pepper.UnitTests {
    public class BasicTests {

        

        [Test]
        public void HelloWorld() {
            var source = """
                int main() {
                    print("Hello World!");
                    return 0;
                }
                """;
            Utils.CompileAndRun("HelloWorld", source);
        }

        [Test]
        public void Let() {
            var source = """
                int main() {
                    int x = 12;
                    return x;
                }
                """;
            Utils.CompileAndRun("Let", source, 12);
        }
    }
}