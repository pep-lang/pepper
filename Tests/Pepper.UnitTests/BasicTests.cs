using System.Runtime.CompilerServices;
using Antlr4.Runtime;

namespace Pepper.UnitTests {
    public class Tests {
        [SetUp]
        public void Setup() {
        }

        static void CompileAndRun(string module, string source, int expectedResult = 0) {
            Compiler.Compile("HelloWorld", CharStreams.fromString(source));
            int result = Compiler.JIT("main");
            Assert.That(result, Is.EqualTo(expectedResult));
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
                    int x = 12;
                    return x;
                }
                """;
            CompileAndRun("Let", source, 12);
        }

        [Test]
        public void Multiply() {
            var source = """
                int main() {
                    int x = 12;
                    return x * 5;
                }
                """;
            CompileAndRun("Multiply", source, 60);
        }
    }
}