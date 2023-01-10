//
// Created by Justin Boswell on 12/26/22.
//

#include "AST/BinaryOps.h"
#include "Codegen.h"
#include "Core/Exceptions.h"
#include "Frontend/TypeOps.h"
#include "Frontend/Types.h"

namespace pepper {
    using namespace pepper::ast;

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

    static Ref<Type> largestIntType(Ref<Type> lhs, Ref<Type> rhs) {
        auto bits = std::max(lhs->llvmType()->getIntegerBitWidth(), rhs->llvmType()->getIntegerBitWidth());
        return (bits > 32) ? Types::Int64 : Types::Int32;
    }

    static Ref<Type> largestOperandType(Ref<Type> lhs, Ref<Type> rhs) {
        if (lhs->llvmType()->isIntegerTy() && rhs->llvmType()->isIntegerTy()) {
            return largestIntType(lhs, rhs);
        }
        if (lhs->llvmType()->isFloatingPointTy() || rhs->llvmType()->isFloatingPointTy()) {
            auto bits = std::max(lhs->llvmType()->getPrimitiveSizeInBits(), rhs->llvmType()->getPrimitiveSizeInBits());
            return (bits > 32) ? Types::Double : Types::Float;
        }
        return nullptr;
    }

    static Ref<Type> structOperandType(Ref<BinaryOp> op, Ref<Type> lhs, Ref<Type> rhs) {
        if (op->is<Assign>() && lhs == rhs) {
            return lhs;
        }
        if ((op->is<Equal>() || op->is<NotEqual>()) && lhs->llvmType()->isPointerTy() &&
            rhs->llvmType()->isPointerTy()) {
            return Types::VoidPtr;
        }
        throw CompileError(
            op->Source, "Cannot perform {0} between {1} and {2}", op->rtti()->name(), lhs->name(), rhs->name());
    }

    static Ref<Type> operandType(Ref<BinaryOp> op, Ref<Type> lhs, Ref<Type> rhs) {
        if (lhs->llvmType()->isStructTy() || lhs->llvmType()->isPointerTy()) {
            return structOperandType(op, lhs, rhs);
        }
        if (lhs->llvmType()->isIntegerTy() && lhs->llvmType()->isIntegerTy()) {
            auto intType = llvm::StringSwitch<Ref<Type>>(op->rtti()->name())
                               .Cases("LShift", "RShift", "BitAnd", "BitOr", "BitXor", largestIntType(lhs, rhs))
                               .Cases("LShiftAssign",
                                      "RShiftAssign",
                                      "BitAndAssign",
                                      "BitOrAssign",
                                      "BitXorAssign",
                                      largestIntType(lhs, rhs))
                               .Default(nullptr);
            if (intType)
                return intType;
        }
        return llvm::StringSwitch<Ref<Type>>(op->rtti()->name())
            .Cases("Add", "Sub", "Mul", "Div", "Mod", "Pow", largestOperandType(lhs, rhs))
            .Cases("Equal", "NotEqual", "Less", "LessEqual", "Greater", "GreaterEqual", largestOperandType(lhs, rhs))
            .Cases("LogicalAnd", "LogicalOr", Types::Bool)
            .Cases("AddAssign", "SubAssign", "MulAssign", "ModAssign", largestOperandType(lhs, rhs))
            .Case("Assign", lhs);
    }

    static auto compoundOp(Ref<CompoundAssign> op) {
        if (op->is<AddAssign>())
            return &TypeOps::add;
        if (op->is<SubAssign>())
            return &TypeOps::sub;
        if (op->is<MulAssign>())
            return &TypeOps::mul;
        if (op->is<DivAssign>())
            return &TypeOps::div;
        if (op->is<ModAssign>())
            return &TypeOps::mod;
        if (op->is<LShiftAssign>())
            return &TypeOps::lshift;
        if (op->is<RShiftAssign>())
            return &TypeOps::rshift;
        if (op->is<BitAndAssign>())
            return &TypeOps::bitAnd;
        if (op->is<BitOrAssign>())
            return &TypeOps::bitOr;
        if (op->is<BitXorAssign>())
            return &TypeOps::bitXor;
        throw InternalCompilerError("Unknown compound assignment op: {0}", op->rtti()->name());
    }

    Value Codegen::emit(Ref<Assign> op) {
        auto rhs = codegen(op->RHS);
        auto lhs = codegen(op->LHS);
        auto typeOps = lhs.Ty->ops();
        typeOps->assign(lhs, typeOps->coerce(rhs));
        return lhs;
    }

    Value Codegen::emit(Ref<CompoundAssign> op) {
        auto rhs = codegen(op->RHS);
        auto lhs = codegen(op->LHS);
        auto opType = lhs.Ty;
        if (!opType) {
            throw InternalCompilerError("Unable to determine operand types for {0} {2} {1}",
                                        Types::toString(lhs->getType()),
                                        Types::toString(rhs->getType()),
                                        op->rtti()->name());
        }
        auto typeOps = opType->ops();
        auto mathOp = compoundOp(op);
        auto lhsOperand = typeOps->coerce(read(lhs));
        auto rhsOperand = typeOps->coerce(read(rhs));
        auto result = std::invoke(mathOp, typeOps, lhsOperand, rhsOperand);
        typeOps->assign(lhs, result);
        return lhs;
    }

    Value Codegen::emit(Ref<BinaryOp> op) {
        if (op->is<CompoundAssign>())
            return emit(op.as<CompoundAssign>());
        if (op->is<Assign>())
            return emit(op.as<Assign>());

        auto rhs = codegen(op->RHS);
        auto lhs = codegen(op->LHS);
        lhs = read(lhs);
        rhs = read(rhs);
        auto opType = operandType(op, lhs.Ty, rhs.Ty);
        if (!opType) {
            throw InternalCompilerError("Unable to determine operand types for {0} {2} {1}",
                                        Types::toString(lhs->getType()),
                                        Types::toString(rhs->getType()),
                                        op->rtti()->name());
        }
        auto typeOps = opType->ops();
        auto lhsOperand = typeOps->coerce(lhs);
        auto rhsOperand = typeOps->coerce(rhs);
        auto typeOp = binaryOp(op);
        auto result = std::invoke(typeOp, typeOps, lhsOperand, rhsOperand);
        return result;
    }

    static auto unaryOp(Ref<UnaryOp> op) {
        if (op->is<Plus>())
            return &TypeOps::pos;
        if (op->is<Minus>())
            return &TypeOps::neg;
        if (op->is<PreIncrement>())
            return &TypeOps::preIncrement;
        if (op->is<PostIncrement>())
            return &TypeOps::postIncrement;
        if (op->is<PreDecrement>())
            return &TypeOps::preDecrement;
        if (op->is<PostDecrement>())
            return &TypeOps::postDecrement;
        if (op->is<LogicalNot>())
            return &TypeOps::logicalNot;
        if (op->is<BitNot>())
            return &TypeOps::bitNot;
        throw InternalCompilerError("Unknown unary op: {0}", op->rtti()->name());
    }

    Value Codegen::emit(Ref<UnaryOp> op) {
        if (op->is<Minus>()) {
            if (op->Operand->is<IntegerLiteral>()) {
                auto intLiteral = op->Operand.as<IntegerLiteral>();
                return codegen(Ref<IntegerLiteral>::New(-intLiteral->Value));
            }
            if (op->Operand->is<FloatLiteral>()) {
                auto floatLiteral = op->Operand.as<FloatLiteral>();
                return codegen(Ref<FloatLiteral>::New(-floatLiteral->Value));
            }
        }

        auto operand = codegen(op->Operand);
        auto type = operand.Ty;
        auto ops = type->ops();
        auto typeOp = unaryOp(op);
        auto result = std::invoke(typeOp, ops, operand);
        return result;
    }
} // namespace pepper
