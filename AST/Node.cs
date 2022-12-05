using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using LLVMSharp.Interop;
using Pepper.Compiler;

namespace Pepper.AST
{
    internal abstract class Node
    {
        protected Context Ctx;
        public Node(Context ctx) {
            Ctx = ctx;
        }

        public abstract LLVMValueRef Emit();

        //public abstract Type IrType { get; }

    }
}
