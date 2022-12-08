using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.Compiler {
    internal class Scope {
        public Scope? Outer { get; private set; } = null;
        private LLVMBuilderRef? ScopeBuilder = null;
        private readonly Dictionary<string, Type> Types = new();
        private readonly Dictionary<string, Function> Functions = new();
        private readonly Dictionary<string, Value> Variables = new();
        private readonly Stack<Value> Stack = new();
        public Function? ScopeReturnTarget = null;

        public LLVMBuilderRef Builder {
            get {
                return ScopeBuilder ?? Outer!.Builder;
            }
        }

        public Function ReturnTarget {
            get {
                return ScopeReturnTarget ?? Outer!.ReturnTarget;
            }
        }

        public Scope(Scope? outer = null, LLVMBuilderRef? builder = null) {
            Outer = outer;
            ScopeBuilder = builder;
        }

        internal Type AddType(Type NewType) {
            Types[NewType.Name] = NewType;
            return NewType;
        }

        internal Type AliasType(Type SourceType, string alias) {
            Types[alias] = SourceType;
            return SourceType;
        }

        public Type? GetType(string name) {
            if (Types.TryGetValue(name, out var type)) return type;
            return Outer?.GetType(name);
        }

        public T GetType<T>(string name) where T: Type {
            return (T)GetType(name)!;
        }

        public Function AddFunction(Function NewFunction) {
            Functions[NewFunction.Name] = NewFunction;
            ScopeReturnTarget = NewFunction;
            return NewFunction;
        }

        public Function AliasFunction(Function sourceFunction, string alias) {
            Functions[alias] = sourceFunction;
            return sourceFunction;
        }

        public Function? GetFunction(string name) {
            if (Functions.TryGetValue(name, out var function)) return function;
            return Outer?.GetFunction(name);
        }

        public Value AddVariable(Value NewVariable) {
            Variables[NewVariable.Name] = NewVariable;
            return NewVariable;
        }

        public Value? GetVariable(string name) {
            if (Variables.TryGetValue(name, out var variable)) return variable;
            return Outer?.GetVariable(name);
        }

        public bool Exists(string name) {
            return GetType(name) != null || GetFunction(name) != null || GetVariable(name) != null;
        }

        public Value PushStack(Value val) {
            Stack.Push(val);
            return val;
        }

        public Value PopStack() {
            return Stack.Pop();
        }

        public T PopStack<T>() where T: class {
            var top = PopStack();
            return top as T ?? throw new InternalCompilerException($"Tried to pop {typeof(T)} from stack, found {top.GetType()}");
        }
    }
}
