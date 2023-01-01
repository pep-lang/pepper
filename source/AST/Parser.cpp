
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
            // unwrap pending node if found
            if (val->is<Pending>() && val.as<Pending>()->Type->is(RTTI::of<N>()))
                return val.as<Pending>()->Value.as<N>();
            // std::cout << "lpop:  " << (val ? val->toString() : "null") << std::endl;
            if (val->is<N>()) {
                return std::static_pointer_cast<N>(val);
            }
            throw InternalCompilerError("Attempted to pop {0} from AST l-value stack, found {1} instead",
                                        RTTI::of<N>()->name(),
                                        RTTI::of(*val)->name());
        }

        template <typename N>
        Ref<N> lvaluePeek(unsigned int idx = 0) {
            auto val = builder->peekLValue(idx);
            // unwrap pending node if found
            if constexpr (!std::is_same_v<N, Pending>) {
                if (val && val->is<Pending>() && val.as<Pending>()->Type->is(RTTI::of<N>()))
                    return val.as<Pending>()->Value.as<N>();
            }
            if (val && val->is<N>()) {
                return std::static_pointer_cast<N>(val);
            }
            return nullptr;
        }

        void rvaluePush(Ref<Node> val) {
            // Only bother tracking this rvalue if there is a pending l-value on the stack to receive it
            if (lvaluePeek<Pending>() || lvaluePeek<Node>())
                builder->pushRValue(std::move(val));
        }

        template <typename N>
        Ref<N> rvaluePop() {
            auto val = builder->popRValue();
            if (val->is<N>()) {
                return std::static_pointer_cast<N>(val);
            }
            throw InternalCompilerError("Attempted to pop {0} from AST r-value stack, found {1} instead",
                                        RTTI::of<N>()->name(),
                                        RTTI::of(*val)->name());
        }

        template <typename N>
        Ref<N> rvaluePeek(unsigned int idx) {
            auto val = builder->peekRValue(idx);
            if (val && val->is<N>()) {
                return val.as<N>();
            }
            throw InternalCompilerError("Attempted to peek a {0} in AST r-value stack at slot {1}, found {2} instead",
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
            if (value.find('.') != -1) {
                try {
                    auto floatVal = std::stold(value);
                    return builder->New<FloatLiteral>(floatVal);
                } catch (std::invalid_argument) {
                }
            }
            try {
                auto intVal = std::stoll(value);
                return builder->New<IntegerLiteral>(intVal);
            } catch (std::invalid_argument) {
            }

            throw CompileError("Unable to parse numeric literal: {0}", value);
        }

        Ref<Expression> evalBoolConstant(PepperParser::BoolConstantContext* boolConstant) {
            bool boolVal = boolConstant->True();
            return builder->New<BoolLiteral>(boolVal);
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
                symbol->Default = defaultValue;
            }

            builder->symbol(symbol);
            rvaluePush(symbol);
        }

        Ref<Expression> resolveLocal(const Ident& identifier) {
            auto symbol = builder->findSymbol(identifier);
            if (symbol && symbol->is<FieldDef>()) {
                auto field = symbol.as<FieldDef>();
                return builder->New<MemberRef>(Ref<ThisRef>::New(field->Struct), field->Identifier);
            }
            if (symbol && symbol->is<MethodDef>()) {
                auto method = symbol.as<MethodDef>();
                return builder->New<MemberRef>(Ref<ThisRef>::New(method->Struct), method->Identifier);
            }
            // anything else can be looked up later, at codegen/pass time
            return builder->New<VariableRef>(identifier);
        }

        void exitPrimaryExpression(PepperParser::PrimaryExpressionContext* context) override {
            auto boolConstant = context->boolConstant();
            if (boolConstant) {
                rvaluePush(evalBoolConstant(boolConstant));
                return;
            }
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
                auto symbol = resolveLocal(ident->toString());
                rvaluePush(symbol);
                return;
            }
        }

        void enterParameterDeclaration(PepperParser::ParameterDeclarationContext* context) override {
            lvaluePush(Ref<Pending>::New(Ref<VariableDef>()));
        }

        void exitParameterDeclaration(PepperParser::ParameterDeclarationContext* context) override {
            lvaluePop<VariableDef>();
            auto identifiers = context->Identifier();
            auto typeName = identifiers[0]->toString();
            auto name = identifiers[1]->toString();
            Ref<Expression> defaultValue;
            if (context->Assign()) {
                defaultValue = rvaluePop<Expression>();
            }
            auto func = builder->functionTarget();
            func->Parameters.emplace_back(name, typeName, defaultValue);
        }

        void enterFunctionDefinition(PepperParser::FunctionDefinitionContext* context) override {
            auto identifier = context->Identifier()->toString();
            auto returnType =
                context->returnType()->Identifier() ? context->returnType()->Identifier()->toString() : "void";

            auto function =
                builder->structTarget()
                    ? builder->New<MethodDef>(builder->structTarget(), returnType, identifier).as<FunctionDef>()
                    : builder->New<FunctionDef>(returnType, identifier);
            lvaluePush(function);
            builder->beginFunction(function);
        }

        void exitFunctionDefinition(PepperParser::FunctionDefinitionContext* context) override {
            builder->endFunction();

            auto function = lvaluePop<FunctionDef>();
            if (function->is<MethodDef>()) {
                builder->structTarget()->Methods.push_back(function.as<MethodDef>());
            }
        }

        void enterStructDeclaration(PepperParser::StructDeclarationContext* context) override {
            auto identifier = context->Identifier()->toString();
            auto structDef = StructDef::New(identifier, identifier);
            builder->beginStruct(structDef);
        }

        void exitStructDeclaration(PepperParser::StructDeclarationContext* context) override {
            builder->endStruct();
        }

        void enterConstructorDefinition(PepperParser::ConstructorDefinitionContext* context) override {
            auto st = builder->structTarget();
            st->Constructor = builder->New<MethodDef>(st, "void", "__ctor");
            lvaluePush(st->Constructor);
            builder->beginFunction(st->Constructor);
        }

        void exitConstructorDefinition(PepperParser::ConstructorDefinitionContext* context) override {
            builder->endFunction();
        }

        void enterConstructorParam(PepperParser::ConstructorParamContext* context) override {
            lvaluePush(Ref<Pending>::New(Ref<VariableDef>()));
        }

        void exitConstructorParam(PepperParser::ConstructorParamContext* context) override {
            // normal params are handled by ParamDeclaration, this is for this-initializers
            if (context->This()) {
                lvaluePop<VariableDef>();
                auto fieldName = context->Identifier()->toString();
                Ref<Expression> defaultValue;
                if (context->Assign()) {
                    defaultValue = rvaluePop<Expression>();
                }

                // lookup the desired field
                auto st = builder->structTarget();
                auto field = Query(st->Fields).find([&](auto f) { return f->Identifier == fieldName; });
                if (!field) {
                    throw CompileError("Unknown field {0} found during this initializer", fieldName);
                }

                // generate a parameter to receive the argument value/establish defaults
                auto paramName = "__this__" + fieldName;
                auto func = builder->functionTarget();
                func->Parameters.emplace_back(paramName, field.value()->Type, defaultValue);

                // GreaterEqual the assignment to the field to the ctor
                func->Body->Items.push_back(builder->New<Assign>(
                    builder->New<MemberRef>(Ref<ThisRef>::New(st), fieldName), builder->New<VariableRef>(paramName)));
            }
        }

        void enterExtensionDefinition(PepperParser::ExtensionDefinitionContext* context) override {
            auto identifiers = context->Identifier();
            if (identifiers.size() == 1) {
                auto structName = identifiers[0]->toString();
                auto structDef = builder->findStruct(structName);
                builder->beginExtension(structDef);
                return;
            }
            throw InternalCompilerError("extension with is not implemented");
        }

        void exitExtensionDefinition(PepperParser::ExtensionDefinitionContext* context) override {
            builder->endExtension();
        }

        void enterMethodCall(PepperParser::MethodCallContext* context) override {
            auto call = Pending::New<MethodCall>();
            lvaluePush(call);
        }

        void exitMethodCall(PepperParser::MethodCallContext* context) override {
            lvaluePop<MethodCall>();
            auto providedArgsCount = context->argumentExpressionList()
                                         ? context->argumentExpressionList()->assignmentExpression().size()
                                         : 0;
            Vector<Ref<Expression>> args;
            for (int argIdx = 0; argIdx < providedArgsCount; ++argIdx) {
                args.insert(args.begin(), rvaluePop<Expression>());
            }
            auto member = rvaluePop<MemberRef>();
            auto call = builder->New<MethodCall>(member->LHS, member->MemberName, args);
            builder->insert(call);
        }

        void enterFreeFunctionCall(PepperParser::FreeFunctionCallContext* context) override {
            auto call = Pending::New<FunctionCall>();
            lvaluePush(call);
        }

        void exitFreeFunctionCall(PepperParser::FreeFunctionCallContext* context) override {
            lvaluePop<FunctionCall>();
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
            builder->insert(call);
        }

        void enterReturn(PepperParser::ReturnContext* context) override {
            auto ret = Pending::New<Return>();
            lvaluePush(ret);
        }

        void exitReturn(PepperParser::ReturnContext* context) override {
            lvaluePop<Return>();
            auto function = builder->functionTarget();
            Ref<Expression> returnValue;
            if (context->expression()) {
                returnValue = rvaluePop<Expression>();
            }
            auto ret = builder->New<Return>(function, returnValue);
            builder->insert(ret);
        }

        void enterMemberAccess(PepperParser::MemberAccessContext* context) override {
            auto memberRef = Pending::New<MemberRef>();
            lvaluePush(memberRef);
            if (context->This()) {
                rvaluePush(builder->New<VariableRef>("this"));
            }
        }

        void exitMemberAccess(PepperParser::MemberAccessContext* context) override {
            auto lhs = rvaluePop<Expression>();
            auto rhs = context->Identifier()->toString();
            lvaluePop<MemberRef>();
            auto memberRef = builder->New<MemberRef>(lhs, rhs);
            builder->insert(memberRef);
        }

        void enterSelectionStatement(PepperParser::SelectionStatementContext* context) override {
            auto branch = builder->New<If>();
            if (context->ifStatement()) {
                branch->Then = Ref<Block>::New(branch, "then");
            }
            if (context->elseStatement()) {
                branch->Else = Ref<Block>::New(branch, "else");
            }
            builder->beginScope("select");
            lvaluePush(branch);
        }

        void exitSelectionStatement(PepperParser::SelectionStatementContext* context) override {
            auto branch = lvaluePop<Branch>();
            builder->endScope();
            builder->insert(branch);
        }

        void enterIfStatement(PepperParser::IfStatementContext* context) override {
        }

        void exitIfStatement(PepperParser::IfStatementContext* context) override {
            builder->endBlock();
        }

        void exitIfCondition(PepperParser::IfConditionContext* context) override {
            auto branch = lvaluePeek<Branch>();
            branch->Condition = rvaluePop<Expression>();
            builder->beginBlock(branch->Then);
        }

        void enterElseStatement(PepperParser::ElseStatementContext* context) override {
            auto branch = lvaluePeek<Branch>();
            builder->beginBlock(branch->Else);
        }

        void exitElseStatement(PepperParser::ElseStatementContext* context) override {
            builder->endBlock();
        }

        void enterTernary(PepperParser::TernaryContext* context) override {
            auto branch = builder->New<Ternary>();
            lvaluePush(branch);
        }

        void enterWhileLoop(PepperParser::WhileLoopContext* context) override {
            auto loop = builder->New<While>();
            loop->Body = builder->New<Block>();
            lvaluePush(loop);
        }

        void exitWhileLoop(PepperParser::WhileLoopContext* context) override {
            builder->endBlock();
            auto loop = lvaluePop<While>();
            builder->insert(loop);
        }

        void exitWhileCondition(PepperParser::WhileConditionContext* context) override {
            auto loop = lvaluePeek<While>();
            loop->Condition = rvaluePop<Expression>();
            builder->beginBlock(loop->Body);
        }

        void enterForLoop(PepperParser::ForLoopContext* context) override {
            auto loop = builder->New<ForRange>();
            loop->Body = builder->New<Block>();
            lvaluePush(loop);
        }

        void exitForCondition(PepperParser::ForConditionContext* context) override {
            auto loop = lvaluePeek<ForRange>();
            if (context->forDeclaration()) {
                loop->Var = rvaluePop<VariableDef>();
            }
            auto rangeExpr = context->forExpression();
            if (auto slice = rangeExpr->sliceNotation()) {
                auto exprs = slice->expression();
                if (exprs.size() == 3) {
                    loop->Init = rvaluePop<Expression>();
                    loop->Done = rvaluePop<Expression>();
                    loop->Step = rvaluePop<Expression>();
                } else if (exprs.size() == 2) {
                    loop->Init = rvaluePop<Expression>();
                    loop->Done = rvaluePop<Expression>();
                } else {
                    loop->Init = rvaluePop<Expression>();
                }
                if (!loop->Step) {
                    // TODO: figure out which is larger and set the step pos or neg
                    // TODO: emit a range that encapsulates all of this
                    loop->Step = builder->New<IntegerLiteral>(1);
                }
            }
        }

        void exitForLoop(PepperParser::ForLoopContext* context) override {
        }

        void exitTernary(PepperParser::TernaryContext* context) override {
            auto branch = lvaluePop<Ternary>();
            branch->FalseResult = rvaluePop<Expression>();
            branch->TrueResult = rvaluePop<Expression>();
            branch->Condition = rvaluePop<Expression>();
            builder->insert(branch);
        }

        template <typename Op>
        void beginBinaryOp() {
            auto op = Pending::New<Op>();
            lvaluePush(op);
        }

        template <typename Op>
        void endBinaryOp() {
            lvaluePop<Op>();
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            builder->insert(builder->New<Op>(lhs, rhs));
        }

        void enterAdd(PepperParser::AddContext* context) override {
            beginBinaryOp<Add>();
        }

        void exitAdd(PepperParser::AddContext* context) override {
            endBinaryOp<Add>();
        }

        void enterSub(PepperParser::SubContext* context) override {
            beginBinaryOp<Sub>();
        }

        void exitSub(PepperParser::SubContext* context) override {
            endBinaryOp<Sub>();
        }

        void enterMul(PepperParser::MulContext* context) override {
            beginBinaryOp<Mul>();
        }

        void exitMul(PepperParser::MulContext* context) override {
            endBinaryOp<Mul>();
        }

        void enterDiv(PepperParser::DivContext* context) override {
            beginBinaryOp<Div>();
        }

        void exitDiv(PepperParser::DivContext* context) override {
            endBinaryOp<Div>();
        }

        void enterMod(PepperParser::ModContext* context) override {
            beginBinaryOp<Mod>();
        }

        void exitMod(PepperParser::ModContext* context) override {
            endBinaryOp<Mod>();
        }

        void enterPow(PepperParser::PowContext* context) override {
            beginBinaryOp<Pow>();
        }

        void exitPow(PepperParser::PowContext* context) override {
            endBinaryOp<Pow>();
        }

        void enterLShift(PepperParser::LShiftContext* context) override {
            beginBinaryOp<LShift>();
        }

        void exitLShift(PepperParser::LShiftContext* context) override {
            endBinaryOp<LShift>();
        }

        void enterRShift(PepperParser::RShiftContext* context) override {
            beginBinaryOp<RShift>();
        }

        void exitRShift(PepperParser::RShiftContext* context) override {
            endBinaryOp<RShift>();
        }

        void enterBitwiseAnd(PepperParser::BitwiseAndContext* context) override {
            beginBinaryOp<BitAnd>();
        }

        void exitBitwiseAnd(PepperParser::BitwiseAndContext* context) override {
            endBinaryOp<BitAnd>();
        }

        void enterBitwiseXor(PepperParser::BitwiseXorContext* context) override {
            beginBinaryOp<BitXor>();
        }

        void exitBitwiseXor(PepperParser::BitwiseXorContext* context) override {
            endBinaryOp<BitXor>();
        }

        void enterBitwiseOr(PepperParser::BitwiseOrContext* context) override {
            beginBinaryOp<BitOr>();
        }

        void exitBitwiseOr(PepperParser::BitwiseOrContext* context) override {
            endBinaryOp<BitOr>();
        }

        void enterLess(PepperParser::LessContext* context) override {
            beginBinaryOp<Less>();
        }

        void exitLess(PepperParser::LessContext* context) override {
            endBinaryOp<Less>();
        }

        void enterLessEqual(PepperParser::LessEqualContext* context) override {
            beginBinaryOp<LessEqual>();
        }

        void exitLessEqual(PepperParser::LessEqualContext* context) override {
            endBinaryOp<LessEqual>();
        }

        void enterGreater(PepperParser::GreaterContext* context) override {
            beginBinaryOp<Greater>();
        }

        void exitGreater(PepperParser::GreaterContext* context) override {
            endBinaryOp<Greater>();
        }

        void enterGreaterEqual(PepperParser::GreaterEqualContext* context) override {
            beginBinaryOp<GreaterEqual>();
        }

        void exitGreaterEqual(PepperParser::GreaterEqualContext* context) override {
            endBinaryOp<GreaterEqual>();
        }

        void enterEqual(PepperParser::EqualContext* context) override {
            beginBinaryOp<Equal>();
        }

        void exitEqual(PepperParser::EqualContext* context) override {
            endBinaryOp<Equal>();
        }

        void enterNotEqual(PepperParser::NotEqualContext* context) override {
            beginBinaryOp<NotEqual>();
        }

        void exitNotEqual(PepperParser::NotEqualContext* context) override {
            endBinaryOp<NotEqual>();
        }

        void enterLogicalAnd(PepperParser::LogicalAndContext* context) override {
            beginBinaryOp<LogicalAnd>();
        }

        void exitLogicalAnd(PepperParser::LogicalAndContext* context) override {
            endBinaryOp<LogicalAnd>();
        }

        void enterLogicalOr(PepperParser::LogicalOrContext* context) override {
            beginBinaryOp<LogicalOr>();
        }

        void exitLogicalOr(PepperParser::LogicalOrContext* context) override {
            endBinaryOp<LogicalOr>();
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
            builder->insert(builder->New<Op>(lhs, rhs));
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
