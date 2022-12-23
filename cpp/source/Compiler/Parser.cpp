
#include "Compiler/Parser.h"

#include "ANTLRInputStream.h"
#include "AST/AST.h"
#include "AST/Builder.h"
#include "AST/Nodes.h"
#include "Compiler/Exceptions.h"
#include "Compiler/Type.h"
#include "Param.h"
#include "PepperBaseListener.h"
#include "PepperLexer.h"
#include "PepperParser.h"
#include "llvm/Support/FormatVariadic.h"
#include <utility>

namespace pepper {
    using namespace Pepper::Parser;

    std::string SourceLocation::toString() const {
        return llvm::formatv("{0}:({1})", File, Line);
    }

    class ParserListener : public PepperBaseListener {
        using Super = PepperBaseListener;

        ast::AST ast;
        Ref<ast::Builder> builder;

      public:
        ParserListener() {
            builder = ast.builder();
        }

        void pushStack(Ref<ast::Node> val) {
            builder->pushStack(std::move(val));
        }

        template <typename N> Ref<N> popStack() {
            auto val = builder->popStack();
            if (val->is<N>()) {
                return std::static_pointer_cast<N>(val);
            }
            throw InternalCompilerError("Attempted to pop {} from AST stack, found {} instead",
                                        RTTI::of<N>()->name(),
                                        RTTI::of(*val)->name());
        }

        template <typename N> Ref<N> peekStack(unsigned int idx) {
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
            return {context->start->getInputStream()->getSourceName(), static_cast<int>(context->start->getLine())};
        }

        void exitVariableSpecifier(PepperParser::VariableSpecifierContext* context) override {
            Super::exitVariableSpecifier(context);
            auto identifiers = context->Identifier();
            if (identifiers.size() != 2) {
                throw CompileError(sourceLocation(context), "Expected <type> <identifier> in variable declaration");
            }
            auto typeName = identifiers[0]->toString();
            auto identifier = identifiers[1]->toString();
            auto type = builder->findType(typeName);
            auto decl = Ref<ast::VariableDef>::New(type, identifier);
            builder->variable(decl);
        }

        void enterFunctionDefinition(PepperParser::FunctionDefinitionContext* context) override {
            Super::enterFunctionDefinition(context);
            auto identifier = context->Identifier()->toString();
            auto returnTypeName =
                context->returnType()->Identifier() ? context->returnType()->Identifier()->toString() : "void";
            auto returnType = builder->findType(returnTypeName);
            // TODO: args, pass to FunctionDef
            Params params;
            auto function = builder->create<ast::FunctionDef>(returnType, identifier, params);
            builder->beginFunction(function);
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
            std::vector<Ref<ast::Expression>> args;
            for (int argIdx = 0; argIdx < providedArgsCount; ++argIdx) {
                args.push_back(popStack<ast::Expression>());
            }
            auto call = builder->create<ast::FunctionCall>(func, args);
            builder->expression(call);
            if (func->returnType() != Types::Void) {
                pushStack(call);
            }
        }

        void exitReturn(PepperParser::ReturnContext* context) override {
            Super::exitReturn(context);

            Ref<ast::Expression> returnValue = nullptr;
            if (context->expression()) {
                returnValue = popStack<ast::Expression>();
            }
            auto function = builder->returnTarget();
            builder->expression(Ref<ast::Return>::New(function, returnValue));
        }

        void exitAdd(PepperParser::AddContext* context) override {
            Super::exitAdd(context);
        }

        void exitSub(PepperParser::SubContext* context) override {
            Super::exitSub(context);
        }

        void exitMul(PepperParser::MulContext* context) override {
            Super::exitMul(context);
        }

        void exitDiv(PepperParser::DivContext* context) override {
            Super::exitDiv(context);
        }

        void exitMod(PepperParser::ModContext* context) override {
            Super::exitMod(context);
        }

        void exitPow(PepperParser::PowContext* context) override {
            Super::exitPow(context);
        }

        void exitLShift(PepperParser::LShiftContext* context) override {
            Super::exitLShift(context);
        }

        void exitRShift(PepperParser::RShiftContext* context) override {
            Super::exitRShift(context);
        }

        void exitBitwiseAnd(PepperParser::BitwiseAndContext* context) override {
            Super::exitBitwiseAnd(context);
        }

        void exitBitwiseXor(PepperParser::BitwiseXorContext* context) override {
            Super::exitBitwiseXor(context);
        }

        void exitBitwiseOr(PepperParser::BitwiseOrContext* context) override {
            Super::exitBitwiseOr(context);
        }

        void exitLess(PepperParser::LessContext* context) override {
            Super::exitLess(context);
        }

        void exitLessEqual(PepperParser::LessEqualContext* context) override {
            Super::exitLessEqual(context);
        }

        void exitGreater(PepperParser::GreaterContext* context) override {
            Super::exitGreater(context);
        }

        void exitGreaterEqual(PepperParser::GreaterEqualContext* context) override {
            Super::exitGreaterEqual(context);
        }

        void exitEqual(PepperParser::EqualContext* context) override {
            Super::exitEqual(context);
        }

        void exitNotEqual(PepperParser::NotEqualContext* context) override {
            Super::exitNotEqual(context);
        }

        void exitLogicalAnd(PepperParser::LogicalAndContext* context) override {
            Super::exitLogicalAnd(context);
        }

        void exitLogicalOr(PepperParser::LogicalOrContext* context) override {
            Super::exitLogicalOr(context);
        }

        void exitTernary(PepperParser::TernaryContext* context) override {
            Super::exitTernary(context);
        }

        void exitAssignment(PepperParser::AssignmentContext* context) override {
            Super::exitAssignment(context);
        }

        void exitMulAssignment(PepperParser::MulAssignmentContext* context) override {
            Super::exitMulAssignment(context);
        }

        void exitDivAssignment(PepperParser::DivAssignmentContext* context) override {
            Super::exitDivAssignment(context);
        }

        void exitModAssignment(PepperParser::ModAssignmentContext* context) override {
            Super::exitModAssignment(context);
        }

        void exitAddAssignment(PepperParser::AddAssignmentContext* context) override {
            Super::exitAddAssignment(context);
        }

        void exitSubAssignment(PepperParser::SubAssignmentContext* context) override {
            Super::exitSubAssignment(context);
        }

        void exitLShiftAssignment(PepperParser::LShiftAssignmentContext* context) override {
            Super::exitLShiftAssignment(context);
        }

        void exitRShiftAssignment(PepperParser::RShiftAssignmentContext* context) override {
            Super::exitRShiftAssignment(context);
        }

        void exitBitAndAssignment(PepperParser::BitAndAssignmentContext* context) override {
            Super::exitBitAndAssignment(context);
        }

        void exitBitXorAssignment(PepperParser::BitXorAssignmentContext* context) override {
            Super::exitBitXorAssignment(context);
        }

        void exitBitOrAssignment(PepperParser::BitOrAssignmentContext* context) override {
            Super::exitBitOrAssignment(context);
        }
    };

    void Parser::parse(std::istream& stream, const std::string& name) {
        antlr4::ANTLRInputStream inputStream(stream);
        inputStream.name = name;
        PepperLexer lexer(&inputStream);
        antlr4::CommonTokenStream tokenStream(&lexer);
        PepperParser parser(&tokenStream);

        antlr4::tree::ParseTree* tree = parser.compilationUnit();
        ParserListener listener;
        antlr4::tree::ParseTreeWalker::DEFAULT.walk(&listener, tree);
    }

} // namespace pepper
