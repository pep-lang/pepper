using Pepper.Codegen;

namespace Pepper.AST {
    public abstract class BinaryOp : Expression {
        public override Type Type => OperandType;
        public virtual Type OperandType {
            get {
                var lhs = LHS.Type;
                var rhs = RHS.Type;
                if (lhs.IsFloat || rhs.IsFloat)
                    return lhs.Bits > 32 ? Types.Double : Types.Float;
                var resultType = (lhs.Bits > rhs.Bits) ? lhs : rhs;
                return resultType;
            }
        }

        public Expression LHS { get; private set; }
        public Expression RHS { get; private set; }

        public abstract Func<Value, Value, Value> Op { get; }

        public BinaryOp(Expression lhs, Expression rhs) {
            LHS = lhs;
            RHS = rhs;
        }
    }

    public class Add : BinaryOp {
        public Add(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Func<Value, Value, Value> Op => OperandType.Add;
    }

    public class Sub : BinaryOp {
        public Sub(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Func<Value, Value, Value> Op => OperandType.Sub;
    }

    public class Mul : BinaryOp {
        public Mul(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Func<Value, Value, Value> Op => OperandType.Mul;
    }

    public class Div : BinaryOp {
        public Div(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Func<Value, Value, Value> Op => OperandType.Div;
    }

    public class Mod : BinaryOp {
        public Mod(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Func<Value, Value, Value> Op => OperandType.Mod;
    }

    public class Pow : BinaryOp {
        public Pow(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Func<Value, Value, Value> Op => OperandType.Pow;
    }

    public class Equal : BinaryOp {
        public Equal(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Type Type => Types.Bool;
        public override Func<Value, Value, Value> Op => OperandType.Equal;
    }

    public class NotEqual : BinaryOp {
        public NotEqual(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Type Type => Types.Bool;
        public override Func<Value, Value, Value> Op => OperandType.NotEqual;
    }

    public class Less : BinaryOp {
        public Less(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Type Type => Types.Bool;
        public override Func<Value, Value, Value> Op => OperandType.Less;
    }

    public class LessEqual : BinaryOp {
        public LessEqual(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Type Type => Types.Bool;
        public override Func<Value, Value, Value> Op => OperandType.LessEqual;
    }

    public class Greater : BinaryOp {
        public Greater(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Type Type => Types.Bool;
        public override Func<Value, Value, Value> Op => OperandType.Greater;
    }

    public class GreaterEqual : BinaryOp {
        public GreaterEqual(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Type Type => Types.Bool;
        public override Func<Value, Value, Value> Op => OperandType.GreaterEqual;
    }

    public class Assign : BinaryOp {
        public Assign(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Func<Value, Value, Value> Op => OperandType.Assign;
    }

    public class LShift : BinaryOp {
        public LShift(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Func<Value, Value, Value> Op => OperandType.LShift;
    }

    public class RShift : BinaryOp {
        public RShift(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Func<Value, Value, Value> Op => OperandType.RShift;
    }

    public class BitAnd : BinaryOp {
        public BitAnd(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Func<Value, Value, Value> Op => OperandType.BitAnd;
    }

    public class BitOr : BinaryOp {
        public BitOr(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Func<Value, Value, Value> Op => OperandType.BitOr;
    }

    public class BitXor : BinaryOp {
        public BitXor(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Func<Value, Value, Value> Op => OperandType.BitXor;
    }

    public class LogicalAnd : BinaryOp {
        public LogicalAnd(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Type OperandType => Types.Bool;
        public override Type Type => Types.Bool;
        public override Func<Value, Value, Value> Op => OperandType.BitAnd;
    }

    public class LogicalOr : BinaryOp {
        public LogicalOr(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
        public override Type OperandType => Types.Bool;
        public override Type Type => Types.Bool;
        public override Func<Value, Value, Value> Op => OperandType.BitOr;
    }

    public abstract class CompoundAssign : Assign {
        public CompoundAssign(Expression lhs, Expression rhs)
            : base(lhs, rhs) {
        }
    }

    public class AddAssign : CompoundAssign {
        public AddAssign(Expression lhs, Expression rhs)
            : base(lhs, new Add(lhs, rhs)) {
        }
    }

    public class SubAssign : CompoundAssign {
        public SubAssign(Expression lhs, Expression rhs)
            : base(lhs, new Sub(lhs, rhs)) {
        }
    }

    public class MulAssign : CompoundAssign {
        public MulAssign(Expression lhs, Expression rhs)
            : base(lhs, new Mul(lhs, rhs)) {
        }
    }

    public class DivAssign : CompoundAssign {
        public DivAssign(Expression lhs, Expression rhs)
            : base(lhs, new Div(lhs, rhs)) {
        }
    }

    public class ModAssign : CompoundAssign {
        public ModAssign(Expression lhs, Expression rhs)
            : base(lhs, new Mod(lhs, rhs)) {
        }
    }

    public class LShiftAssign : CompoundAssign {
        public LShiftAssign(Expression lhs, Expression rhs)
            : base(lhs, new LShift(lhs, rhs)) {
        }
    }

    public class RShiftAssign : CompoundAssign {
        public RShiftAssign(Expression lhs, Expression rhs)
            : base(lhs, new RShift(lhs, rhs)) {
        }
    }

    public class BitAndAssign : CompoundAssign {
        public BitAndAssign(Expression lhs, Expression rhs)
            : base(lhs, new BitAnd(lhs, rhs)) {
        }
    }

    public class BitOrAssign : CompoundAssign {
        public BitOrAssign(Expression lhs, Expression rhs)
            : base(lhs, new BitOr(lhs, rhs)) {
        }
    }

    public class BitXorAssign : CompoundAssign {
        public BitXorAssign(Expression lhs, Expression rhs)
            : base(lhs, new BitXor(lhs, rhs)) {
        }
    }
}
