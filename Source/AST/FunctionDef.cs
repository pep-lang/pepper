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

        public FunctionDef(string name, Type returnType, IEnumerable<Parameter>? parameters = null, bool vararg = false)
            : base(returnType, name, parameters?.ToList() ?? Enumerable.Empty<Parameter>(), vararg) {
        }

        public override IEnumerable<Node> Children {
            get {
                var children = Variables.Cast<Node>().ToList();
                children.AddRange(Body.Cast<Node>());
                return children;
            }
        }
    }

    public class MethodDef : FunctionDef {
        public StructDef Struct { get; private set; }
        public MethodDef(StructDef st, string name, Type returnType, IEnumerable<Parameter>? parameters = null, bool vararg = false)
            : base(name, returnType, parameters?.ToList() ?? Enumerable.Empty<Parameter>(), vararg) {
            Struct = st;
        }
    }

    public class ExternFunction : FunctionNode {
        public ExternFunction(Type returnType, string name, List<Parameter> parameters, bool vararg = false)
            : base(returnType, name, parameters, vararg) {
        }

        public static readonly ExternFunction Malloc = new(Types.VoidPtr, "malloc", new List<Parameter> { new Parameter(Types.UInt64, "size") });
        public static readonly ExternFunction Free = new(Types.Void, "free", new List<Parameter> { new Parameter(Types.VoidPtr, "ptr") });
    }

    public class FunctionCall : Expression {
        public override Type Type => Target.ReturnType;
        public FunctionNode Target { get; private set; }
        public List<Expression> Args { get; private set; }
        public FunctionCall(FunctionDef target, List<Expression> args) {
            Target = target;
            Args = args;
        }

        public override IEnumerable<Node> Children => Args;
    }

    public class FunctionEnd : Node { }

    public class Return : Expression {
        public override Type Type => Target.ReturnType;
        public FunctionDef Target { get; private set; }
        public Expression? Value { get; private set; }

        public Return(FunctionDef target, Expression? value = null) {
            Target = target;
            Value = value;
        }

        public override IEnumerable<Node> Children => new List<Node?> { Value, new FunctionEnd() }.NonNull();
    }
}
