using Antlr4.Runtime.Misc;
using CommandLine;
using LLVMSharp;
using LLVMSharp.Interop;
using Pepper.AST;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection.Emit;
using System.Text;
using System.Threading.Tasks;
using System.Xml.Linq;

namespace Pepper.Codegen {
    internal class IRCodegen {
        private readonly ParseTree Tree;
        protected readonly Compiler Compiler;

        public IRCodegen(Compiler compiler, ParseTree ast) {
            Compiler = compiler;
            Tree = ast;

            MemoizeEmit<StructDef>(Emit);
            MemoizeEmit<FunctionDef>(Emit);
            MemoizeEmit<VariableDef>(Emit);
            MemoizeEmit<Expression>(Emit);
            MemoizeEmit<VariableRef>(Emit);
            MemoizeEmit<Literal>(Emit);
            MemoizeEmit<StringLiteral>(Emit);
            MemoizeEmit<IntegerLiteral>(Emit);
            MemoizeEmit<FloatLiteral>(Emit);
            MemoizeEmit<BinaryOp>(Emit);
            MemoizeEmit<FunctionCall>(Emit);
            MemoizeEmit<Return>(Emit);
        }

        public LLVMModuleRef Emit() {
            foreach (var symbol in Tree.TopLevelSymbols) {
                if (symbol is FunctionDef function) {
                    Codegen(function);
                    continue;
                }
                throw new CompileError($"Unexpected top level symbol: {symbol}");
            }
            return Context.Module;
        }

        // Create one memoized emitter per type
        private Dictionary<System.Type, Func<Node, Value>> MemoizedEmitters = new();
        private void MemoizeEmit<N>(Func<N, Value> emit) {
            var type = typeof(N);
            Func<Node, Value> downcastEmit = (n) => emit(n.Cast<N>());
            MemoizedEmitters[type] = Memoizer.Memoize(downcastEmit);
        }

        private Func<Node, Value> MemoizedEmit(System.Type type) {
            return MemoizedEmitters[type];
        }

        public Value Codegen<N>(N node) where N : Node {
            return MemoizedEmit(typeof(N))(node);
        }

        private Value Emit(StructDef structDef) {
            var fields = structDef.Fields.Select(f => Emit(f)).ToList(); ;
            var methods = structDef.Methods.Select(m => Emit(m)).ToList();
            var st = new Struct(structDef.Name, fields, methods);
            Context.PushScope(null);

            Context.PopScope();
            return st;
        }

        private Function Emit(FunctionDef funcDef) {
            var function = new UserFunction(
                funcDef.Name,
                funcDef.ReturnType,
                funcDef.Params.Select(p => new UserFunction.Parameter(p.Type, p.Name, MaybeCodegen(p.Default))));
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
            var locals = funcDef.Variables.Select(Codegen).ToList();

            // Emit the body of the function
            var body = funcDef.Body.Select(Codegen).ToList();

            Context.PopScope();
            return function;
        }

        private Value Emit(VariableDef variableDef) {
            return Context.Locals.AddVariable(
                new(variableDef.Type,
                variableDef.InitialValue != null ? Emit(variableDef.InitialValue) : variableDef.Type.DefaultValue,
                variableDef.Name));
        }

        private Value Emit(Expression expr) {
            if (expr is BinaryOp op) {
                return Codegen(op);
            }
            if (expr is FunctionCall call) {
                return Codegen(call);
            }
            if (expr is Return ret) {
                return Codegen(ret);
            }
            if (expr is VariableRef varRef) {
                return Codegen(varRef);
            }
            if (expr is Literal lit) {
                return Codegen(lit);
            }
            throw new InternalCompilerError($"Unexpected expression encountered during codegen: {expr}");
        }

        public Value? MaybeCodegen(Expression? expr) {
            if (expr != null) {
                return Emit(expr!);
            }
            return null;
        }

        private Value Emit(VariableRef variableRef) {
            return Context.Locals.GetVariable(variableRef.Identifier)!;
        }

        private Value Emit(Literal lit) {
            if (lit is StringLiteral str) {
                return Codegen(str);
            }
            if (lit is IntegerLiteral intLit) {
                return Codegen(intLit);
            }
            if (lit is FloatLiteral floatLit) {
                return Codegen(floatLit);
            }
            throw new InternalCompilerError($"unexpected literal encountered during codegen: {lit}");
        }

        private Value Emit(StringLiteral lit) {
            return new ConstantString(lit.Value);
        }

        private Value Emit(IntegerLiteral intLit) {
            return new ConstantInt(intLit.Value);
        }

        private Value Emit(FloatLiteral floatLit) {
            return new ConstantFloat(floatLit.Value);
        }

        private Value Emit(BinaryOp op) {
            Value lhs = Codegen(op.LHS);
            Value rhs = Codegen(op.RHS);
            var result = op.Op(op.OperandType.Coerce(lhs), op.OperandType.Coerce(rhs));
            return op.Type.Coerce(result);
        }

        private Value Emit(FunctionCall call) {
            var func = Context.Locals.GetFunction(call.Target.Name);
            if (func == null) {
                throw new CompileError("Function {Target.Name} not found", call.Source);
            }
            return func.Call(call.Args.Select(Emit));
        }

        private Value Emit(Return ret) {
            var returnValue = MaybeCodegen(ret.Value);
            if (returnValue != null) {
                return new Value(ret.Type, Context.Locals.Builder.BuildRet(ret.Type.Coerce(returnValue).Load()), "ret");
            }
            return new Instruction(Context.Locals.Builder.BuildRetVoid());
        }
    }
}
