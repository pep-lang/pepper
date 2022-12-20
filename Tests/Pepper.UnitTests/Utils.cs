using Antlr4.Runtime;
using System;
using System.Runtime.CompilerServices;

namespace Pepper.UnitTests {
    public static class Utils {
        public static void CompileAndRun(string moduleName,
            string source, int expectedResult = 0,
            [CallerFilePath] string sourcePath = "",
            [CallerMemberName] string testName = "") {
            var stream = new CodePointCharStream(source) {
                name = $"{sourcePath}:{testName}"
            };
            var module = Compiler.Compile(moduleName, $"{sourcePath}:{testName}", stream);
            var jit = new Executor();
            int result = jit.Interpret(module, "main");
            try {
                Log.Info($"main returned {result}");
                Assert.That(result, Is.EqualTo(expectedResult));
            } catch (Exception ex) {
                Log.Error(ex.Message);
            }
        }
    }
}

