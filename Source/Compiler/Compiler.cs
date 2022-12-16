using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using Antlr4.Runtime.Tree;
using LLVMSharp.Interop;
using Pepper.AST;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Xml.Linq;

namespace Pepper {
    public class Compiler : IDisposable {

        static Context Context { get { return Context; } }

        public string SourcePath { get; private set; }
        public ICharStream SourceStream { get; private set; }
        public LLVMModuleRef Module => Context.Module;

        public static void CompileAndRun() {
            using var compiler = Compile(Options.Parse());
            var jit = new Executor();
            var exitCode = jit.Execute(Context.Module, "main");
            Log.Info($"main returned {exitCode}");
            Environment.Exit(exitCode);
        }

        public static Compiler Compile(Options options) {
            var inputStream = CharStreams.fromPath(options.Inputs.First());
            return Compile(options.ModuleName, options.Inputs.First(), inputStream);
        }

        public static Compiler Compile(string moduleName, string path, ICharStream inputStream) {
            var compiler = new Compiler(moduleName, path, inputStream);
            compiler.Compile();
            return compiler;
        }

        private Compiler(string moduleName, string sourcePath, ICharStream? inputStream = null) {
            Context.Create(moduleName);
            SourcePath = sourcePath;
            SourceStream = inputStream ?? CharStreams.fromPath(sourcePath);
        }

        ParseTree Parse() {
            var parser = new Parser(SourcePath, SourceStream);
            var ast = parser.Parse();
            return ast;
        }

        void Compile() {
            var ast = Parse();
            foreach (var globalSymbol in ast.TopLevelSymbols) {
                globalSymbol.Codegen();
            }

            Log.Info(Module.PrintToString());
            Module.Verify(LLVMVerifierFailureAction.LLVMPrintMessageAction);
            //Module.WriteBitcodeToFile(Path.ChangeExtension(SourcePath, "bc"));
        }

        public void Dispose() {
            GC.SuppressFinalize(this);
            Context.Destroy();
        }
    }
}
