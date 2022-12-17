using LLVMSharp.Interop;
using Pepper.AST;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Xml.Linq;

namespace Pepper.Codegen {
    internal class IRCodegen {
        private readonly ParseTree Tree;

        public IRCodegen(ParseTree ast) {
            this.Tree = ast;
        }

        public LLVMModuleRef Emit() {
            foreach (var symbol in Tree.TopLevelSymbols) {
                if (symbol is FunctionDef function) {
                    EmitFunction(function);
                }
                throw new CompileError($"Unexpected top level symbol: {symbol}");
            }
            return Context.Module;
        }

        public Value EmitFunction(FunctionDef funcDef) {
            var function = new UserFunction(
                funcDef.Name,
                funcDef.ReturnType,
                funcDef.Params.Select(p => new UserFunction.Parameter(p.Type, p.Name, p.Default?.Codegen())));
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
            var locals = funcDef.Variables.Select(v => v.Codegen()).ToList();

            // Emit the body of the function
            var body = funcDef.Body.Select(expr => expr.Codegen()).ToList();

            Context.PopScope();
            return function;
        }
    }
}
