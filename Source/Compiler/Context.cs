
using LLVMSharp.Interop;
namespace Pepper;

internal class Context {
    private static Context? Current = null;

    static Context() {
        Types.StaticInit();
        ExternFunction.StaticInit();
    }

    // Runtime receives all static initialization of global functions and types, it is
    // never torn down or re-initialized. It it assumed that it will not change after
    // initialization
    public static readonly Scope Runtime = new();

    // Access to the scopes available globally
    public static Scope Globals => Current != null ? Current._Globals : Runtime;
    public static Scope Locals { 
        get { return Current!._Locals; }
        private set { Current!._Locals = value; }
    }
    public static LLVMModuleRef Module => Current!._Module;

    public static Context Create(string moduleName) {
        return new Context(moduleName);
    }

    public static void Destroy() {
        Current = null;
    }

    public static LLVMBuilderRef CreateBuilder() {
        var builder = Module.Context.CreateBuilder();
        return builder;
    }

    public static Scope PushScope(LLVMBuilderRef? builder) {
        return Locals = new Scope(Locals, builder);
    }

    public static Scope PopScope() {
        return Locals = Locals.Outer ?? Globals;
    }

    private LLVMModuleRef _Module;
    private Scope _Globals;
    private Scope _Locals;

    private Context(string moduleName) {
        Current = this;
        _Module = LLVMModuleRef.CreateWithName(moduleName);
        _Globals = new(Runtime);
        _Locals = Globals;
        InjectRuntime();
    }

    private static void InjectRuntime() {
        foreach (var pair in Runtime.GetFunctions().Where(f => f.Value is ExternFunction)) {
            string name = pair.Key;
            var function = (pair.Value as ExternFunction)!;
            if (name == function.Name) // no aliases
                function.Rebind(Module.AddFunction(name, function.Type));
        }
    }
}

