using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using Antlr4.Runtime.Tree;
using LLVMSharp.Interop;
using NUnit.Framework;
using Pepper.Parser;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

namespace Pepper.Compiler {
    internal class Compiler : PepperBaseListener {

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int IntMain0();

        static Context Context { get { return Context.Default; } }

        public Scope Globals { get { return Context.Globals; } }
        public Scope Locals { get { return Context.Locals; } }

        Compiler() {}

        public static void Compile() {
            var inputStream = CharStreams.fromPath(Context.Options.Input);

            var lexer = new PepperLexer(inputStream);
            var tokens = new BufferedTokenStream(lexer);
            var parser = new PepperParser(tokens);
            parser.BuildParseTree = true;
            parser.Trace = true;

            var tree = parser.compilationUnit();
            var compiler = new Compiler();
            ParseTreeWalker.Default.Walk(compiler, tree);

            Context.Module.Verify(LLVMVerifierFailureAction.LLVMPrintMessageAction);

            _ = LLVM.InitializeNativeTarget();
            _ = LLVM.InitializeNativeAsmParser();
            _ = LLVM.InitializeNativeAsmPrinter();

            var engine = Context.Module.CreateMCJITCompiler();
            var main = compiler.Globals.GetFunction("main")!.Ref;
            var entry = engine.GetPointerToGlobal<IntMain0>(main);
            var result = entry();
            Assert.AreEqual(0, result);
        }

        LLVMValueRef EvalConstant(ITerminalNode constant) {
            var value = constant.ToString();
            if (Int64.TryParse(value, out var uintVal)) {
                return Locals.PushStack(LLVMValueRef.CreateConstInt(LLVMTypeRef.Int64, (ulong)uintVal));
            } else if (Double.TryParse(value, out var doubleVal)) {
                return Locals.PushStack(LLVMValueRef.CreateConstFPCast(LLVMValueRef.CreateConstInt(LLVMTypeRef.Int64, BitConverter.DoubleToUInt64Bits(uintVal)), LLVMTypeRef.Double));
            }
            throw new CompileException($"Unable to parse numeric constant '{constant}'");
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
            var parameters = new List<Variable>();
            if (paramList != null) {
                var paramDecls = paramList.initDeclarator();
                //var params = paramDecls.Select(p => {
                //    var specifiers = p.declarationSpecifiers().declarationSpecifier();
                //    var decls = p.initDeclaratorList().initDeclarator();
                //});
            }
            var func = new Function(identifier, returnType, parameters);
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
                returnValue = returnType.Coerce(returnValue);
                Locals.Builder.BuildRet(returnValue);
            }
        }

        public override void EnterAssignmentExpression([NotNull] PepperParser.AssignmentExpressionContext context) {
            base.EnterAssignmentExpression(context);
            var constant = context.Constant();
            if (constant != null) {
                EvalConstant(constant);
            }
        }

        public override void EnterPrimaryExpression([NotNull] PepperParser.PrimaryExpressionContext context) {
            base.EnterPrimaryExpression(context);
            var constant = context.Constant();
            if (constant != null) {
                EvalConstant(constant);
            }
        }

        public override void EnterExpression([NotNull] PepperParser.ExpressionContext context) {
            base.EnterExpression(context);
        }
    }
}
