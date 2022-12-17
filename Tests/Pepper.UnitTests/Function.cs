using System;
namespace Pepper.UnitTests {
    public class Function {
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


    }
}

