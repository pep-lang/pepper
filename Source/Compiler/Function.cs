using LLVMSharp;
using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper {
    internal abstract class Function : Value {
        public new FunctionType Type => (base.Type as FunctionType)!;
        public Type ReturnType => Type.ReturnType;
        public IEnumerable<Symbol> Parameters => Type.Parameters;
        public bool Varargs => Type.Varargs;

        public Function(string name, Type returnType, IEnumerable<Symbol> parameters, bool varargs = false)
            : base(
                  FunctionType.Create(returnType, parameters, varargs),
                  Context.Default.Module.AddFunction(name, FunctionType.Create(returnType, parameters, varargs)),
                  name) {
            Context.Default.Locals.AddFunction(this);
        }

        protected Function(string name, Type type)
            : base(type, LLVMValueRef.CreateConstNull(Types.Int8Ptr), name) {
            Context.Runtime.AddFunction(this);
        }

        public Value Call(IEnumerable<Value> args) {
            var coercedArgs = args.Select((arg, idx) => {
                var argType = Parameters.ElementAt(idx).Type;
                return argType.Coerce(arg);
            });
            var returnValue = Context.Default.Locals.Builder.BuildCall2(this, this, coercedArgs.Select(a => a.Address).ToArray(), Name);
            return new Value(ReturnType, returnValue, $"return {Name}");
        }

        public Value Call(params Value[] args) {
            return Call(args);
        }

        public override string ToString() {
            return $"{Type} {Name}";
        }

        public static implicit operator LLVMTypeRef(Function func) => func.Type;
        public static implicit operator LLVMValueRef(Function func) => func.Address;
    }

    internal class UserFunction : Function {
        public LLVMBuilderRef Builder;
        public LLVMBasicBlockRef Body;
        public uint NumLocals = 0;

        public UserFunction(string name, Type returnType, IEnumerable<Symbol> parameters)
            : base(name, returnType, parameters) {
            Context.Default.Locals.AddFunction(this);
            Body = Address.AppendBasicBlock("entry");
            Builder = Context.Default.Module.Context.CreateBuilder();
            Builder.PositionAtEnd(Body);
        }
    }

    internal class ExternFunction : Function {
        public ExternFunction(string name, Type returnType, IEnumerable<Symbol> parameters, bool varargs = false)
            : base(name, FunctionType.Create(returnType, parameters, varargs)) {
        }

        public ExternFunction(string name, Type returnType, params Symbol[] parameters)
            : this(name, returnType, parameters, false) {
        }

        public static void StaticInit() {
            _ = Puts;
        }

        private static ExternFunction Alias(ExternFunction sourceFunction, string name) {
            Context.Runtime.AliasFunction(sourceFunction, name);
            return sourceFunction;
        }

        internal void Rebind(LLVMValueRef funcRef) {
            Address = funcRef;
        }

        public static readonly ExternFunction Puts = new("puts", Types.Int32, new Symbol(Types.Int8Ptr, "str"));
        public static readonly ExternFunction Print = Alias(Puts, "print");
        public static readonly ExternFunction Malloc = new("malloc", Types.VoidPtr, new Symbol(Types.UInt64, "size"));
        public static readonly ExternFunction Free = new("free", Types.Void, new Symbol(Types.Int8Ptr, "ptr"));
        public static readonly ExternFunction Realloc = new("realloc", Types.VoidPtr, new Symbol(Types.Int8Ptr, "ptr"), new Symbol(Types.UInt64, "new_size"));
    }
}
