using LLVMSharp.Interop;
using Pepper.Codegen;
namespace Pepper {
    public class StructType : Type {
        public OrderedMap<string, Symbol> Fields = new(); 
        public LLVMTypeRef[] Entries => Fields.Values.Select(f => f.Type.Ref).ToArray();
       

        // this is the type info that is stored per struct globally
        //public static class StaticTypeInfo {
        //    public static LLVMValueRef TypeInfo(string name, LLVMValueRef vtable) {
        //        var values = new LLVMValueRef[] {
        //            vtable,
        //            new ConstantString(name),
        //        };
        //        var types = values.Select(e => e.TypeOf).ToArray();
        //        var fields = new[] {
        //            new Symbol(vtable.TypeOf, "__vtable"),
        //            new Symbol(Types.ConstantString, "__name"),
        //        };

        //        var typeInfo = Create($"{name}.__typeinfo", fields);
        //        var global = Context.Module.AddGlobal(typeInfo, $"{name}.typeinfo");
        //        global.Initializer = LLVMValueRef.CreateConstStruct(values, true);
        //        return global;
        //    }

        //    public static LLVMValueRef VTable(string name, IEnumerable<Function> methods) {
        //        var values = methods.Select(m => m.Address).ToArray();
        //        var fields = methods.Select(m => new Symbol(m.Type, m.Name));

        //        var vtableType = Create($"{name}.__vtable", fields);
        //        var global = Context.Module.AddGlobal(vtableType, $"{name}.vtable");
        //        global.Initializer = LLVMValueRef.CreateConstStruct(values, true); ;
        //        return global;
        //    }
        //}

        //public static class Header {
        //    public static Symbol[] Insert(IEnumerable<Symbol> fields, LLVMValueRef typeInfo) {
        //        return new[] {
        //            new Symbol(typeInfo.TypeOf, "__typeinfo"),
        //            new Symbol(Types.UInt32, "__refcount"),
        //        }.Concat(fields).ToArray();
        //    }
        //}

        public static StructType Create(string name, IEnumerable<Symbol>? fields = null, OrderedMap<string, FreeFunction>? methods = null, bool packed = true) {
            try {
                var st = Context.Locals.GetType<StructType>(name) ?? Runtime.Environment.GetType<StructType>(name);
                if (st != null)
                    return st;
            } catch { }

            fields ??= Enumerable.Empty<Symbol>();
            methods ??= new();

            // Figure out the vtable type as early as possible. TypeInfo and per-object headers
            // depend on knowing this type, and it's different for every struct
            //var vtable = methods.Any() ? StaticTypeInfo.VTable(name, methods.Values) : null;
            //var typeInfo = methods.Any() ? StaticTypeInfo.TypeInfo(name, vtable) : null;

            //if (vtable != null) {
            //    // Prepend the header fields to the fields list before type gen
            //    fields = Header.Insert(fields, typeInfo);
            //}

            var elements = fields.Select(f => f.Type.Ref).ToArray();
            var namedType = Context.Module.Context.CreateNamedStruct($"struct.{name}");
            namedType.StructSetBody(elements, packed);
            var structType = methods.Any() ? new ObjectType(name, namedType, fields.ToList(), methods) : new StructType(name, namedType, fields.ToList());
            Context.Locals.AddType(structType);
            Context.Locals.AddType(structType.Pointer());
            return structType;
        }

        public static T Create<T>(string name, IEnumerable<Symbol>? fields = null, OrderedMap<string, FreeFunction>? methods = null, bool packed = true)
            where T : StructType {
            return (T)Create(name, fields, methods, packed);
        }

        // Placeholder type, used during AST parsing
        public StructType(string name)
            : this(name, Types.VoidPtr) {
        }

        // Real struct type, during codegen
        protected StructType(string name, LLVMTypeRef type,
            List<Symbol>? fields = null)
            : base(name, type) {
            Fields = fields?.ToOrderedMap(f => f.Name) ?? Fields;
        }

        public virtual Value GetMember(string name, Value instance) {
            if (instance.Type is PointerType ptr && ptr.Pointee.Name == Name) {
                if (Fields.TryGetValue(name, out var field)) 
                    return GetField(field, instance);
            }
            throw new MissingFieldException(name);
        }

        Value GetField(Symbol field, Value instance) {
            uint idx = (uint)Fields.IndexOf(field.Name);
            var addr = Context.Locals.Builder.BuildStructGEP2(this, instance, idx, field.Name);
            var value = Value.New(field.Type, addr);
            return value;
        }
        
        public override Value Coerce(Value val) {
            if (!val.Type.IsPointer) {
                throw new CompileError($"Cannot cast from {val.Type} to {this}");
            }
            return val;
        }

        public override PointerType Pointer() {
            return new PointerType($"{this}*", this, LLVMTypeRef.CreatePointer(this, 0));
        }
    }

    public class ObjectType : StructType {
        public OrderedMap<string, FreeFunction> Methods = new();

        public static new ObjectType Create(string name, IEnumerable<Symbol> fields, OrderedMap<string, FreeFunction> methods, bool packed = true) {
            return Create<ObjectType>(name, fields, methods, packed);
        }

        public ObjectType(string name, LLVMTypeRef type, List<Symbol> fields, OrderedMap<string, FreeFunction> methods)
            : base(name, type, fields) {
            Methods = methods;
        }

        public override Value GetMember(string name, Value instance) {
            try {
                var field = base.GetMember(name, instance);
                if (field != null) return field;
            } catch (MissingFieldException) { }
            
            if (Methods.TryGetValue(name, out var method)) 
                return GetMethod(method, instance);
            throw new MissingMethodException(name);
        }

        Value GetMethod(Function method, Value instance) {
            // TODO: vtable lookup
            throw new NotImplementedException();
        }
    }
}
