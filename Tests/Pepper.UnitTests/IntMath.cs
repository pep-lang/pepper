using System;
namespace Pepper.UnitTests {
    public class IntMath {
        [Test]
        public void Add() {
            var source = """
                int main() {
                    int x = 12;
                    return x + 5;
                }
                """;
            Utils.CompileAndRun("Add", source, 17);
        }

        [Test]
        public void Subtract() {
            var source = """
                int main() {
                    int x = 12;
                    return x - 5;
                }
                """;
            Utils.CompileAndRun("Subtract", source, 7);
        }

        [Test]
        public void Multiply() {
            var source = """
                int main() {
                    int x = 12;
                    return x * 5;
                }
                """;
            Utils.CompileAndRun("Multiply", source, 60);
        }

        [Test]
        public void Divide() {
            var source = """
                int main() {
                    int x = 12;
                    return x / 5;
                }
                """;
            Utils.CompileAndRun("Divide", source, 2);
        }

        [Test]
        public void Modulo() {
            var source = """
                int main() {
                    int x = 12;
                    return x % 5;
                }
                """;
            Utils.CompileAndRun("Modulo", source, 2);
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
            Utils.CompileAndRun("MultiVariableAdd", source, 54);
        }

        [Test]
        public void LeftShift() {
            var source = """
                int main() {
                    int x = 12;
                    return x << 2;
                }
                """;
            Utils.CompileAndRun("LeftShift", source, 48);
        }

        [Test]
        public void RightShift() {
            var source = """
                int main() {
                    int x = 12;
                    return x >> 2;
                }
                """;
            Utils.CompileAndRun("RightShift", source, 3);
        }

        [Test]
        public void LessThanInt() {
            var source = """
                int main() {
                    int x = 12;
                    return x < 2;
                }
                """;
            Utils.CompileAndRun("LessThanInt", source);
        }

        [Test]
        public void BitwiseAnd() {
            var source = """
                int main() {
                    int x = 12;
                    return x & 1;
                }
                """;
            Utils.CompileAndRun("BitwiseAnd", source);
        }

        [Test]
        public void BitwiseOr() {
            var source = """
                int main() {
                    int x = 12;
                    return x | 1;
                }
                """;
            Utils.CompileAndRun("BitwiseOr", source, 13);
        }

        [Test]
        public void BitwiseXor() {
            var source = """
                int main() {
                    int x = 12;
                    return x ^ 1;
                }
                """;
            Utils.CompileAndRun("BitwiseXor", source, 13);
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
        public void MulAssign() {
            var source = """
                int main() {
                    int x = 1;
                    int y = 4;
                    x *= y;
                    return x;
                }
                """;
            Utils.CompileAndRun("LogicalOr", source, 4);
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
            Utils.CompileAndRun("CompoundFormula", source, 3);
        }
    }
}

