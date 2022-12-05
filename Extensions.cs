using LLVMSharp.Interop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper {
    public static class Extensions {
        public static (LLVMTypeRef functionType, LLVMValueRef function) AddFunction(this LLVMModuleRef module, LLVMTypeRef returnType, string name, LLVMTypeRef[] parameterTypes, Action<LLVMValueRef, LLVMBuilderRef> action) {
            var type = LLVMTypeRef.CreateFunction(returnType, parameterTypes);
            var func = module.AddFunction(name, type);
            var block = func.AppendBasicBlock(string.Empty);
            var builder = module.Context.CreateBuilder();
            builder.PositionAtEnd(block);
            action(func, builder);
            return (type, func);
        }
    }
}
