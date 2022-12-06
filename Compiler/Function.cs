using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.Compiler {
    internal class Function {
        public LLVMTypeRef TypeRef;
        public LLVMValueRef Ref;
        public string Name { get; set; } = String.Empty;
        public Type ReturnType = IntegralType.Void;
        public IEnumerable<Variable> Parameters { get; set; } = new List<Variable>();
        public LLVMBuilderRef Builder;
        public LLVMBasicBlockRef Body;

        public Function(string name, Type returnType, IEnumerable<Variable> parameters) {
            Name = name;
            ReturnType = returnType;
            Parameters = parameters;

            TypeRef = LLVMTypeRef.CreateFunction(returnType, parameters.Select(p => p.Type.Ref).ToArray());
            Ref = Context.Default.Module.AddFunction(name, TypeRef);
            Body = Ref.AppendBasicBlock(string.Empty);
            Builder = Context.Default.Module.Context.CreateBuilder();
            Builder.PositionAtEnd(Body);

            Context.Default.Locals.AddFunction(this);
        }

        public static implicit operator LLVMTypeRef(Function func) => func.TypeRef;
        public static implicit operator LLVMValueRef(Function func) => func.Ref;
    }
}
