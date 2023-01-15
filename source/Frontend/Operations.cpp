//
// Created by Justin Boswell on 12/22/22.
//

#include "Frontend/Operations.h"

#include "CodeGen/Value.h"
#include "Core/Exceptions.h"
#include "Frontend/LLVMUtils.h"
#include "Frontend/Types.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper {
    Value Operations::add(Value, Value) const {
        throw CompileError("Type {0} does not support addition", Types::toString(Ty));
    }

    Value Operations::sub(Value, Value) const {
        throw CompileError("Type {0} does not support subtraction", Types::toString(Ty));
    }

    Value Operations::mul(Value, Value) const {
        throw CompileError("Type {0} does not support multiplication", Types::toString(Ty));
    }

    Value Operations::div(Value, Value) const {
        throw CompileError("Type {0} does not support division", Types::toString(Ty));
    }

    Value Operations::mod(Value, Value) const {
        throw CompileError("Type {0} does not support modulus", Types::toString(Ty));
    }

    Value Operations::pow(Value, Value) const {
        throw CompileError("Type {0} does not support pow", Types::toString(Ty));
    }

    Value Operations::less(Value, Value) const {
        throw CompileError("Type {0} does not support <", Types::toString(Ty));
    }

    Value Operations::lessEq(Value, Value) const {
        throw CompileError("Type {0} does not support <=", Types::toString(Ty));
    }

    Value Operations::greater(Value, Value) const {
        throw CompileError("Type {0} does not support >", Types::toString(Ty));
    }

    Value Operations::greaterEq(Value, Value) const {
        throw CompileError("Type {0} does not support >=", Types::toString(Ty));
    }

    Value Operations::lshift(Value, Value) const {
        throw CompileError("Type {0} does not support <<", Types::toString(Ty));
    }

    Value Operations::rshift(Value, Value) const {
        throw CompileError("Type {0} does not support >>", Types::toString(Ty));
    }

    Value Operations::equal(Value, Value) const {
        throw CompileError("Type {0} does not support equality", Types::toString(Ty));
    }

    Value Operations::notEqual(Value, Value) const {
        throw CompileError("Type {0} does not support non-equality", Types::toString(Ty));
    }

    void Operations::init(Value lhs, Value rhs) const {
        assign(lhs, rhs);
    }

    Value Operations::assign(Value, Value) const {
        throw CompileError("Type {0} does not support assignment", Types::toString(Ty));
    }

    Value Operations::bitAnd(Value, Value) const {
        throw CompileError("Type {0} does not support bitwise and", Types::toString(Ty));
    }

    Value Operations::bitXor(Value, Value) const {
        throw CompileError("Type {0} does not support bitwise xor", Types::toString(Ty));
    }

    Value Operations::bitOr(Value, Value) const {
        throw CompileError("Type {0} does not support bitwise or", Types::toString(Ty));
    }

    Value Operations::neg(Value) const {
        throw CompileError("Type {0} does not support unary negation", Types::toString(Ty));
    }

    Value Operations::pos(Value) const {
        throw CompileError("Type {0} does not support unary positive", Types::toString(Ty));
    }

    Value Operations::preIncrement(Value) const {
        throw CompileError("Type {0} does not support pre-increment", Types::toString(Ty));
    }

    Value Operations::preDecrement(Value) const {
        throw CompileError("Type {0} does not support post-increment", Types::toString(Ty));
    }

    Value Operations::postIncrement(Value) const {
        throw CompileError("Type {0} does not support post-increment", Types::toString(Ty));
    }

    Value Operations::postDecrement(Value) const {
        throw CompileError("Type {0} does not support post-decrement", Types::toString(Ty));
    }

    Value Operations::bitNot(Value) const {
        throw CompileError("Type {0} does not support bitwise not", Types::toString(Ty));
    }

    Value Operations::logicalNot(Value) const {
        throw CompileError("Type {0} does not support logical not", Types::toString(Ty));
    }

    Value Operations::asBool(Value) const {
        throw CompileError("Type {0} does not support conversion to bool", Types::toString(Ty));
    }

    Value PointerOperations::coerce(Value value) const {
        value = load(value);
        if (value.Ty->llvmType()->isPointerTy()) {
            return value;
        }
        throw CompileError("Coercion to pointer is not supported");
    }

    Value PointerOperations::equal(Value lhs, Value rhs) const {
        return Value{Types::Bool, ir()->CreateICmpEQ(coerce(lhs), coerce(rhs))};
    }

    Value PointerOperations::notEqual(Value lhs, Value rhs) const {
        return Value{Types::Bool, ir()->CreateICmpNE(coerce(lhs), coerce(rhs))};
    }

    Value PointerOperations::assign(Value lhs, Value rhs) const {
        rhs = coerce(rhs);
        ir()->CreateStore(rhs, lhs);
        return lhs;
    }

    Value PointerOperations::asBool(Value value) const {
        auto zero = zeroValue(Ty);
        auto valAsInt = load(value);
        return Value{Types::Bool, ir()->CreateICmpNE(zero, valAsInt, "bool")};
    }

    Value PointerOperations::logicalNot(Value value) const {
        auto zero = llvm::ConstantInt::getFalse(*Ty);
        auto valAsInt = ir()->CreatePtrToInt(value, *Types::Int64);
        return Value{Types::Bool, ir()->CreateICmpEQ(zero, valAsInt, "not")};
    }

    class VoidOperations : public NativeOperations {
        DECLARE_RTTI(VoidOperations, NativeOperations)
      public:
        VoidOperations()
            : NativeOperations(Types::Void) {
        }

        Value coerce(Value value) const override {
            throw CompileError("Cannot convert {0} to void", Types::toString(value->getType()));
        }
    };

    class IntegerOperations : public NativeOperations {
        DECLARE_RTTI(IntegerOperations, NativeOperations)
        uint32_t Bits;
        bool Signed = false;

      public:
        IntegerOperations(Ref<Type> type)
            : NativeOperations(type)
            , Bits(type->llvmType()->getIntegerBitWidth()) {
        }

        bool isSigned() const {
            return Signed;
        }

        Value coerce(Value value) const override {
            value = read(value);
            if (value->getType() == *this) {
                return value;
            }
            auto type = value->getType();
            const bool signedVal = !type->isIntegerTy(1) && isSigned();

            if (type->isIntegerTy()) {
                return Value{Ty, ir()->CreateIntCast(value, *this, signedVal)};
            }
            if (type->isFloatingPointTy()) {
                return Value{Ty, signedVal ? ir()->CreateFPToSI(value, *this) : ir()->CreateFPToUI(value, *this)};
            }
            throw CompileError("Cannot convert from {0} to {0}", Types::toString(type), Types::toString(Ty));
        }

        Value add(Value lhs, Value rhs) const override {
            return Value{Ty, ir()->CreateNSWAdd(coerce(lhs), coerce(rhs), "add")};
        }

        Value sub(Value lhs, Value rhs) const override {
            return Value{Ty, ir()->CreateNSWSub(coerce(lhs), coerce(rhs), "sub")};
        }

        Value mul(Value lhs, Value rhs) const override {
            return Value{Ty, ir()->CreateNSWMul(coerce(lhs), coerce(rhs), "mul")};
        }

        Value div(Value lhs, Value rhs) const override {
            return Value{Ty,
                         isSigned() ? ir()->CreateSDiv(coerce(lhs), coerce(rhs), "sdiv")
                                    : ir()->CreateUDiv(coerce(lhs), coerce(rhs), "udiv")};
        }

        Value mod(Value lhs, Value rhs) const override {
            return Value{Ty,
                         isSigned() ? ir()->CreateSRem(coerce(lhs), coerce(rhs), "srem")
                                    : ir()->CreateURem(coerce(lhs), coerce(rhs), "urem")};
        }

        Value pow(Value lhs, Value rhs) const override {
            auto floatOps = Types::Double->ops();
            auto flhs = floatOps->coerce(lhs);
            auto frhs = floatOps->coerce(rhs);
            Vector<llvm::Type*> types = {
                *Types::Double,
            };
            Vector<llvm::Value*> values = {
                flhs,
                frhs,
            };

            auto res = Value{Types::Double, ir()->CreateIntrinsic(llvm::Intrinsic::pow, types, values, nullptr, "pow")};
            return Value{Ty, coerce(res)};
        }

        Value less(Value lhs, Value rhs) const override {
            return Value(Types::Bool,
                         isSigned() ? ir()->CreateICmpSLT(coerce(lhs), coerce(rhs), "slt")
                                    : ir()->CreateICmpULT(coerce(lhs), coerce(rhs), "ult"));
        }

        Value lessEq(Value lhs, Value rhs) const override {
            return Value(Types::Bool,
                         isSigned() ? ir()->CreateICmpSLE(coerce(lhs), coerce(rhs), "sle")
                                    : ir()->CreateICmpULE(coerce(lhs), coerce(rhs), "ule"));
        }

        Value greater(Value lhs, Value rhs) const override {
            return Value(Types::Bool,
                         isSigned() ? ir()->CreateICmpSGT(coerce(lhs), coerce(rhs), "sgt")
                                    : ir()->CreateICmpUGT(coerce(lhs), coerce(rhs), "ugt"));
        }

        Value greaterEq(Value lhs, Value rhs) const override {
            return Value(Types::Bool,
                         isSigned() ? ir()->CreateICmpSGE(coerce(lhs), coerce(rhs), "sge")
                                    : ir()->CreateICmpUGE(coerce(lhs), coerce(rhs), "uge"));
        }

        Value lshift(Value lhs, Value rhs) const override {
            return Value{Ty, ir()->CreateShl(coerce(lhs), coerce(rhs), "shl")};
        }

        Value rshift(Value lhs, Value rhs) const override {
            return Value{Ty, ir()->CreateLShr(coerce(lhs), coerce(rhs), "lshr")};
        }

        Value equal(Value lhs, Value rhs) const override {
            return Value{Types::Bool, ir()->CreateICmpEQ(coerce(lhs), coerce(rhs), "eq")};
        }

        Value notEqual(Value lhs, Value rhs) const override {
            return Value{Types::Bool, ir()->CreateICmpNE(coerce(lhs), coerce(rhs), "ne")};
        }

        Value assign(Value lhs, Value rhs) const override {
            ir()->CreateStore(coerce(rhs), lhs);
            return lhs;
        }

        Value bitAnd(Value lhs, Value rhs) const override {
            return Value{Ty, ir()->CreateAnd(coerce(lhs), coerce(rhs), "and")};
        }

        Value bitXor(Value lhs, Value rhs) const override {
            return Value{Ty, ir()->CreateXor(coerce(lhs), coerce(rhs), "xor")};
        }

        Value bitOr(Value lhs, Value rhs) const override {
            return Value{Ty, ir()->CreateOr(coerce(lhs), coerce(rhs), "or")};
        }

        Value neg(Value val) const override {
            return Value{Ty, ir()->CreateNeg(coerce(val), "neg")};
        }

        Value pos(Value val) const override {
            return Value{Ty, coerce(val), "pos"};
        }

        Value preIncrement(Value val) const override {
            auto one = llvm::ConstantInt::get(*Ty, 1);
            auto newVal = ir()->CreateAdd(read(val), one, "preinc");
            ir()->CreateStore(newVal, val);
            return Value{Ty, newVal};
        }

        Value preDecrement(Value val) const override {
            auto one = llvm::ConstantInt::get(*Ty, 1);
            auto newVal = ir()->CreateSub(read(val), one, "predec");
            ir()->CreateStore(newVal, val);
            return Value{Ty, newVal};
        }

        Value postIncrement(Value val) const override {
            auto one = llvm::ConstantInt::get(*Ty, 1);
            auto ret = ir()->CreateAlloca(*Ty);
            auto oldVal = read(val);
            auto newVal = ir()->CreateAdd(oldVal, one, "postinc");
            ir()->CreateStore(oldVal, ret);
            ir()->CreateStore(newVal, val);
            return Value{Ty, ret};
        }

        Value postDecrement(Value val) const override {
            auto one = llvm::ConstantInt::get(*Ty, 1);
            auto ret = ir()->CreateAlloca(*Ty);
            auto oldVal = read(val);
            auto newVal = ir()->CreateSub(oldVal, one, "postdec");
            ir()->CreateStore(oldVal, ret);
            ir()->CreateStore(newVal, val);
            return Value{Ty, ret};
        }

        Value bitNot(Value val) const override {
            auto one = llvm::ConstantInt::get(*Ty, 1);
            auto plusOne = ir()->CreateAdd(val, one);
            auto negated = ir()->CreateNeg(plusOne, "bitneg");
            return Value{Ty, negated};
        }

        Value logicalNot(Value val) const override {
            auto zero = llvm::ConstantInt::get(*Ty, 0);
            return Value{Types::Bool, ir()->CreateICmpEQ(read(val), zero, "not")};
        }

        Value asBool(Value value) const override {
            auto zero = llvm::ConstantInt::get(*Ty, 0);
            return Value{Types::Bool, ir()->CreateICmpNE(read(value), zero, "bool")};
        }
    };

    class BoolOperations : public IntegerOperations {
      public:
        BoolOperations(Ref<Type> type)
            : IntegerOperations(type) {
        }

        Value coerce(Value value) const override {
            value = read(value);
            if (value->getType() == *this) {
                return value;
            }
            auto type = value->getType();
            auto bits = type->getPrimitiveSizeInBits();
            auto intType = bits > 32 ? *Types::Int64 : *Types::Int32;
            auto zero = llvm::ConstantInt::get(intType, 0);
            if (type->isIntegerTy()) {
                return Value{Types::Bool, ir()->CreateICmpNE(value, zero, "bool")};
            }
            if (type->isFloatingPointTy()) {
                auto asInt = ir()->CreateFPToSI(value, *this);
                return Value{Types::Bool, ir()->CreateICmpNE(asInt, zero, "bool")};
            }
            throw CompileError("Cannot convert from {0} to {0}", Types::toString(type), Types::toString(Ty));
        }
    };

    class FloatOperations : public NativeOperations {
        DECLARE_RTTI(FloatOperations, NativeOperations)
      public:
        FloatOperations(Ref<Type> type)
            : NativeOperations(type) {
        }

        ~FloatOperations() = default;

        Value coerce(Value value) const override {
            value = read(value);
            if (value->getType() == *this) {
                return value;
            }
            auto type = value->getType();

            if (type->isIntegerTy() || type->isFloatingPointTy()) {
                llvm::Value* cast = nullptr;
                if (type->isIntegerTy()) {
                    const bool signedInt = true;
                    if (signedInt)
                        cast = ir()->CreateSIToFP(value, *this);
                    else
                        cast = ir()->CreateUIToFP(value, *this);
                } else {
                    if (Ty->llvmType()->getPrimitiveSizeInBits() > type->getPrimitiveSizeInBits())
                        cast = ir()->CreateFPExt(value, *this);
                    else
                        cast = ir()->CreateFPTrunc(value, *this);
                }
                return Value{Ty, cast};
            }
            throw CompileError(
                "Cannot convert from {0} to {0}", Types::toString(value->getType()), Types::toString(Ty));
        }

        Value add(Value lhs, Value rhs) const override {
            return Value{Ty, ir()->CreateFAdd(coerce(lhs), coerce(rhs), "fdd")};
        }

        Value sub(Value lhs, Value rhs) const override {
            return Value{Ty, ir()->CreateFSub(coerce(lhs), coerce(rhs), "fsub")};
        }

        Value mul(Value lhs, Value rhs) const override {
            return Value{Ty, ir()->CreateFMul(coerce(lhs), coerce(rhs), "fmul")};
        }

        Value div(Value lhs, Value rhs) const override {
            return Value{Ty, ir()->CreateFDiv(coerce(lhs), coerce(rhs), "fdiv")};
        }

        Value mod(Value lhs, Value rhs) const override {
            return Value{Ty, ir()->CreateFRem(coerce(lhs), coerce(rhs), "frem")};
        }

        Value pow(Value lhs, Value rhs) const override {
            auto floatOps = Types::Double->ops();
            auto flhs = floatOps->coerce(lhs);
            auto frhs = floatOps->coerce(rhs);
            Vector<llvm::Type*> types = {
                *Types::Double,
            };
            Vector<llvm::Value*> values = {
                flhs,
                frhs,
            };

            auto res = Value{Types::Double, ir()->CreateIntrinsic(llvm::Intrinsic::pow, types, values, nullptr, "pow")};
            return Value{Ty, coerce(res)};
        }

        Value less(Value lhs, Value rhs) const override {
            return Value{Types::Bool, ir()->CreateFCmpOLT(coerce(lhs), coerce(rhs), "olt")};
        }

        Value lessEq(Value lhs, Value rhs) const override {
            return Value{Types::Bool, ir()->CreateFCmpOLE(coerce(lhs), coerce(rhs), "ole")};
        }

        Value greater(Value lhs, Value rhs) const override {
            return Value{Types::Bool, ir()->CreateFCmpOGT(coerce(lhs), coerce(rhs), "ogt")};
        }

        Value greaterEq(Value lhs, Value rhs) const override {
            return Value{Types::Bool, ir()->CreateFCmpOGE(coerce(lhs), coerce(rhs), "oge")};
        }

        Value equal(Value lhs, Value rhs) const override {
            return Value{Types::Bool, ir()->CreateFCmpOEQ(coerce(lhs), coerce(rhs), "oeq")};
        }

        Value notEqual(Value lhs, Value rhs) const override {
            return Value{Types::Bool, ir()->CreateFCmpONE(coerce(lhs), coerce(rhs), "one")};
        }

        Value assign(Value lhs, Value rhs) const override {
            ir()->CreateStore(coerce(rhs), lhs);
            return lhs;
        }

        Value neg(Value val) const override {
            return Value{Ty, ir()->CreateFNeg(coerce(val), "fneg")};
        }

        Value asBool(Value value) const override {
            auto intType = Ty->llvmType()->getIntegerBitWidth() > 32 ? llvm::Type::getInt64Ty(ir()->getContext())
                                                                     : llvm::Type::getInt32Ty(ir()->getContext());
            auto zero = llvm::ConstantInt::getFalse(intType);
            auto valAsInt = ir()->CreateFPToSI(value, intType);
            return Value{Types::Bool, ir()->CreateICmpNE(valAsInt, zero, "bool")};
        }
    };

    Ref<Operations> Operations::get(Ref<Type> type) {
        auto llvmTy = type->llvmType();
        if (llvmTy->isIntegerTy()) {
            if (llvmTy->getIntegerBitWidth() == 1)
                return Ref<BoolOperations>::New(type);
            return Ref<IntegerOperations>::New(type);
        }
        if (llvmTy->isFloatingPointTy()) {
            return Ref<FloatOperations>::New(type);
        }
        if (llvmTy->isPointerTy()) {
            return Ref<PointerOperations>::New(type);
        }
        if (llvmTy->isVoidTy()) {
            return Ref<VoidOperations>::New();
        }
        throw InternalCompilerError("Unknown type {0} found while looking for TypeOps", Types::toString(type));
    }
} // namespace pepper
