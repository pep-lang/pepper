
using LLVMSharp.Interop;

namespace Pepper.Codegen {
    public abstract class Function : Value {
        public new FunctionType Type => (base.Type as FunctionType)!;
        public Type ReturnType => Type.ReturnType;
        public IEnumerable<Symbol> Parameters => Type.Parameters;
        public bool Varargs => Type.Varargs;

        public class Parameter : Symbol {
            public Value? Default;

            public Parameter(Symbol param)
                : this(param.Type, param.Name) {
            }

            public Parameter(Type type, string name, Value? defaultValue = null)
                : base(type, name) {
                Default = defaultValue;
            }
        }

        public Function(string name, Type returnType, IEnumerable<Symbol> parameters, bool varargs = false)
            : base(
                  FunctionType.Create(returnType, parameters, varargs),
                  Context.Module.AddFunction(name, FunctionType.Create(returnType, parameters, varargs)),
                  name) {
        }

        protected Function(string name, Type type)
            : base(type, LLVMValueRef.CreateConstNull(Types.Int8Ptr), name) {
            // function reference is empty, will be re-bound per-module, see Context.InjectRuntime
        }

        public Value Call(IEnumerable<Value> args) {
            var coercedArgs = args.Select((arg, idx) => {
                var argType = Parameters.ElementAt(idx).Type;
                return argType.Coerce(arg.Load());
            });
            var returnValue = Context.Locals.Builder.BuildCall2(this, this, coercedArgs.Select(a => a.Load().Address).ToArray(), ReturnType != Types.Void ? Name : "");
            return New(ReturnType, returnValue, $"return {Name}");
        }

        public Value Call(params Value[] args) {
            return Call(args.Cast<Value>());
        }

        public override string ToString() {
            return $"{Type} {Name}";
        }

        public static implicit operator LLVMTypeRef(Function func) => func.Type;
        public static implicit operator LLVMValueRef(Function func) => func.Address;
    }

    public abstract class UserFunction : Function {
        public LLVMBuilderRef Builder;
        public LLVMBasicBlockRef Body;
        public uint NumLocals = 0;

        public UserFunction(string name, Type returnType, IEnumerable<Parameter> parameters)
            : base(name, returnType, parameters) {
            Context.Locals.AddFunction(this);
            Body = Address.AppendBasicBlock("entry");
            Builder = Context.CreateBuilder();
            Builder.PositionAtEnd(Body);
            // TODO: insert default values for params
        }
    }

    public class FreeFunction : UserFunction {
        public FreeFunction(string name, Type returnType, IEnumerable<Parameter>? parameters = null)
            : base(name, returnType, parameters?.ToList() ?? Enumerable.Empty<Parameter>()) { }
    }

    public class Method : UserFunction {
        public Method(string name, string mangledName, Type returnType, IEnumerable<Parameter> parameters)
            : base(mangledName, returnType, parameters) {
            Name = name;
        }
    }

    public class ExternFunction : Function {
        public ExternFunction(string name, Type returnType, IEnumerable<Symbol> parameters, bool varargs = false)
            : base(name, FunctionType.Create(returnType, parameters, varargs)) {
            Runtime.Environment.AddFunction(this);
        }

        public ExternFunction(string name, Type returnType, params Symbol[] parameters)
            : this(name, returnType, parameters, false) {
        }

        public static void StaticInit() {
            _ = Puts;
        }

        private static ExternFunction Alias(ExternFunction sourceFunction, string name) {
            Runtime.Environment.AliasFunction(sourceFunction, name);
            return sourceFunction;
        }

        internal void Rebind(LLVMValueRef funcRef) {
            Address = funcRef;
        }

        // These functions will end up in the runtime. All other externs declared by the user will go into
        // globals, as they will be created within a scope
        public static readonly ExternFunction Puts = new("puts", Types.Int32, new Symbol(Types.Int8Ptr, "str"));
        public static readonly ExternFunction Print = Alias(Puts, "print");
        public static readonly ExternFunction Malloc = new("malloc", Types.VoidPtr, new Symbol(Types.UInt64, "size"));
        public static readonly ExternFunction Free = new("free", Types.Void, new Symbol(Types.Int8Ptr, "ptr"));
        public static readonly ExternFunction Realloc = new("realloc", Types.VoidPtr, new Symbol(Types.Int8Ptr, "ptr"), new Symbol(Types.UInt64, "new_size"));
    }

    public static class SymbolExtension {
        public static IEnumerable<Symbol> ToSymbols(this IEnumerable<AST.Symbol> symbols) {
            return symbols.Select(s => new Symbol(s.Type, s.Name));
        }
    }
}
