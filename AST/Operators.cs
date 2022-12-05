using LLVMSharp;
using LLVMSharp.Interop;
using Pepper.Compiler;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.AST;
internal class Add : Node {
    public LLVMValueRef Left { get; private set; }
    public LLVMValueRef Right { get; private set; }
    
    Add(Context ctx, LLVMValueRef lhs, LLVMValueRef rhs) : base(ctx) {
        Left = lhs;
        Right = rhs;
    }
    public override LLVMValueRef Emit() {
        return Ctx.Builder.BuildAdd(Left, Right);
    }
}

