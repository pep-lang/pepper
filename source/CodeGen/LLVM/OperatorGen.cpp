

#include "CodeGen/LLVM/LLVMCodeGenerator.h"
#include "Core/Exceptions.h"
#include "Core/LLVMUtils.h"
#include "Sema/Model/BinaryOps.h"
#include "Sema/Operations.h"
#include "Sema/Types.h"

namespace pepper {
    using namespace pepper::sema;

    static auto binaryOp(const BinaryOp* op) {
        if (op->is<Assign>())
            return &Operations::assign;
        if (op->is<Add>())
            return &Operations::add;
        if (op->is<Sub>())
            return &Operations::sub;
        if (op->is<Mul>())
            return &Operations::mul;
        if (op->is<Div>())
            return &Operations::div;
        if (op->is<Mod>())
            return &Operations::mod;
        if (op->is<Pow>())
            return &Operations::pow;
        if (op->is<LShift>())
            return &Operations::lshift;
        if (op->is<RShift>())
            return &Operations::rshift;
        if (op->is<Equal>() || op->is<Identical>())
            return &Operations::equal;
        if (op->is<NotEqual>())
            return &Operations::notEqual;
        if (op->is<Assign>())
            return &Operations::assign;
        if (op->is<Less>())
            return &Operations::less;
        if (op->is<LessEqual>())
            return &Operations::lessEq;
        if (op->is<Greater>())
            return &Operations::greater;
        if (op->is<GreaterEqual>())
            return &Operations::greaterEq;
        if (op->is<BitAnd>())
            return &Operations::bitAnd;
        if (op->is<BitOr>())
            return &Operations::bitOr;
        if (op->is<BitXor>())
            return &Operations::bitXor;
        if (op->is<LogicalAnd>())
            return &Operations::bitAnd;
        if (op->is<LogicalOr>())
            return &Operations::bitOr;
        throw InternalCompilerError("Unknown binary op: {0}", op->rtti()->name());
    }

    static Ref<Type> largestIntType(Ref<Type> lhs, Ref<Type> rhs) {
        auto lhsType = Types::get(lhs.get());
        auto rhsType = Types::get(rhs.get());
        auto bits = std::max(lhsType->getIntegerBitWidth(), rhsType->getIntegerBitWidth());
        return (bits > 32) ? Types::Int64 : Types::Int32;
    }

    static Ref<Type> largestOperandType(Ref<Type> lhs, Ref<Type> rhs) {
        auto lhsType = Types::get(lhs.get());
        auto rhsType = Types::get(rhs.get());
        if (lhsType->isIntegerTy() && rhsType->isIntegerTy()) {
            return largestIntType(lhs, rhs);
        }
        if (lhsType->isFloatingPointTy() || rhsType->isFloatingPointTy()) {
            auto bits = std::max(lhsType->getPrimitiveSizeInBits(), rhsType->getPrimitiveSizeInBits());
            return (bits > 32) ? Types::Double : Types::Float;
        }
        return nullptr;
    }

    static Ref<Type> structOperandType(const BinaryOp* op, Ref<Type> lhs, Ref<Type> rhs) {
        if (op->is<Assign>() && lhs == rhs) {
            return lhs;
        }
        auto lhsType = Types::get(lhs.get());
        auto rhsType = Types::get(rhs.get());
        const bool isEq = op->is<Equal>() || op->is<NotEqual>() || op->is<Identical>();
        if (isEq && lhsType->isPointerTy() && rhsType->isPointerTy()) {
            return Types::VoidPtr;
        }
        throw CompileError(
            op->source_loc, "Cannot perform {0} between {1} and {2}", op->rtti()->name(), lhs->name(), rhs->name());
    }

    static Ref<Type> operandType(const BinaryOp* op, Ref<Type> lhs, Ref<Type> rhs) {
        if ((lhs->is_pointer() && lhs.as<PointerType>()->pointee_type()->is_struct()) ||
            (rhs->is_pointer() && rhs.as<PointerType>()->pointee_type()->is_struct())) {
            return structOperandType(op, lhs, rhs);
        }
        auto lhsType = Types::get(lhs.get());
        auto rhsType = Types::get(rhs.get());

        if (lhsType->isPointerTy() && rhsType->isIntegerTy()) {
            return lhs;
        }

        auto op_name = op->rtti()->name();
        const auto colon_pos = op_name.find_last_of(':');
        op_name = colon_pos != std::string::npos ? op_name.substr(colon_pos + 1) : op_name;

        if (lhsType->isIntegerTy() && rhsType->isIntegerTy()) {
            auto intType = llvm::StringSwitch<Ref<Type>>(op_name)
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

        return llvm::StringSwitch<Ref<Type>>(op_name)
            .Cases("Add", "Sub", "Mul", "Div", "Mod", "Pow", largestOperandType(lhs, rhs))
            .Cases("Equal", "NotEqual", "Less", "LessEqual", "Greater", "GreaterEqual", largestOperandType(lhs, rhs))
            .Cases("LogicalAnd", "LogicalOr", Types::Bool)
            .Cases("AddAssign", "SubAssign", "MulAssign", "ModAssign", largestOperandType(lhs, rhs))
            .Case("Assign", lhs);
    }

    static auto compoundOp(const CompoundAssign* op) {
        if (op->is<AddAssign>())
            return &Operations::add;
        if (op->is<SubAssign>())
            return &Operations::sub;
        if (op->is<MulAssign>())
            return &Operations::mul;
        if (op->is<DivAssign>())
            return &Operations::div;
        if (op->is<ModAssign>())
            return &Operations::mod;
        if (op->is<LShiftAssign>())
            return &Operations::lshift;
        if (op->is<RShiftAssign>())
            return &Operations::rshift;
        if (op->is<BitAndAssign>())
            return &Operations::bitAnd;
        if (op->is<BitOrAssign>())
            return &Operations::bitOr;
        if (op->is<BitXorAssign>())
            return &Operations::bitXor;
        throw InternalCompilerError("Unknown compound assignment op: {0}", op->rtti()->name());
    }

    Address LLVMCodeGenerator::emit(const Assign* op) {
        auto rhs = codegen(op->rhs);
        auto lhs = codegen(op->lhs);
        auto typeOps = lhs.type->ops();
        typeOps->assign(lhs, typeOps->coerce(rhs));
        return lhs;
    }

    Address LLVMCodeGenerator::emit(const CompoundAssign* op) {
        auto rhs = codegen(op->rhs);
        auto lhs = codegen(op->lhs);
        auto opType = lhs.type;
        if (!opType) {
            throw InternalCompilerError("Unable to determine operand types for {0} {2} {1}",
                                        Types::to_string(lhs->getType()),
                                        Types::to_string(rhs->getType()),
                                        op->rtti()->name());
        }
        auto typeOps = opType->ops();
        auto mathOp = compoundOp(op);
        auto lhsOperand = typeOps->coerce(lhs);
        auto rhsOperand = typeOps->coerce(rhs);
        auto result = std::invoke(mathOp, typeOps, lhsOperand, rhsOperand);
        typeOps->assign(lhs, result);
        return lhs;
    }

    Address LLVMCodeGenerator::emit(const BinaryOp* op) {
        if (op->is<CompoundAssign>())
            return emit(op->as<CompoundAssign>());
        if (op->is<Assign>())
            return emit(op->as<Assign>());

        auto rhs = codegen(op->rhs);
        auto lhs = codegen(op->lhs);
        lhs = load(lhs);
        rhs = load(rhs);
        auto opType = operandType(op, lhs.type, rhs.type);
        if (!opType) {
            throw InternalCompilerError("Unable to determine operand types for {0} {2} {1}",
                                        Types::to_string(lhs->getType()),
                                        Types::to_string(rhs->getType()),
                                        op->rtti()->name());
        }
        auto typeOps = opType->ops();
        auto lhsOperand = typeOps->coerce(lhs);
        auto rhsOperand = typeOps->coerce(rhs);
        auto typeOp = binaryOp(op);
        auto result = std::invoke(typeOp, typeOps, lhsOperand, rhsOperand);
        return result;
    }

    static auto unaryOp(const UnaryOp* op) {
        if (op->is<Plus>())
            return &Operations::pos;
        if (op->is<Minus>())
            return &Operations::neg;
        if (op->is<PreIncrement>())
            return &Operations::preIncrement;
        if (op->is<PostIncrement>())
            return &Operations::postIncrement;
        if (op->is<PreDecrement>())
            return &Operations::preDecrement;
        if (op->is<PostDecrement>())
            return &Operations::postDecrement;
        if (op->is<LogicalNot>())
            return &Operations::logicalNot;
        if (op->is<BitNot>())
            return &Operations::bitNot;
        throw InternalCompilerError("Unknown unary op: {0}", op->rtti()->name());
    }

    Address LLVMCodeGenerator::emit(const UnaryOp* op) {
        auto operand = codegen(op->operand);
        auto type = operand.type;
        auto ops = type->ops();
        auto typeOp = unaryOp(op);
        auto result = std::invoke(typeOp, ops, operand);
        return result;
    }
} // namespace pepper
