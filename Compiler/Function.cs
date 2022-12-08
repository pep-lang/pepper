using LLVMSharp;
using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.Compiler {
    internal abstract class Function : Value {
        public Type ReturnType = IntegralType.Void;
        public IEnumerable<Value> Parameters { get; private set; }
        public bool Varargs = false;

        public Function(string name, Type returnType, IEnumerable<Value> parameters, bool varargs = false) 
            : base(FunctionType.Create(returnType, parameters), name) {
            ReturnType = returnType;
            Parameters = parameters;
            Varargs = varargs;

            Context.Default.Locals.AddFunction(this);
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

        public UserFunction(string name, Type returnType, IEnumerable<Value> parameters) 
            : base(name, returnType, parameters) {
            Address = Context.Default.Module.AddFunction(name, Type.Ref);
            Body = Address.AppendBasicBlock(string.Empty);
            Builder = Context.Default.Module.Context.CreateBuilder();
            Builder.PositionAtEnd(Body);
        }
    }

    internal class ExternFunction : Function {
        public ExternFunction(string name, Type returnType, IEnumerable<Value> parameters, bool varargs = false)
            : base(name, returnType, parameters, varargs) {
            Address = Context.Default.Module.AddFunction(name, Type);
        }

        public ExternFunction(string name, Type returnType, params Value[] parameters) 
            : this(name, returnType, parameters, false) {
        }

        public static void StaticInit() {
            
            Context.Default.Locals.AliasFunction(Puts, "print");
        }

        public static readonly ExternFunction Puts = new("puts", IntegralType.Int32, new Value(IntegralType.Int8Ptr, "str"));
    }
}
