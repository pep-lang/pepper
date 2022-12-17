using LLVMSharp.Interop;
using Pepper.Codegen;

namespace Pepper {
    public class IntegerType : NativeType {
        public IntegerType(string name, LLVMTypeRef typeRef, bool signed = true)
            : base(name, typeRef) {
            IsInt = true;
            IsSigned = signed;
        }

        public override Value Coerce(Value val) {
            if (val.Type.Equals(this) && val is not Constant) {
                return val;
            }
            bool signed = val.Type != Types.Bool && IsSigned;
            if (val.Type.IsInt) {
                if (this.Bits > val.Type.Bits)
                    return new Value(this, Builder.BuildZExtOrBitCast(val.Load(), this), $"{val.RegisterName}.zext").Store();
                else
                    return new Value(this, Builder.BuildTruncOrBitCast(val.Load(), this), $"{val.RegisterName}.trunc").Store();
            }
            Func<LLVMValueRef, LLVMTypeRef, string, LLVMValueRef> convert = signed ? Builder.BuildFPToSI : Builder.BuildFPToUI;
            return new Value(this, convert(val.Load(), this, ""), $"{val.Name}.fptoi").Store();
        }

        public override Value CreateConstant<U>(U value) {
            return new ConstantInt((long)Convert.ChangeType(value, typeof(long))!);
        }

        public override Value DefaultValue => new(this, LLVMValueRef.CreateConstInt(this, 0, IsSigned), $"{Name}.zero");
        public override Value Add(Value lhs, Value rhs) => new(this, Builder.BuildAdd(lhs.Load(), rhs.Load(), "add"));
        public override Value Sub(Value lhs, Value rhs) => new(this, Builder.BuildSub(lhs.Load(), rhs.Load(), "sub"));
        public override Value Mul(Value lhs, Value rhs) => new(this, Builder.BuildMul(lhs.Load(), rhs.Load(), "mul"));
        public override Value Div(Value lhs, Value rhs) => new(this, Builder.BuildSDiv(lhs.Load(), rhs.Load(), "div"));
        public override Value Mod(Value lhs, Value rhs) => new(this, Builder.BuildSRem(lhs.Load(), rhs.Load(), "mod"));
        public override Value Pow(Value lhs, Value rhs) => throw new NotImplementedException();
        public override Value Less(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildICmp(LLVMIntPredicate.LLVMIntULT, lhs.Load(), rhs.Load(), "lt"));
        public override Value Greater(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildICmp(LLVMIntPredicate.LLVMIntUGT, lhs.Load(), rhs.Load(), "gt"));
        public override Value LessEqual(Value lhs, Value rhs) => new(this, Builder.BuildICmp(LLVMIntPredicate.LLVMIntSLE, lhs.Load(), rhs.Load(), "le"));
        public override Value GreaterEqual(Value lhs, Value rhs) => new(this, Builder.BuildICmp(LLVMIntPredicate.LLVMIntSGE, lhs.Load(), rhs.Load(), "ge"));
        public override Value LShift(Value lhs, Value rhs) => new(this, Builder.BuildShl(lhs.Load(), rhs.Load(), "lshift"));
        public override Value RShift(Value lhs, Value rhs) => new(this, Builder.BuildAShr(lhs.Load(), rhs.Load(), "rshift"));
        public override Value Equal(Value lhs, Value rhs) => new(this, Builder.BuildICmp(LLVMIntPredicate.LLVMIntEQ, lhs.Load(), rhs.Load(), "eq"));
        public override Value NotEqual(Value lhs, Value rhs) => new(this, Builder.BuildICmp(LLVMIntPredicate.LLVMIntNE, lhs.Load(), rhs.Load(), "ne"));
        public override Value Assign(Value lhs, Value rhs) { lhs.Store(Coerce(rhs)); return lhs; }
        public override Value BitAnd(Value lhs, Value rhs) => new(this, Builder.BuildAnd(lhs.Load(), rhs.Load(), "and"));
        public override Value BitOr(Value lhs, Value rhs) => new(this, Builder.BuildOr(lhs.Load(), rhs.Load(), "or"));
        public override Value BitXor(Value lhs, Value rhs) => new(this, Builder.BuildXor(lhs.Load(), rhs.Load(), "xor"));
        public override Value AsBool(Value val) {
            var name = val.RegisterName;
            return new(this, Builder.BuildICmp(LLVMIntPredicate.LLVMIntNE, val.Load(), ConstantBool.False.As(this), name));
        }
    }
}
