using Pepper.AST;
using Antlr4.Runtime.Tree;
using Antlr4.Runtime.Misc;
using Antlr4.Runtime;
using Pepper.ANTLR;
using Pepper.Codegen;

namespace Pepper {
    internal class Parser : PepperBaseListener {
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
                Trace = true,
                ErrorHandler = new BailErrorStrategy(),
            };

            try {
                var tree = parser.compilationUnit();
                ParseTreeWalker.Default.Walk(this, tree);
                //Log.Info(FormatAntlrTree(tree.ToStringTree(parser)));
            } catch (ParseCanceledException pcex) {
                if (pcex.InnerException is InputMismatchException imex) {
                    var sourceLocation = new SourceLocation(imex.OffendingToken.TokenSource.SourceName, imex.OffendingToken.Line, imex.OffendingToken.Column);
                    throw new CompileError($"Unexpected token \"{imex.OffendingToken.Text}\"", sourceLocation);
                }
                if (pcex.InnerException is NoViableAltException nva) {
                    var sourceLocation = new SourceLocation(nva.OffendingToken.TokenSource.SourceName, nva.OffendingToken.Line, nva.OffendingToken.Column);
                    throw new CompileError($"Parse failure at \"{nva.OffendingToken.Text}\"", sourceLocation);
                }
                throw new CompileError($"Parse error: {pcex.Message}", SourceLocation.Current);
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
            throw new CompileError($"Unable to parse numeric constant '{constant}'", SourceLocation.Current);
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
                throw new CompileError($"Unknown return type {returnType}", SourceLocation.Current);
            }
            var paramList = context.parameterList();
            IEnumerable<FunctionDef.Parameter> parameters = new List<FunctionDef.Parameter>();
            if (paramList != null) {
                var paramDecls = paramList.parameterDeclaration();
                parameters = paramDecls.Select(p => {
                    var identifiers = p.Identifier().Select(i => i.ToString()!).ToArray();
                    (var typeName, var paramName) = (identifiers[0], identifiers[1]);
                    Expression? defaultValue = null;
                    if (p.Assign() != null) {
                        defaultValue = Builder.PopStack<Expression>();
                    }
                    var type = Context.Locals.GetType(typeName);
                    if (type == null) {
                        throw new CompileError($"Unknown type {typeName}", SourceLocation.Current);
                    }
                    var param = new FunctionDef.Parameter(type, paramName);
                    return new FunctionDef.Parameter(type, paramName, defaultValue);
                }).ToList();
            }
            // Start new function scope
            var func = Builder.StructTarget != null ? new MethodDef(Builder.StructTarget, identifier, returnType, parameters) : new FunctionDef(identifier, returnType, parameters);
            Builder.BeginFunction(func);
            // Add all params
            foreach (var param in parameters) {
                Builder.NewSymbol(param);
            }
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
                throw new CompileError($"Unable to resolve function {identifier}", SourceLocation.Current);
            }
            var providedArgsCount = context.argumentExpressionList()?.assignmentExpression().Length ?? 0;
            var args = new List<Expression>();
            for (int argIdx = 0; argIdx < providedArgsCount; ++argIdx) {
                args.Add(Builder.PopStack<Expression>());
            }
            var result = new FunctionCall(func, args);
            Builder.NewExpression(result);
        }

        public override void ExitReturn([NotNull] PepperParser.ReturnContext context) {
            base.ExitReturn(context);

            if (context.expression() != null) {
                var returnValue = Builder.PopStack<Expression>();
                var func = Builder.FunctionTarget!;
                Builder.NewExpression(new Return(func, returnValue));
            }
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
                var symbol = Builder.FindSymbol(identifier);
                if (symbol == null) {
                    throw new CompileError($"Unable to find symbol {identifier}", SourceLocation.Current);
                }
                var variable = new VariableRef(identifier, symbol);
                Builder.PushStack(variable);
                return;
            }
        }

        public override void ExitVariableSpecifier([NotNull] PepperParser.VariableSpecifierContext context) {
            base.ExitVariableSpecifier(context);
            if (context.Identifier().Length != 2) {
                throw new CompileError("Expected <type> <name> while parsing variable declaration", SourceLocation.Current);
            }
            var identifiers = context.Identifier().Select(i => i.ToString()!).ToArray();
            (var typeName, var varName) = (identifiers[0], identifiers[1]);
            var type = Builder.FindType(typeName);
            if (type == null) {
                throw new CompileError($"Unknown type {typeName}", SourceLocation.Current);
            }
            var initialValue = Builder.PopStack<Expression>();
            if (Builder.StructTarget != null) {
                Builder.NewSymbol(new FieldDef(Builder.StructTarget, type, varName, initialValue));
            } else {
                Builder.NewSymbol(new VariableDef(type, varName, initialValue));
            }
        }

        public override void EnterStructDeclaration([NotNull] PepperParser.StructDeclarationContext context) {
            base.EnterStructDeclaration(context);

            var name = context.Identifier().ToString()!;
            var structDef = new StructDef(name);
            Builder.BeginStruct(structDef);
        }

        public override void ExitStructDeclaration([NotNull] PepperParser.StructDeclarationContext context) {
            base.ExitStructDeclaration(context);

            Builder.EndStruct();
        }

        public override void ExitMemberAccess([NotNull] PepperParser.MemberAccessContext context) {
            base.ExitMemberAccess(context);
            var lhs = Builder.PopStack<Expression>();
            var rhs = context.Identifier()!.ToString()!;
            var structType = ((PointerType)lhs.Type).Pointee;
            var structDef = Builder.FindSymbol(structType.Name)!.Cast<StructDef>();
            var type = structDef.Fields.Find(f => f.Name == rhs)!.Type;
            Builder.NewExpression(new MemberRef(type, lhs, rhs));
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

        public override void ExitDivAssignment([NotNull] PepperParser.DivAssignmentContext context) {
            base.ExitDivAssignment(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new DivAssign(lhs, rhs));
        }

        public override void ExitModAssignment([NotNull] PepperParser.ModAssignmentContext context) {
            base.ExitModAssignment(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new ModAssign(lhs, rhs));
        }

        public override void ExitLShiftAssignment([NotNull] PepperParser.LShiftAssignmentContext context) {
            base.ExitLShiftAssignment(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new LShiftAssign(lhs, rhs));
        }

        public override void ExitRShiftAssignment([NotNull] PepperParser.RShiftAssignmentContext context) {
            base.ExitRShiftAssignment(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new RShiftAssign(lhs, rhs));
        }

        public override void ExitBitAndAssignment([NotNull] PepperParser.BitAndAssignmentContext context) {
            base.ExitBitAndAssignment(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new BitAndAssign(lhs, rhs));
        }

        public override void ExitBitOrAssignment([NotNull] PepperParser.BitOrAssignmentContext context) {
            base.ExitBitOrAssignment(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new BitOrAssign(lhs, rhs));
        }

        public override void ExitBitXorAssignment([NotNull] PepperParser.BitXorAssignmentContext context) {
            base.ExitBitXorAssignment(context);
            var rhs = Builder.PopStack<Expression>();
            var lhs = Builder.PopStack<Expression>();
            Builder.NewExpression(new BitXorAssign(lhs, rhs));
        }

        public override void ExitTernary([NotNull] PepperParser.TernaryContext context) {
            base.ExitTernary(context);
        }

        public override void VisitTerminal([NotNull] ITerminalNode node) {
            base.VisitTerminal(node);
            SourceLocation.Current = new SourceLocation(node.Symbol.TokenSource.SourceName, node.Symbol.Line, node.Symbol.Column);
        }
    }
}
