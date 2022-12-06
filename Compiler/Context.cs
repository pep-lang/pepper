using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

using LLVMSharp;
using LLVMSharp.Interop;
using NUnit.Framework;

namespace Pepper.Compiler;

internal class Context {
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int IntMain0();
    public LLVMContextRef Ctx { get; private set; }
    public LLVMBuilderRef Builder { get; private set; }
    public LLVMModuleRef Module { get; private set; }

    public Options Options { get; private set; }

    public Context() {
        Options = Options.Parse();

        Module = LLVMModuleRef.CreateWithName(Options.ModuleName);
        Ctx = Module.Context;
        Builder = Ctx.CreateBuilder();
        
        (_, var main) = Module.AddFunction(LLVMTypeRef.Int32, "main", Array.Empty<LLVMTypeRef>(), (func, builder) => {
            builder.BuildRet(LLVMValueRef.CreateConstInt(LLVMTypeRef.Int32, 0));
        });
        
        Module.Verify(LLVMVerifierFailureAction.LLVMPrintMessageAction);

        _ = LLVM.InitializeNativeTarget();
        _ = LLVM.InitializeNativeAsmParser();
        _ = LLVM.InitializeNativeAsmPrinter();

        var engine = Module.CreateMCJITCompiler();
        var entry = engine.GetPointerToGlobal<IntMain0>(main);
        var result = entry();
        Assert.AreEqual(0, result);
    }
}