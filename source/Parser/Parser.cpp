
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
        Builder* builder;

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
                } catch (std::invalid_argument&) {
                }
            }
            try {
                int64_t intVal = 0;
                if (llvm::to_integer(value, intVal))
                    return builder->New<IntegerLiteral>(intVal);
            } catch (std::invalid_argument&) {
            }

            throw CompileError(builder->Source, "Unable to parse numeric literal: {0}", value);
        }

        Ref<Expression> evalBoolConstant(PepperParser::BoolConstantContext* boolConstant) {
            const bool boolVal = boolConstant->True();
            return builder->New<BoolLiteral>(boolVal);
        }

        TypeName parseTypeName(PepperParser::TypeSpecifierContext* typeSpec) {
            TypeName type{typeSpec->Identifier()->toString()};
            if (auto genericParams = typeSpec->genericArgs()) {
                for (auto paramType : genericParams->genericArgsList()->typeSpecifier()) {
                    type.GenericTypes.emplace_back(parseTypeName(paramType));
                }
            }
            return type;
        }

        TypeName typeOfExpr(Ref<Expression> expr) const {
            if (expr->type() != TypeName::Auto) {
                return expr->type();
            }
            if (expr->is<VariableRef>()) {
                auto var = expr.as<VariableRef>();
                auto symbol = builder->findSymbol(var->identifier());
                if (!symbol) {
                    throw CompileError(builder->Source, "Unknown symbol referenced: {0}", var->identifier());
                }
                return symbol->Type;
            }
            if (expr->is<MemberRef>()) {
                auto ref = expr.as<MemberRef>();
                return typeOfExpr(ref->LHS);
            }
            throw CompileError(builder->Source, "Unknown expression type in {0}", expr->rtti()->name());
        }

        void enterExplicitVariableDeclaration(PepperParser::ExplicitVariableDeclarationContext* context) override {
            auto typeName = parseTypeName(context->typeSpecifier());
            auto identifier = context->Identifier()->toString();
            if (!typeName.GenericTypes.empty()) {
                builder->specialize(typeName);
            }

            if (builder->structTarget()) {
                lvaluePush(builder->New<FieldDef>(builder->structTarget().get(), typeName, identifier));
            } else {
                lvaluePush(builder->New<VariableDef>(typeName, identifier));
            }
        }

        void exitExplicitVariableDeclaration(PepperParser::ExplicitVariableDeclarationContext* context) override {
            auto symbol = lvaluePop<VariableDef>();
            if (context->assignmentExpression()) {
                auto defaultValue = rvaluePop<Expression>();
                symbol->Default = defaultValue;
            }

            builder->symbol(symbol);
            rvaluePush(symbol);
        }

        void enterImplicitVariableDeclaration(PepperParser::ImplicitVariableDeclarationContext* context) override {
            bool isConst = context->typeQualifier()->Const();
            auto identifier = context->Identifier()->toString();
            const auto& typeName = TypeName::Auto;
            if (builder->structTarget()) {
                lvaluePush(builder->New<FieldDef>(builder->structTarget().get(), typeName, identifier));
            } else {
                lvaluePush(builder->New<VariableDef>(typeName, identifier));
            }
        }

        void exitImplicitVariableDeclaration(PepperParser::ImplicitVariableDeclarationContext*) override {
            auto symbol = lvaluePop<VariableDef>();
            auto defaultValue = rvaluePop<Expression>();
            symbol->Default = defaultValue;
            symbol->Type = typeOfExpr(symbol->Default);
            builder->symbol(symbol);
            rvaluePush(symbol);
        }

        Ref<Expression> resolveLocal(const Ident& identifier) {
            auto symbol = builder->findSymbol(identifier);
            if (symbol && symbol->is<FieldDef>()) {
                auto field = symbol.as<FieldDef>();
                return builder->New<MemberRef>(Ref<ThisRef>::New(), field->Name);
            }
            if (symbol && symbol->is<MethodDef>()) {
                auto method = symbol.as<MethodDef>();
                return builder->New<MemberRef>(Ref<ThisRef>::New(), method->Name);
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
            if (!stringLiterals.empty()) {
                std::string strVal;
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

        void enterParameterDeclaration(PepperParser::ParameterDeclarationContext*) override {
            lvaluePush(Ref<Pending>::New(Ref<VariableDef>()));
        }

        void exitParameterDeclaration(PepperParser::ParameterDeclarationContext* context) override {
            lvaluePop<VariableDef>();
            auto name = context->Identifier()->toString();
            auto typeName = parseTypeName(context->typeSpecifier());
            Ref<Expression> defaultValue;
            if (context->Assign()) {
                defaultValue = rvaluePop<Expression>();
            }
            auto func = builder->functionTarget();
            func->Parameters.emplace_back(name, typeName, defaultValue);
        }

        void enterFunctionDefinition(PepperParser::FunctionDefinitionContext* context) override {
            auto identifier = context->Identifier()->toString();
            auto returnType = context->typeSpecifier() ? parseTypeName(context->typeSpecifier()) : TypeName("void");

            auto function =
                builder->structTarget()
                    ? builder->New<MethodDef>(builder->structTarget().get(), returnType, identifier).as<FunctionDef>()
                    : builder->New<FunctionDef>(returnType, identifier);
            lvaluePush(function);
            builder->beginFunction(function);
        }

        void exitFunctionDefinition(PepperParser::FunctionDefinitionContext*) override {
            builder->endFunction();

            auto function = lvaluePop<FunctionDef>();
            if (function->is<MethodDef>()) {
                builder->structTarget()->Methods.push_back(function.as<MethodDef>());
            }
        }

        TypeName parseTypeDeclaration(PepperParser::TypeDeclarationContext* typeDecl) {
            TypeName type{typeDecl->Identifier()->toString()};
            if (auto genericParams = typeDecl->genericParams()) {
                for (auto param : genericParams->genericParamsList()->Identifier()) {
                    type.GenericTypes.emplace_back(param->toString());
                }
            }
            return type;
        }

        Ref<StructDef> findStructOrGeneric(const TypeName& typeName) {
            if (auto st = builder->findStruct(typeName)) {
                return st;
            }
            if (!typeName.GenericTypes.empty()) {
                if (auto st = builder->findStruct(typeName.Name)) {
                    return st;
                }
            }
            return nullptr;
        }

        void enterStructDeclaration(PepperParser::StructDeclarationContext* context) override {
            const TypeName type = parseTypeDeclaration(context->typeDeclaration());
            auto structDef = StructDef::New(type);
            if (auto genericParams = context->typeDeclaration()->genericParams()) {
                for (auto param : genericParams->genericParamsList()->Identifier()) {
                    structDef->GenericParams.emplace_back(param->toString());
                }
            }
            builder->beginStruct(structDef);
        }

        void exitStructDeclaration(PepperParser::StructDeclarationContext*) override {
            builder->endStruct();
        }

        void enterConstructorDefinition(PepperParser::ConstructorDefinitionContext* context) override {
            auto st = builder->structTarget();
            if (context->New()) {
                lvaluePush(st->Constructor);
                builder->beginFunction(st->Constructor);
            } else {
                lvaluePush(st->Destructor);
                builder->beginFunction(st->Destructor);
            }
        }

        void exitConstructorDefinition(PepperParser::ConstructorDefinitionContext*) override {
            builder->endFunction();
        }

        void enterConstructorParam(PepperParser::ConstructorParamContext*) override {
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
                auto field = Query(st->Fields).find([&](auto f) { return f->Name == fieldName; });
                if (!field) {
                    throw CompileError(builder->Source, "Unknown field {0} found during this initializer", fieldName);
                }

                // generate a parameter to receive the argument value/establish defaults
                auto paramName = "__this__" + fieldName;
                auto func = builder->functionTarget();
                func->Parameters.emplace_back(paramName, field.value()->Type, defaultValue);

                // Add the assignment to the field to the ctor
                func->Body->Items.emplace_back(builder->New<Assign>(
                    builder->New<MemberRef>(Ref<ThisRef>::New(), fieldName), builder->New<VariableRef>(paramName)));
            }
        }

        void enterExtensionDefinition(PepperParser::ExtensionDefinitionContext* context) override {
            auto structType = parseTypeDeclaration(context->typeDeclaration());
            if (auto structDef = builder->findStruct(structType)) {
                builder->beginExtension(structDef);
                return;
            }
            // If the target is generic, but hasn't been specialized yet, do it now
            if (!structType.GenericTypes.empty()) {
                if (builder->findStruct(structType.Name)) {
                    auto specialized = builder->specialize(structType);
                    builder->beginExtension(specialized);
                    return;
                }
            }
            throw CompileError(builder->Source, "Unable to extend unknown type {0}", structType.toString());
        }

        void exitExtensionDefinition(PepperParser::ExtensionDefinitionContext*) override {
            builder->endExtension();
        }

        void enterMethodCall(PepperParser::MethodCallContext*) override {
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
            assert(member->LHS);
            auto structType = typeOfExpr(member->LHS);
            auto structDef = builder->findStruct(structType);
            assert(structDef);
            auto method = structDef->getMethod(member->MemberName);
            if (!method) {
                throw CompileError(
                    builder->Source, "No method named {0} in {1}", member->MemberName, structType.toString());
            }
            auto call = builder->New<MethodCall>(method->ReturnType, member->LHS, member->MemberName, args);
            builder->insert(call);
        }

        void enterFreeFunctionCall(PepperParser::FreeFunctionCallContext*) override {
            auto call = Pending::New<FunctionCall>();
            lvaluePush(call);
        }

        void exitFreeFunctionCall(PepperParser::FreeFunctionCallContext* context) override {
            lvaluePop<FunctionCall>();
            auto functionName = parseTypeName(context->typeSpecifier());
            auto identifier = functionName.toString();
            auto func = builder->findFunction(identifier);
            if (!func) {
                throw CompileError(builder->Source, "Function {0} not found", identifier);
            }
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

        void enterReturn(PepperParser::ReturnContext*) override {
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
            auto ret = builder->New<Return>(function->ReturnType, returnValue);
            builder->insert(ret);
        }

        void enterMemberAccess(PepperParser::MemberAccessContext* context) override {
            auto memberRef = Pending::New<MemberRef>();
            lvaluePush(memberRef);
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
                branch->Then = Ref<Block>::New("then");
            }
            if (context->elseStatement()) {
                branch->Else = Ref<Block>::New("else");
            }
            builder->beginScope("select");
            lvaluePush(branch);
        }

        void exitSelectionStatement(PepperParser::SelectionStatementContext*) override {
            auto branch = lvaluePop<Branch>();
            builder->endScope();
            builder->insert(branch);
        }

        void enterIfStatement(PepperParser::IfStatementContext* context) override {
        }

        void exitIfStatement(PepperParser::IfStatementContext*) override {
            builder->endBlock();
        }

        void exitIfCondition(PepperParser::IfConditionContext*) override {
            auto branch = lvaluePeek<Branch>();
            branch->Condition = rvaluePop<Expression>();
            builder->beginBlock(branch->Then);
        }

        void enterElseStatement(PepperParser::ElseStatementContext*) override {
            auto branch = lvaluePeek<Branch>();
            builder->beginBlock(branch->Else);
        }

        void exitElseStatement(PepperParser::ElseStatementContext*) override {
            builder->endBlock();
        }

        void enterTernary(PepperParser::TernaryContext*) override {
            auto branch = builder->New<Ternary>();
            lvaluePush(branch);
        }

        void enterWhileLoop(PepperParser::WhileLoopContext*) override {
            auto loop = builder->New<While>();
            loop->Body = builder->New<Block>();
            lvaluePush(loop);
        }

        void exitWhileLoop(PepperParser::WhileLoopContext*) override {
            builder->endBlock();
            auto loop = lvaluePop<While>();
            builder->insert(loop);
        }

        void exitWhileCondition(PepperParser::WhileConditionContext*) override {
            auto loop = lvaluePeek<While>();
            loop->Condition = rvaluePop<Expression>();
            builder->beginBlock(loop->Body);
        }

        void enterForLoop(PepperParser::ForLoopContext*) override {
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
            }
        }

        void exitForLoop(PepperParser::ForLoopContext* context) override {
        }

        void exitTernary(PepperParser::TernaryContext*) override {
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

        void enterAdd(PepperParser::AddContext*) override {
            beginBinaryOp<Add>();
        }

        void exitAdd(PepperParser::AddContext*) override {
            endBinaryOp<Add>();
        }

        void enterSub(PepperParser::SubContext*) override {
            beginBinaryOp<Sub>();
        }

        void exitSub(PepperParser::SubContext*) override {
            endBinaryOp<Sub>();
        }

        void enterMul(PepperParser::MulContext*) override {
            beginBinaryOp<Mul>();
        }

        void exitMul(PepperParser::MulContext*) override {
            endBinaryOp<Mul>();
        }

        void enterDiv(PepperParser::DivContext*) override {
            beginBinaryOp<Div>();
        }

        void exitDiv(PepperParser::DivContext*) override {
            endBinaryOp<Div>();
        }

        void enterMod(PepperParser::ModContext*) override {
            beginBinaryOp<Mod>();
        }

        void exitMod(PepperParser::ModContext*) override {
            endBinaryOp<Mod>();
        }

        void enterPow(PepperParser::PowContext*) override {
            beginBinaryOp<Pow>();
        }

        void exitPow(PepperParser::PowContext*) override {
            endBinaryOp<Pow>();
        }

        void enterLShift(PepperParser::LShiftContext*) override {
            beginBinaryOp<LShift>();
        }

        void exitLShift(PepperParser::LShiftContext*) override {
            endBinaryOp<LShift>();
        }

        void enterRShift(PepperParser::RShiftContext*) override {
            beginBinaryOp<RShift>();
        }

        void exitRShift(PepperParser::RShiftContext*) override {
            endBinaryOp<RShift>();
        }

        void enterBitwiseAnd(PepperParser::BitwiseAndContext*) override {
            beginBinaryOp<BitAnd>();
        }

        void exitBitwiseAnd(PepperParser::BitwiseAndContext*) override {
            endBinaryOp<BitAnd>();
        }

        void enterBitwiseXor(PepperParser::BitwiseXorContext*) override {
            beginBinaryOp<BitXor>();
        }

        void exitBitwiseXor(PepperParser::BitwiseXorContext*) override {
            endBinaryOp<BitXor>();
        }

        void enterBitwiseOr(PepperParser::BitwiseOrContext*) override {
            beginBinaryOp<BitOr>();
        }

        void exitBitwiseOr(PepperParser::BitwiseOrContext*) override {
            endBinaryOp<BitOr>();
        }

        void enterLess(PepperParser::LessContext*) override {
            beginBinaryOp<Less>();
        }

        void exitLess(PepperParser::LessContext*) override {
            endBinaryOp<Less>();
        }

        void enterLessEqual(PepperParser::LessEqualContext*) override {
            beginBinaryOp<LessEqual>();
        }

        void exitLessEqual(PepperParser::LessEqualContext*) override {
            endBinaryOp<LessEqual>();
        }

        void enterGreater(PepperParser::GreaterContext*) override {
            beginBinaryOp<Greater>();
        }

        void exitGreater(PepperParser::GreaterContext*) override {
            endBinaryOp<Greater>();
        }

        void enterGreaterEqual(PepperParser::GreaterEqualContext*) override {
            beginBinaryOp<GreaterEqual>();
        }

        void exitGreaterEqual(PepperParser::GreaterEqualContext*) override {
            endBinaryOp<GreaterEqual>();
        }

        void enterEqual(PepperParser::EqualContext*) override {
            beginBinaryOp<Equal>();
        }

        void exitEqual(PepperParser::EqualContext*) override {
            endBinaryOp<Equal>();
        }

        void enterNotEqual(PepperParser::NotEqualContext*) override {
            beginBinaryOp<NotEqual>();
        }

        void exitNotEqual(PepperParser::NotEqualContext*) override {
            endBinaryOp<NotEqual>();
        }

        void enterLogicalAnd(PepperParser::LogicalAndContext*) override {
            beginBinaryOp<LogicalAnd>();
        }

        void exitLogicalAnd(PepperParser::LogicalAndContext*) override {
            endBinaryOp<LogicalAnd>();
        }

        void enterLogicalOr(PepperParser::LogicalOrContext*) override {
            beginBinaryOp<LogicalOr>();
        }

        void exitLogicalOr(PepperParser::LogicalOrContext*) override {
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

        void enterAssignment(PepperParser::AssignmentContext*) override {
            beginAssign<Assign>();
        }

        void exitAssignment(PepperParser::AssignmentContext*) override {
            endAssign<Assign>();
        }

        void enterMulAssignment(PepperParser::MulAssignmentContext*) override {
            beginAssign<MulAssign>();
        }

        void exitMulAssignment(PepperParser::MulAssignmentContext*) override {
            endAssign<MulAssign>();
        }

        void enterDivAssignment(PepperParser::DivAssignmentContext*) override {
            beginAssign<DivAssign>();
        }

        void exitDivAssignment(PepperParser::DivAssignmentContext*) override {
            endAssign<DivAssign>();
        }

        void enterModAssignment(PepperParser::ModAssignmentContext*) override {
            beginAssign<ModAssign>();
        }

        void exitModAssignment(PepperParser::ModAssignmentContext*) override {
            endAssign<ModAssign>();
        }

        void enterAddAssignment(PepperParser::AddAssignmentContext*) override {
            beginAssign<AddAssign>();
        }

        void exitAddAssignment(PepperParser::AddAssignmentContext*) override {
            endAssign<AddAssign>();
        }

        void enterSubAssignment(PepperParser::SubAssignmentContext*) override {
            beginAssign<SubAssign>();
        }

        void exitSubAssignment(PepperParser::SubAssignmentContext*) override {
            endAssign<SubAssign>();
        }

        void enterLShiftAssignment(PepperParser::LShiftAssignmentContext*) override {
            beginAssign<LShiftAssign>();
        }

        void exitLShiftAssignment(PepperParser::LShiftAssignmentContext*) override {
            endAssign<LShiftAssign>();
        }

        void enterRShiftAssignment(PepperParser::RShiftAssignmentContext*) override {
            beginAssign<RShiftAssign>();
        }

        void exitRShiftAssignment(PepperParser::RShiftAssignmentContext*) override {
            endAssign<RShiftAssign>();
        }

        void enterBitAndAssignment(PepperParser::BitAndAssignmentContext*) override {
            beginAssign<BitAndAssign>();
        }

        void exitBitAndAssignment(PepperParser::BitAndAssignmentContext*) override {
            endAssign<BitAndAssign>();
        }

        void enterBitXorAssignment(PepperParser::BitXorAssignmentContext*) override {
            beginAssign<BitXorAssign>();
        }

        void exitBitXorAssignment(PepperParser::BitXorAssignmentContext*) override {
            endAssign<BitXorAssign>();
        }

        void enterBitOrAssignment(PepperParser::BitOrAssignmentContext*) override {
            beginAssign<BitOrAssign>();
        }

        void exitBitOrAssignment(PepperParser::BitOrAssignmentContext*) override {
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
        auto rec = rex.getRecognizer();
        auto expected = rex.getExpectedTokens();
        auto tokenMap = rec->getTokenTypeMap();
        auto possibles = Vector<std::string_view>{};
        for (auto tokenIt : tokenMap) {
            if (expected.contains(tokenIt.second)) {
                possibles.emplace_back(tokenIt.first);
            }
        }
        auto expectedTokens = llvm::join(possibles.begin(), possibles.end(), ", ");
        throw CompileError(src, R"({0} "{1}", expected {2})", prefix, text, expectedTokens);
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
