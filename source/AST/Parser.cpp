
#include "Parser.h"
#include <utility>

#include "ANTLRInputStream.h"
#include "AST/AST.h"
#include "AST/Builder.h"
#include "AST/Nodes.h"
#include "AST/Param.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "PepperBaseListener.h"
#include "PepperLexer.h"
#include "PepperParser.h"

namespace pepper {
    using namespace Pepper::Parser;
    using namespace pepper::ast;

    class ParserListener : public PepperBaseListener {
        using Super = PepperBaseListener;

        Ref<AST> Tree;
        Ref<Builder> builder;

      public:
        ParserListener()
            : Tree(Ref<AST>::New()) {
            builder = Tree->builder();
        }

        Ref<AST> ast() const {
            return Tree;
        }

        void lvaluePush(Ref<Node> val) {
            // std::cout << "lpush: " << val->toString() << std::endl;
            builder->pushLValue(std::move(val));
        }

        template <typename N>
        Ref<N> lvaluePop() {
            auto val = builder->popLValue();
            // std::cout << "lpop:  " << (val ? val->toString() : "null") << std::endl;
            if (val->is<N>()) {
                return std::static_pointer_cast<N>(val);
            }
            throw InternalCompilerError(
                "Attempted to pop {} from AST stack, found {} instead", RTTI::of<N>()->name(), RTTI::of(*val)->name());
        }

        template <typename N>
        Ref<N> lvaluePeek(unsigned int idx = 0) {
            auto val = builder->peekLValue(idx);
            if (val && val->is<N>()) {
                return std::static_pointer_cast<N>(val);
            }
            return nullptr;
        }

        void rvaluePush(Ref<Node> val) {
            // Only bother tracking this rvalue if there is an l-value on the stack to receive it
            if (lvaluePeek<Node>())
                builder->pushRValue(std::move(val));
        }

        template <typename N>
        Ref<N> rvaluePop() {
            auto val = builder->popRValue();
            if (val->is<N>()) {
                return std::static_pointer_cast<N>(val);
            }
            throw InternalCompilerError(
                "Attempted to pop {} from AST stack, found {} instead", RTTI::of<N>()->name(), RTTI::of(*val)->name());
        }

        template <typename N>
        Ref<N> rvaluePeek(unsigned int idx) {
            auto val = builder->peekRValue(idx);
            if (val->is<N>()) {
                return std::static_pointer_cast<N>(val);
            }
            throw InternalCompilerError("Attempted to peek a {} in AST stack at slot {}, found {} instead",
                                        RTTI::of<N>()->name(),
                                        idx,
                                        RTTI::of(*val)->name());
        }

        static SourceLocation sourceLocation(const antlr4::ParserRuleContext* context) {
            return {
                context->start->getInputStream()->getSourceName(),
                context->start->getLine(),
                context->start->getCharPositionInLine(),
            };
        }

        void recordSourceLocation(const antlr4::ParserRuleContext* context) {
            builder->Source = sourceLocation(context);
        }

        void enterEveryRule(antlr4::ParserRuleContext* context) override {
            recordSourceLocation(context);
        }

        void exitEveryRule(antlr4::ParserRuleContext* context) override {
            recordSourceLocation(context);
        }

        void visitTerminal(antlr4::tree::TerminalNode* terminal) override {
            Super::visitTerminal(terminal);
        }

        Ref<Expression> evalNumericConstant(antlr4::tree::TerminalNode* constant) {
            auto value = constant->toString();
            try {
                auto intVal = std::stoll(value);
                return builder->New<IntegerLiteral>(intVal);
            } catch (std::invalid_argument) {
            }
            try {
                auto floatVal = std::stold(value);
                return builder->New<FloatLiteral>(floatVal);
            } catch (std::invalid_argument) {
            }
            throw CompileError("Unable to parse numeric literal: {0}", value);
        }

        void enterVariableSpecifier(PepperParser::VariableSpecifierContext* context) override {
            auto identifiers = context->Identifier();
            if (identifiers.size() != 2) {
                throw CompileError(sourceLocation(context), "Expected <type> <identifier> in variable declaration");
            }
            auto typeName = identifiers[0]->toString();
            auto identifier = identifiers[1]->toString();

            if (builder->structTarget()) {
                lvaluePush(builder->New<FieldDef>(builder->structTarget(), typeName, identifier));
            } else {
                lvaluePush(builder->New<VariableDef>(typeName, identifier));
            }
        }

        void exitVariableSpecifier(PepperParser::VariableSpecifierContext* context) override {
            auto symbol = lvaluePop<VariableDef>();
            if (context->assignmentExpression()) {
                auto defaultValue = rvaluePop<Expression>();
                symbol->setDefaultValue(defaultValue);
            }

            builder->symbol(symbol);
        }

        void exitPrimaryExpression(PepperParser::PrimaryExpressionContext* context) override {
            auto constant = context->Constant();
            if (constant) {
                rvaluePush(evalNumericConstant(constant));
                return;
            }
            auto stringLiterals = context->StringLiteral();
            if (stringLiterals.size()) {
                std::string strVal = "";
                std::for_each(
                    stringLiterals.begin(), stringLiterals.end(), [&strVal](auto str) { strVal += str->toString(); });
                rvaluePush(builder->New<StringLiteral>(strVal));
                return;
            }
            auto ident = context->Identifier();
            if (ident) {
                auto identifier = ident->toString();
                rvaluePush(builder->New<VariableRef>(identifier));
                return;
            }
        }

        void enterFunctionDefinition(PepperParser::FunctionDefinitionContext* context) override {
            auto identifier = context->Identifier()->toString();
            auto returnType =
                context->returnType()->Identifier() ? context->returnType()->Identifier()->toString() : "void";
            // TODO: args, pass to FunctionDef
            Params params;
            if (auto paramList = context->parameterList()) {
                auto paramDecls = paramList->parameterDeclaration();
                params = Query(paramDecls).select<Param>([&](auto p) {
                    auto identifiers = p->Identifier();
                    auto typeName = identifiers[0]->toString();
                    auto paramName = identifiers[1]->toString();
                    return Param{paramName, typeName};
                });
            }

            auto function = builder->New<FunctionDef>(returnType, identifier, params);
            lvaluePush(function);
            builder->beginFunction(function);
        }

        void exitFunctionDefinition(PepperParser::FunctionDefinitionContext* context) override {
            builder->endFunction();
            // for each default value, fill them in from computed rvalues
            auto function = lvaluePop<FunctionDef>();
            if (auto paramsList = context->parameterList()) {
                auto paramDecls = paramsList->parameterDeclaration();
                int idx = 0;
                Query(paramDecls).each([&](auto p) {
                    if (p->Assign()) {
                        function->params()[idx].Default = rvaluePop<Expression>();
                    }
                    ++idx;
                });
            }
        }

        void exitFunctionCall(PepperParser::FunctionCallContext* context) override {
            auto identifier = context->Identifier()->toString();
            auto func = builder->findFunction(identifier);
            auto providedArgsCount = context->argumentExpressionList()
                                         ? context->argumentExpressionList()->assignmentExpression().size()
                                         : 0;
            Vector<Ref<Expression>> args;
            for (int argIdx = 0; argIdx < providedArgsCount; ++argIdx) {
                args.insert(args.begin(), rvaluePop<Expression>());
            }
            auto call = builder->New<FunctionCall>(func, args);
            builder->expression(call);
        }

        void enterReturn(PepperParser::ReturnContext* context) override {
            auto function = builder->functionTarget();
            auto ret = builder->New<Return>(function);
            lvaluePush(ret);
        }

        void exitReturn(PepperParser::ReturnContext* context) override {
            auto ret = lvaluePop<Return>();
            if (context->expression()) {
                auto returnValue = rvaluePop<Expression>();
                ret->setValue(returnValue);
            }
            builder->expression(ret);
        }

        void enterStructDeclaration(PepperParser::StructDeclarationContext* context) override {
            auto identifier = context->Identifier()->toString();
            auto structDef = StructDef::New(identifier, identifier);
            builder->beginStruct(structDef);
        }

        void exitStructDeclaration(PepperParser::StructDeclarationContext* context) override {
            builder->endStruct();
        }

        void exitMemberAccess(PepperParser::MemberAccessContext* context) override {
            auto lhs = rvaluePop<Expression>();
            auto rhs = context->Identifier()->toString();
            builder->expression(builder->New<MemberRef>(lhs, rhs));
        }

        void enterSelectionStatement(PepperParser::SelectionStatementContext* context) override {
            auto branch = builder->New<If>();
            if (context->ifStatement()) {
                branch->thenBlock() = builder->New<Block>(branch, "then");
            }
            if (context->elseStatement()) {
                branch->elseBlock() = builder->New<Block>(branch, "else");
            }
            builder->beginScope("select");
            lvaluePush(branch);
        }

        void exitSelectionStatement(PepperParser::SelectionStatementContext* context) override {
            auto branch = lvaluePop<Branch>();
            builder->endScope();
            builder->expression(branch);
        }

        void enterIfStatement(PepperParser::IfStatementContext* context) override {
        }

        void exitIfStatement(PepperParser::IfStatementContext* context) override {
            builder->endBlock();
        }

        void exitCondition(PepperParser::ConditionContext* context) override {
            auto branch = lvaluePeek<Branch>();
            branch->Condition = rvaluePop<Expression>();
        }

        void exitIfCondition(PepperParser::IfConditionContext* context) override {
            auto branch = lvaluePeek<Branch>();
            builder->beginBlock(branch->thenBlock());
        }

        void enterElseStatement(PepperParser::ElseStatementContext* context) override {
            auto branch = lvaluePeek<Branch>();
            builder->beginBlock(branch->elseBlock());
        }

        void exitElseStatement(PepperParser::ElseStatementContext* context) override {
            builder->endBlock();
        }

        void exitAdd(PepperParser::AddContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<Add>(lhs, rhs));
        }

        void exitSub(PepperParser::SubContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<Sub>(lhs, rhs));
        }

        void exitMul(PepperParser::MulContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<Mul>(lhs, rhs));
        }

        void exitDiv(PepperParser::DivContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<Div>(lhs, rhs));
        }

        void exitMod(PepperParser::ModContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<Mod>(lhs, rhs));
        }

        void exitPow(PepperParser::PowContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<Pow>(lhs, rhs));
        }

        void exitLShift(PepperParser::LShiftContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<LShift>(lhs, rhs));
        }

        void exitRShift(PepperParser::RShiftContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<RShift>(lhs, rhs));
        }

        void exitBitwiseAnd(PepperParser::BitwiseAndContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<BitAnd>(lhs, rhs));
        }

        void exitBitwiseXor(PepperParser::BitwiseXorContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<BitXor>(lhs, rhs));
        }

        void exitBitwiseOr(PepperParser::BitwiseOrContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<BitOr>(lhs, rhs));
        }

        void exitLess(PepperParser::LessContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<Less>(lhs, rhs));
        }

        void exitLessEqual(PepperParser::LessEqualContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<LessEqual>(lhs, rhs));
        }

        void exitGreater(PepperParser::GreaterContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<Greater>(lhs, rhs));
        }

        void exitGreaterEqual(PepperParser::GreaterEqualContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<GreaterEqual>(lhs, rhs));
        }

        void exitEqual(PepperParser::EqualContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<Equal>(lhs, rhs));
        }

        void exitNotEqual(PepperParser::NotEqualContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<NotEqual>(lhs, rhs));
        }

        void exitLogicalAnd(PepperParser::LogicalAndContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<LogicalAnd>(lhs, rhs));
        }

        void exitLogicalOr(PepperParser::LogicalOrContext* context) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePush(builder->New<LogicalOr>(lhs, rhs));
        }

        void exitTernary(PepperParser::TernaryContext* context) override {
        }

        template <typename Op>
        void beginAssign() {
            auto op = builder->New<Op>();
            lvaluePush(op);
        }

        template <typename Op>
        void endAssign() {
            auto op = lvaluePop<Op>();
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            builder->expression(builder->New<Op>(lhs, rhs));
        }

        void enterAssignment(PepperParser::AssignmentContext* context) override {
            beginAssign<Assign>();
        }

        void exitAssignment(PepperParser::AssignmentContext* context) override {
            endAssign<Assign>();
        }

        void enterMulAssignment(PepperParser::MulAssignmentContext* context) override {
            beginAssign<MulAssign>();
        }

        void exitMulAssignment(PepperParser::MulAssignmentContext* context) override {
            endAssign<MulAssign>();
        }

        void enterDivAssignment(PepperParser::DivAssignmentContext* context) override {
            beginAssign<DivAssign>();
        }

        void exitDivAssignment(PepperParser::DivAssignmentContext* context) override {
            endAssign<DivAssign>();
        }

        void enterModAssignment(PepperParser::ModAssignmentContext* context) override {
            beginAssign<ModAssign>();
        }

        void exitModAssignment(PepperParser::ModAssignmentContext* context) override {
            endAssign<ModAssign>();
        }

        void enterAddAssignment(PepperParser::AddAssignmentContext* context) override {
            beginAssign<AddAssign>();
        }

        void exitAddAssignment(PepperParser::AddAssignmentContext* context) override {
            endAssign<AddAssign>();
        }

        void enterSubAssignment(PepperParser::SubAssignmentContext* context) override {
            beginAssign<SubAssign>();
        }

        void exitSubAssignment(PepperParser::SubAssignmentContext* context) override {
            endAssign<SubAssign>();
        }

        void enterLShiftAssignment(PepperParser::LShiftAssignmentContext* context) override {
            beginAssign<LShiftAssign>();
        }

        void exitLShiftAssignment(PepperParser::LShiftAssignmentContext* context) override {
            endAssign<LShiftAssign>();
        }

        void enterRShiftAssignment(PepperParser::RShiftAssignmentContext* context) override {
            beginAssign<RShiftAssign>();
        }

        void exitRShiftAssignment(PepperParser::RShiftAssignmentContext* context) override {
            endAssign<RShiftAssign>();
        }

        void enterBitAndAssignment(PepperParser::BitAndAssignmentContext* context) override {
            beginAssign<BitAndAssign>();
        }

        void exitBitAndAssignment(PepperParser::BitAndAssignmentContext* context) override {
            endAssign<BitAndAssign>();
        }

        void enterBitXorAssignment(PepperParser::BitXorAssignmentContext* context) override {
            beginAssign<BitXorAssign>();
        }

        void exitBitXorAssignment(PepperParser::BitXorAssignmentContext* context) override {
            endAssign<BitXorAssign>();
        }

        void enterBitOrAssignment(PepperParser::BitOrAssignmentContext* context) override {
            beginAssign<BitOrAssign>();
        }

        void exitBitOrAssignment(PepperParser::BitOrAssignmentContext* context) override {
            endAssign<BitOrAssign>();
        }
    };

    static void reportError(const antlr4::RecognitionException& rex, const std::string& prefix) {
        auto src = SourceLocation{
            rex.getOffendingToken()->getTokenSource()->getSourceName(),
            rex.getOffendingToken()->getLine(),
            rex.getOffendingToken()->getCharPositionInLine(),
        };
        auto text = rex.getOffendingToken()->getText();
        auto expected = rex.getExpectedTokens().toString();
        throw CompileError(src, "{0} \"{1}\", expected \"{2}\"", prefix, text, expected);
    }

    Ref<AST> Parser::parse(std::istream& stream, const std::string& name) {
        antlr4::ANTLRInputStream inputStream(stream);
        inputStream.name = name;
        PepperLexer lexer(&inputStream);
        antlr4::CommonTokenStream tokenStream(&lexer);
        PepperParser parser(&tokenStream);
        parser.setBuildParseTree(true);
        parser.setErrorHandler(std::make_shared<antlr4::BailErrorStrategy>());
        // parser.setTrace(true);

        try {
            antlr4::tree::ParseTree* tree = parser.compilationUnit();
            ParserListener listener;
            antlr4::tree::ParseTreeWalker::DEFAULT.walk(&listener, tree);

            return listener.ast();
        } catch (const antlr4::ParseCancellationException& pex) {
            try {
                std::rethrow_if_nested(pex);
                Messages::Report<Error>(pex.what());
            } catch (const antlr4::InputMismatchException& ime) {
                reportError(ime, "Unexpected token: ");
            } catch (const antlr4::NoViableAltException& nva) {
                reportError(nva, "Parse failure at: ");
            }
        }
        return nullptr;
    }

} // namespace pepper
