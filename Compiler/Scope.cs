using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.Compiler {
    internal class Scope {
        public Scope? Outer { get; private set; } = null;
        public Dictionary<string, Function> Functions = new Dictionary<string, Function>();
        public Dictionary<string, Variable> Variables = new Dictionary<string, Variable>();

        public Scope(Scope? outer = null) {
            Outer = outer;
        }

        public Function? GetFunction(string name) {
            if (Functions.TryGetValue(name, out var function)) {
                return function;
            }
            return Outer?.GetFunction(name);
        }

        public Variable? GetVariable(string name) {
            if (Variables.TryGetValue(name, out var variable)) { 
                return variable; 
            }
            return Outer?.GetVariable(name);
        }

        public bool Exists(string name) {
            return GetFunction(name) != null || GetVariable(name) != null;
        }
    }
}
