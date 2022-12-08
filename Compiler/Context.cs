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

    // One context per thread, it's not possible for there to be multiple any other way
    private static readonly ThreadLocal<Context> ThreadContext = new(() => new Context());
    public static Context Default {
        get {
            if (!ThreadContext.IsValueCreated) {
                ThreadContext.Value!.RegisterGlobals();
            }
            return ThreadContext.Value!;
        }
    }

    public LLVMModuleRef Module { get; private set; }

    public Options Options { get; private set; }

    public Scope Globals { get; private set; }
    public Scope Locals { get; private set; }

    public Context() {
        Options = Options.Parse();
        Module = LLVMModuleRef.CreateWithName(Options.ModuleName);
        Globals = new(null, Module.Context.CreateBuilder());
        Locals = Globals;
    }

    void RegisterGlobals() {
        IntegralType.StaticInit();
        ExternFunction.StaticInit();
        //Globals.AddFunction(new ExternFunction("printf", IntegralType.I32, new Variable[] { 
        //    new Variable("fmt", IntegralType.I8),
        //}, true));
    }

    public Scope PushScope(LLVMBuilderRef? builder) {
        return Locals = new Scope(Locals, builder);
    }

    public Scope PopScope() {
        return Locals = Locals.Outer ?? Globals;
    }
}

