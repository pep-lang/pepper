using Antlr4.Runtime;
using LLVMSharp.Interop;
using Pepper.AST;
using Pepper.AST.Transforms;
using Pepper.AST.Validation;
using Pepper.Codegen;

namespace Pepper {
    public class Message {
        public String What { get; private set; }
        public SourceLocation Where { get; private set; }

        public Message(string what, SourceLocation where) {
            What = what;
            Where = where;
        }
    }

    public class Warning : Message {
        public Warning(string what, SourceLocation where) : base(what, where) { }
    }

    public class Error : Message {
        public Error(string what, SourceLocation where) : base(what, where) { }
    }

    public class Compiler {

        public string SourcePath { get; private set; }
        public ICharStream SourceStream { get; private set; }

        static Compiler? Current;
        public List<Message> AllMessages { get; private set; } = new();
        public List<Error> Errors { get; private set; } = new();
        public List<Warning> Warnings { get; private set; } = new();

        public static void CompileAndRun() {
            var compiler = Compile(Options.Parse());
            var jit = new Executor();
            var exitCode = jit.Execute(Context.Module, "main");
            Log.Info($"main returned {exitCode}");
            Environment.Exit(exitCode);
        }

        public static LLVMModuleRef Compile(Options options) {
            var inputStream = CharStreams.fromPath(options.Inputs.First());
            return Compile(options.ModuleName, options.Inputs.First(), inputStream);
        }

        public static LLVMModuleRef Compile(string moduleName, string path, ICharStream inputStream) {
            Action<Exception, SourceLocation?> reportException = (ex, source) => {
                source ??= SourceLocation.Current;
                Log.Error($"{source.ToString()}: {ex.Message}\n    during {SourceLocation.Context}");
            };
            try {
                var compiler = new Compiler(moduleName, path, inputStream);
                return compiler.Compile();
            } catch (Pepper.CompilerException err) {
                var source = err.SourceLocation ?? SourceLocation.Current;
                Log.Error($"{err.Message} during {SourceLocation.Context}");
                Environment.Exit(-1);
            }
            return null;
        }

        private Compiler(string moduleName, string sourcePath, ICharStream? inputStream = null) {
            Current = this;
            Context.Create(moduleName);
            SourcePath = sourcePath;
            SourceStream = inputStream ?? CharStreams.fromPath(sourcePath);
        }

        ParseTree Parse() {

            var parser = new Parser(SourcePath, SourceStream);
            var ast = parser.Parse();
            return ast;
        }

        LLVMModuleRef Compile() {
            SourceLocation.Context = "Parsing";
            var ast = Parse();

            SourceLocation.Context = "Validation";
            Validator.ValidationPass(this, ast);

            SourceLocation.Context = "Transform";
            Transform.TransformPass(this, ast);

            SourceLocation.Context = "Code generation";
            var codegen = new IRCodegen(this, ast);
            var module = codegen.Emit();

            Log.Info(module.PrintToString());
            SourceLocation.Context = "Validation";
            module.Verify(LLVMVerifierFailureAction.LLVMPrintMessageAction);
            //Module.WriteBitcodeToFile(Path.ChangeExtension(SourcePath, "bc"));
            return module;
        }

        public static void Report<M>(string what, SourceLocation? where = null, object? _ = null) where M : Message {
            Current!.Report<M>(what, where);
        }

        public void Report<M>(string what, SourceLocation? where = null) where M : Message {
            var m = (M)Activator.CreateInstance(typeof(M), what, where)!;
            Current!.Report(m);
        }

        public void Report(Message msg) => AllMessages.Add(msg);
        public void Report(Warning warning) {
            AllMessages.Add(warning); 
            Warnings.Add(warning); 
        }

        public void Report(Error error) {
            AllMessages.Add(error);
            Errors.Add(error);
        }
    }
}
