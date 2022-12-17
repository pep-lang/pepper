using Pepper.Codegen;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

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

        protected override Value Codegen() {
            var function = new UserFunction(Name, ReturnType, Params.Select(p => new UserFunction.Parameter(p.Type, p.Name, p.Default?.Codegen())));
            Context.PushScope(function.Builder);

            // Allocate parameters
            var llvmFunction = function.Address.IsAFunction;
            var llvmParams = llvmFunction.Params;
            var args = new List<Value>();
            for (int paramIdx = 0; paramIdx < llvmFunction.ParamsCount; ++paramIdx) {
                var param = function.Parameters.ElementAt(paramIdx);
                var arg = llvmParams[paramIdx];
                args.Add(Context.Locals.AddVariable(new Value(param.Type, arg, param.Name)));
            }

            // Push all known variables at the top of the function block
            var locals = Variables.Select(v => v.Codegen()).ToList();

            // Emit the body of the function
            var body = Body.Select(expr => expr.Codegen()).ToList();

            Context.PopScope();
            return function;
        }
    }

    public class ExternFunction : FunctionNode {
        public ExternFunction(Type returnType, string name, List<Parameter> parameters, bool vararg = false)
            : base(returnType, name, parameters, vararg) {

        }

        protected override Value Codegen() {
            var func = new Codegen.ExternFunction(Name, ReturnType, Params.ToSymbols(), Vararg);
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
                throw new CompileError("Function {Target.Name} not found", Source);
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
