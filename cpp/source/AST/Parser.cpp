
#include "Parser.h"
#include <utility>

#include "ANTLRInputStream.h"
#include "AST/AST.h"
#include "AST/Builder.h"
#include "AST/Nodes.h"
#include "AST/Param.h"
#include "Compiler/Compiler.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "PepperBaseListener.h"
#include "PepperLexer.h"
#include "PepperParser.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper {
    using namespace Pepper::Parser;
    using namespace pepper::ast;

    std::string SourceLocation::toString() const {
        return llvm::formatv("{0}({1},{2})", File, Line, Column);
    }

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

        void pushStack(Ref<Node> val) {
            builder->pushStack(std::move(val));
        }

        template <typename N>
        Ref<N> popStack() {
            auto val = builder->popStack();
            if (val->is<N>()) {
                return std::static_pointer_cast<N>(val);
            }
            throw InternalCompilerError(
                "Attempted to pop {} from AST stack, found {} instead", RTTI::of<N>()->name(), RTTI::of(*val)->name());
        }

        template <typename N>
        Ref<N> peekStack(unsigned int idx) {
            auto val = builder->peekStack(idx);
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

        void visitTerminal(antlr4::tree::TerminalNode* terminal) override {
            Super::visitTerminal(terminal);
        }

        Ref<Expression> evalNumericConstant(antlr4::tree::TerminalNode* constant) {
            auto value = constant->toString();
            try {
                auto intVal = std::stoll(value);
                return Ref<IntegerLiteral>::New(intVal);
            } catch (std::invalid_argument) {
            }
            try {
                auto floatVal = std::stold(value);
                return Ref<FloatLiteral>::New(floatVal);
            } catch (std::invalid_argument) {
            }
            throw CompileError("Unable to parse numeric literal: {0}", value);
        }

        void exitVariableSpecifier(PepperParser::VariableSpecifierContext* context) override {
            Super::exitVariableSpecifier(context);
            auto identifiers = context->Identifier();
            if (identifiers.size() != 2) {
                throw CompileError(sourceLocation(context), "Expected <type> <identifier> in variable declaration");
            }
            auto typeName = identifiers[0]->toString();
            auto identifier = identifiers[1]->toString();

            if (builder->structTarget()) {
                builder->symbol(Ref<FieldDef>::New(builder->structTarget(), typeName, identifier));
            } else {
                auto defaultValue = (context->assignmentExpression()) ? popStack<Expression>() : nullptr;
                builder->symbol(Ref<VariableDef>::New(typeName, identifier, defaultValue));
            }
        }

        void exitPrimaryExpression(PepperParser::PrimaryExpressionContext* context) override {
            Super::exitPrimaryExpression(context);
            auto constant = context->Constant();
            if (constant) {
                builder->pushStack(evalNumericConstant(constant));
                return;
            }
            auto stringLiterals = context->StringLiteral();
            if (stringLiterals.size()) {
                std::string strVal = "";
                std::for_each(
                    stringLiterals.begin(), stringLiterals.end(), [&strVal](auto str) { strVal += str->toString(); });
                builder->pushStack(Ref<StringLiteral>::New(strVal));
                return;
            }
            auto ident = context->Identifier();
            if (ident) {
                auto identifier = ident->toString();
                builder->pushStack(Ref<VariableRef>::New(identifier));
                return;
            }
        }

        void enterFunctionDefinition(PepperParser::FunctionDefinitionContext* context) override {
            Super::enterFunctionDefinition(context);
            auto identifier = context->Identifier()->toString();
            auto returnType =
                context->returnType()->Identifier() ? context->returnType()->Identifier()->toString() : "void";
            // TODO: args, pass to FunctionDef
            Params params;
            if (auto paramList = context->parameterList()) {
                auto paramDecls = paramList->parameterDeclaration();
                std::for_each(paramDecls.begin(), paramDecls.end(), [&](auto p) {
                    auto identifiers = p->Identifier();
                    auto typeName = identifiers[0]->toString();
                    auto paramName = identifiers[1]->toString();
                    Ref<Expression> defaultValue;
                    if (p->Assign()) {
                        defaultValue = builder->popStack();
                    }
                    params.emplace_back(paramName, typeName, defaultValue);
                });
            }

            auto function = builder->create<FunctionDef>(returnType, identifier, params);
            builder->beginFunction(function);
            for (auto& param : params) {
                builder->symbol(Ref<VariableDef>::New(param.Type, param.Identifier));
            }
        }

        void exitFunctionDefinition(PepperParser::FunctionDefinitionContext* context) override {
            Super::exitFunctionDefinition(context);
            builder->endFunction();
        }

        void exitFunctionCall(PepperParser::FunctionCallContext* context) override {
            Super::exitFunctionCall(context);
            auto identifier = context->Identifier()->toString();
            auto func = builder->findFunction(identifier);
            auto providedArgsCount = context->argumentExpressionList()->assignmentExpression().size();
            std::vector<Ref<Expression>> args;
            for (int argIdx = 0; argIdx < providedArgsCount; ++argIdx) {
                args.push_back(popStack<Expression>());
            }
            auto call = builder->create<FunctionCall>(func, args);
            builder->expression(call);
            if (func->returnType() != "void") {
                pushStack(call);
            }
        }

        void exitReturn(PepperParser::ReturnContext* context) override {
            Super::exitReturn(context);

            Ref<Expression> returnValue = nullptr;
            if (context->expression()) {
                returnValue = popStack<Expression>();
            }
            auto function = builder->functionTarget();
            builder->expression(Ref<Return>::New(function, returnValue));
        }

        void enterStructDeclaration(PepperParser::StructDeclarationContext* context) override {
            Super::enterStructDeclaration(context);
            auto identifier = context->Identifier()->toString();
            auto structDef = Ref<StructDef>::New(identifier, identifier);
            builder->beginStruct(structDef);
        }

        void exitStructDeclaration(PepperParser::StructDeclarationContext* context) override {
            Super::exitStructDeclaration(context);
            builder->endStruct();
        }

        void exitMemberAccess(PepperParser::MemberAccessContext* context) override {
            Super::exitMemberAccess(context);
            auto lhs = popStack<Expression>();
            auto rhs = context->Identifier()->toString();
            builder->expression(Ref<MemberRef>::New(lhs, rhs));
        }

        void exitAdd(PepperParser::AddContext* context) override {
            Super::exitAdd(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<Add>::New(lhs, rhs));
        }

        void exitSub(PepperParser::SubContext* context) override {
            Super::exitSub(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<Sub>::New(lhs, rhs));
        }

        void exitMul(PepperParser::MulContext* context) override {
            Super::exitMul(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<Mul>::New(lhs, rhs));
        }

        void exitDiv(PepperParser::DivContext* context) override {
            Super::exitDiv(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<Div>::New(lhs, rhs));
        }

        void exitMod(PepperParser::ModContext* context) override {
            Super::exitMod(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<Mod>::New(lhs, rhs));
        }

        void exitPow(PepperParser::PowContext* context) override {
            Super::exitPow(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<Pow>::New(lhs, rhs));
        }

        void exitLShift(PepperParser::LShiftContext* context) override {
            Super::exitLShift(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<LShift>::New(lhs, rhs));
        }

        void exitRShift(PepperParser::RShiftContext* context) override {
            Super::exitRShift(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<RShift>::New(lhs, rhs));
        }

        void exitBitwiseAnd(PepperParser::BitwiseAndContext* context) override {
            Super::exitBitwiseAnd(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<BitAnd>::New(lhs, rhs));
        }

        void exitBitwiseXor(PepperParser::BitwiseXorContext* context) override {
            Super::exitBitwiseXor(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<BitXor>::New(lhs, rhs));
        }

        void exitBitwiseOr(PepperParser::BitwiseOrContext* context) override {
            Super::exitBitwiseOr(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<BitOr>::New(lhs, rhs));
        }

        void exitLess(PepperParser::LessContext* context) override {
            Super::exitLess(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<Less>::New(lhs, rhs));
        }

        void exitLessEqual(PepperParser::LessEqualContext* context) override {
            Super::exitLessEqual(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<LessEqual>::New(lhs, rhs));
        }

        void exitGreater(PepperParser::GreaterContext* context) override {
            Super::exitGreater(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<Greater>::New(lhs, rhs));
        }

        void exitGreaterEqual(PepperParser::GreaterEqualContext* context) override {
            Super::exitGreaterEqual(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<GreaterEqual>::New(lhs, rhs));
        }

        void exitEqual(PepperParser::EqualContext* context) override {
            Super::exitEqual(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<Equal>::New(lhs, rhs));
        }

        void exitNotEqual(PepperParser::NotEqualContext* context) override {
            Super::exitNotEqual(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<NotEqual>::New(lhs, rhs));
        }

        void exitLogicalAnd(PepperParser::LogicalAndContext* context) override {
            Super::exitLogicalAnd(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<LogicalAnd>::New(lhs, rhs));
        }

        void exitLogicalOr(PepperParser::LogicalOrContext* context) override {
            Super::exitLogicalOr(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<LogicalOr>::New(lhs, rhs));
        }

        void exitTernary(PepperParser::TernaryContext* context) override {
            Super::exitTernary(context);
        }

        void exitAssignment(PepperParser::AssignmentContext* context) override {
            Super::exitAssignment(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<Assign>::New(lhs, rhs));
        }

        void exitMulAssignment(PepperParser::MulAssignmentContext* context) override {
            Super::exitMulAssignment(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<MulAssign>::New(lhs, rhs));
        }

        void exitDivAssignment(PepperParser::DivAssignmentContext* context) override {
            Super::exitDivAssignment(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<DivAssign>::New(lhs, rhs));
        }

        void exitModAssignment(PepperParser::ModAssignmentContext* context) override {
            Super::exitModAssignment(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<ModAssign>::New(lhs, rhs));
        }

        void exitAddAssignment(PepperParser::AddAssignmentContext* context) override {
            Super::exitAddAssignment(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<AddAssign>::New(lhs, rhs));
        }

        void exitSubAssignment(PepperParser::SubAssignmentContext* context) override {
            Super::exitSubAssignment(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<SubAssign>::New(lhs, rhs));
        }

        void exitLShiftAssignment(PepperParser::LShiftAssignmentContext* context) override {
            Super::exitLShiftAssignment(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<LShiftAssign>::New(lhs, rhs));
        }

        void exitRShiftAssignment(PepperParser::RShiftAssignmentContext* context) override {
            Super::exitRShiftAssignment(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<RShiftAssign>::New(lhs, rhs));
        }

        void exitBitAndAssignment(PepperParser::BitAndAssignmentContext* context) override {
            Super::exitBitAndAssignment(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<BitAndAssign>::New(lhs, rhs));
        }

        void exitBitXorAssignment(PepperParser::BitXorAssignmentContext* context) override {
            Super::exitBitXorAssignment(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<BitXorAssign>::New(lhs, rhs));
        }

        void exitBitOrAssignment(PepperParser::BitOrAssignmentContext* context) override {
            Super::exitBitOrAssignment(context);
            auto rhs = popStack<Expression>();
            auto lhs = popStack<Expression>();
            builder->expression(Ref<BitOrAssign>::New(lhs, rhs));
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
        Messages::Report<Error>(src, "{0} \"{1}\", expected \"{2}\"", prefix, text, expected);
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
