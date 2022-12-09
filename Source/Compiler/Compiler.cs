using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using Antlr4.Runtime.Tree;
using LLVMSharp.Interop;
using Pepper.Parser;
using System.Diagnostics;
using System.Runtime.InteropServices;

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

            Log.Info(Context.Module.PrintToString());
            Context.Module.Verify(LLVMVerifierFailureAction.LLVMPrintMessageAction);
        }

        public static int JIT(string entryFunction) {
            _ = LLVM.InitializeNativeTarget();
            _ = LLVM.InitializeNativeAsmParser();
            _ = LLVM.InitializeNativeAsmPrinter();

            var engine = Context.Module.CreateMCJITCompiler();
            var entryAddress = Context.Globals.GetFunction(entryFunction)!.Address;
            var entry = engine.GetPointerToGlobal<IntMain0>(entryAddress);
            if (entry == null) {
                throw new CompileException($"Entry function {entryFunction} not found");
            }
            var result = entry();
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
            string returnTypeName = context.returnType()?.Identifier().ToString()! ?? IntegralType.Void.Name;
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
            }

        }

        public override void EnterPostfixExpression([NotNull] PepperParser.PostfixExpressionContext context) {
            base.EnterPostfixExpression(context);
        }

        public override void EnterFunctionCall([NotNull] PepperParser.FunctionCallContext context) {
            base.EnterFunctionCall(context);
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
            if (func.ReturnType != IntegralType.Void) {
                var result = func.Call(args);
                Locals.PushStack(result);
            }            
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

        public override void EnterAddSubExpression([NotNull] PepperParser.AddSubExpressionContext context) {
            base.EnterAddSubExpression(context);
        }

        public override void ExitAddSubExpression([NotNull] PepperParser.AddSubExpressionContext context) {
            base.ExitAddSubExpression(context);
        }

        public override void EnterMulDivExpression([NotNull] PepperParser.MulDivExpressionContext context) {
            base.EnterMulDivExpression(context);
        }

        public override void ExitMulDivExpression([NotNull] PepperParser.MulDivExpressionContext context) {
            base.ExitMulDivExpression(context);
            Func<LLVMValueRef, LLVMValueRef, string, LLVMValueRef>? Op = null;
            string OpName = "";
            if (context.Star().Length > 0) {
                Op = Context.Locals.Builder.BuildMul;
                OpName = "mul";
            } else if (context.Div().Length > 0) {
                Op = Context.Locals.Builder.BuildSDiv;
                OpName = "div";
            } else if (context.Mod().Length > 0) {
                Op = Context.Locals.Builder.BuildSRem;
                OpName = "mod";
            } else if (context.Pow().Length > 0) {
                // todo
                throw new NotImplementedException();
            }

            if (Op != null) {
                var rhs = Locals.PopStack();
                var lhs = Locals.PopStack();
                var resultType = (lhs.Type.Ref.IntWidth > rhs.Type.Ref.IntWidth) ? lhs.Type : rhs.Type;
                var result = new Value(resultType, Op(resultType.Coerce(lhs).Load(), resultType.Coerce(rhs).Load(), ""), OpName);
                Locals.PushStack(result);
            }
        }
    }
}
