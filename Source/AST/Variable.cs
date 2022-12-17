using Pepper.Codegen;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.AST {
    public class VariableDef : Symbol {
        public readonly Expression? InitialValue;
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

    public class VariableRef : Expression {
        public override Type Type => Symbol.Type;
        public string Identifier { get; private set; }
        public Symbol Symbol { get; private set; }
        public VariableRef(string identifier, Symbol symbol) {
            Identifier = identifier;
            Symbol = symbol;
        }

        protected override Value Codegen() {
            return Context.Locals.GetVariable(Identifier)!;
        }
    }
}
