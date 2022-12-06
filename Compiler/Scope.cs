using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.Compiler {
    internal class Scope {
        public Scope? Outer { get; private set; } = null;
        private Dictionary<string, Type> Types = new();
        private Dictionary<string, Function> Functions = new();
        private Dictionary<string, Variable> Variables = new();

        public Scope(Scope? outer = null) {
            Outer = outer;
        }

        internal Type AddType(Type NewType) {
            Types[NewType.Name] = NewType;
            return NewType;
        }

        public Type? GetType(string name) {
            if (Types.TryGetValue(name, out var type)) return type;
            return Outer?.GetType(name);
        }

        public Function AddFunction(Function NewFunction) {
            Functions[NewFunction.Name] = NewFunction;
            return NewFunction;
        }

        public Function? GetFunction(string name) {
            if (Functions.TryGetValue(name, out var function)) return function;
            return Outer?.GetFunction(name);
        }

        public Variable AddVariable(Variable NewVariable) {
            Variables[NewVariable.Name] = NewVariable;
            return NewVariable;
        }

        public Variable? GetVariable(string name) {
            if (Variables.TryGetValue(name, out var variable)) return variable;
            return Outer?.GetVariable(name);
        }

        public bool Exists(string name) {
            return GetType(name) != null || GetFunction(name) != null || GetVariable(name) != null;
        }
    }
}
