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

    static Context() {
        Types.StaticInit();
        ExternFunction.StaticInit();
    }

    public static Scope Runtime = new();
    public Scope Globals { get; private set; }
    public Scope Locals { get; private set; }

    public static Context Create(string moduleName) {
        return ThreadContext = new Context(moduleName);
    }

    public static void Destroy() {
        ThreadContext = null;
    }

    private Context(string moduleName) {
        Module = LLVMModuleRef.CreateWithName(moduleName);
        Globals = new(Runtime, Module.Context.CreateBuilder());
        Locals = Globals;
        InjectRuntime();
    }

    private void InjectRuntime() {
        foreach (var pair in Runtime.GetFunctions().Where(f => f.Value is ExternFunction)) {
            string name = pair.Key;
            var function = (pair.Value as ExternFunction)!;
            if (name == function.Name) // no aliases
                function.Rebind(Module.AddFunction(name, function.Type));
        }
    }

    public Scope PushScope(LLVMBuilderRef? builder) {
        return Locals = new Scope(Locals, builder);
    }

    public Scope PopScope() {
        return Locals = Locals.Outer ?? Globals;
    }
}

