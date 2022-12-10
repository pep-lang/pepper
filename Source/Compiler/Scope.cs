using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper {
    internal class BinaryOp {
        public Func<LLVMValueRef, LLVMValueRef, string, LLVMValueRef> Op;
        public string Name;

        public BinaryOp(Func<LLVMValueRef, LLVMValueRef, string, LLVMValueRef> op, string name) {
            Op = op;
            Name = name;
        }

        public override string ToString() => Name;
    }

    internal class StackEntry {
        Value? StoredValue = null;
        public Value Value { 
            get { return StoredValue!; }
            private set { StoredValue = value; }
        }
        public StackEntry(Value value) {
            Value = value;
        }
        public static implicit operator StackEntry(Value value) => new(value);
        public static implicit operator Value(StackEntry entry) => entry.Value;

        BinaryOp? StoredBinaryOp = null;
        public BinaryOp BinaryOp {
            get { return StoredBinaryOp!; }
            private set { StoredBinaryOp = value; }
        }
        public StackEntry(BinaryOp op) {
            BinaryOp = op;
        }
        public static implicit operator StackEntry(BinaryOp op) => new(op);
        public static implicit operator BinaryOp(StackEntry entry) => entry.BinaryOp;
        
        public T? As<T>() where T : class {
            var type = typeof(T);
            if (type == typeof(Value)) {
                return StoredValue as T;
            } else if (type == typeof(BinaryOp)) {
                return StoredBinaryOp as T;
            }
            return null;
        }

        public override string ToString() {
            if (StoredValue != null) return StoredValue.ToString();
            if (StoredBinaryOp != null) return StoredBinaryOp.ToString();
            return string.Empty;
        }
    }

    internal class Scope {
        public Scope? Outer { get; private set; } = null;
        private LLVMBuilderRef? ScopeBuilder = null;
        private readonly Dictionary<string, Type> Types = new();
        private readonly Dictionary<string, Function> Functions = new();
        private readonly Dictionary<string, Value> Variables = new();
        private readonly Stack<StackEntry> Stack = new();
        public UserFunction? ScopeReturnTarget = null;

        public LLVMBuilderRef Builder {
            get {
                return ScopeBuilder ?? Outer!.Builder;
            }
        }

        public LLVMBuilderRef FunctionRegisters {
            get {
                var func = (ReturnTarget as UserFunction)!;
                var funcStart = func.Body.FirstInstruction;
                if (funcStart.Handle != 0) {
                    // skip past existing locals
                    for (int localIdx = 0; localIdx < func.NumLocals; ++localIdx)
                        funcStart = funcStart.NextInstruction;
                    var tempBuilder = Context.Default.Module.Context.CreateBuilder();
                    tempBuilder.PositionBefore(funcStart);
                    return tempBuilder;
                }
                ++func.NumLocals;
                return func.Builder;
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

        public Function AddFunction(Function newFunction) {
            if (newFunction is UserFunction userFunction) {
                ScopeReturnTarget = userFunction;
            }
            Functions[newFunction.Name] = newFunction;
            return newFunction;
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

        public StackEntry PushStack(StackEntry val) {
            Stack.Push(val);
            Log.Info($"PUSH {val}");
            return val;
        }

        public StackEntry PopStack() {
            var val = Stack.Pop();
            Log.Info($"POP  {val}");
            return val;
        }

        public T PopStack<T>() where T: class {
            var top = PopStack();
            return top.As<T>() ?? throw new InternalCompilerException($"Tried to pop {typeof(T)} from stack, found {top}");
        }

        public StackEntry StackTop() {
            return Stack.First();
        }

        public T? StackTop<T>() where T : class {
            var top = StackTop();
            return top.As<T>();
        }
    }
}
