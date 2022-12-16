using Pepper.AST;
using Antlr4.Runtime.Tree;
using Antlr4.Runtime.Misc;
using Antlr4.Runtime;
using Pepper.ANTLR;

namespace Pepper {
    internal class Parser : ANTLR.PepperBaseListener {
        private readonly ParseTree AST = new();
        private readonly Builder Builder;
        private readonly ICharStream SourceStream;
        private readonly string SourcePath;
        public Parser(string sourcePath, ICharStream? sourceStream) {
            SourcePath = sourcePath;
            SourceStream = sourceStream ?? CharStreams.fromPath(sourcePath);
            Builder = AST.Builder();
        }

        public ParseTree Parse() {
            var lexer = new ANTLR.PepperLexer(SourceStream);
            var tokens = new BufferedTokenStream(lexer);
            var parser = new ANTLR.PepperParser(tokens) {
                BuildParseTree = true,
                //Trace = true,
                ErrorHandler = new BailErrorStrategy(),
            };

            try {
                var tree = parser.compilationUnit();
                ParseTreeWalker.Default.Walk(this, tree);
                //Log.Info(FormatAntlrTree(tree.ToStringTree(parser)));
            } catch (ParseCanceledException pcex) {
                Log.Error(pcex.Message);
                if (pcex.InnerException is InputMismatchException imex) {
                    Log.Error($"Unexpected token \"{imex.OffendingToken.Text}\"");
                }
                Log.Error("Stopping compilation");
                throw new CompileException("Stopping compilation");
            }

            return AST;
        }

        public static string FormatAntlrTree(string tree) {
            string result = "";
            int depth = 0;
            foreach (var c in tree) {
                if (c == '(') {
                    depth++;
                    result += c + Environment.NewLine + new string(' ', depth);
                } else if (c == ')') {
                    depth--;
                    result += Environment.NewLine + new string(' ', depth) + c;
                } else {
                    result += c;
                }
            }
            return result;
        }

        Expression EvalConstant(ITerminalNode constant) {
            var value = constant.ToString();
            if (long.TryParse(value, out var longVal)) {
                return new IntegerLiteral(longVal);
            } else if (double.TryParse(value, out var doubleVal)) {
                return new FloatLiteral(doubleVal);
            }
            throw new CompileException($"Unable to parse numeric constant '{constant}'");
        }

        Expression EvalStringLiteral(string value) {
            return new StringLiteral(value);
        }

        public override void EnterFunctionDefinition([NotNull] PepperParser.FunctionDefinitionContext context) {
            base.EnterFunctionDefinition(context);
            var identifier = context.Identifier().ToString()!;
            string returnTypeName = context.returnType()?.Identifier().ToString() ?? Types.Void.Name;
            var returnType = Builder.FindType(returnTypeName);
            if (returnType == null) {
                throw new CompileException($"Unknown return type {returnType}");
            }
            var paramList = context.initDeclaratorList();
            var parameters = new List<AST.Symbol>();
            if (paramList != null) {
                var paramDecls = paramList.initDeclarator();
                // TODO
                //var params = paramDecls.Select(p => {
                //    var specifiers = p.declarationSpecifiers().declarationSpecifier();
                //    var decls = p.initDeclaratorList().initDeclarator();
                //});
            }
            var func = new UserFunction(identifier, returnType, parameters.Select(p => (Symbol)p));
            Builder.BeginFunction(new FunctionDef(returnType, identifier, parameters));
        }

        public override void ExitFunctionDefinition([NotNull] PepperParser.FunctionDefinitionContext context) {
            base.ExitFunctionDefinition(context);
            Builder.EndFunction();
        }

        public override void ExitFunctionCall([NotNull] PepperParser.FunctionCallContext context) {
            base.ExitFunctionCall(context);
            var identifier = context.Identifier()?.ToString()!;
            var func = identifier != null ? Builder.FindFunction(identifier) : Builder.PopStack<FunctionDef>();
            if (func == null) {
                throw new CompileException($"Unable to resolve function {identifier}");
            }
            var providedArgsCount = context.argumentExpressionList().assignmentExpression().Length;
            var args = new List<Expression>();
            for (int argIdx = 0; argIdx < providedArgsCount; ++argIdx) {
                args.Add(Builder.PopStack<Expression>());
            }
            var result = new FunctionCall(func, args);
            if (func.ReturnType != Types.Void) {
                Builder.PushStack(result);
            }
        }

        public override void EnterDeclaration([NotNull] PepperParser.DeclarationContext context) {
            base.EnterDeclaration(context);
        }

        public override void ExitReturn([NotNull] PepperParser.ReturnContext context) {
            base.ExitReturn(context);

            if (context.expression() != null) {
                var returnValue = Builder.PopStack<Expression>();
                var func = Builder.ReturnTarget;
                Builder.NewExpression(new Return(func, returnValue));
            }
        }

        public override void EnterPrimaryExpression([NotNull] PepperParser.PrimaryExpressionContext context) {
            base.EnterPrimaryExpression(context);
        }

        public override void ExitPrimaryExpression([NotNull] PepperParser.PrimaryExpressionContext context) {
            base.ExitPrimaryExpression(context);

            var constant = context.Constant();
            if (constant != null) {
                Builder.PushStack(EvalConstant(constant));
                return;
            }
            var stringLiterals = context.StringLiteral();
            if (stringLiterals.Length > 0) {
                // Combine consecutive strings together like C
                var stringLiteral = stringLiterals.Select(s => s.ToString()).Aggregate("", (contents, literal) => contents + literal?.Trim('"'));
                Builder.PushStack(EvalStringLiteral(stringLiteral));
                return;
            }
            if (context.Identifier() != null) {
                var identifier = context.Identifier().ToString()!;
                var variableRef = Builder.FindVariable(identifier);
                if (variableRef == null) {
                    throw new CompileException($"Unable to find symbol {identifier}");
                }
                var variable = new VariableRef(identifier, variableRef);
                Builder.PushStack(variable);
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
            var type = Builder.FindType(typeName);
            if (type == null) {
                throw new CompileException($"Unknown type {typeName}");
            }
            var initialValue = Builder.PopStack<Expression>();
            Builder.NewVariable(new VariableDef(type, varName, initialValue));
        }

        public override void ExitMul([NotNull] PepperParser.MulContext context) {
            base.ExitMul(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new Mul(lhs, rhs));
        }

        public override void ExitDiv([NotNull] PepperParser.DivContext context) {
            base.ExitDiv(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new Div(lhs, rhs));
        }

        public override void ExitMod([NotNull] PepperParser.ModContext context) {
            base.ExitMod(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new Mod(lhs, rhs));
        }

        public override void ExitPow([NotNull] PepperParser.PowContext context) {
            base.ExitPow(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new Pow(lhs, rhs));
        }

        public override void ExitAdd([NotNull] PepperParser.AddContext context) {
            base.ExitAdd(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new Add(lhs, rhs));
        }

        public override void ExitSub([NotNull] PepperParser.SubContext context) {
            base.ExitSub(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new Sub(lhs, rhs));
        }

        public override void ExitLShift([NotNull] PepperParser.LShiftContext context) {
            base.ExitLShift(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new LShift(lhs, rhs));
        }

        public override void ExitRShift([NotNull] PepperParser.RShiftContext context) {
            base.ExitRShift(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new RShift(lhs, rhs));
        }

        public override void ExitLess([NotNull] PepperParser.LessContext context) {
            base.ExitLess(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new Less(lhs, rhs));
        }

        public override void ExitGreater([NotNull] PepperParser.GreaterContext context) {
            base.ExitGreater(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new Greater(lhs, rhs));
        }

        public override void ExitLessEqual([NotNull] PepperParser.LessEqualContext context) {
            base.ExitLessEqual(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new LessEqual(lhs, rhs));
        }

        public override void ExitGreaterEqual([NotNull] PepperParser.GreaterEqualContext context) {
            base.ExitGreaterEqual(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new GreaterEqual(lhs, rhs));
        }

        public override void ExitBitwiseAnd([NotNull] PepperParser.BitwiseAndContext context) {
            base.ExitBitwiseAnd(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new BitAnd(lhs, rhs));
        }

        public override void ExitBitwiseOr([NotNull] PepperParser.BitwiseOrContext context) {
            base.ExitBitwiseOr(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new BitOr(lhs, rhs));
        }

        public override void ExitBitwiseXor([NotNull] PepperParser.BitwiseXorContext context) {
            base.ExitBitwiseXor(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new BitXor(lhs, rhs));
        }

        public override void ExitLogicalAnd([NotNull] PepperParser.LogicalAndContext context) {
            base.ExitLogicalAnd(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new LogicalAnd(lhs, rhs));
        }

        public override void ExitLogicalOr([NotNull] PepperParser.LogicalOrContext context) {
            base.ExitLogicalOr(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new LogicalOr(lhs, rhs));
        }

        public override void ExitEqual([NotNull] PepperParser.EqualContext context) {
            base.ExitEqual(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new Equal(lhs, rhs));
        }

        public override void ExitNotEqual([NotNull] PepperParser.NotEqualContext context) {
            base.ExitNotEqual(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new NotEqual(lhs, rhs));
        }

        public override void ExitAssignment([NotNull] PepperParser.AssignmentContext context) {
            base.ExitAssignment(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new Assign(lhs, rhs));
        }

        public override void ExitAssignmentDigits([NotNull] PepperParser.AssignmentDigitsContext context) {
            base.ExitAssignmentDigits(context);
            var constant = context.DigitSequence();
            if (constant != null) {
                Builder.PushStack(EvalConstant(constant));
            }
        }

        public override void ExitMulAssignment([NotNull] PepperParser.MulAssignmentContext context) {
            base.ExitMulAssignment(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new MulAssign(lhs, rhs));
        }

        public override void ExitTernary([NotNull] PepperParser.TernaryContext context) {
            base.ExitTernary(context);
        }

        //public override void VisitTerminal([NotNull] ITerminalNode node) {
        //    base.VisitTerminal(node);
        //    Log.Info($"{node}");
        //}
    }
}
