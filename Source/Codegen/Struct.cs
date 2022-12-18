
using LLVMSharp.Interop;

namespace Pepper.Codegen {
    public class Struct : Type {
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

        public Struct(string name, List<Symbol> fields, List<Function> methods)
            : base(name, Create(name, fields)) {
            Fields = fields;
            Methods = methods;
        }

        public override string ToString() {
            return Name;
        }
    }
}
