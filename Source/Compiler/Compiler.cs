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

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int IntMain0();

        static Context Context { get { return Context.Default; } }

        public string SourcePath { get; private set; }
        public ICharStream SourceStream { get; private set; }

        public static void CompileAndRun() {
            using var compiler = Compile(Options.Parse());
            var exitCode = compiler.JIT("main");
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

        public int JIT(string entryFunction) {
            _ = LLVM.InitializeNativeTarget();
            _ = LLVM.InitializeNativeAsmParser();
            _ = LLVM.InitializeNativeAsmPrinter();

            try {
                using var engine = Context.Module.CreateMCJITCompiler();
                var entryAddress = Context.Globals.GetFunction(entryFunction)!.Address;
                var entry = engine.GetPointerToGlobal<IntMain0>(entryAddress);
                if (entry == null) {
                    throw new CompileException($"Entry function {entryFunction} not found");
                }
                var result = entry();
                return result;
            } catch (Exception ex) {
                Log.Error($"JIT execution error: {ex}");
            }
            return -1;
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

            Log.Info(Context.Module.PrintToString());
            Context.Module.Verify(LLVMVerifierFailureAction.LLVMPrintMessageAction);
        }

        public void Dispose() {
            GC.SuppressFinalize(this);
            Context.Destroy();
        }
    }
}
