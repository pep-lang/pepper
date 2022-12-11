using System;
namespace Pepper.UnitTests
{
    public class FloatMath
    {
        [Test]
        public void LessThanFloat()
        {
            var source = """
                int main() {
                    float x = 12.0;
                    return x < 2.0;
                }
                """;
            Utils.CompileAndRun("LessThanFloat", source);
        }
    }
}

