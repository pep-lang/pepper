
namespace Pepper.AST {
    public class VariableDef : Symbol {
        public readonly Expression? InitialValue;
        public VariableDef(Type type, string name = "", Expression? initialValue = null)
            : base(type, name) {
            InitialValue = initialValue;
        }
    }

    public class FieldDef : VariableDef {
        public readonly StructDef Struct;
        public FieldDef(StructDef st, Type type, string name, Expression? initialValue = null)
            : base(type, name, initialValue) {
            Struct = st;
        }
    }

    public class ConstantDef : VariableDef {
        public ConstantDef(NativeType type, string name, Expression initialValue)
            : base(type, name, initialValue) {
        }
    }

    public class VariableRef : Expression {
        public override Type Type => Types.From(Symbol.Type.Name);
        public string Identifier { get; private set; }
        public Symbol Symbol { get; private set; }
        public VariableRef(string identifier, Symbol symbol) {
            Identifier = identifier;
            Symbol = symbol;
        }
    }
}
