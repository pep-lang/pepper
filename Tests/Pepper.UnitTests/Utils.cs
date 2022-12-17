using Antlr4.Runtime;
using System;
using System.Runtime.CompilerServices;

namespace Pepper.UnitTests {
    public static class Utils {
        public static void CompileAndRun(string module,
            string source, int expectedResult = 0,
            [CallerFilePath] string sourcePath = "",
            [CallerMemberName] string testName = "") {
            var stream = new CodePointCharStream(source) {
                name = $"{sourcePath}:{testName}"
            };
            using var compiler = Compiler.Compile(module, $"{sourcePath}:{testName}", stream);
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

