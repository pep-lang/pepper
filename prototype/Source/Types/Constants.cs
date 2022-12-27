
using Pepper.Codegen;

namespace Pepper {
    public abstract class DerivedFrom<T> : NativeType where T : NativeType {
        readonly T Base;

        public DerivedFrom(string name, T baseType)
            : base(name, baseType) {
            Base = baseType;
        }

        public override bool IsInt => Base.IsInt;
        public override bool IsFloat => Base.IsFloat;
        public override bool IsPointer => Base.IsPointer;
        public override bool IsSigned => Base.IsSigned;
        public override uint Bits => Base.Bits;
        public override Value DefaultValue => Base.DefaultValue;
        public override Value Coerce(Value val) => Base.Coerce(val);
        public override PointerType Pointer() => Base.Pointer();
        public override Value Add(Value lhs, Value rhs) => Base.Add(lhs, rhs);
        public override Value Sub(Value lhs, Value rhs) => Base.Sub(lhs, rhs);
        public override Value Mul(Value lhs, Value rhs) => Base.Mul(lhs, rhs);
        public override Value Div(Value lhs, Value rhs) => Base.Div(lhs, rhs);
        public override Value Mod(Value lhs, Value rhs) => Base.Mod(lhs, rhs);
        public override Value Pow(Value lhs, Value rhs) => Base.Pow(lhs, rhs);
        public override Value Less(Value lhs, Value rhs) => Base.Less(lhs, rhs);
        public override Value Greater(Value lhs, Value rhs) => Base.Greater(lhs, rhs);
        public override Value LessEqual(Value lhs, Value rhs) => Base.LessEqual(lhs, rhs);
        public override Value GreaterEqual(Value lhs, Value rhs) => Base.GreaterEqual(lhs, rhs);
        public override Value LShift(Value lhs, Value rhs) => Base.LShift(lhs, rhs);
        public override Value RShift(Value lhs, Value rhs) => Base.RShift(lhs, rhs);
        public override Value Equal(Value lhs, Value rhs) => Base.Equal(lhs, rhs);
        public override Value NotEqual(Value lhs, Value rhs) => Base.NotEqual(lhs, rhs);
        public override Value Assign(Value lhs, Value rhs) => Base.Assign(lhs, rhs);
        public override Value BitAnd(Value lhs, Value rhs) => Base.BitAnd(lhs, rhs);
        public override Value BitOr(Value lhs, Value rhs) => Base.BitOr(lhs, rhs);
        public override Value BitXor(Value lhs, Value rhs) => Base.BitXor(lhs, rhs);
        public override Value AsBool(Value val) => Base.AsBool(val);
    }

    public class ConstantType<T, V, C> : DerivedFrom<T>
        where T : NativeType
        where C : Constant {
        readonly Func<V, C> Create;

        public ConstantType(T baseType, Func<V, C> create)
            : base($"const {baseType.Name}", baseType) {
            Create = create;
        }

        public override Value DefaultValue => base.DefaultValue;

        public override Value CreateConstant<U>(U value) {
            return Create((V)Convert.ChangeType(value, typeof(V))!);
        }
    }
}
