

#include "Operations.h"

#include "CodeGen/Address.h"
#include "Core/Exceptions.h"
#include "Core/LLVMUtils.h"
#include "Types.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper {
    Address Operations::add(Address, Address) const {
        throw CompileError("Type {0} does not support addition", Types::toString(Ty));
    }

    Address Operations::sub(Address, Address) const {
        throw CompileError("Type {0} does not support subtraction", Types::toString(Ty));
    }

    Address Operations::mul(Address, Address) const {
        throw CompileError("Type {0} does not support multiplication", Types::toString(Ty));
    }

    Address Operations::div(Address, Address) const {
        throw CompileError("Type {0} does not support division", Types::toString(Ty));
    }

    Address Operations::mod(Address, Address) const {
        throw CompileError("Type {0} does not support modulus", Types::toString(Ty));
    }

    Address Operations::pow(Address, Address) const {
        throw CompileError("Type {0} does not support pow", Types::toString(Ty));
    }

    Address Operations::less(Address, Address) const {
        throw CompileError("Type {0} does not support <", Types::toString(Ty));
    }

    Address Operations::lessEq(Address, Address) const {
        throw CompileError("Type {0} does not support <=", Types::toString(Ty));
    }

    Address Operations::greater(Address, Address) const {
        throw CompileError("Type {0} does not support >", Types::toString(Ty));
    }

    Address Operations::greaterEq(Address, Address) const {
        throw CompileError("Type {0} does not support >=", Types::toString(Ty));
    }

    Address Operations::lshift(Address, Address) const {
        throw CompileError("Type {0} does not support <<", Types::toString(Ty));
    }

    Address Operations::rshift(Address, Address) const {
        throw CompileError("Type {0} does not support >>", Types::toString(Ty));
    }

    Address Operations::equal(Address, Address) const {
        throw CompileError("Type {0} does not support equality", Types::toString(Ty));
    }

    Address Operations::notEqual(Address, Address) const {
        throw CompileError("Type {0} does not support non-equality", Types::toString(Ty));
    }

    void Operations::init(Address lhs, Address rhs) const {
        assign(lhs, rhs);
    }

    Address Operations::assign(Address, Address) const {
        throw CompileError("Type {0} does not support assignment", Types::toString(Ty));
    }

    Address Operations::bitAnd(Address, Address) const {
        throw CompileError("Type {0} does not support bitwise and", Types::toString(Ty));
    }

    Address Operations::bitXor(Address, Address) const {
        throw CompileError("Type {0} does not support bitwise xor", Types::toString(Ty));
    }

    Address Operations::bitOr(Address, Address) const {
        throw CompileError("Type {0} does not support bitwise or", Types::toString(Ty));
    }

    Address Operations::neg(Address) const {
        throw CompileError("Type {0} does not support unary negation", Types::toString(Ty));
    }

    Address Operations::pos(Address) const {
        throw CompileError("Type {0} does not support unary positive", Types::toString(Ty));
    }

    Address Operations::preIncrement(Address) const {
        throw CompileError("Type {0} does not support pre-increment", Types::toString(Ty));
    }

    Address Operations::preDecrement(Address) const {
        throw CompileError("Type {0} does not support post-increment", Types::toString(Ty));
    }

    Address Operations::postIncrement(Address) const {
        throw CompileError("Type {0} does not support post-increment", Types::toString(Ty));
    }

    Address Operations::postDecrement(Address) const {
        throw CompileError("Type {0} does not support post-decrement", Types::toString(Ty));
    }

    Address Operations::bitNot(Address) const {
        throw CompileError("Type {0} does not support bitwise not", Types::toString(Ty));
    }

    Address Operations::logicalNot(Address) const {
        throw CompileError("Type {0} does not support logical not", Types::toString(Ty));
    }

    Address Operations::asBool(Address) const {
        throw CompileError("Type {0} does not support conversion to bool", Types::toString(Ty));
    }

    Address PointerOperations::coerce(Address value) const {
        value = load(value);
        if (value.Ty->is<PointerType>()) {
            return value;
        }
        throw CompileError("Coercion to pointer is not supported");
    }

    Address PointerOperations::equal(Address lhs, Address rhs) const {
        return Address{Types::Bool, ir()->CreateICmpEQ(coerce(lhs), coerce(rhs))};
    }

    Address PointerOperations::notEqual(Address lhs, Address rhs) const {
        return Address{Types::Bool, ir()->CreateICmpNE(coerce(lhs), coerce(rhs))};
    }

    Address PointerOperations::assign(Address lhs, Address rhs) const {
        rhs = coerce(rhs);
        ir()->CreateStore(rhs, lhs);
        return lhs;
    }

    Address PointerOperations::asBool(Address value) const {
        auto zero = zeroValue(Ty);
        auto valAsInt = load(value);
        return Address{Types::Bool, ir()->CreateICmpNE(zero, valAsInt, "bool")};
    }

    Address PointerOperations::logicalNot(Address value) const {
        auto zero = llvm::ConstantInt::getFalse(*Ty);
        auto valAsInt = ir()->CreatePtrToInt(value, *Types::Int64);
        return Address{Types::Bool, ir()->CreateICmpEQ(zero, valAsInt, "not")};
    }

    class VoidOperations : public NativeOperations {
        DECLARE_RTTI(VoidOperations, NativeOperations)
      public:
        VoidOperations()
            : NativeOperations(Types::Void) {}

        Address coerce(Address value) const override {
            throw CompileError("Cannot convert {0} to void", Types::toString(value->getType()));
        }
    };

    class IntegerOperations : public NativeOperations {
        DECLARE_RTTI(IntegerOperations, NativeOperations)
        uint32_t Bits;
        bool Signed = false;

      public:
        IntegerOperations(Ref<Type> type)
            : NativeOperations(type) {
            auto llvmType = Types::get(type.get());
            Bits = llvmType->getIntegerBitWidth();
        }

        bool isSigned() const {
            return Signed;
        }

        Address coerce(Address value) const override {
            value = read(value);
            if (value->getType() == *this) {
                return value;
            }
            auto type = value->getType();
            const bool signedVal = !type->isIntegerTy(1) && isSigned();

            if (type->isIntegerTy()) {
                return Address{Ty, ir()->CreateIntCast(value, *this, signedVal)};
            }
            if (type->isFloatingPointTy()) {
                return Address{Ty, signedVal ? ir()->CreateFPToSI(value, *this) : ir()->CreateFPToUI(value, *this)};
            }
            throw CompileError("Cannot convert from {0} to {0}", Types::toString(type), Types::toString(Ty));
        }

        Address add(Address lhs, Address rhs) const override {
            return Address{Ty, ir()->CreateNSWAdd(coerce(lhs), coerce(rhs), "add")};
        }

        Address sub(Address lhs, Address rhs) const override {
            return Address{Ty, ir()->CreateNSWSub(coerce(lhs), coerce(rhs), "sub")};
        }

        Address mul(Address lhs, Address rhs) const override {
            return Address{Ty, ir()->CreateNSWMul(coerce(lhs), coerce(rhs), "mul")};
        }

        Address div(Address lhs, Address rhs) const override {
            return Address{Ty,
                           isSigned() ? ir()->CreateSDiv(coerce(lhs), coerce(rhs), "sdiv")
                                      : ir()->CreateUDiv(coerce(lhs), coerce(rhs), "udiv")};
        }

        Address mod(Address lhs, Address rhs) const override {
            return Address{Ty,
                           isSigned() ? ir()->CreateSRem(coerce(lhs), coerce(rhs), "srem")
                                      : ir()->CreateURem(coerce(lhs), coerce(rhs), "urem")};
        }

        Address pow(Address lhs, Address rhs) const override {
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

            auto res =
                Address{Types::Double, ir()->CreateIntrinsic(llvm::Intrinsic::pow, types, values, nullptr, "pow")};
            return Address{Ty, coerce(res)};
        }

        Address less(Address lhs, Address rhs) const override {
            return Address(Types::Bool,
                           isSigned() ? ir()->CreateICmpSLT(coerce(lhs), coerce(rhs), "slt")
                                      : ir()->CreateICmpULT(coerce(lhs), coerce(rhs), "ult"));
        }

        Address lessEq(Address lhs, Address rhs) const override {
            return Address(Types::Bool,
                           isSigned() ? ir()->CreateICmpSLE(coerce(lhs), coerce(rhs), "sle")
                                      : ir()->CreateICmpULE(coerce(lhs), coerce(rhs), "ule"));
        }

        Address greater(Address lhs, Address rhs) const override {
            return Address(Types::Bool,
                           isSigned() ? ir()->CreateICmpSGT(coerce(lhs), coerce(rhs), "sgt")
                                      : ir()->CreateICmpUGT(coerce(lhs), coerce(rhs), "ugt"));
        }

        Address greaterEq(Address lhs, Address rhs) const override {
            return Address(Types::Bool,
                           isSigned() ? ir()->CreateICmpSGE(coerce(lhs), coerce(rhs), "sge")
                                      : ir()->CreateICmpUGE(coerce(lhs), coerce(rhs), "uge"));
        }

        Address lshift(Address lhs, Address rhs) const override {
            return Address{Ty, ir()->CreateShl(coerce(lhs), coerce(rhs), "shl")};
        }

        Address rshift(Address lhs, Address rhs) const override {
            return Address{Ty, ir()->CreateLShr(coerce(lhs), coerce(rhs), "lshr")};
        }

        Address equal(Address lhs, Address rhs) const override {
            return Address{Types::Bool, ir()->CreateICmpEQ(coerce(lhs), coerce(rhs), "eq")};
        }

        Address notEqual(Address lhs, Address rhs) const override {
            return Address{Types::Bool, ir()->CreateICmpNE(coerce(lhs), coerce(rhs), "ne")};
        }

        Address assign(Address lhs, Address rhs) const override {
            ir()->CreateStore(coerce(rhs), lhs);
            return lhs;
        }

        Address bitAnd(Address lhs, Address rhs) const override {
            return Address{Ty, ir()->CreateAnd(coerce(lhs), coerce(rhs), "and")};
        }

        Address bitXor(Address lhs, Address rhs) const override {
            return Address{Ty, ir()->CreateXor(coerce(lhs), coerce(rhs), "xor")};
        }

        Address bitOr(Address lhs, Address rhs) const override {
            return Address{Ty, ir()->CreateOr(coerce(lhs), coerce(rhs), "or")};
        }

        Address neg(Address val) const override {
            return Address{Ty, ir()->CreateNeg(coerce(val), "neg")};
        }

        Address pos(Address val) const override {
            return Address{Ty, coerce(val), "pos"};
        }

        Address preIncrement(Address val) const override {
            auto one = llvm::ConstantInt::get(*Ty, 1);
            auto newVal = ir()->CreateAdd(read(val), one, "preinc");
            ir()->CreateStore(newVal, val);
            return Address{Ty, newVal};
        }

        Address preDecrement(Address val) const override {
            auto one = llvm::ConstantInt::get(*Ty, 1);
            auto newVal = ir()->CreateSub(read(val), one, "predec");
            ir()->CreateStore(newVal, val);
            return Address{Ty, newVal};
        }

        Address postIncrement(Address val) const override {
            auto one = llvm::ConstantInt::get(*Ty, 1);
            auto ret = ir()->CreateAlloca(*Ty);
            auto oldVal = read(val);
            auto newVal = ir()->CreateAdd(oldVal, one, "postinc");
            ir()->CreateStore(oldVal, ret);
            ir()->CreateStore(newVal, val);
            return Address{Ty, ret};
        }

        Address postDecrement(Address val) const override {
            auto one = llvm::ConstantInt::get(*Ty, 1);
            auto ret = ir()->CreateAlloca(*Ty);
            auto oldVal = read(val);
            auto newVal = ir()->CreateSub(oldVal, one, "postdec");
            ir()->CreateStore(oldVal, ret);
            ir()->CreateStore(newVal, val);
            return Address{Ty, ret};
        }

        Address bitNot(Address val) const override {
            auto one = llvm::ConstantInt::get(*Ty, 1);
            auto plusOne = ir()->CreateAdd(val, one);
            auto negated = ir()->CreateNeg(plusOne, "bitneg");
            return Address{Ty, negated};
        }

        Address logicalNot(Address val) const override {
            auto zero = llvm::ConstantInt::get(*Ty, 0);
            return Address{Types::Bool, ir()->CreateICmpEQ(read(val), zero, "not")};
        }

        Address asBool(Address value) const override {
            auto zero = llvm::ConstantInt::get(*Ty, 0);
            return Address{Types::Bool, ir()->CreateICmpNE(read(value), zero, "bool")};
        }
    };

    class BoolOperations : public IntegerOperations {
      public:
        BoolOperations(Ref<Type> type)
            : IntegerOperations(type) {}

        Address coerce(Address value) const override {
            value = read(value);
            if (value->getType() == *this) {
                return value;
            }
            auto type = value->getType();
            auto bits = type->getPrimitiveSizeInBits();
            auto intType = bits > 32 ? *Types::Int64 : *Types::Int32;
            auto zero = llvm::ConstantInt::get(intType, 0);
            if (type->isIntegerTy()) {
                return Address{Types::Bool, ir()->CreateICmpNE(value, zero, "bool")};
            }
            if (type->isFloatingPointTy()) {
                auto asInt = ir()->CreateFPToSI(value, *this);
                return Address{Types::Bool, ir()->CreateICmpNE(asInt, zero, "bool")};
            }
            throw CompileError("Cannot convert from {0} to {0}", Types::toString(type), Types::toString(Ty));
        }
    };

    class FloatOperations : public NativeOperations {
        DECLARE_RTTI(FloatOperations, NativeOperations)
      public:
        FloatOperations(Ref<Type> type)
            : NativeOperations(type) {}

        ~FloatOperations() = default;

        Address coerce(Address value) const override {
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
                    auto llvmType = Types::get(Ty.get());
                    if (llvmType->getPrimitiveSizeInBits() > type->getPrimitiveSizeInBits())
                        cast = ir()->CreateFPExt(value, *this);
                    else
                        cast = ir()->CreateFPTrunc(value, *this);
                }
                return Address{Ty, cast};
            }
            throw CompileError(
                "Cannot convert from {0} to {0}", Types::toString(value->getType()), Types::toString(Ty));
        }

        Address add(Address lhs, Address rhs) const override {
            return Address{Ty, ir()->CreateFAdd(coerce(lhs), coerce(rhs), "fdd")};
        }

        Address sub(Address lhs, Address rhs) const override {
            return Address{Ty, ir()->CreateFSub(coerce(lhs), coerce(rhs), "fsub")};
        }

        Address mul(Address lhs, Address rhs) const override {
            return Address{Ty, ir()->CreateFMul(coerce(lhs), coerce(rhs), "fmul")};
        }

        Address div(Address lhs, Address rhs) const override {
            return Address{Ty, ir()->CreateFDiv(coerce(lhs), coerce(rhs), "fdiv")};
        }

        Address mod(Address lhs, Address rhs) const override {
            return Address{Ty, ir()->CreateFRem(coerce(lhs), coerce(rhs), "frem")};
        }

        Address pow(Address lhs, Address rhs) const override {
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

            auto res =
                Address{Types::Double, ir()->CreateIntrinsic(llvm::Intrinsic::pow, types, values, nullptr, "pow")};
            return Address{Ty, coerce(res)};
        }

        Address less(Address lhs, Address rhs) const override {
            return Address{Types::Bool, ir()->CreateFCmpOLT(coerce(lhs), coerce(rhs), "olt")};
        }

        Address lessEq(Address lhs, Address rhs) const override {
            return Address{Types::Bool, ir()->CreateFCmpOLE(coerce(lhs), coerce(rhs), "ole")};
        }

        Address greater(Address lhs, Address rhs) const override {
            return Address{Types::Bool, ir()->CreateFCmpOGT(coerce(lhs), coerce(rhs), "ogt")};
        }

        Address greaterEq(Address lhs, Address rhs) const override {
            return Address{Types::Bool, ir()->CreateFCmpOGE(coerce(lhs), coerce(rhs), "oge")};
        }

        Address equal(Address lhs, Address rhs) const override {
            return Address{Types::Bool, ir()->CreateFCmpOEQ(coerce(lhs), coerce(rhs), "oeq")};
        }

        Address notEqual(Address lhs, Address rhs) const override {
            return Address{Types::Bool, ir()->CreateFCmpONE(coerce(lhs), coerce(rhs), "one")};
        }

        Address assign(Address lhs, Address rhs) const override {
            ir()->CreateStore(coerce(rhs), lhs);
            return lhs;
        }

        Address neg(Address val) const override {
            return Address{Ty, ir()->CreateFNeg(coerce(val), "fneg")};
        }

        Address asBool(Address value) const override {
            auto llvmType = Types::get(Ty.get());
            auto intType = llvmType->getIntegerBitWidth() > 32 ? llvm::Type::getInt64Ty(ir()->getContext())
                                                               : llvm::Type::getInt32Ty(ir()->getContext());
            auto zero = llvm::ConstantInt::getFalse(intType);
            auto valAsInt = ir()->CreateFPToSI(value, intType);
            return Address{Types::Bool, ir()->CreateICmpNE(valAsInt, zero, "bool")};
        }
    };

    Ref<Operations> Operations::get(Ref<Type> type) {
        auto llvmTy = Types::get(type.get());
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
