
using System.Reflection;


namespace Pepper.AST.Validation {
    using Error = Compiler.Error;
    using Warning = Compiler.Warning;
    using Message = Compiler.Message;

    public abstract class Validator : Pass {
        public int Priority { get; protected set; } = 0;

        static Validator() {
            var assembly = Assembly.GetExecutingAssembly();
            Validators = assembly.RegisterSubclasses<Validator>().OrderByDescending(t => t.Priority).ToList();
        }

        private static readonly List<Validator> Validators = new();

        public static void ValidationPass(Compiler compiler, ParseTree ast) {
            foreach (var Validator in Validators) {
                Validator.Evaluate(compiler, ast);
            }
        }
    }
}
