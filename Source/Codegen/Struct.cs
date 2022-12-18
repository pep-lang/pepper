
using LLVMSharp.Interop;

namespace Pepper.Codegen {
    public class Struct : Value {
        public List<Symbol> Fields;
        public List<Function> Methods;

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

        static LLVMValueRef StructDesc(StructType type) {
            // var builder = Context.Locals.Builder;
            // Context.Module.AddGlobal()
            return LLVMValueRef.CreateConstNull(Types.VoidPtr);
        }

        public Struct(string name, List<Symbol> fields, List<Function> methods)
            : base(Create(name, fields), StructDesc(Create(name, fields)), name) {
            Fields = fields;
            Methods = methods;
        }

        public override string ToString() {
            return Name;
        }
    }
}
