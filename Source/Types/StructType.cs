using LLVMSharp.Interop;
using Pepper.Codegen;
namespace Pepper {
    public class StructType : Type {
        public OrderedMap<string, Symbol> Fields = new();
        public OrderedMap<string, Function> Methods = new();

        // This is placeholder, a new one will be created once the structure is known
        static readonly StructType StructVTable = new("VTable", LLVMTypeRef.CreateStruct(Array.Empty<LLVMTypeRef>(), true));

        static readonly StructType StructTypeInfo = new("TypeInfo", LLVMTypeRef.CreateStruct(
            new LLVMTypeRef[]{
                StructVTable,
                LLVMTypeRef.CreatePointer(LLVMTypeRef.Int8, 0), // name
            }, true));

        // Placeholder type, used during AST parsing
        public StructType(string name)
            : this(name, StructTypeInfo) {
        }

        // Real struct type, during codegen
        public StructType(string name, LLVMTypeRef type, List<Symbol>? fields = null, List<Function>? methods = null)
            : base(name, type) {
            Fields = fields?.ToOrderedMap(f => f.Name) ?? Fields;
            Methods = methods?.ToOrderedMap(m => m.Name) ?? Methods;
        }

        public Value GetMember(string name, Value instance) {
            if (instance.Type is PointerType ptr && ptr.Pointee.Name == Name) {
                if (Fields.TryGetValue(name, out var field)) return GetField(field, instance);
                if (Methods.TryGetValue(name, out var method)) return GetMethod(method, instance);
                throw new CompileError($"{this} does not contain member \"{name}\"");
            } 
            throw new CompileError($"{instance} of type {instance.Type} does not match {this.Pointer()}");
        }

        Value GetField(Symbol field, Value instance) {
            uint idx = (uint)Fields.IndexOf(field.Name);
            var addr = Context.Locals.Builder.BuildStructGEP2(this, instance, idx, field.Name);
            var value = Value.New(field.Type, addr).Load();
            return value;
        }

        Value GetMethod(Function method, Value instance) {
            throw new NotImplementedException();
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
}
