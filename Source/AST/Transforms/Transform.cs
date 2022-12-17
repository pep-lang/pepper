using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.AST.Transforms {
    public abstract class Transform : Pass {
        public int Priority { get; protected set; } = 0;

        static Transform() {
            var assembly = Assembly.GetExecutingAssembly();
            Transforms = assembly.RegisterSubclasses<Transform>().OrderByDescending(t => t.Priority).ToList();
        }

        private static readonly List<Transform> Transforms = new();

        public static void TransformPass(ParseTree ast) {
            foreach (var transform in Transforms) {
                transform.Evaluate(ast);
            }
        }
    }
}
