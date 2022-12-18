
using LLVMSharp.Interop;

namespace Pepper.Codegen {
    public class Struct : Value {
        public List<Value> Fields;
        public List<Function> Methods;

        static StructType Create(string name, List<Value> fields) {
            var elements = fields.Select(f => f.Type.Ref).ToArray();
            return new StructType(name, LLVMTypeRef.CreateStruct(elements, false));
        }

        public Struct(string name, List<Value> fields, List<Function> methods)
            : base(Create(name, fields), LLVMValueRef.CreateConstPointerNull(Types.VoidPtr), name) {
            Fields = fields;
            Methods = methods;
        }

        public override string ToString() {
            return Name;
        }

        public static implicit operator LLVMTypeRef(Struct st) => st.Type;
        public static implicit operator LLVMValueRef(Struct st) => st.Address;
    }
}
