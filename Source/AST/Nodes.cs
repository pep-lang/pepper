
using LLVMSharp;
using System;

namespace Pepper.AST {
    public abstract class Node {
        // Each node should only every be codegen'ed once
        private Func<Node, Value> CachedCodegen = Memoizer.Memoize<Node, Value>(node => node.Codegen());
        // This is the implementation that gets overridden by nodes
        protected abstract Value Codegen();
        // This is the public interface. The parameter is a dummy to differentiate the signatures
        public Value Codegen(object? dummy = null) => CachedCodegen(this);
    }

    public class Symbol : Node {
        public Type Type { get; private set; }
        public string Name { get; private set; }
        public Symbol(Type type, string name) {
            Type = type;
            Name = name;
        }

        protected override Value Codegen() {
            throw new NotImplementedException();
        }
        public static implicit operator Pepper.Symbol(Symbol sym) => new Pepper.Symbol(sym.Type, sym.Name);
    }

    public class VariableDef : Symbol {
        readonly Expression? InitialValue;
        public VariableDef(Type type, string name = "", Expression? initialValue = null)
            : base(type, name) {
            InitialValue = initialValue;
        }

        protected override Value Codegen() =>
                Context.Locals.AddVariable(new(Type, InitialValue != null ? InitialValue.Codegen() : Type.DefaultValue, Name));
    }

    public class ConstantDef : VariableDef {
        public ConstantDef(NativeType type, string name, Expression initialValue)
            : base(type, name, initialValue) {
        }
    }

    public abstract class Expression : Node {
        public abstract Type Type { get; }
    }

    public class IntegerLiteral : Expression {
        public override Type Type => Types.Int64;
        public long Value { get; private set; }
        public IntegerLiteral(long value) {
            Value = value;
        }

        protected override Value Codegen() {
            return new ConstantInt(Value);
        }
    }

    public class FloatLiteral : Expression {
        public override Type Type => Types.Double;
        public double Value { get; private set; }
        public FloatLiteral(double value) {
            Value = value;
        }

        protected override Value Codegen() {
            return new ConstantFloat(Value);
        }
    }

    public class StringLiteral : Expression {
        public override Type Type => Types.ConstantString;
        public string Value { get; private set; }
        public StringLiteral(string value) {
            Value = value;
        }

        protected override Value Codegen() {
            return new ConstantString(Value);
        }
    }

    public class VariableRef : Expression {
        public override Type Type => Variable.Type;
        public string Identifier { get; private set; }
        public VariableDef Variable { get; private set; }
        public VariableRef(string identifier, VariableDef variable) {
            Identifier = identifier;
            Variable = variable;
        }

        protected override Value Codegen() {
            return Context.Locals.GetVariable(Identifier)!;
        }
    }

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

        protected Value EmitBinaryOp(Func<Value, Value, Value> op) {
            Value lhs = LHS.Codegen();
            Value rhs = RHS.Codegen();
            var result = op(OperandType.Coerce(lhs), OperandType.Coerce(rhs));
            return Type.Coerce(result);
        }

        protected override Value Codegen() => EmitBinaryOp(Op);
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

    public abstract class FunctionNode : Symbol {
        public Type ReturnType { get; private set; }
        public IEnumerable<Symbol> Params { get; private set; }
        public bool Vararg { get; private set; } = false;

        public FunctionNode(Type returnType, string name, IEnumerable<Symbol> parameters, bool vararg = false)
            : base(FunctionType.Create(returnType, parameters.Select(p => (Pepper.Symbol)p), vararg), name) {
            ReturnType = returnType;
            Params = parameters;
            Vararg = vararg;
        }
    }

    public class FunctionDef : FunctionNode {
        public List<VariableDef> Variables { get; set; } = new();
        public List<Expression> Body { get; set; } = new();

        public FunctionDef(Type returnType, string name, IEnumerable<Symbol> parameters, bool vararg = false)
            : base(returnType, name, parameters, vararg) {

        }

        protected override Value Codegen() {
            var function = new UserFunction(Name, ReturnType, Params.Select(p => new Pepper.Symbol(p.Type, p.Name)));
            Context.PushScope(function.Builder);

            // TODO: get params and alloc/store them

            // Push all known variables at the top of the function block
            foreach (var variable in Variables) {
                variable.Codegen();
            }

            // Emit the body of the function
            foreach (var expr in Body) {
                expr.Codegen();
            }

            Context.PopScope();
            return function;
        }
    }

    public class ExternFunction : FunctionNode {
        public ExternFunction(Type returnType, string name, List<Symbol> parameters, bool vararg = false)
            : base(returnType, name, parameters, vararg) {

        }

        protected override Value Codegen() {
            var func = new Pepper.ExternFunction(Name, ReturnType, Params.Select(p => new Pepper.Symbol(p.Type, p.Name)), Vararg);
            return func;
        }
    }

    public class FunctionCall : Expression {
        public override Type Type => Target.ReturnType;
        public FunctionDef Target { get; private set; }
        public List<Expression> Args { get; private set; }
        public FunctionCall(FunctionDef target, List<Expression> args) {
            Target = target;
            Args = args;
        }

        protected override Value Codegen() {
            var func = Context.Locals.GetFunction(Target.Name);
            if (func == null) {
                throw new CompileException("Function {Target.Name} not found");
            }
            return func.Call(Args.Select(a => a.Codegen()));
        }
    }

    public class Return : Expression {
        public override Type Type => Target.ReturnType;
        public FunctionDef Target { get; private set; }
        public Expression? Value { get; private set; }

        public Return(FunctionDef target, Expression? value) {
            Target = target;
            Value = value;
        }

        protected override Value Codegen() {
            var returnValue = Value?.Codegen();
            if (returnValue != null) {
                return new Value(Type, Context.Locals.Builder.BuildRet(Type.Coerce(returnValue).Load()), "ret");
            }
            return new Instruction(Context.Locals.Builder.BuildRetVoid());
        }
    }
}
