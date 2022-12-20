using LLVMSharp.Interop;
using Pepper.Codegen;

namespace Pepper {
    public class PointerType : NativeType {
        public Type Pointee { get; private set; }
        public override Value DefaultValue => Value.New(Types.VoidPtr, LLVMValueRef.CreateConstPointerNull(Types.VoidPtr), "nullptr");
        public PointerType(string name, Type pointee, LLVMTypeRef typeRef)
            : base(name, typeRef) {
            IsPointer = true;
            Pointee = pointee;
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
                return Value.New(this, LLVMValueRef.CreateConstPointerCast(val, this), $"{val.RegisterName}.ptr");
            }
            throw new CompileError($"Cannot convert non-pointer type {type} to {this}");
        }

        public override Value CreateConstant<U>(U value) {
            return new ConstantPointer((IntPtr)Convert.ChangeType(value, typeof(IntPtr))!);
        }

        public override Value Equal(Value lhs, Value rhs) => Value.New(this, Builder.BuildICmp(LLVMIntPredicate.LLVMIntEQ, lhs, rhs));
        public override Value Assign(Value lhs, Value rhs) { lhs.Store(rhs); return lhs; }

        public static LLVMValueRef Null = LLVMValueRef.CreateConstPointerNull(Types.Int8Ptr);
    }
}
