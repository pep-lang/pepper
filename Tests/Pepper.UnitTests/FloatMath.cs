using System;
namespace Pepper.UnitTests
{
    public class FloatMath
    {
        [Test]
        public void Add() {
            var source = """
                int main() {
                    float x = 12.5;
                    return x + 5;
                }
                """;
            Utils.CompileAndRun("Add", source, 17);
        }

        [Test]
        public void Subtract() {
            var source = """
                int main() {
                    float x = 12.5;
                    return x - 5;
                }
                """;
            Utils.CompileAndRun("Subtract", source, 7);
        }

        [Test]
        public void Multiply() {
            var source = """
                int main() {
                    float x = 12.5;
                    return x * 5;
                }
                """;
            Utils.CompileAndRun("Multiply", source, 62);
        }

        [Test]
        public void Divide() {
            var source = """
                int main() {
                    float x = 12.5;
                    return x / 5;
                }
                """;
            Utils.CompileAndRun("Divide", source, 2);
        }

        [Test]
        public void Modulo() {
            var source = """
                int main() {
                    float x = 12.5;
                    return x % 5;
                }
                """;
            Utils.CompileAndRun("Modulo", source, 2);
        }

        [Test]
        public void MultiVariableAdd() {
            var source = """
                int main() {
                    float x = 12.55;
                    float y = 42.5;
                    return x + y;
                }
                """;
            Utils.CompileAndRun("MultiVariableAdd", source, 55);
        }

        [Test]
        public void LessThan()
        {
            var source = """
                int main() {
                    float x = 12.0;
                    return x < 2.0;
                }
                """;
            Utils.CompileAndRun("LessThan", source);
        }

        [Test]
        public void GreaterThan() {
            var source = """
                int main() {
                    float x = 12.0;
                    return x > 2.0;
                }
                """;
            Utils.CompileAndRun("GreaterThan", source, 1);
        }

        [Test]
        public void LessEqual() {
            var source = """
                int main() {
                    float x = 12.0;
                    return x <= 2.0;
                }
                """;
            Utils.CompileAndRun("LessEqual", source);
        }

        [Test]
        public void GreaterEqual() {
            var source = """
                int main() {
                    float x = 12.0;
                    return x >= 2.0;
                }
                """;
            Utils.CompileAndRun("GreaterEqual", source, 1);
        }
    }
}

