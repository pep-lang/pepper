
#include "Compiler/Parser.h"

#include "ANTLRInputStream.h"
#include "Compiler/Codegen.h"
#include "Compiler/Exceptions.h"
#include "PepperBaseListener.h"
#include "PepperLexer.h"
#include "PepperParser.h"

using namespace Pepper::Parser;

class ParserListener : public PepperBaseListener {
    using Super = PepperBaseListener;

  private:
    std::shared_ptr<Codegen> Generator;

  public:
    ParserListener(std::shared_ptr<Codegen> gen)
        : Generator(gen) {}

    void exitVariableSpecifier(
        PepperParser::VariableSpecifierContext* context) override {
        Super::exitVariableSpecifier(context);
        auto identifiers = context->Identifier();
        if(identifiers.size() != 2) {
            throw new CompileError("Expected <type> <identifier> in variable declaration");
        }
        auto typeName = identifiers[0];
        auto identifier = identifiers[1];
    }

    void enterFunctionDefinition(
        PepperParser::FunctionDefinitionContext* context) override {
        Super::enterFunctionDefinition(context);
    }

    void exitFunctionDefinition(
        PepperParser::FunctionDefinitionContext* context) override {
        Super::exitFunctionDefinition(context);
    }

    void exitFunctionCall(PepperParser::FunctionCallContext* context) override {
        Super::exitFunctionCall(context);
    }

    void exitReturn(PepperParser::ReturnContext* context) { Super::exitReturn(context); }

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

    void exitAdd(PepperParser::AddContext* context) override {
        Super::exitAdd(context);
    }

    void exitSub(PepperParser::SubContext* context) override {
        Super::exitSub(context);
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

    void
    exitMulAssignment(PepperParser::MulAssignmentContext* context) override {
        Super::exitMulAssignment(context);
    }

    void
    exitDivAssignment(PepperParser::DivAssignmentContext* context) override {
        Super::exitDivAssignment(context);
    }

    void
    exitModAssignment(PepperParser::ModAssignmentContext* context) override {
        Super::exitModAssignment(context);
    }

    void
    exitAddAssignment(PepperParser::AddAssignmentContext* context) override {
        Super::exitAddAssignment(context);
    }

    void
    exitSubAssignment(PepperParser::SubAssignmentContext* context) override {
        Super::exitSubAssignment(context);
    }

    void exitLShiftAssignment(
        PepperParser::LShiftAssignmentContext* context) override {
        Super::exitLShiftAssignment(context);
    }

    void exitRShiftAssignment(
        PepperParser::RShiftAssignmentContext* context) override {
        Super::exitRShiftAssignment(context);
    }

    void exitBitAndAssignment(
        PepperParser::BitAndAssignmentContext* context) override {
        Super::exitBitAndAssignment(context);
    }

    void exitBitXorAssignment(
        PepperParser::BitXorAssignmentContext* context) override {
        Super::exitBitXorAssignment(context);
    }

    void exitBitOrAssignment(
        PepperParser::BitOrAssignmentContext* context) override {
        Super::exitBitOrAssignment(context);
    }
};

void Parser::parse(std::istream& stream) {
    antlr4::ANTLRInputStream inputStream(stream);
    PepperLexer lexer(&inputStream);
    antlr4::CommonTokenStream tokenStream(&lexer);
    PepperParser parser(&tokenStream);

    antlr4::tree::ParseTree* tree = parser.compilationUnit();
    ParserListener listener(Generator);
    antlr4::tree::ParseTreeWalker::DEFAULT.walk(&listener, tree);
}
