using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.AST.Validation {
    public abstract class Validator : Pass {
        public int Priority { get; protected set; } = 0;

        static Validator() {
            var assembly = Assembly.GetExecutingAssembly();
            Validators = assembly.RegisterSubclasses<Validator>().OrderByDescending(t => t.Priority).ToList();
        }

        private static readonly List<Validator> Validators = new();

        public static void ValidationPass(ParseTree ast) {
            foreach (var Validator in Validators) {
                Validator.Evaluate(ast);
            }
        }
    }
}
