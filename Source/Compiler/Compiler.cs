using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using Antlr4.Runtime.Tree;
using LLVMSharp.Interop;
using Pepper.Parser;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Xml.Linq;

namespace Pepper {
    public class Compiler : PepperBaseListener {

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int IntMain0();

        static Context Context { get { return Context.Default; } }

        internal Scope Globals { get { return Context.Globals; } }
        internal Scope Locals { get { return Context.Locals; } }

        Compiler() {}

        public static void CompileAndRun() {
            Compile(Options.Parse());
            var exitCode = JIT("main");
            Environment.Exit(exitCode);
        }

        public static void Compile(Options options) {
            var inputStream = CharStreams.fromPath(options.Input);
            Compile(options.ModuleName, inputStream);
        }

        public static void Compile(string moduleName, ICharStream inputStream) {
            var lexer = new PepperLexer(inputStream);
            var tokens = new BufferedTokenStream(lexer);
            var parser = new PepperParser(tokens) {
                BuildParseTree = true,
                Trace = true
            };

            var tree = parser.compilationUnit();
            var compiler = new Compiler(moduleName);
            ParseTreeWalker.Default.Walk(compiler, tree);

            //Log.Info(FormatTree(tree.ToStringTree(parser)));
            Log.Info(Context.Module.PrintToString());
            Context.Module.Verify(LLVMVerifierFailureAction.LLVMPrintMessageAction);
        }

        public static int JIT(string entryFunction) {
            _ = LLVM.InitializeNativeTarget();
            _ = LLVM.InitializeNativeAsmParser();
            _ = LLVM.InitializeNativeAsmPrinter();

            using var engine = Context.Module.CreateMCJITCompiler();
            var entryAddress = Context.Globals.GetFunction(entryFunction)!.Address;
            var entry = engine.GetPointerToGlobal<IntMain0>(entryAddress);
            if (entry == null) {
                throw new CompileException($"Entry function {entryFunction} not found");
            }
            var result = entry();
            return result;
        }

        public static string FormatTree(string tree) {
            string result = "";
            int depth = 0;
            foreach (var c in tree) {
                if (c == '(') {
                    depth++;
                    result += c + Environment.NewLine + new string(' ', depth * 2);
                } else if (c == ')') {
                    depth--;
                    result += Environment.NewLine + new string(' ', depth * 2) + c;
                } else {
                    result += c;
                }
            }
            return result;
        }

        private Compiler(string moduleName) {
            _ = new Context(moduleName);
        }

        Value EvalConstant(ITerminalNode constant) {
            var value = constant.ToString();
            if (long.TryParse(value, out var longVal)) {
                return Locals.PushStack(new ConstantInt(longVal));
            } else if (double.TryParse(value, out var doubleVal)) {
                return Locals.PushStack(new ConstantDouble(doubleVal));
            }
            throw new CompileException($"Unable to parse numeric constant '{constant}'");
        }

        Value EvalStringLiteral(string value) {
            return Locals.PushStack(new ConstantString(value));
        }

        public override void EnterFunctionDefinition([NotNull] PepperParser.FunctionDefinitionContext context) {
            base.EnterFunctionDefinition(context);
            var identifier = context.Identifier().ToString()!;
            string returnTypeName = context.returnType()?.Identifier().ToString()! ?? VoidType.Void.Name;
            var returnType = Locals.GetType(returnTypeName);
            if (returnType == null) {
                throw new CompileException($"Unknown return type {returnType}");
            }
            var paramList = context.initDeclaratorList();
            var parameters = new List<Value>();
            if (paramList != null) {
                var paramDecls = paramList.initDeclarator();
                //var params = paramDecls.Select(p => {
                //    var specifiers = p.declarationSpecifiers().declarationSpecifier();
                //    var decls = p.initDeclaratorList().initDeclarator();
                //});
            }
            var func = new UserFunction(identifier, returnType, parameters);
            Context.PushScope(func.Builder);
        }

        public override void ExitFunctionDefinition([NotNull] PepperParser.FunctionDefinitionContext context) {
            base.ExitFunctionDefinition(context);
            Context.PopScope();
        }

        public override void ExitFunctionCall([NotNull] PepperParser.FunctionCallContext context) {
            base.ExitFunctionCall(context);
            var identifier = context.Identifier()?.ToString();
            var func = identifier != null ? Locals.GetFunction(identifier) : Locals.PopStack<Function>();
            if (func == null) {
                throw new CompileException($"Unable to resolve function {identifier}");
            }
            var providedArgsCount = context.argumentExpressionList().assignmentExpression().Length;
            var args = new List<Value>();
            for (int argIdx = 0; argIdx < providedArgsCount; ++argIdx) {
                args.Add(Locals.PopStack());
            }
            if (func.ReturnType != VoidType.Void) {
                var result = func.Call(args);
                Locals.PushStack(result);
            }
        }

        public override void EnterDeclaration([NotNull] PepperParser.DeclarationContext context) {
            base.EnterDeclaration(context);
        }

        public override void EnterJumpStatement([NotNull] PepperParser.JumpStatementContext context) {
            base.EnterJumpStatement(context);
        }

        public override void ExitJumpStatement([NotNull] PepperParser.JumpStatementContext context) {
            base.ExitJumpStatement(context);

            if (context.Return() != null && context.expression() != null) {
                var returnValue = Locals.PopStack();
                var func = Locals.ReturnTarget;
                var returnType = func!.ReturnType;
                var coercedReturnValue = returnType.Coerce(returnValue);
                Locals.Builder.BuildRet(coercedReturnValue.Load());
            }
        }

        public override void EnterAssignmentExpression([NotNull] PepperParser.AssignmentExpressionContext context) {
            base.EnterAssignmentExpression(context);
            var constant = context.DigitSequence();
            if (constant != null) {
                EvalConstant(constant);
            }
        }

        public override void EnterPrimaryExpression([NotNull] PepperParser.PrimaryExpressionContext context) {
            base.EnterPrimaryExpression(context);
        }

        public override void ExitPrimaryExpression([NotNull] PepperParser.PrimaryExpressionContext context) {
            base.ExitPrimaryExpression(context);

            var constant = context.Constant();
            if (constant != null) {
                EvalConstant(constant);
                return;
            }
            var stringLiterals = context.StringLiteral();
            if (stringLiterals.Length > 0) {
                // Combine consecutive strings together like C
                var stringLiteral = stringLiterals.Select(s => s.ToString()).Aggregate("", (contents, literal) => contents + literal?.Trim('"'));
                EvalStringLiteral(stringLiteral);
                return;
            }
            if (context.Identifier() != null) {
                var identifier = context.Identifier().ToString()!;
                var variable = Locals.GetVariable(identifier);
                if (variable == null) {
                    throw new CompileException($"Could not find variable {identifier}");
                }
                Locals.PushStack(variable);
                return;
            }
        }

        public override void EnterPostfixExpression([NotNull] PepperParser.PostfixExpressionContext context) {
            base.EnterPostfixExpression(context);
        }

        public override void EnterFunctionCall([NotNull] PepperParser.FunctionCallContext context) {
            base.EnterFunctionCall(context);
        }

        public override void EnterInitDeclarator([NotNull] PepperParser.InitDeclaratorContext context) {
            base.EnterInitDeclarator(context);
        }

        public override void ExitInitDeclarator([NotNull] PepperParser.InitDeclaratorContext context) {
            base.ExitInitDeclarator(context);
            if (context.Assign() != null) {
                var type = context.declarator();
                var identifier = context.declarator().Identifier();
            }
        }

        public override void EnterVariableSpecifier([NotNull] PepperParser.VariableSpecifierContext context) {
            base.EnterVariableSpecifier(context);
        }

        public override void ExitVariableSpecifier([NotNull] PepperParser.VariableSpecifierContext context) {
            base.ExitVariableSpecifier(context);
            if (context.Identifier().Length != 2) {
                throw new CompileException("Expected <type> <name> while parsing variable declaration");
            }
            var identifiers = context.Identifier().Select(i => i.ToString()!).ToArray();
            (var typeName, var varName) = (identifiers[0], identifiers[1]);
            var type = Locals.GetType(typeName);
            if (type == null) {
                throw new CompileException($"Unknown type {typeName}");
            }
            var value = Locals.PopStack();
            var coercedValue = type.Coerce(value);
            var variable = new Value(type, coercedValue.Load(), varName);
            Locals.AddVariable(variable);
        }

        Type BinaryOpResultType() {
            var lhs = Locals.PeekStack<Value>(0);
            var rhs = Locals.PeekStack<Value>(1);
            return BinaryOpResultType(lhs.Type, rhs.Type);
        }

        static Type BinaryOpResultType(Type lhs, Type rhs) {
            var resultType = (lhs.Ref.IntWidth > rhs.Ref.IntWidth) ? lhs : rhs;
            return resultType;
        }

        void EmitBinaryOp(Func<Value, Value, Value> op) {
            var rhs = Locals.PopStack<Value>();
            var lhs = Locals.PopStack<Value>();
            var resultType = BinaryOpResultType(lhs.Type, rhs.Type);
            var result = op(resultType.Coerce(lhs), resultType.Coerce(rhs));
            Locals.PushStack(result);
        }

        public override void ExitMul([NotNull] PepperParser.MulContext context) {
            base.ExitMul(context);
            var resultType = BinaryOpResultType();
            EmitBinaryOp(resultType.Mul);
        }

        public override void ExitDiv([NotNull] PepperParser.DivContext context) {
            base.ExitDiv(context);
            var resultType = BinaryOpResultType();
            EmitBinaryOp(resultType.Div);
        }

        public override void ExitMod([NotNull] PepperParser.ModContext context) {
            base.ExitMod(context);
            var resultType = BinaryOpResultType();
            EmitBinaryOp(resultType.Mod);
        }

        public override void ExitPow([NotNull] PepperParser.PowContext context) {
            base.ExitPow(context);
            var resultType = BinaryOpResultType();
            throw new NotImplementedException();
        }

        public override void ExitAdd([NotNull] PepperParser.AddContext context) {
            base.ExitAdd(context);
            var resultType = BinaryOpResultType();
            EmitBinaryOp(resultType.Add);
        }

        public override void ExitSub([NotNull] PepperParser.SubContext context) {
            base.ExitSub(context);
            var resultType = BinaryOpResultType();
            EmitBinaryOp(resultType.Sub);
        }

        public override void ExitLShift([NotNull] PepperParser.LShiftContext context) {
            base.ExitLShift(context);
            var resultType = BinaryOpResultType();
            EmitBinaryOp(resultType.LShift);
        }

        public override void ExitRShift([NotNull] PepperParser.RShiftContext context) {
            base.ExitRShift(context);
            var resultType = BinaryOpResultType();
            EmitBinaryOp(resultType.RShift);
        }

        public override void ExitLess([NotNull] PepperParser.LessContext context) {
            base.ExitLess(context);
            var rhs = Locals.PopStack<Value>();
            var lhs = Locals.PopStack<Value>();
            bool isInt = lhs.Type.IsInt && rhs.Type.IsInt;
            if (isInt) {
                var operandType = IntegerType.Int64;
                var compare = Context.Locals.Builder.BuildICmp(LLVMIntPredicate.LLVMIntSLT, 
                    operandType.Coerce(lhs).Load(), operandType.Coerce(rhs).Load(), "");
                var result = new Value(IntegerType.Bool, compare, "less");
                Locals.PushStack(result);
            } else {
                var operandType = FloatType.Double;
                var coercedLhs = new Value(operandType, operandType.Coerce(lhs)).Load();
                var coercedRhs = new Value(operandType, operandType.Coerce(rhs)).Load();
                var compare = Context.Locals.Builder.BuildFCmp(LLVMRealPredicate.LLVMRealOLT, 
                    coercedLhs, coercedRhs, "");
                var result = new Value(IntegerType.Bool, compare, "less");
                Locals.PushStack(result);
            }
            
        }

        //public override void VisitTerminal([NotNull] ITerminalNode node) {
        //    base.VisitTerminal(node);
        //    Log.Info($"{node}");
        //}
    }
}
