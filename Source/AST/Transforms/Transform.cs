
using System.Reflection;

namespace Pepper.AST.Transforms {

    public abstract class Transform : Pass {
        public int Priority { get; protected set; } = 0;

        static Transform() {
            var assembly = Assembly.GetExecutingAssembly();
            Transforms = assembly.RegisterSubclasses<Transform>().OrderByDescending(t => t.Priority).ToList();
        }

        private static readonly List<Transform> Transforms = new();

        public static void TransformPass(Compiler compiler, ParseTree ast) {
            foreach (var transform in Transforms) {
                transform.Evaluate(compiler, ast);
            }
        }
    }
}
