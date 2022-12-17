using Pepper.Codegen;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.AST {
    public abstract class Literal : Expression { }

    public class IntegerLiteral : Literal {
        public override Type Type => Types.Int64;
        public long Value { get; private set; }
        public IntegerLiteral(long value) {
            Value = value;
        }

        protected override Value Codegen() {
            return new ConstantInt(Value);
        }
    }

    public class FloatLiteral : Literal {
        public override Type Type => Types.Double;
        public double Value { get; private set; }
        public FloatLiteral(double value) {
            Value = value;
        }

        protected override Value Codegen() {
            return new ConstantFloat(Value);
        }
    }

    public class StringLiteral : Literal {
        public override Type Type => Types.ConstantString;
        public string Value { get; private set; }
        public StringLiteral(string value) {
            Value = value;
        }

        protected override Value Codegen() {
            return new ConstantString(Value);
        }
    }
}
