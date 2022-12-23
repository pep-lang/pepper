
#include "Codegen.h"

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "Codegen/Function.h"
#include "Codegen/Scope.h"
#include "Codegen/TypeOps.h"
#include "Compiler/Context.h"
#include "Compiler/Exceptions.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"
#include <functional>
#include <unordered_map>

namespace pepper {
    using namespace pepper::ast;

    static llvm::Value* codegen(Ref<Node> node);

    static Ref<llvm::IRBuilderBase> ir() {
        return Context::get().locals()->builder();
    }

    static llvm::Value* emit(Ref<VariableRef> variableRef) {
        auto value = Context::get().locals()->findSymbol(variableRef->identifier());
        return value;
    }

    static llvm::Value* emit(Ref<VariableDef> variableDef) {
        auto value = ir()->CreateAlloca(variableDef->type(), nullptr, variableDef->identifier());
        if (variableDef->defaultValue()) {
            auto defaultValue = codegen(variableDef->defaultValue());
            ir()->CreateStore(defaultValue, value);
        }
        Context::get().locals()->newSymbol(variableDef->identifier(), value);
        return value;
    }

    static llvm::Value* emit(Ref<StringLiteral> stringLiteral) {
        auto value = ir()->CreateGlobalString(stringLiteral->value());
        return value;
    }

    static llvm::Value* emit(Ref<IntegerLiteral> intLiteral) {
        auto value = llvm::ConstantInt::get(intLiteral->type(), intLiteral->value());
        return value;
    }

    static llvm::Value* emit(Ref<FloatLiteral> floatLiteral) {
        auto value = llvm::ConstantFP::get(floatLiteral->type(), floatLiteral->value());
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
            auto local = ir()->CreateAlloca(param.Type, nullptr, param.Name);
            Context::get().locals()->newSymbol(param.Name, local);
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

    static llvm::Value* emit(Ref<FunctionDef> functionDef) {
        auto function =
            Ref<UserFunction>::New(functionDef->identifier(), functionDef->returnType(), functionDef->params());
        codegen(function, functionDef);
        return function->function();
    }

    static llvm::Value* emit(Ref<Return> ret) {
        return nullptr;
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

    static llvm::Value* emit(Ref<BinaryOp> op) {
        auto lhs = codegen(op->lhs());
        auto rhs = codegen(op->rhs());
        auto operandType = op->operandType(lhs->getType(), rhs->getType());
        auto typeOps = TypeOps::get(operandType);
        auto lhsOperand = typeOps->coerce(lhs);
        auto rhsOperand = typeOps->coerce(rhs);
        auto typeOp = binaryOp(op);
        auto result = std::invoke(typeOp, typeOps, lhsOperand, rhsOperand);
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

    void Codegen::emit() {
        for (const auto& root : Tree->roots()) {
            codegen(root);
        }
    }
} // namespace pepper
