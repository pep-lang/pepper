
#include "Codegen.h"
#include <functional>
#include <unordered_map>

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "Codegen/Context.h"
#include "Codegen/Function.h"
#include "Codegen/ModuleContext.h"
#include "Codegen/Scope.h"
#include "Codegen/TypeOps.h"
#include "Codegen/Types.h"
#include "Core/Exceptions.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper {
    using namespace pepper::ast;

    static llvm::Value* codegen(Ref<Node> node);

    template <typename N>
    static llvm::Value* maybeCodegen(Ref<N> node) {
        return node ? codegen(node) : nullptr;
    }

    static Ref<llvm::IRBuilderBase> ir() {
        return Context::get().locals()->builder();
    }

    static Ref<llvm::IRBuilderBase> registers() {
        return Context::get().locals()->registers();
    }

    using llvm::cast;
    using llvm::isa;

    static llvm::Value* read(llvm::Value* value) {
        if (isa<llvm::AllocaInst>(*value)) {
            auto allocaInst = cast<llvm::AllocaInst>(value);
            auto type = allocaInst->getAllocatedType();
            return ir()->CreateLoad(type, value);
        }
        return value;
    }

    static llvm::Value* emit(Ref<VariableRef> variableRef) {
        auto value = Context::get().locals()->findSymbol(variableRef->identifier());
        Context::get().locals()->pushStack(value);
        return value;
    }

    static llvm::Value* emit(Ref<VariableDef> variableDef) {
        auto type = Types::get(variableDef->type());
        auto value = registers()->CreateAlloca(*type, nullptr, variableDef->identifier());
        if (variableDef->defaultValue()) {
            auto defaultValue = codegen(variableDef->defaultValue());
            auto typeOps = TypeOps::get(*type);
            auto coercedValue = typeOps->coerce(defaultValue);
            ir()->CreateStore(coercedValue, value);
        }
        Context::get().locals()->newSymbol(variableDef->identifier(), value);
        return value;
    }

    static llvm::Value* emit(Ref<StringLiteral> stringLiteral) {
        auto value = ir()->CreateGlobalString(stringLiteral->value());
        Context::get().locals()->pushStack(value);
        return value;
    }

    static llvm::Value* emit(Ref<IntegerLiteral> intLiteral) {
        auto value = llvm::ConstantInt::get(*Types::Int64, intLiteral->value());
        Context::get().locals()->pushStack(value);
        return value;
    }

    static llvm::Value* emit(Ref<FloatLiteral> floatLiteral) {
        auto value = llvm::ConstantFP::get(*Types::Double, floatLiteral->value());
        Context::get().locals()->pushStack(value);
        return value;
    }

    static llvm::Value* emit(Ref<StructDef> structDef) {
        return nullptr;
    }

    static llvm::Value* emit(Ref<FieldDef> fieldDef) {
        return nullptr;
    }

    static llvm::Value* emit(Ref<MemberRef> memberRef) {
        return nullptr;
    }

    static llvm::Value* emit(Ref<ThisRef> thisRef) {
        auto thisPtr = Context::get().locals()->findSymbol("this");
        return thisPtr;
    }

    static void codegen(Ref<UserFunction> function, Ref<FunctionDef> funcDef) {
        Context::get().pushFunction(function);

        // Allocate parameters
        auto llvmFunction = function->function();
        auto args = llvm::SmallVector<llvm::Value*>();
        for (int paramIdx = 0; paramIdx < function->params().size(); ++paramIdx) {
            auto param = function->params()[paramIdx];
            auto arg = llvmFunction->getArg(paramIdx);
            auto local = ir()->CreateAlloca(*param.ParamType, nullptr, param.ParamName);
            Context::get().locals()->newSymbol(param.ParamName, local);
            args.push_back(local);
        }

        // Push all known variables at the top of the function block
        std::for_each(funcDef->locals().begin(), funcDef->locals().end(), [&](const auto& local) { codegen(local); });

        // Emit the body of the function, after ensuring there is a return instruction
        auto lastExpr = (funcDef->body().size()) ? funcDef->body().back() : nullptr;
        if (!lastExpr || !lastExpr->is<Return>()) {
            funcDef->body().push_back(Ref<Return>::New(funcDef));
        }
        std::for_each(funcDef->body().begin(), funcDef->body().end(), [&](const auto& expr) { codegen(expr); });

        Context::get().popScope();
    }

    static pepper::Params astToTypedParams(const ast::Params& src) {
        pepper::Params params;
        for (auto p : src) {
            params.emplace_back(p.Identifier, Types::get(p.Type), maybeCodegen(p.Default));
        }
        return params;
    }

    static llvm::Value* emit(Ref<FunctionDef> functionDef) {
        auto returnType = Types::get(functionDef->returnType());
        auto params = astToTypedParams(functionDef->params());
        auto function = Ref<UserFunction>::New(functionDef->identifier(), returnType, params);
        codegen(function, functionDef);
        return function->function();
    }

    static llvm::Value* emit(Ref<Return> ret) {
        if (ret->value()) {
            auto returnValue = Context::get().locals()->popStack();
            auto func = ret->target();
            auto returnType = Types::get(func->returnType());
            auto type = TypeOps::get(*returnType);
            auto rv = type->coerce(returnValue);
            return ir()->CreateRet(rv);
        }
        return ir()->CreateRetVoid();
    }

    static llvm::Value* emit(Ref<FunctionCall> call) {
        return nullptr;
    }

    static auto binaryOp(Ref<BinaryOp> op) {
        if (op->is<Assign>())
            return &TypeOps::assign;
        if (op->is<Add>())
            return &TypeOps::add;
        if (op->is<Sub>())
            return &TypeOps::sub;
        if (op->is<Mul>())
            return &TypeOps::mul;
        if (op->is<Div>())
            return &TypeOps::div;
        if (op->is<Mod>())
            return &TypeOps::mod;
        if (op->is<Pow>())
            return &TypeOps::pow;
        if (op->is<LShift>())
            return &TypeOps::lshift;
        if (op->is<RShift>())
            return &TypeOps::rshift;
        if (op->is<Equal>())
            return &TypeOps::equal;
        if (op->is<NotEqual>())
            return &TypeOps::notEqual;
        if (op->is<Assign>())
            return &TypeOps::assign;
        if (op->is<Less>())
            return &TypeOps::less;
        if (op->is<LessEqual>())
            return &TypeOps::lessEq;
        if (op->is<Greater>())
            return &TypeOps::greater;
        if (op->is<GreaterEqual>())
            return &TypeOps::greaterEq;
        if (op->is<BitAnd>())
            return &TypeOps::bitAnd;
        if (op->is<BitOr>())
            return &TypeOps::bitOr;
        if (op->is<BitXor>())
            return &TypeOps::bitXor;
        if (op->is<LogicalAnd>())
            return &TypeOps::bitAnd;
        if (op->is<LogicalOr>())
            return &TypeOps::bitOr;
        throw InternalCompilerError("Unknown binary op: {0}", op->rtti()->name());
    }

    static Ref<Type> largestIntType(llvm::Type* lhs, llvm::Type* rhs) {
        auto bits = std::max(lhs->getIntegerBitWidth(), rhs->getIntegerBitWidth());
        return (bits > 32) ? Types::Int64 : Types::Int32;
    }

    static Ref<Type> largestOperandType(llvm::Type* lhs, llvm::Type* rhs) {
        if (lhs->isIntegerTy() && lhs->isIntegerTy()) {
            return largestIntType(lhs, rhs);
        }
        if (lhs->isFloatingPointTy() || lhs->isFloatingPointTy()) {
            auto bits = std::max(lhs->getPrimitiveSizeInBits(), rhs->getPrimitiveSizeInBits());
            return (bits > 32) ? Types::Double : Types::Float;
        }
        return nullptr;
    }

    static Ref<Type> structOperandType(Ref<BinaryOp> op, llvm::Type* lhs, llvm::Type* rhs) {
        return nullptr;
    }

    static Ref<Type> operandType(Ref<BinaryOp> op, llvm::Type* lhs, llvm::Type* rhs) {
        if (lhs->isStructTy() || lhs->isPointerTy()) {
            return structOperandType(op, lhs, rhs);
        }
        return llvm::StringSwitch<Ref<Type>>(op->rtti()->name())
            .Cases("Add", "Sub", "Mul", "Div", "Mod", "Pow", largestOperandType(lhs, rhs))
            .Cases("Equal", "NotEqual", "Less", "LessEqual", "Greater", "GreaterEqual", largestOperandType(lhs, rhs))
            .Cases("LShift", "RShift", "BitAnd", "BitOr", "BitXor", largestIntType(lhs, rhs))
            .Cases("LogicalAnd", "LogicalOr", Types::Bool)
            .Case("Assign", Types::get(lhs));
    }

    static llvm::Value* emit(Ref<BinaryOp> op) {
        auto lhs = codegen(op->lhs());
        auto rhs = codegen(op->rhs());
        lhs = read(lhs);
        rhs = read(rhs);
        auto opType = operandType(op, lhs->getType(), rhs->getType());
        if (!opType) {
            throw InternalCompilerError("Unable to determine operand types for {0} {2} {1}",
                                        Types::toString(lhs->getType()),
                                        Types::toString(rhs->getType()),
                                        op->rtti()->name());
        }
        auto typeOps = TypeOps::get(*opType);
        auto lhsOperand = typeOps->coerce(lhs);
        auto rhsOperand = typeOps->coerce(rhs);
        auto typeOp = binaryOp(op);
        auto result = std::invoke(typeOp, typeOps, lhsOperand, rhsOperand);
        Context::get().locals()->pushStack(result);
        return result;
    }

    static llvm::Value* codegen(Ref<Node> node) {
        if (node->is<BinaryOp>())
            return emit(node.as<BinaryOp>());
        if (node->is<StructDef>())
            return emit(node.as<StructDef>());
        if (node->is<FieldDef>())
            return emit(node.as<FieldDef>());
        if (node->is<VariableDef>())
            return emit(node.as<VariableDef>());
        if (node->is<ThisRef>())
            return emit(node.as<ThisRef>());
        if (node->is<MemberRef>())
            return emit(node.as<MemberRef>());
        if (node->is<VariableRef>())
            return emit(node.as<VariableRef>());
        if (node->is<FunctionDef>())
            return emit(node.as<FunctionDef>());
        if (node->is<Return>())
            return emit(node.as<Return>());
        if (node->is<FunctionCall>())
            return emit(node.as<FunctionCall>());
        if (node->is<StringLiteral>())
            return emit(node.as<StringLiteral>());
        if (node->is<FloatLiteral>())
            return emit(node.as<FloatLiteral>());
        if (node->is<IntegerLiteral>())
            return emit(node.as<IntegerLiteral>());
        throw InternalCompilerError("Unknown AST node");
    }

    Codegen::Codegen(const Name& moduleName, Ref<ast::AST> tree)
        : Tree(tree) {
        Ctx = Ref<Context>::New(moduleName);
        Module = Ctx->moduleContext();
    }

    Ref<ModuleContext> Codegen::emit() {
        for (const auto& root : Tree->roots()) {
            codegen(root);
        }
        return Context::get().moduleContext();
    }
} // namespace pepper
