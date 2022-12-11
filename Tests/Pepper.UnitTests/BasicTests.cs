
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

        

        [Test]
        public void LogicalAnd() {
            var source = """
                int main() {
                    int x = 1;
                    int y = 0;
                    return x && y;
                }
                """;
            Utils.CompileAndRun("LogicalAnd", source);
        }

        [Test]
        public void LogicalOr() {
            var source = """
                int main() {
                    int x = 1;
                    int y = 0;
                    return x || y;
                }
                """;
            Utils.CompileAndRun("LogicalOr", source, 1);
        }

        [Test]
        public void CompoundFormula() {
            var source = """
                int main() {
                    int x = 12;
                    int y = 16;
                    return x * 5 / y;
                }
                """;
            Utils.CompileAndRun("Modulo", source, 3);
        }
    }
}