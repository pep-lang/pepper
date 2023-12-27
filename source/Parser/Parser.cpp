
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
    using namespace pepper::parser;
    using namespace pepper::ast;

    class ParserListener : public PepperBaseListener {
        using Super = PepperBaseListener;

        Ref<AST> Tree;
        Builder* builder;

      public:
        ParserListener()
            : Tree(Ref<AST>::New(AST::TreeType::SourceFile)) {
            builder = Tree->builder();
        }

        Ref<AST> ast() const {
            return Tree;
        }

        void lvaluePush(Node* val) {
            // std::cout << "lpush: " << val->toString() << std::endl;
            builder->pushLValue(val);
        }

        template <typename N>
        N* lvaluePop() {
            auto val = builder->popLValue();
            // unwrap pending node if found
            if (val) {
                if (val->is<Pending>() && val->as<Pending>()->Type->is(RTTI::of<N>())) {
                    auto value = val->as<Pending>()->Value;
                    return value ? value->as<N>() : nullptr;
                }

                // std::cout << "lpop:  " << (val ? val->toString() : "null") << std::endl;
                if (val->is<N>()) {
                    return val->as<N>();
                }
            }

            throw InternalCompilerError("Attempted to pop {0} from AST l-value stack, found {1} instead",
                                        RTTI::of<N>()->name(),
                                        RTTI::of(*val)->name());
        }

        template <typename N>
        N* lvaluePeek(unsigned int idx = 0) {
            auto val = builder->peekLValue(idx);
            // unwrap pending node if found
            if constexpr (!std::is_same_v<N, Pending>) {
                if (val && val->is<Pending>() && val->as<Pending>()->Type->is(RTTI::of<N>())) {
                    auto value = val->as<Pending>()->Value;
                    return value ? value->as<N>() : nullptr;
                }
            }
            if (val && val->is<N>()) {
                return val->as<N>();
            }
            return nullptr;
        }

        bool rvaluePush(Node* val) {
            // Only bother tracking this rvalue if there is a pending l-value on the stack to receive it
            if (lvaluePeek<Pending>() || lvaluePeek<Node>()) {
                builder->pushRValue(val);
                return true;
            }
            return false;
        }

        void rvaluePushOrInsert(Node* val) {
            if (rvaluePush(val))
                return;
            builder->insert(val);
        }

        template <typename N>
        N* rvaluePop() {
            auto val = builder->popRValue();
            if (val->is<N>()) {
                return val->as<N>();
            }
            throw InternalCompilerError("Attempted to pop {0} from AST r-value stack, found {1} instead",
                                        RTTI::of<N>()->name(),
                                        RTTI::of(*val)->name());
        }

        template <typename N>
        N* rvaluePeek(unsigned int idx) {
            auto val = builder->peekRValue(idx);
            if (val && val->is<N>()) {
                return val->as<N>();
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

        void pushSourceLocation(const antlr4::ParserRuleContext* context) {
            Node::PushSource(builder->Source = sourceLocation(context));
        }

        void enterEveryRule(antlr4::ParserRuleContext* context) override {
            pushSourceLocation(context);
        }

        void exitEveryRule(antlr4::ParserRuleContext* context) override {
            Node::PopSource();
        }

        void visitTerminal(antlr4::tree::TerminalNode* terminal) override {
            Super::visitTerminal(terminal);
        }

        static TypeName parseTypeName(PepperParser::TypeNameContext* typeSpec) {
            TypeName type{typeSpec->Identifier()->toString()};
            if (auto genericParams = typeSpec->genericArgs()) {
                for (auto paramType : genericParams->genericArgsList()->typeName()) {
                    type.SubTypes.emplace_back(parseTypeName(paramType));
                }
            }
            if (typeSpec->Brackets())
                type.Flags = TypeName::Array;
            return type;
        }

        static TypeName parseTypeDeclaration(PepperParser::TypeDeclarationContext* typeDecl) {
            TypeName type{typeDecl->Identifier()->toString()};
            if (auto genericParams = typeDecl->genericParams()) {
                for (auto param : genericParams->genericParamsList()->Identifier()) {
                    type.SubTypes.emplace_back(param->toString());
                }
            }
            return type;
        }

        static TypeName parseFunctionSpec(PepperParser::FunctionNameContext* context) {
            TypeName fnSpec;
            if (auto op = context->unaryOperator()) {
                if (op->Brackets())
                    fnSpec = {"[]"};
            } else if (auto op = context->binaryOperator()) {
                fnSpec = {op->getText()};
            } else if (auto assign = context->assignmentOperator()) {
                fnSpec = {assign->getText()};
            } else {
                fnSpec = parseTypeDeclaration(context->typeDeclaration());
            }
            return fnSpec;
        }

        void exitUseStatement(PepperParser::UseStatementContext* context) override {
            bool local = false;
            std::string import;
            std::string alias;
            if (context->StringLiteral()) {
                local = true;
                import = trim(context->StringLiteral()->toString(), "\"");
                alias = context->Identifier().size() ? context->Identifier()[0]->toString() : "";
            } else {
                import = context->Identifier()[0]->toString();
                alias = context->Identifier().size() > 1 ? context->Identifier()[1]->toString() : "";
            }

            auto importNode = new Import(import, local, alias);
            builder->import(importNode);
        }

        void enterExplicitVariableDeclaration(PepperParser::ExplicitVariableDeclarationContext* context) override {
            auto typeName = parseTypeName(context->typeName());
            auto identifier = context->Identifier()->toString();

            if (auto st = builder->targetAs<StructDef>()) {
                auto structType = st->Type;
                lvaluePush(new FieldDef(structType, typeName, identifier));

            } else {
                lvaluePush(new VariableDef(typeName, identifier));
            }
        }

        void exitExplicitVariableDeclaration(PepperParser::ExplicitVariableDeclarationContext* context) override {
            auto symbol = lvaluePop<VariableDef>();
            if (context->Assign()) {
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

            if (auto st = builder->targetAs<StructDef>()) {
                auto structType = st->Type;
                lvaluePush(new FieldDef(structType, typeName, identifier));

            } else {
                lvaluePush(new VariableDef(typeName, identifier));
            }
        }

        void exitImplicitVariableDeclaration(PepperParser::ImplicitVariableDeclarationContext*) override {
            auto symbol = lvaluePop<VariableDef>();
            auto defaultValue = rvaluePop<Expression>();
            symbol->Default = defaultValue;
            builder->symbol(symbol);
            rvaluePush(symbol);
        }

        void exitIdentifierExpr(PepperParser::IdentifierExprContext* context) override {
            auto identifier = context->This() ? "this" : context->Identifier()->toString();
            auto symbol = new SymbolRef(identifier);
            rvaluePush(symbol);
        }

        void exitLiteralExpr(PepperParser::LiteralExprContext* context) override {
            auto literal = context->literal();
            if (literal->BooleanLiteral()) {
                bool boolLiteral = literal->BooleanLiteral()->toString() == "true";
                rvaluePush(new BoolLiteral(boolLiteral));
                return;
            }

            if (literal->numericLiteral()) {
                auto numLiteral = literal->numericLiteral();
                if (numLiteral->DecimalLiteral()) {
                    auto decStr = numLiteral->DecimalLiteral()->toString();
                    if (decStr.find('.') != std::string::npos) {
                        try {
                            double floatVal = 0.0;
                            llvm::to_float(decStr, floatVal);
                            rvaluePush(new FloatLiteral(floatVal));
                            return;
                        } catch (std::invalid_argument&) {}
                    }
                    try {
                        int64_t intVal = 0;
                        if (llvm::to_integer(decStr, intVal)) {
                            rvaluePush(new IntegerLiteral(intVal));
                            return;
                        }
                    } catch (std::invalid_argument&) {}
                }

                if (numLiteral->OctalIntegerLiteral()) {
                    auto octStr = numLiteral->OctalIntegerLiteral()->toString();
                    try {
                        int64_t intVal = 0;
                        if (llvm::to_integer(octStr, intVal, 8)) {
                            rvaluePush(new IntegerLiteral(intVal));
                            return;
                        }
                    } catch (std::invalid_argument&) {}
                }

                if (numLiteral->HexIntegerLiteral()) {
                    auto hexStr = numLiteral->HexIntegerLiteral()->toString();
                    try {
                        int64_t intVal = 0;
                        hexStr = hexStr.substr(2); // remove 0x
                        if (llvm::to_integer(hexStr, intVal, 16)) {
                            rvaluePush(new IntegerLiteral(intVal));
                            return;
                        }
                    } catch (std::invalid_argument&) {}
                }

                if (numLiteral->BinaryIntegerLiteral()) {
                    auto binStr = numLiteral->BinaryIntegerLiteral()->toString();
                    try {
                        int64_t intVal = 0;
                        if (llvm::to_integer(binStr, intVal, 2)) {
                            rvaluePush(new IntegerLiteral(intVal));
                            return;
                        }
                    } catch (std::invalid_argument&) {}
                }

                throw CompileError(builder->Source, "Unable to parse numeric literal: {0}", numLiteral->toString());
            }

            if (!literal->StringLiteral().empty()) {
                std::string stringLiteral;
                bool raw = false;
                for (auto sl : literal->StringLiteral()) {
                    auto str = sl->toString();
                    if (str.starts_with('@'))
                        raw = true;
                    stringLiteral += trim(str, "@\"");
                }
                rvaluePush(new StringLiteral(stringLiteral, raw));
                return;
            }

            if (literal->Null()) {
                rvaluePush(PointerLiteral::Null());
            }
        }

        void enterParameterDeclaration(PepperParser::ParameterDeclarationContext*) override {
            lvaluePush(Pending::New<VariableDef>());
        }

        void exitParameterDeclaration(PepperParser::ParameterDeclarationContext* context) override {
            lvaluePop<VariableDef>();
            auto name = context->Identifier()->toString();
            auto typeName = parseTypeName(context->typeName());
            Expression* defaultValue = nullptr;
            if (context->Assign()) {
                defaultValue = rvaluePop<Expression>();
            }
            assert(builder->targetAs<FunctionNode>());
            auto func = builder->targetAs<FunctionNode>();
            func->Parameters.emplace_back(name, typeName, defaultValue);
        }

        void enterFunctionDefinition(PepperParser::FunctionDefinitionContext* context) override {
            TypeName fnSpec = parseFunctionSpec(context->functionName());

            auto returnType = context->typeName() ? parseTypeName(context->typeName()) : TypeName::Void;
            auto identifier = fnSpec.Name;
            auto storageClass = context->storageClass() && context->storageClass()->Static()
                                    ? FunctionNode::StorageClassType::Static
                                    : FunctionNode::StorageClassType::Default;

            FunctionDef* function = nullptr;
            if (builder->target()) {
                if (auto st = builder->targetAs<StructDef>())
                    function = new MethodDef(st->Type, returnType, fnSpec);
                else if (auto ext = builder->targetAs<ExtensionDef>())
                    function = new MethodDef(ext->Target, returnType, fnSpec);
            }

            if (!function) {
                function = new FunctionDef(returnType, fnSpec);
            }

            function->StorageClass = storageClass;

            lvaluePush(function);
            builder->beginFunction(function);
        }

        void exitFunctionDefinition(PepperParser::FunctionDefinitionContext*) override {
            builder->endFunction();

            auto function = lvaluePop<FunctionDef>();
            if (auto method = function->as<MethodDef>()) {
                if (method->Name == "[]") { // special case indexer
                    method->Name = method->Parameters.size() == 2 ? "__index_set" : "__index_get";
                }
            }
        }

        void exitExternParameter(PepperParser::ExternParameterContext* context) override {
            auto func = builder->targetAs<ExternFunctionRef>();
            assert(func && "Extern parameters only belong in function declarations");
            auto name = context->Identifier()->toString();
            auto typeName = context->externTypeName()->Identifier()->toString();
            if (context->externTypeName()->Star())
                typeName += "*";
            func->Parameters.emplace_back(name, TypeName{typeName});
        }

        void enterExternFunction(PepperParser::ExternFunctionContext* context) override {
            auto returnType = context->externTypeName()->Identifier()->toString();
            if (context->externTypeName()->Star())
                returnType += "*";
            auto identifier = context->Identifier()->toString();
            auto vararg = context->externParameterList()->Ellipsis() != nullptr;
            auto function = new ExternFunctionRef(TypeName{returnType}, identifier);
            if (context->Weak())
                function->Weak = true;
            lvaluePush(function);
            builder->beginFunction(function);
        }

        void exitExternFunction(PepperParser::ExternFunctionContext*) override {
            builder->endFunction();
            auto function = lvaluePop<ExternFunctionRef>();
        }

        void enterStructDeclaration(PepperParser::StructDeclarationContext* context) override {
            const TypeName type = parseTypeDeclaration(context->typeDeclaration());
            auto structDef = new StructDef(type, type.Name);
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
            auto st = builder->targetAs<StructDef>();
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

        void enterConstructorParam(PepperParser::ConstructorParamContext* context) override {
            if (context->This()) {
                lvaluePush(Pending::New<VariableDef>());
            }
        }

        void exitConstructorParam(PepperParser::ConstructorParamContext* context) override {
            // normal params are handled by ParamDeclaration, this is for this-initializers
            if (context->This()) {
                lvaluePop<VariableDef>();
                auto fieldName = context->Identifier()->toString();
                Expression* defaultValue = nullptr;
                if (context->Assign()) {
                    defaultValue = rvaluePop<Expression>();
                }

                // lookup the desired field
                StructDef* st = nullptr;
                FunctionDef* func = nullptr;
                if (auto ctor = builder->targetAs<ConstructorDef>()) {
                    func = ctor;
                    st = ctor->Struct;
                } else if (auto method = builder->targetAs<MethodDef>()) {
                    func = method;
                    st = method->Struct.value();
                }
                auto field = Query(st->Fields).find([&](auto& f) { return f->Name == fieldName; });
                if (!field) {
                    throw CompileError(builder->Source, "Unknown field {0} found during this initializer", fieldName);
                }

                // generate a parameter to receive the argument value/establish defaults
                auto paramName = "__this__" + fieldName;
                func->Parameters.emplace_back(paramName, field.value()->Type, defaultValue);

                // Add the assignment to the field to the ctor
                func->Body->Items.push_back(
                    new Assign(new MemberRef(new ThisRef(), fieldName), new SymbolRef(paramName)));
            }
        }

        void enterTraitDeclaration(PepperParser::TraitDeclarationContext* context) override {
            auto spec = parseTypeName(context->typeName());
            auto trait = new TraitDecl(spec);
            builder->beginTrait(trait);
        }

        void exitTraitDeclaration(PepperParser::TraitDeclarationContext*) override {
            builder->endTrait();
        }

        void enterFunctionDeclaration(PepperParser::FunctionDeclarationContext* context) override {
            auto returnType = context->typeName() ? parseTypeName(context->typeName()) : TypeName{"this"};
            auto identifier = parseFunctionSpec(context->functionName());
            auto storageClass = context->storageClass() && context->storageClass()->Static()
                                    ? FunctionNode::StorageClassType::Static
                                    : FunctionNode::StorageClassType::Default;
            auto function = new MethodDecl(returnType, identifier, {});
            function->StorageClass = storageClass;
            lvaluePush(function);
            builder->beginFunction(function);
        }

        void exitFunctionDeclaration(PepperParser::FunctionDeclarationContext*) override {
            builder->endFunction();
            lvaluePop<MethodDecl>();
        }

        void enterExtensionDefinition(PepperParser::ExtensionDefinitionContext* context) override {
            auto structType = parseTypeDeclaration(context->typeDeclaration()[0]);
            if (context->With()) {
                auto traitDecl = parseTypeDeclaration(context->typeDeclaration()[1]);
                auto traitDef = new TraitDef(traitDecl, structType);
                builder->beginExtension(traitDef);
            } else {
                auto ext = new ExtensionDef(structType);
                builder->beginExtension(ext);
            }
        }

        void exitExtensionDefinition(PepperParser::ExtensionDefinitionContext*) override {
            builder->endExtension();
        }

        void beginFunctionCall() {
            auto call = Pending::New<FunctionCall>();
            lvaluePush(call);
        }

        template <typename C>
        void endFunctionCall(C* context) {
            lvaluePop<FunctionCall>();

            ExprList args;
            auto providedArgs = context->argumentList()->argument();
            for (int argIdx = 0; argIdx < providedArgs.size(); ++argIdx) {
                args.insert(args.begin(), rvaluePop<Expression>());
            }

            auto symbol = rvaluePop<SymbolRef>(); // identifiers are always pushed as rvalues

            if (symbol->is<MemberRef>()) { // method
                auto member = symbol->as<MemberRef>();
                assert(member->LHS && "MemberRef created without an object reference");

                auto call = new MethodCall(member->LHS, member->Name, args);
                builder->insert(call);
                return;
            }

            // TODO: Move this into a pass on the AST
            auto spec = !symbol->Type.empty() ? symbol->Type : symbol->Name;
            if (spec.Name == "sizeof") {
                if (spec.SubTypes.size() != 1)
                    throw CompileError(builder->Source, "sizeof<T>() accepts only a single generic type argument");
                auto typeName = spec.SubTypes.front();
                auto sizeOf = new SizeOf(typeName);
                builder->insert(sizeOf);
                return;
            }
            auto call = new FunctionCall(spec, std::move(args));
            builder->insert(call);
        }

        // When a generic class ctor is called, e.g. mystruct<int>() the typename is
        // the name of the function
        void enterGenericCtor(PepperParser::GenericCtorContext* context) override {
            beginFunctionCall();
            auto typeName = parseTypeName(context->typeName());
            rvaluePush(new SymbolRef(typeName));
        }

        void exitGenericCtor(PepperParser::GenericCtorContext* context) override {
            endFunctionCall(context);
        }

        void enterFunctionCall(PepperParser::FunctionCallContext*) override {
            beginFunctionCall();
        }

        void exitFunctionCall(PepperParser::FunctionCallContext* context) override {
            endFunctionCall(context);
        }

        void enterReturn(PepperParser::ReturnContext*) override {
            auto ret = Pending::New<Return>();
            lvaluePush(ret);
        }

        void exitReturn(PepperParser::ReturnContext* context) override {
            lvaluePop<Return>();
            auto function = builder->targetAs<FunctionDef>();
            Expression* returnValue = nullptr;
            if (context->expression()) {
                returnValue = rvaluePop<Expression>();
            }
            auto ret = new Return(function->ReturnType, returnValue);
            builder->insert(ret);
        }

        void enterMemberAccess(PepperParser::MemberAccessContext*) override {
            auto memberRef = Pending::New<MemberRef>();
            lvaluePush(memberRef);
        }

        void exitMemberAccess(PepperParser::MemberAccessContext* context) override {
            auto lhs = rvaluePop<Expression>();
            auto rhs = context->Identifier()->toString();
            lvaluePop<MemberRef>();
            auto memberRef = new MemberRef(lhs, rhs);
            builder->insert(memberRef);
        }

        void enterIndexAccess(PepperParser::IndexAccessContext*) override {
            auto index = Pending::New<Index>();
            lvaluePush(index);
        }

        void exitIndexAccess(PepperParser::IndexAccessContext*) override {
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            lvaluePop<Index>();
            auto index = new Index(lhs, rhs);
            builder->insert(index);
        }

        void enterIfStatement(PepperParser::IfStatementContext* context) override {
            auto branch = new If();
            if (context->ifBranch()) {
                branch->Then = new Block("then");
            }
            if (context->elseBranch()) {
                branch->Else = new Block("else");
            }
            builder->beginScope("select");
            lvaluePush(branch);
        }

        void exitIfStatement(PepperParser::IfStatementContext*) override {
            auto branch = lvaluePop<Branch>();
            builder->endScope();
            builder->insert(branch);
        }

        void enterIfBranch(PepperParser::IfBranchContext* context) override {}

        void exitIfBranch(PepperParser::IfBranchContext*) override {
            builder->endBlock();
        }

        void exitIfCondition(PepperParser::IfConditionContext*) override {
            auto branch = lvaluePeek<Branch>();
            branch->Condition = rvaluePop<Expression>();
            builder->beginBlock(branch->Then);
        }

        void enterElseBranch(PepperParser::ElseBranchContext*) override {
            auto branch = lvaluePeek<Branch>();
            builder->beginBlock(branch->Else);
        }

        void exitElseBranch(PepperParser::ElseBranchContext*) override {
            builder->endBlock();
        }

        void enterTernary(PepperParser::TernaryContext*) override {
            auto branch = new Ternary();
            lvaluePush(branch);
        }

        void enterWhileLoop(PepperParser::WhileLoopContext*) override {
            auto loop = new While();
            loop->Body = new Block();
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
            auto loop = new ForRange();
            loop->Body = new Block();
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

        void exitForLoop(PepperParser::ForLoopContext* context) override {}

        void exitTernary(PepperParser::TernaryContext*) override {
            auto branch = lvaluePop<Ternary>();
            branch->FalseResult = rvaluePop<Expression>();
            branch->TrueResult = rvaluePop<Expression>();
            branch->Condition = rvaluePop<Expression>();
            builder->insert(branch);
        }

        template <typename N>
        void beginUnaryOp() {
            lvaluePush(Pending::New<N>());
        }

        template <typename N>
        void endUnaryOp() {
            lvaluePop<N>();
            auto operand = rvaluePop<Expression>();
            auto op = new N(operand);
            rvaluePushOrInsert(op);
        }

        void enterUnaryPlus(PepperParser::UnaryPlusContext*) override {
            beginUnaryOp<Plus>();
        }

        void exitUnaryPlus(PepperParser::UnaryPlusContext*) override {
            endUnaryOp<Plus>();
        }

        void enterUnaryMinus(PepperParser::UnaryMinusContext*) override {
            beginUnaryOp<Minus>();
        }

        void exitUnaryMinus(PepperParser::UnaryMinusContext*) override {
            endUnaryOp<Minus>();
        }

        void enterPreIncrement(PepperParser::PreIncrementContext*) override {
            beginUnaryOp<PreIncrement>();
        }

        void exitPreIncrement(PepperParser::PreIncrementContext*) override {
            endUnaryOp<PreIncrement>();
        }

        void enterPostIncrement(PepperParser::PostIncrementContext*) override {
            beginUnaryOp<PostIncrement>();
        }

        void exitPostIncrement(PepperParser::PostIncrementContext*) override {
            endUnaryOp<PostIncrement>();
        }

        void enterPreDecrement(PepperParser::PreDecrementContext*) override {
            beginUnaryOp<PreDecrement>();
        }

        void exitPreDecrement(PepperParser::PreDecrementContext*) override {
            endUnaryOp<PreDecrement>();
        }

        void enterPostDecrement(PepperParser::PostDecrementContext*) override {
            beginUnaryOp<PostDecrement>();
        }

        void exitPostDecrement(PepperParser::PostDecrementContext*) override {
            endUnaryOp<PostDecrement>();
        }

        void enterBitNot(PepperParser::BitNotContext*) override {
            beginUnaryOp<BitNot>();
        }

        void exitBitNot(PepperParser::BitNotContext*) override {
            endUnaryOp<BitNot>();
        }

        void enterLogicalNot(PepperParser::LogicalNotContext*) override {
            beginUnaryOp<LogicalNot>();
        }

        void exitLogicalNot(PepperParser::LogicalNotContext*) override {
            endUnaryOp<LogicalNot>();
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
            builder->insert(new Op(lhs, rhs));
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

        void enterBitAnd(PepperParser::BitAndContext*) override {
            beginBinaryOp<BitAnd>();
        }

        void exitBitAnd(PepperParser::BitAndContext*) override {
            endBinaryOp<BitAnd>();
        }

        void enterBitXor(PepperParser::BitXorContext*) override {
            beginBinaryOp<BitXor>();
        }

        void exitBitXor(PepperParser::BitXorContext*) override {
            endBinaryOp<BitXor>();
        }

        void enterBitOr(PepperParser::BitOrContext*) override {
            beginBinaryOp<BitOr>();
        }

        void exitBitOr(PepperParser::BitOrContext*) override {
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

        void enterIdentical(PepperParser::IdenticalContext*) override {
            beginBinaryOp<Identical>();
        }

        void exitIdentical(PepperParser::IdenticalContext*) override {
            endBinaryOp<Identical>();
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
            auto op = new Op();
            lvaluePush(op);
        }

        template <typename Op>
        void endAssign() {
            auto op = lvaluePop<Op>();
            auto rhs = rvaluePop<Expression>();
            auto lhs = rvaluePop<Expression>();
            rvaluePushOrInsert(new Op(lhs, rhs));
        }

        void enterAssignment(PepperParser::AssignmentContext*) override {
            beginAssign<Assign>();
        }

        void exitAssignment(PepperParser::AssignmentContext*) override {
            endAssign<Assign>();
        }

        void enterAssignmentOp(PepperParser::AssignmentOpContext* context) override {
            auto op = context->assignmentOperator();
            if (op->MulAssign())
                beginAssign<MulAssign>();
            else if (op->DivAssign())
                beginAssign<DivAssign>();
            else if (op->ModAssign())
                beginAssign<ModAssign>();
            else if (op->AddAssign())
                beginAssign<AddAssign>();
            else if (op->SubAssign())
                beginAssign<SubAssign>();
            else if (op->LShiftAssign())
                beginAssign<LShiftAssign>();
            else if (op->RShiftAssign())
                beginAssign<RShiftAssign>();
            else if (op->BitAndAssign())
                beginAssign<BitAndAssign>();
            else if (op->BitOrAssign())
                beginAssign<BitOrAssign>();
            else if (op->BitXorAssign())
                beginAssign<BitXorAssign>();
        }

        void exitAssignmentOp(PepperParser::AssignmentOpContext* context) override {
            auto op = context->assignmentOperator();
            if (op->MulAssign())
                endAssign<MulAssign>();
            else if (op->DivAssign())
                endAssign<DivAssign>();
            else if (op->ModAssign())
                endAssign<ModAssign>();
            else if (op->AddAssign())
                endAssign<AddAssign>();
            else if (op->SubAssign())
                endAssign<SubAssign>();
            else if (op->LShiftAssign())
                endAssign<LShiftAssign>();
            else if (op->RShiftAssign())
                endAssign<RShiftAssign>();
            else if (op->BitAndAssign())
                endAssign<BitAndAssign>();
            else if (op->BitOrAssign())
                endAssign<BitOrAssign>();
            else if (op->BitXorAssign())
                endAssign<BitXorAssign>();
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
            Node::PushSource(SourceLocation(name, 0, 0));
            antlr4::tree::ParseTree* tree = parser.compilationUnit();
            ParserListener listener;
            antlr4::tree::ParseTreeWalker::DEFAULT.walk(&listener, tree);
            Node::PopSource();
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
