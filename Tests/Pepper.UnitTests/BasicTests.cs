using System.Runtime.CompilerServices;
using Antlr4.Runtime;

namespace Pepper.UnitTests {
    public class Tests {
        [SetUp]
        public void Setup() {
        }

        [Test]
        public void HelloWorld() {
            var source = """
                int main() {
                    print("Hello World!");
                    return 0;
                }
                """;
            Compiler.Compile("HelloWorld", CharStreams.fromString(source));
            int result = Compiler.JIT("main");
            Assert.That(result, Is.EqualTo(0));
        }
    }
}