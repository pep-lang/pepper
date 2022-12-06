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
    
    public LLVMContextRef Ctx { get; private set; }
    public LLVMBuilderRef Builder { get; private set; }
    public LLVMModuleRef Module { get; private set; }

    public Options Options { get; private set; }

    public Context() {
        Options = Options.Parse();

        Module = LLVMModuleRef.CreateWithName(Options.ModuleName);
        Ctx = Module.Context;
        Builder = Ctx.CreateBuilder();
    }
}