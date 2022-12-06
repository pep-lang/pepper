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

        Context Ctx;
        Scope Globals = new Scope();
        Scope LocalScope;

        Compiler(Context context) {
            Ctx = context;
            LocalScope = Globals;
        }

        public static void Compile(Context Ctx) {
            var inputStream = CharStreams.fromPath(Ctx.Options.Input);

            var lexer = new PepperLexer(inputStream);
            var tokens = new BufferedTokenStream(lexer);
            var parser = new PepperParser(tokens);
            parser.BuildParseTree = true;

            var tree = parser.compilationUnit();
            var compiler = new Compiler(Ctx);
            ParseTreeWalker.Default.Walk(compiler, tree);

            //(_, var main) = Ctx.Module.AddFunction(LLVMTypeRef.Int32, "main", Array.Empty<LLVMTypeRef>(), (func, builder) => {
            //    builder.BuildRet(LLVMValueRef.CreateConstInt(LLVMTypeRef.Int32, 0));
            //});

            Ctx.Module.Verify(LLVMVerifierFailureAction.LLVMPrintMessageAction);

            _ = LLVM.InitializeNativeTarget();
            _ = LLVM.InitializeNativeAsmParser();
            _ = LLVM.InitializeNativeAsmPrinter();

            var engine = Ctx.Module.CreateMCJITCompiler();
            var main = compiler.Globals.GetFunction("main")!.Ref;
            var entry = engine.GetPointerToGlobal<IntMain0>(main);
            var result = entry();
            Assert.AreEqual(0, result);
        }

        Scope PushScope() {
            return LocalScope = new Scope(LocalScope);
        }

        Scope PopScope() {
            return LocalScope = LocalScope.Outer ?? Globals;
        }

        public override void EnterFunctionDefinition([NotNull] PepperParser.FunctionDefinitionContext context) {
            base.EnterFunctionDefinition(context);
            var identifier = context.declarator().Identifier().ToString()!;
            var paramList = context.initDeclaratorList();
            if (paramList != null) {
                var paramDecls = paramList.initDeclarator();
                //var params = paramDecls.Select(p => {
                //    var specifiers = p.declarationSpecifiers().declarationSpecifier();
                //    var decls = p.initDeclaratorList().initDeclarator();
                //});
            }
            var args = new List<Variable>();
            (var funcType, var funcRef) = Ctx.Module.AddFunction(LLVMTypeRef.Int32, identifier, Array.Empty<LLVMTypeRef>(), (func, builder) => {
                var body = context.compoundStatement();
                var exprs = body.blockItemList().blockItem();
                foreach (var expr in exprs) {
                    var decl = expr.declaration();
                    if (decl != null) {
                        // do something
                    }

                    var statement = expr.statement();
                    if (statement != null) {
                        if (statement.jumpStatement().Return() != null) {
                            builder.BuildRet(LLVMValueRef.CreateConstInt(LLVMTypeRef.Int32, 0));
                        }
                    }
                }
            });
            var func = new Function {
                TypeRef = funcType,
                Ref = funcRef,
                Name = identifier,
                ReturnType = "void",
                Parameters = args,
            };
            LocalScope.Functions.Add(identifier, func);
        }
    }
}
