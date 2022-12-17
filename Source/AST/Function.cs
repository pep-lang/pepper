using Antlr4.Runtime.Misc;
using Pepper.Codegen;

namespace Pepper.AST {
    public abstract class FunctionNode : Symbol {
        public class Parameter : Symbol {
            public Expression? Default { get; private set; }
            public Parameter(Type type, string name, Expression? defaultValue = null)
                : base(type, name) {
                Default = defaultValue;
            }
        }

        public Type ReturnType { get; private set; }
        public IEnumerable<Parameter> Params { get; private set; }
        public bool Vararg { get; private set; } = false;

        public FunctionNode(Type returnType, string name, IEnumerable<Parameter> parameters, bool vararg = false)
            : base(FunctionType.Create(returnType, parameters.ToSymbols(), vararg), name) {
            ReturnType = returnType;
            Params = parameters;
            Vararg = vararg;
        }
    }

    public class FunctionDef : FunctionNode {
        public List<VariableDef> Variables { get; set; } = new();
        public List<Expression> Body { get; set; } = new();

        public FunctionDef(Type returnType, string name, IEnumerable<Parameter> parameters, bool vararg = false)
            : base(returnType, name, parameters.ToList(), vararg) {
        }

        public override IEnumerable<Node> Children => Variables.As<Node>().Mix(Body.As());
    }

    public class ExternFunction : FunctionNode {
        public ExternFunction(Type returnType, string name, List<Parameter> parameters, bool vararg = false)
            : base(returnType, name, parameters, vararg) {
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

        public override IEnumerable<Node> Children => new List<Node> { Target }.Mix(Args);
    }

    public class Return : Expression {
        public override Type Type => Target.ReturnType;
        public FunctionDef Target { get; private set; }
        public Expression? Value { get; private set; }

        public Return(FunctionDef target, Expression? value) {
            Target = target;
            Value = value;
        }

        public override IEnumerable<Node> Children => new List<Node?> { Target }.Append(Value).NonNull();
    }
}
