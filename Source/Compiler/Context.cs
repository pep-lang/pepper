using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

using LLVMSharp;
using LLVMSharp.Interop;
namespace Pepper;

internal class Context {

    // One context per thread, it's not possible for there to be multiple any other way
    //private static readonly ThreadLocal<Context> ThreadContext = new(() => new Context());
    private static Context? ThreadContext = null;
    public static Context Default {
        get {
            return ThreadContext!;
        }
    }

    public LLVMModuleRef Module { get; private set; }

    public Scope Globals { get; private set; }
    public Scope Locals { get; private set; }

    public Context(string moduleName) {
        ThreadContext = this;
        Module = LLVMModuleRef.CreateWithName(moduleName);
        Globals = new(null, Module.Context.CreateBuilder());
        Locals = Globals;
        RegisterGlobals();
    }

    void RegisterGlobals() {
        NativeType.StaticInit();
        ExternFunction.StaticInit();
    }

    public Scope PushScope(LLVMBuilderRef? builder) {
        return Locals = new Scope(Locals, builder);
    }

    public Scope PopScope() {
        return Locals = Locals.Outer ?? Globals;
    }
}

