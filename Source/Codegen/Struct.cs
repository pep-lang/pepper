
using LLVMSharp.Interop;
using System;
using System.Runtime.CompilerServices;
using System.Xml.Linq;

namespace Pepper.Codegen {
    // A struct's value is its TypeInfo*
    public class Struct : Value {
        public LLVMValueRef TypeInfo { get; private set; }
        public LLVMValueRef VTable { get; private set; }
        public LLVMValueRef Size => Type.Ref.SizeOf;
        public OrderedMap<string, Symbol> Fields;
        public FreeFunction Initializer => Methods["__init"];
        public FreeFunction Constructor => Methods["__ctor"];
        public FreeFunction Destructor => Methods["__dtor"];
        public OrderedMap<string, FreeFunction> Methods = new();

        // this is the type info that is stored per struct globally
        public static class StaticTypeInfo {
            public static readonly Symbol[] TemplateFields = new Symbol[]{
                new Symbol(Types.VoidPtr, "__vtable"),
                new Symbol(Types.ConstantString, "__name"),
            };

            public static LLVMValueRef New(Struct st) {
                var elements = new LLVMValueRef[] {
                    st.VTable,
                    new ConstantString(st.Name),
                };
                var types = elements.Select(e => e.TypeOf).ToArray();

                var typeInfo = Context.Module.Context.CreateNamedStruct($"${st.Name}$typeinfo");
                typeInfo.StructSetBody(types, true);
                var global = Context.Module.AddGlobal(typeInfo, $"{st.Name}.typeinfo");
                global.Initializer = LLVMValueRef.CreateConstStruct(elements, true);
                return global;
            }

            public static LLVMTypeRef Type(LLVMTypeRef vtableType) {
                var elements = TemplateFields
                    .Where(f => f.Name != "__vtable") // replace vtable with its real type
                    .Select(f => f.Type.Ref)
                    .Prepend(vtableType).ToArray();
                return LLVMTypeRef.CreateStruct(elements, true);
            }
        }

        public static class Header {
            static readonly Symbol[] TemplateFields = new[] {
                new Symbol(LLVMTypeRef.CreatePointer(Types.VoidPtr, 0), "__typeinfo"),
                new Symbol(Types.UInt32, "__refcount"),
            };

            public static Symbol[] Fields(LLVMTypeRef vtableType) {
                return TemplateFields
                    .Where(f => f.Name != "__typeinfo") // replace typeinfo with its real type
                    .Prepend(new Symbol(StaticTypeInfo.Type(vtableType), "__typeinfo"))
                    .ToArray();
            }
        }

        public static StructType ToType(string name, IEnumerable<Symbol> fields, IEnumerable<Function> methods) {
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
            var namedType = Context.Module.Context.CreateNamedStruct($"${name}");
            namedType.StructSetBody(elements, false);
            var structType = new StructType(name, namedType, fields.ToList(), methods.ToList());
            Context.Locals.AddType(structType);
            Context.Locals.AddType(structType.Pointer());
            return structType;
        }

        public static LLVMValueRef StructVTable(Struct st) {
            var entries = st.Methods.Values.Select(m => m.Address).ToArray();
            var types = entries.Select(e => e.TypeOf).ToArray();
            var vtableType = Context.Module.Context.CreateNamedStruct($"${st.Name}$vtable");
            vtableType.StructSetBody(types, true);
            var vtable = LLVMValueRef.CreateConstStruct(entries, true);
            var global = Context.Module.AddGlobal(vtableType, $"{st.Name}.vtable");
            global.Initializer = vtable;
            return global;
        }

        public static LLVMTypeRef VTableType(IEnumerable<FreeFunction> methods) {
            var entries = methods.Select(m => m.Address.TypeOf).ToArray();
            return LLVMTypeRef.CreateStruct(entries, true);
        }

        public Struct(PointerType type, string name, List<Symbol> fields, OrderedMap<string, FreeFunction> methods)
            : base(type, PointerType.Null, name) {
            Fields = fields.ToOrderedMap(f => f.Name);
            Methods = methods;

            // build vtable
            VTable = StructVTable(this);

            // build typeinfo
            TypeInfo = StaticTypeInfo.New(this);

            // update the value to point to the type info for this struct
            Replace(TypeInfo);
        }

        public override string ToString() {
            return Name;
        }
    }
}
