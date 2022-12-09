using System.Runtime.CompilerServices;
using Antlr4.Runtime;

namespace Pepper.UnitTests {
    public class Tests {
        [SetUp]
        public void Setup() {
        }

        static void CompileAndRun(string module, string source) {
            Compiler.Compile("HelloWorld", CharStreams.fromString(source));
            int result = Compiler.JIT("main");
            Assert.That(result, Is.EqualTo(0));
        }

        [Test]
        public void HelloWorld() {
            var source = """
                int main() {
                    print("Hello World!");
                    return 0;
                }
                """;
            CompileAndRun("HelloWorld", source);
        }

        [Test]
        public void Let() {
            var source = """
                int main() {
                    int x = 0;
                    return x;
                }
                """;
            CompileAndRun("Let", source);
        }
    }
}