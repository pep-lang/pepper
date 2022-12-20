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
            MemoizeEmit<Expression>(Emit);
            MemoizeEmit<VariableRef>(Emit);
            MemoizeEmit<MemberRef>(Emit);
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
                } catch {
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
                    //CodegenFunction(func, m);
                    return new KeyValuePair<string, FreeFunction>(name, func);
                })
                .ToOrderedMap();

            // Figure out the vtable type as early as possible. TypeInfo and per-object headers
            // depend on knowing this type, and it's different for every struct
            var vtableType = new StructType($"${structDef.Name}.vtable", Struct.VTableType(methods.Values));
            var typeInfoType = new StructType($"{structDef.Name}.typeinfo", Struct.StaticTypeInfo.Type(vtableType));

            // Prepend the header fields to the fields list before type gen
            var fields = Struct.Header.Fields(vtableType)
                .Concat(structDef.Fields.Select(f => new Symbol(f.Type, f.Name)))
                .ToList();

            // Generate the new struct type
            var structType = Struct.ToType(structDef.Name, fields, methods.Values);
            var structDesc = new Struct(structType.Pointer(), structDef.Name, fields, methods);

            // Create Struct()/new function
            var newFn = new FreeFunction(structDef.Name, structType.Pointer());
            var builder = newFn.Builder;
            Context.PushScope(builder);
            var addr = ExternFunction.Malloc.Call(structType.SizeOf);
            structDesc.Constructor.Call(addr);
            newFn.Builder.BuildRet(addr);
            Context.PopScope();
            // Export new to the enclosing scope
            Context.Locals.AddFunction(newFn);

            Context.PushScope(structDesc.Initializer.Builder);
            {
                var self = structDesc.Initializer.Address.IsAFunction.Params[0];
                //Context.Locals.AddVariable(Value.New(structType, self, "this"));
                CodegenFunction(structDesc.Initializer, structDef.Initializer);
            }
            Context.PopScope();

            // Insert initializer into st.Constructor
            Context.PushScope(structDesc.Constructor.Builder);
            {
                // push this into scope
                // TODO: deal with ctor params
                //var self = structTypeInfo.Constructor.Address.IsAFunction.Params[0];
                //Context.Locals.AddVariable(Value.New(structType, self, "this"));
                // inject the header values, then call init, then call constructor
                //var typeinfo = structType.GetMember("__typeinfo", self);
                //var refcount = structType.GetMember("__refcount", self);
                //structTypeInfo.Constructor.Builder.BuildStore(structTypeInfo.TypeInfo, typeinfo);
                //structTypeInfo.Constructor.Builder.BuildStore(new ConstantInt32(0), refcount);
                //structTypeInfo.Constructor.Builder.Insert(structTypeInfo.Initializer.Call(self));
                //CodegenFunction(structTypeInfo.Constructor, structDef.Constructor);
                structDesc.Constructor.Builder.BuildRetVoid();
            }            
            Context.PopScope();
            
            Context.PushScope(structDesc.Destructor.Builder);
            {
                var self = structDesc.Destructor.Address.IsAFunction.Params[0];
                //Context.Locals.AddVariable(Value.New(structType, self, "this"));
                CodegenFunction(structDesc.Destructor, structDef.Destructor);
                // Ensure destructor ends with free
                if (structDesc.Destructor.Body.LastInstruction.IsAReturnInst == null) {
                    structDesc.Destructor.Builder.PositionAtEnd(structDesc.Destructor.Body);
                    structDesc.Destructor.Builder.BuildRetVoid();
                }
                structDesc.Destructor.Builder.PositionBefore(structDesc.Destructor.Body.LastInstruction);
                self = structDesc.Destructor.Address.IsAFunction.Params[0];
                ExternFunction.Free.Call(self);
            }            
            Context.PopScope();

            return structDesc;
        }

        private Value Emit(FieldDef fieldDef) {
            var self = Context.Locals.GetVariable("this")!;
            var structType = Context.Locals.GetType<StructType>(((PointerType)self.Type).Pointee.Name);
            var lhs = structType.GetMember(fieldDef.Name, self);
            var value = MaybeCodegen(fieldDef.InitialValue) ?? lhs.Type.DefaultValue;
            return lhs.Type.Assign(lhs, value);
        }

        private Value Emit(MemberRef memberRef) {
            var lhs = Codegen(memberRef.LHS);
            var type = memberRef.LHS.Type;
            var structType = (StructType)(type.IsPointer ? ((PointerType)type).Pointee : type);
            var member = structType.GetMember(memberRef.Name, lhs);
            return member.Store();
        }

        private void CodegenFunction(UserFunction function, FunctionDef funcDef) {
            Context.PushScope(function.Builder);
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
            if (expr is MemberRef fieldRef) {
                return Codegen(fieldRef);
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
                return Emit(expr);
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
            return func.Call(call.Args.Select(Emit));
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
