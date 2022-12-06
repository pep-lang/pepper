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

        public override void EnterFunctionDefinition([NotNull] PepperParser.FunctionDefinitionContext context) {
            base.EnterFunctionDefinition(context);
            var identifier = context.Identifier().ToString()!;
            string returnTypeName = context.returnType()?.Identifier().ToString()! ?? IntegralType.Void.Name;
            var returnType = Locals.GetType(returnTypeName);
            if (returnType == null) {
                throw new Exception($"Unknown return type {returnType}");
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
            var body = context.compoundStatement();
            if (body != null) {
                var exprs = body.blockItemList().blockItem();
                foreach (var expr in exprs) {
                    var decl = expr.declaration();
                    if (decl != null) {
                        // do something
                    }

                    var statement = expr.statement();
                    if (statement != null) {
                        if (statement.jumpStatement().Return() != null) {
                            func.Builder.BuildRet(LLVMValueRef.CreateConstInt(LLVMTypeRef.Int32, 0));
                        }
                    }
                }
            }
        }
    }
}
