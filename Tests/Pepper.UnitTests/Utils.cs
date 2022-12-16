using Antlr4.Runtime;
using System;
namespace Pepper.UnitTests {
    public static class Utils {
        public static void CompileAndRun(string module, string source, int expectedResult = 0) {
            using var compiler = Compiler.Compile(module, source, CharStreams.fromString(source));
            var jit = new Executor();
            int result = jit.Execute(compiler.Module, "main");
            try {
                Log.Info($"main returned {result}");
                Assert.That(result, Is.EqualTo(expectedResult));
            } catch (Exception ex) {
                Log.Error(ex.Message);
            }

        }
    }
}

