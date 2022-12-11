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
                    puts("Hello World!");
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
        public void Add() {
            var source = """
                int main() {
                    int x = 12;
                    return x + 5;
                }
                """;
            CompileAndRun("Add", source, 17);
        }

        [Test]
        public void Subtract() {
            var source = """
                int main() {
                    int x = 12;
                    return x - 5;
                }
                """;
            CompileAndRun("Subtract", source, 7);
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

        [Test]
        public void Divide() {
            var source = """
                int main() {
                    int x = 12;
                    return x / 5;
                }
                """;
            CompileAndRun("Divide", source, 2);
        }

        [Test]
        public void Modulo() {
            var source = """
                int main() {
                    int x = 12;
                    return x % 5;
                }
                """;
            CompileAndRun("Modulo", source, 2);
        }

        [Test]
        public void MultiVariableAdd() {
            var source = """
                int main() {
                    int x = 12;
                    int y = 42;
                    return x + y;
                }
                """;
            CompileAndRun("MultiVariableAdd", source, 54);
        }

        [Test]
        public void LeftShift() {
            var source = """
                    int main() {
                    int x = 12;
                    return x << 2;
                }
                """;
            CompileAndRun("LeftShift", source, 48);
        }

        [Test]
        public void RightShift() {
            var source = """
                    int main() {
                    int x = 12;
                    return x >> 2;
                }
                """;
            CompileAndRun("RightShift", source, 3);
        }

        [Test]
        public void LessThanInt() {
            var source = """
                    int main() {
                    int x = 12;
                    return x < 2;
                }
                """;
            CompileAndRun("LessThanInt", source);
        }

        //[Test]
        //public void LessThanReal() {
        //    var source = """
        //            int main() {
        //            float x = 12.0;
        //            return x < 2.0;
        //        }
        //        """;
        //    CompileAndRun("LessThanFloat", source);
        //}

        [Test]
        public void CompoundFormula() {
            var source = """
                int main() {
                    int x = 12;
                    int y = 16;
                    return x * 5 / y;
                }
                """;
            CompileAndRun("Modulo", source, 3);
        }
    }
}