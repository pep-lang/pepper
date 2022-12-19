
using LLVMSharp.Interop;
using System;
using System.Xml.Linq;

namespace Pepper.Codegen {
    // A struct's value is its TypeInfo*
    public class Struct : Value {
        public List<Symbol> Fields;
        public FreeFunction Initializer => Methods["__init"];
        public FreeFunction Constructor => Methods["__ctor"];
        public FreeFunction Destructor => Methods["__dtor"];
        public Dictionary<string, FreeFunction> Methods = new();

        static StructType Create(string name, List<Symbol> fields) {
            try {
                var st = Context.Locals.GetType<StructType>(name);
                if (st != null)
                    return st;
            } catch {
                var st = Runtime.Environment.GetType<StructType>(name);
                if (st != null)
                    return st;
            }
            var elements = fields.Select(f => f.Type.Ref).ToArray();
            return new StructType(name, LLVMTypeRef.CreateStruct(elements, false));
        }

        // this is the type info that is stored per struct globally
        public static class TypeInfo {
            public static readonly Symbol[] Fields = new Symbol[]{
                new Symbol(Types.VoidPtr, "__vtable"),
                new Symbol(Types.UInt32, "__refcount"),
                new Symbol(Types.ConstantString, "__name"),
            };

            public static LLVMValueRef[] New(LLVMValueRef vtable, string name) {
                return new LLVMValueRef[] {
                    vtable,
                    new ConstantInt(0),
                    new ConstantString(name),
                };
            }
        }



        static LLVMValueRef StructTypeInfo(Struct st) {
            return LLVMValueRef.CreateConstStruct(TypeInfo.New(StructVTable(st), st.Name), true);
        }

        static LLVMValueRef StructVTable(Struct st) {
            var type = Create(st.Name, st.Fields);
            var entries = st.Methods.Values.Select(m => m.Address).ToArray();
            return LLVMValueRef.CreateConstStruct(entries, true);
        }

        public Struct(string name, List<Symbol> fields, List<Function> methods)
            : base(Create(name, fields), new ConstantPointer(0), name) {
            Fields = fields;

            Methods.Add("__ctor", new FreeFunction(Mangle.Method(name, "__ctor"), Type, Enumerable.Empty<Function.Parameter>()));
            Methods.Add("__dtor", new FreeFunction(Mangle.Method(name, "__dtor"), Type, new Function.Parameter[] { new(Type.Pointer(), "p") }));
            // Map names to mangled free functions
            methods.Cast<Method>()
                .Select(m => new Method(m.Name, m.ReturnType, m.Parameters.Cast<Function.Parameter>()))
                .ForAll(method => {
                    var func = new FreeFunction(
                        Mangle.Method(Name, method.Name),
                        method.ReturnType,
                        method.Parameters.Cast<Function.Parameter>().Prepend(new Function.Parameter(Type, "this"))) {
                        Body = method.Body
                    };
                    Methods.Add(method.Name, func);
                }
            );
            // update the value to point to the type info for this struct
            Replace(StructTypeInfo(this));
        }

        public override string ToString() {
            return Name;
        }
    }
}
