using System;
namespace Pepper.UnitTests {
    public class FunctionTest {
        [Test]
        public void Sum() {
            var source = """
                int sum(int x, int y) {
                    return x + y;
                }
                int main() {
                    return sum(2, 2);
                }
                """;
            Utils.CompileAndRun("Sum", source, 4);
        }

        [Test]
        public void SumMul() {
            var source = """
                int mul(int x, int y) {
                    return x * y;
                }
                int sum(int x, int y) {
                    return x + y;
                }
                int main() {
                    return sum(mul(10, 2), mul(-10, 2));
                }
                """;
            Utils.CompileAndRun("SumMul", source, 0);
        }
    }
}

