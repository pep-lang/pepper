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

        public void Call(LLVMBuilderRef builder, IEnumerable<Value> args) {
            builder.BuildCall2(this, this, args.Select(a => a.Ref).ToArray(), Name);
        }

        public void Call(LLVMBuilderRef builder, params Value[] args) {
            Call(builder, args);
        }

        public static implicit operator LLVMTypeRef(Function func) => func.Type;
        public static implicit operator LLVMValueRef(Function func) => func.Ref;
    }

    internal class UserFunction : Function {
        public LLVMBuilderRef Builder;
        public LLVMBasicBlockRef Body;

        public UserFunction(string name, Type returnType, IEnumerable<Value> parameters) 
            : base(name, returnType, parameters) {
            Ref = Context.Default.Module.AddFunction(name, Type.Ref);
            Body = Ref.AppendBasicBlock(string.Empty);
            Builder = Context.Default.Module.Context.CreateBuilder();
            Builder.PositionAtEnd(Body);
        }
    }

    internal class ExternFunction : Function {
        public ExternFunction(string name, Type returnType, IEnumerable<Value> parameters, bool varargs = false)
            : base(name, returnType, parameters, varargs) {
            Ref = Context.Default.Module.AddFunction(name, Type);
        }

        public ExternFunction(string name, Type returnType, params Value[] parameters) : base(name, returnType, parameters) { }

        public static void StaticInit() {
            
        }

        public static readonly ExternFunction Puts = new("puts", IntegralType.I32, new Value(IntegralType.I8.Pointer()));
    }
}
