

#include "Operations.h"

#include "CodeGen/LLVM/Address.h"
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
        throw CompileError("Type {0} does not support addition", Types::to_string(operand_type));
    }

    Address Operations::sub(Address, Address) const {
        throw CompileError("Type {0} does not support subtraction", Types::to_string(operand_type));
    }

    Address Operations::mul(Address, Address) const {
        throw CompileError("Type {0} does not support multiplication", Types::to_string(operand_type));
    }

    Address Operations::div(Address, Address) const {
        throw CompileError("Type {0} does not support division", Types::to_string(operand_type));
    }

    Address Operations::mod(Address, Address) const {
        throw CompileError("Type {0} does not support modulus", Types::to_string(operand_type));
    }

    Address Operations::pow(Address, Address) const {
        throw CompileError("Type {0} does not support pow", Types::to_string(operand_type));
    }

    Address Operations::less(Address, Address) const {
        throw CompileError("Type {0} does not support <", Types::to_string(operand_type));
    }

    Address Operations::lessEq(Address, Address) const {
        throw CompileError("Type {0} does not support <=", Types::to_string(operand_type));
    }

    Address Operations::greater(Address, Address) const {
        throw CompileError("Type {0} does not support >", Types::to_string(operand_type));
    }

    Address Operations::greaterEq(Address, Address) const {
        throw CompileError("Type {0} does not support >=", Types::to_string(operand_type));
    }

    Address Operations::lshift(Address, Address) const {
        throw CompileError("Type {0} does not support <<", Types::to_string(operand_type));
    }

    Address Operations::rshift(Address, Address) const {
        throw CompileError("Type {0} does not support >>", Types::to_string(operand_type));
    }

    Address Operations::equal(Address, Address) const {
        throw CompileError("Type {0} does not support equality", Types::to_string(operand_type));
    }

    Address Operations::notEqual(Address, Address) const {
        throw CompileError("Type {0} does not support non-equality", Types::to_string(operand_type));
    }

    void Operations::init(Address lhs, Address rhs) const {
        assign(lhs, rhs);
    }

    Address Operations::assign(Address, Address) const {
        throw CompileError("Type {0} does not support assignment", Types::to_string(operand_type));
    }

    Address Operations::bitAnd(Address, Address) const {
        throw CompileError("Type {0} does not support bitwise and", Types::to_string(operand_type));
    }

    Address Operations::bitXor(Address, Address) const {
        throw CompileError("Type {0} does not support bitwise xor", Types::to_string(operand_type));
    }

    Address Operations::bitOr(Address, Address) const {
        throw CompileError("Type {0} does not support bitwise or", Types::to_string(operand_type));
    }

    Address Operations::neg(Address) const {
        throw CompileError("Type {0} does not support unary negation", Types::to_string(operand_type));
    }

    Address Operations::pos(Address) const {
        throw CompileError("Type {0} does not support unary positive", Types::to_string(operand_type));
    }

    Address Operations::preIncrement(Address) const {
        throw CompileError("Type {0} does not support pre-increment", Types::to_string(operand_type));
    }

    Address Operations::preDecrement(Address) const {
        throw CompileError("Type {0} does not support post-increment", Types::to_string(operand_type));
    }

    Address Operations::postIncrement(Address) const {
        throw CompileError("Type {0} does not support post-increment", Types::to_string(operand_type));
    }

    Address Operations::postDecrement(Address) const {
        throw CompileError("Type {0} does not support post-decrement", Types::to_string(operand_type));
    }

    Address Operations::bitNot(Address) const {
        throw CompileError("Type {0} does not support bitwise not", Types::to_string(operand_type));
    }

    Address Operations::logicalNot(Address) const {
        throw CompileError("Type {0} does not support logical not", Types::to_string(operand_type));
    }

    Address Operations::asBool(Address) const {
        throw CompileError("Type {0} does not support conversion to bool", Types::to_string(operand_type));
    }

    Address PointerOperations::coerce(Address value) const {
        value = load(value);
        if (value.type->is<PointerType>()) {
            return value;
        }
        if (value.type->is_integer()) {
            return value;
        }
        throw CompileError("Coercion from {} to pointer is not supported", value.type->name());
    }

    Address PointerOperations::add(Address lhs, Address rhs) const {
        if (!lhs.type->is_pointer() || !rhs.type->is_integer()) {
            throw CompileError("{0} + {1} is not supported, addition is only supported between pointer and integer",
                               lhs.type->name(),
                               rhs.type->name());
        }
        if (lhs.type == Types::VoidPtr) {
            throw CompileError("Addition is not supported for void pointers");
        }
        lhs = load(lhs);
        rhs = load(rhs);
        auto idx = Types::UInt64->ops()->coerce(rhs);
        auto ptr = ir()->CreatePtrToInt(lhs, *Types::UInt64, "ptr");
        auto sum = ir()->CreateNUWAdd(ptr, idx, "sum");
        auto res = ir()->CreateIntToPtr(sum, *lhs.type, "res");
        return Address(lhs.type, res);
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
        auto zero = zero_value(operand_type);
        auto val_as_int = load(value);
        return Address{Types::Bool, ir()->CreateICmpNE(zero, val_as_int, "bool")};
    }

    Address PointerOperations::logicalNot(Address value) const {
        auto zero = llvm::ConstantInt::getFalse(*operand_type);
        auto val_as_int = ir()->CreatePtrToInt(value, *Types::Int64);
        return Address{Types::Bool, ir()->CreateICmpEQ(zero, val_as_int, "not")};
    }

    class VoidOperations : public NativeOperations {
        DECLARE_RTTI(VoidOperations, NativeOperations)
      public:
        VoidOperations()
            : NativeOperations(Types::Void) {}

        Address coerce(Address value) const override {
            throw CompileError("Cannot convert {0} to void", Types::to_string(value->getType()));
        }
    };

    class IntegerOperations : public NativeOperations {
        DECLARE_RTTI(IntegerOperations, NativeOperations)
        uint32_t bit_width;
        bool is_signed = false;

      public:
        IntegerOperations(Ref<Type> type)
            : NativeOperations(type) {
            auto llvm_type = Types::get(type.get());
            bit_width = llvm_type->getIntegerBitWidth();
        }

        bool isSigned() const {
            return is_signed;
        }

        Address coerce(Address value) const override {
            value = read(value);
            if (value->getType() == *this) {
                return value;
            }
            auto type = value->getType();
            const bool signedVal = !type->isIntegerTy(1) && isSigned();

            if (type->isIntegerTy()) {
                return Address{operand_type, ir()->CreateIntCast(value, *this, signedVal)};
            }
            if (type->isFloatingPointTy()) {
                return Address{operand_type,
                               signedVal ? ir()->CreateFPToSI(value, *this) : ir()->CreateFPToUI(value, *this)};
            }
            throw CompileError(
                "Cannot convert from {0} to {0}", Types::to_string(type), Types::to_string(operand_type));
        }

        Address add(Address lhs, Address rhs) const override {
            return Address{operand_type, ir()->CreateNSWAdd(coerce(lhs), coerce(rhs), "add")};
        }

        Address sub(Address lhs, Address rhs) const override {
            return Address{operand_type, ir()->CreateNSWSub(coerce(lhs), coerce(rhs), "sub")};
        }

        Address mul(Address lhs, Address rhs) const override {
            return Address{operand_type, ir()->CreateNSWMul(coerce(lhs), coerce(rhs), "mul")};
        }

        Address div(Address lhs, Address rhs) const override {
            return Address{operand_type,
                           isSigned() ? ir()->CreateSDiv(coerce(lhs), coerce(rhs), "sdiv")
                                      : ir()->CreateUDiv(coerce(lhs), coerce(rhs), "udiv")};
        }

        Address mod(Address lhs, Address rhs) const override {
            return Address{operand_type,
                           isSigned() ? ir()->CreateSRem(coerce(lhs), coerce(rhs), "srem")
                                      : ir()->CreateURem(coerce(lhs), coerce(rhs), "urem")};
        }

        Address pow(Address lhs, Address rhs) const override {
            auto float_ops = Types::Double->ops();
            auto flhs = float_ops->coerce(lhs);
            auto frhs = float_ops->coerce(rhs);
            Vector<llvm::Type*> types = {
                *Types::Double,
            };
            Vector<llvm::Value*> values = {
                flhs,
                frhs,
            };

            auto res =
                Address{Types::Double, ir()->CreateIntrinsic(llvm::Intrinsic::pow, types, values, nullptr, "pow")};
            return Address{operand_type, coerce(res)};
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
            return Address{operand_type, ir()->CreateShl(coerce(lhs), coerce(rhs), "shl")};
        }

        Address rshift(Address lhs, Address rhs) const override {
            return Address{operand_type, ir()->CreateLShr(coerce(lhs), coerce(rhs), "lshr")};
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
            return Address{operand_type, ir()->CreateAnd(coerce(lhs), coerce(rhs), "and")};
        }

        Address bitXor(Address lhs, Address rhs) const override {
            return Address{operand_type, ir()->CreateXor(coerce(lhs), coerce(rhs), "xor")};
        }

        Address bitOr(Address lhs, Address rhs) const override {
            return Address{operand_type, ir()->CreateOr(coerce(lhs), coerce(rhs), "or")};
        }

        Address neg(Address val) const override {
            return Address{operand_type, ir()->CreateNeg(coerce(val), "neg")};
        }

        Address pos(Address val) const override {
            return Address{operand_type, coerce(val), "pos"};
        }

        Address preIncrement(Address val) const override {
            auto one = llvm::ConstantInt::get(*operand_type, 1);
            auto new_val = ir()->CreateAdd(read(val), one, "preinc");
            ir()->CreateStore(new_val, val);
            return Address{operand_type, new_val};
        }

        Address preDecrement(Address val) const override {
            auto one = llvm::ConstantInt::get(*operand_type, 1);
            auto new_val = ir()->CreateSub(read(val), one, "predec");
            ir()->CreateStore(new_val, val);
            return Address{operand_type, new_val};
        }

        Address postIncrement(Address val) const override {
            auto one = llvm::ConstantInt::get(*operand_type, 1);
            auto ret = ir()->CreateAlloca(*operand_type);
            auto old_val = read(val);
            auto new_val = ir()->CreateAdd(old_val, one, "postinc");
            ir()->CreateStore(old_val, ret);
            ir()->CreateStore(new_val, val);
            return Address{operand_type, ret};
        }

        Address postDecrement(Address val) const override {
            auto one = llvm::ConstantInt::get(*operand_type, 1);
            auto ret = ir()->CreateAlloca(*operand_type);
            auto old_val = read(val);
            auto new_val = ir()->CreateSub(old_val, one, "postdec");
            ir()->CreateStore(old_val, ret);
            ir()->CreateStore(new_val, val);
            return Address{operand_type, ret};
        }

        Address bitNot(Address val) const override {
            auto one = llvm::ConstantInt::get(*operand_type, 1);
            auto plus_one = ir()->CreateAdd(val, one);
            auto negated = ir()->CreateNeg(plus_one, "bitneg");
            return Address{operand_type, negated};
        }

        Address logicalNot(Address val) const override {
            auto zero = llvm::ConstantInt::get(*operand_type, 0);
            return Address{Types::Bool, ir()->CreateICmpEQ(read(val), zero, "not")};
        }

        Address asBool(Address value) const override {
            auto zero = llvm::ConstantInt::get(*operand_type, 0);
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
            auto int_type = bits > 32 ? *Types::Int64 : *Types::Int32;
            auto zero = llvm::ConstantInt::get(int_type, 0);
            if (type->isIntegerTy()) {
                return Address{Types::Bool, ir()->CreateICmpNE(value, zero, "bool")};
            }
            if (type->isFloatingPointTy()) {
                auto asInt = ir()->CreateFPToSI(value, *this);
                return Address{Types::Bool, ir()->CreateICmpNE(asInt, zero, "bool")};
            }
            throw CompileError(
                "Cannot convert from {0} to {0}", Types::to_string(type), Types::to_string(operand_type));
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
                    auto llvm_type = Types::get(operand_type.get());
                    if (llvm_type->getPrimitiveSizeInBits() > type->getPrimitiveSizeInBits())
                        cast = ir()->CreateFPExt(value, *this);
                    else
                        cast = ir()->CreateFPTrunc(value, *this);
                }
                return Address{operand_type, cast};
            }
            throw CompileError(
                "Cannot convert from {0} to {0}", Types::to_string(value->getType()), Types::to_string(operand_type));
        }

        Address add(Address lhs, Address rhs) const override {
            return Address{operand_type, ir()->CreateFAdd(coerce(lhs), coerce(rhs), "fdd")};
        }

        Address sub(Address lhs, Address rhs) const override {
            return Address{operand_type, ir()->CreateFSub(coerce(lhs), coerce(rhs), "fsub")};
        }

        Address mul(Address lhs, Address rhs) const override {
            return Address{operand_type, ir()->CreateFMul(coerce(lhs), coerce(rhs), "fmul")};
        }

        Address div(Address lhs, Address rhs) const override {
            return Address{operand_type, ir()->CreateFDiv(coerce(lhs), coerce(rhs), "fdiv")};
        }

        Address mod(Address lhs, Address rhs) const override {
            return Address{operand_type, ir()->CreateFRem(coerce(lhs), coerce(rhs), "frem")};
        }

        Address pow(Address lhs, Address rhs) const override {
            auto float_ops = Types::Double->ops();
            auto flhs = float_ops->coerce(lhs);
            auto frhs = float_ops->coerce(rhs);
            Vector<llvm::Type*> types = {
                *Types::Double,
            };
            Vector<llvm::Value*> values = {
                flhs,
                frhs,
            };

            auto res =
                Address{Types::Double, ir()->CreateIntrinsic(llvm::Intrinsic::pow, types, values, nullptr, "pow")};
            return Address{operand_type, coerce(res)};
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
            return Address{operand_type, ir()->CreateFNeg(coerce(val), "fneg")};
        }

        Address asBool(Address value) const override {
            auto llvm_type = Types::get(operand_type.get());
            auto int_type = llvm_type->getIntegerBitWidth() > 32 ? llvm::Type::getInt64Ty(ir()->getContext())
                                                                 : llvm::Type::getInt32Ty(ir()->getContext());
            auto zero = llvm::ConstantInt::getFalse(int_type);
            auto val_as_int = ir()->CreateFPToSI(value, int_type);
            return Address{Types::Bool, ir()->CreateICmpNE(val_as_int, zero, "bool")};
        }
    };

    Ref<Operations> Operations::get(Ref<Type> type) {
        auto llvm_type = Types::get(type.get());
        if (llvm_type->isIntegerTy()) {
            if (llvm_type->getIntegerBitWidth() == 1)
                return Ref<BoolOperations>::create(type);
            return Ref<IntegerOperations>::create(type);
        }
        if (llvm_type->isFloatingPointTy()) {
            return Ref<FloatOperations>::create(type);
        }
        if (llvm_type->isPointerTy()) {
            return Ref<PointerOperations>::create(type);
        }
        if (llvm_type->isVoidTy()) {
            return Ref<VoidOperations>::create();
        }
        throw InternalCompilerError("Unknown type {0} found while looking for TypeOps", Types::to_string(type));
    }
} // namespace pepper
