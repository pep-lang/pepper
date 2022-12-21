using Antlr4.Runtime.Misc;
using CommandLine;
using LLVMSharp;
using LLVMSharp.Interop;
using Pepper.AST;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.Linq;
using System.Reflection;
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
            MemoizeEmit<FieldDef>(Emit);
            MemoizeEmit<FunctionDef>(Emit);
            MemoizeEmit<VariableDef>(Emit);
            MemoizeEmit<VariableRef>(Emit);
            MemoizeEmit<MemberRef>(Emit);
            MemoizeEmit<ThisRef>(Emit);
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
                if (symbol is StructDef st) {
                    Codegen(st);
                    continue;
                }
                throw new CompileError($"Unexpected top level symbol: {symbol}");
            }
            return Context.Module;
        }

        // Create one memoized emitter per type
        private Dictionary<System.Type, Func<Node, object>> MemoizedEmitters = new();
        private void MemoizeEmit<N>(Func<N, Value> emit) {
            var type = typeof(N);
            Func<Node, Value> downcastEmit = (n) => emit(n.Cast<N>());
            MemoizedEmitters[type] = Memoizer.Memoize(downcastEmit);
        }

        private void MemoizeEmit<N>(Func<N, Struct> emit) {
            var type = typeof(N);
            Func<Node, Struct> downcastEmit = (n) => emit(n.Cast<N>());
            MemoizedEmitters[type] = Memoizer.Memoize(downcastEmit);
        }

        private Func<Node, object> MemoizedEmit(System.Type type) {
            return MemoizedEmitters[type];
        }

        public Value Codegen<N>(N node) where N : Node {
            var nodeType = node.GetType();
            while (nodeType != typeof(Node)) {
                try {
                    return (Value)MemoizedEmit(nodeType)(node);
                } catch (KeyNotFoundException) {
                    nodeType = nodeType.BaseType!;
                }
            }
            throw new InternalCompilerError($"Unable to find a way to emit a node of type {node.GetType()}");
        }

        private Struct Emit(StructDef structDef) {
            // Map normal method names to mangled free functions, while maintaining order
            var methods = structDef.Methods
                .Select(m => {
                    var name = m.Name;
                    // Add this as the first parameter to all methods
                    // TODO: deal with static methods?
                    var parameters = m.Params
                        .Select(p => new Function.Parameter(p.Type, p.Name, MaybeCodegen(p.Default)))
                        .Prepend(new Function.Parameter(structDef.Type.Pointer(), "this"));
                    var func = new FreeFunction(
                        Mangle.Method(structDef.Name, name),
                        m.ReturnType,
                        parameters.Cast<Function.Parameter>());
                    if (!name.StartsWith("__"))
                        CodegenFunction(func, m);
                    return new KeyValuePair<string, FreeFunction>(name, func);
                })
                .ToOrderedMap();

            // Convert fields list to symbols before type gen
            var fields = structDef.Fields.Select(f => new Symbol(f.Type, f.Name)).ToList();

            // Generate the new struct type
            var structType = ObjectType.Create(structDef.Name, fields, methods);
            var structDesc = new Struct(structType, structDef.Name);

            // Create Struct()/new function
            var newFn = new FreeFunction(structDef.Name, structType.Pointer());
            Context.PushScope(newFn);
            {
                var size = Value.New(Types.UInt64, structType.SizeOf, "size");
                var addr = ExternFunction.Malloc.Call(new ConstantInt64(4));
                structDesc.Constructor.Call(addr);
                newFn.Builder.BuildRet(addr);
            }            
            Context.PopScope();
            // Export new to the enclosing scope
            Context.Locals.AddFunction(newFn);

            CodegenFunction(structDesc.Initializer, structDef.Initializer);
            Context.Locals.AliasFunction(structDesc.Initializer, "__init");
            CodegenFunction(structDesc.Constructor, structDef.Constructor);
            CodegenFunction(structDesc.Destructor, structDef.Destructor);

            return structDesc;
        }

        private Value Emit(FieldDef fieldDef) {
            var self = Context.Locals.GetVariable("this")!;
            var structType = Context.Locals.GetType<StructType>(((PointerType)self.Type).Pointee.Name);
            var lhs = structType.GetMember(fieldDef.Name, self);
            var value = MaybeCodegen(fieldDef.InitialValue) ?? lhs.Type.DefaultValue;
            return lhs.Type.Assign(lhs.Load(), value);
        }

        private Value Emit(MemberRef memberRef) {
            var lhs = Codegen(memberRef.LHS);
            var type = memberRef.LHS.Type;
            var structType = (StructType)(type.IsPointer ? ((PointerType)type).Pointee : type);
            var member = structType.GetMember(memberRef.Name, lhs);
            return member.Load();
        }

        private Value Emit(ThisRef thisRef) {
            return Context.Locals.GetVariable("this")!;
        }

        private void CodegenFunction(UserFunction function, FunctionDef funcDef) {
            Context.PushScope(function);
            // Allocate parameters
            var llvmFunction = function.Address.IsAFunction;
            var llvmParams = llvmFunction.Params;
            var args = new List<Value>();
            for (int paramIdx = 0; paramIdx < llvmFunction.ParamsCount; ++paramIdx) {
                var param = function.Parameters.ElementAt(paramIdx);
                var arg = llvmParams[paramIdx];
                args.Add(Context.Locals.AddVariable(Value.New(param.Type, arg, param.Name)));
            }

            // Push all known variables at the top of the function block
            var locals = funcDef.Variables.Select(Codegen).ToList();

            // Emit the body of the function
            var lastExpr = funcDef.Body.LastOrDefault();
            if (lastExpr is not Return) {
                funcDef.Body.Add(new Return(funcDef));
            }
            var body = funcDef.Body.Select(Codegen).ToList();
            
            Context.PopScope();
        }

        private Function Emit(FunctionDef funcDef) {
            var function = new FreeFunction(
                funcDef.Name,
                funcDef.ReturnType,
                funcDef.Params.Select(p => new Function.Parameter(p.Type, p.Name, MaybeCodegen(p.Default))));
            CodegenFunction(function, funcDef);
            return function;
        }

        private Value Emit(VariableDef variableDef) {
            return Context.Locals.AddVariable(
                Value.New(variableDef.Type,
                variableDef.InitialValue != null ? Codegen(variableDef.InitialValue) : variableDef.Type.DefaultValue,
                variableDef.Name));
        }

        public Value? MaybeCodegen(Expression? expr) {
            if (expr != null) {
                return Codegen(expr);
            }
            return null;
        }

        private Value Emit(VariableRef variableRef) {
            return Context.Locals.GetVariable(variableRef.Identifier)!;
        }

        private Value Emit(StringLiteral lit) {
            return new ConstantString(lit.Value);
        }

        private Value Emit(IntegerLiteral intLit) {
            return (intLit.Value > int.MaxValue || intLit.Value < int.MinValue) 
                ? new ConstantInt64(intLit.Value) : new ConstantInt32((int)intLit.Value);
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
                throw new CompileError($"Function {call.Target.Name} not found", call.Source);
            }
            return func.Call(call.Args.Select(Codegen));
        }

        private Value Emit(Return ret) {
            var returnValue = MaybeCodegen(ret.Value);
            if (returnValue != null) {
                return Value.New(ret.Type, Context.Locals.Builder.BuildRet(ret.Type.Coerce(returnValue).Load()), "ret");
            }
            return new Instruction(Context.Locals.Builder.BuildRetVoid());
        }
    }
}
