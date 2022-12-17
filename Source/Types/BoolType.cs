using LLVMSharp.Interop;
using Pepper.Codegen;

namespace Pepper {
    public class BoolType : IntegerType {
        public BoolType()
            : base("bool", LLVMTypeRef.Int1, false) { }

        public override Value Coerce(Value val) {
            return val.AsBool();
        }

        public override Value CreateConstant<U>(U value) {
            return new ConstantBool((bool)Convert.ChangeType(value, typeof(bool))!);
        }

        public override Value DefaultValue => new(this, LLVMValueRef.CreateConstInt(this, 0, false), $"{Name}.false");
        public override Value AsBool(Value val) => val;
    }
}
