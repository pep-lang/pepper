using LLVMSharp.Interop;
using Pepper.Codegen;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper {
    public class FloatType : NativeType {
        public FloatType(string name, LLVMTypeRef typeRef)
            : base(name, typeRef) {
            IsFloat = true;
            IsSigned = true;
        }

        public override Value Coerce(Value val) {
            if (val.Type.Equals(this) && val is not Constant) {
                return val;
            }

            var type = val.Type;
            if (type.IsInt) {
                if (type.IsSigned)
                    return new Value(this, Builder.BuildSIToFP(val.Load(), this)).Store();
                else
                    return new Value(this, Builder.BuildUIToFP(val.Load(), this)).Store();
            } else {
                if (Bits > val.Type.Bits)
                    return new Value(this, Builder.BuildFPExt(val.Load(), this)).Store();
                else
                    return new Value(this, Builder.BuildFPTrunc(val.Load(), this)).Store();
            }
        }

        public override Value CreateConstant<U>(U value) {
            return new ConstantFloat((double)Convert.ChangeType(value, typeof(double))!);
        }

        public override uint Bits => Ref == LLVMTypeRef.Float ? 32u : 64u;
        public override Value DefaultValue => new ConstantFloat(0, $"{Name}.zero");
        public override Value Add(Value lhs, Value rhs) => new(this, Builder.BuildFAdd(lhs.Load(), rhs.Load(), "add"));
        public override Value Sub(Value lhs, Value rhs) => new(this, Builder.BuildFSub(lhs.Load(), rhs.Load(), "sub"));
        public override Value Mul(Value lhs, Value rhs) => new(this, Builder.BuildFMul(lhs.Load(), rhs.Load(), "mul"));
        public override Value Div(Value lhs, Value rhs) => new(this, Builder.BuildFDiv(lhs.Load(), rhs.Load(), "div"));
        public override Value Mod(Value lhs, Value rhs) => new(this, Builder.BuildFRem(lhs.Load(), rhs.Load(), "mod"));
        public override Value Pow(Value lhs, Value rhs) => throw new NotImplementedException();
        public override Value Less(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildFCmp(LLVMRealPredicate.LLVMRealULT, lhs.Load(), rhs.Load(), "lt"));
        public override Value Greater(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildFCmp(LLVMRealPredicate.LLVMRealUGT, lhs.Load(), rhs.Load(), "gt"));
        public override Value LessEqual(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildFCmp(LLVMRealPredicate.LLVMRealULE, lhs.Load(), rhs.Load(), "le"));
        public override Value GreaterEqual(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildFCmp(LLVMRealPredicate.LLVMRealUGE, lhs.Load(), rhs.Load(), "ge"));
        public override Value Equal(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildFCmp(LLVMRealPredicate.LLVMRealUEQ, lhs.Load(), rhs.Load(), "eq"));
        public override Value NotEqual(Value lhs, Value rhs) => new(Types.Bool, Builder.BuildFCmp(LLVMRealPredicate.LLVMRealUNE, lhs.Load(), rhs.Load(), "ne"));
        public override Value Assign(Value lhs, Value rhs) { lhs.Store(Coerce(rhs)); return lhs; }
    }
}
