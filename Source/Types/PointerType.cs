using LLVMSharp.Interop;
using Pepper.Codegen;

namespace Pepper {
    public class PointerType : NativeType {
        public override Value DefaultValue => new(Types.VoidPtr, LLVMValueRef.CreateConstPointerNull(Types.VoidPtr), "nullptr");
        public PointerType(string name, LLVMTypeRef typeRef)
            : base(name, typeRef) {
            IsPointer = true;
        }

        public override PointerType Pointer() {
            throw new CompileError($"Pointer to {this} is disallowed");
        }

        public override Value Coerce(Value val) {
            if (val.Type.Equals(this) && val is not Constant) {
                return val;
            }

            var type = val.Type;
            if (type.IsPointer) {
                return new Value(this, LLVMValueRef.CreateConstPointerCast(val, this), $"{val.RegisterName}.ptr");
            }
            throw new CompileError($"Cannot convert non-pointer type {type} to {this}");
        }

        public override Value CreateConstant<U>(U value) {
            return new ConstantPointer((IntPtr)Convert.ChangeType(value, typeof(IntPtr))!);
        }

        public override Value Equal(Value lhs, Value rhs) => new(this, Builder.BuildICmp(LLVMIntPredicate.LLVMIntEQ, lhs, rhs));
        public override Value Assign(Value lhs, Value rhs) { lhs.Store(rhs); return lhs; }
    }
}
