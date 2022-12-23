//
// Created by Justin Boswell on 12/22/22.
//

#include "Codegen/TypeOps.h"

#include "Codegen/Scope.h"
#include "Compiler/Context.h"
#include "Compiler/Exceptions.h"
#include "Compiler/Type.h"

#pragma warning(disable : 4624) // warning C4624: 'llvm::detail::move_construction_triviality_helper<T>': destructor was
                                // implicitly defined as deleted

#include "llvm/ADT/StringExtras.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper {
    llvm::Value* TypeOps::add(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support addition", Types::toString(Type));
    }

    llvm::Value* TypeOps::sub(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support subtraction", Types::toString(Type));
    }

    llvm::Value* TypeOps::mul(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support multiplication", Types::toString(Type));
    }

    llvm::Value* TypeOps::div(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support division", Types::toString(Type));
    }

    llvm::Value* TypeOps::mod(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support modulus", Types::toString(Type));
    }

    llvm::Value* TypeOps::pow(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support pow", Types::toString(Type));
    }

    llvm::Value* TypeOps::less(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support <", Types::toString(Type));
    }

    llvm::Value* TypeOps::lessEq(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support <=", Types::toString(Type));
    }

    llvm::Value* TypeOps::greater(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support >", Types::toString(Type));
    }

    llvm::Value* TypeOps::greaterEq(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support >=", Types::toString(Type));
    }

    llvm::Value* TypeOps::lshift(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support <<", Types::toString(Type));
    }

    llvm::Value* TypeOps::rshift(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support >>", Types::toString(Type));
    }

    llvm::Value* TypeOps::equal(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support equality", Types::toString(Type));
    }

    llvm::Value* TypeOps::notEqual(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support non-equality", Types::toString(Type));
    }

    llvm::Value* TypeOps::assign(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support assignment", Types::toString(Type));
    }

    llvm::Value* TypeOps::bitAnd(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support bitwise and", Types::toString(Type));
    }

    llvm::Value* TypeOps::bitXor(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support bitwise xor", Types::toString(Type));
    }

    llvm::Value* TypeOps::bitOr(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support bitwise or", Types::toString(Type));
    }

    llvm::Value* TypeOps::asBool(llvm::Value* value) const {
        throw CompileError("Type {0} does not support conversion to bool", Types::toString(Type));
    }

    class NativeType : public TypeOps {
        DECLARE_RTTI(NativeType, TypeOps)
      protected:
        static Ref<llvm::IRBuilderBase> builder() {
            return Context::get().locals()->builder();
        }

      public:
        NativeType(llvm::Type* type)
            : TypeOps(type) {
        }
    };

    class PointerType : public NativeType {
        DECLARE_RTTI(PointerType, NativeType)
      public:
        PointerType(llvm::Type* type)
            : NativeType(type) {
        }

        llvm::Value* coerce(llvm::Value* value) const override {
            if (value->getType()->isPointerTy()) {
                return value;
            }
            throw CompileError("Coercion to pointer is not supported");
        }

        llvm::Value* equal(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateICmpEQ(lhs, rhs);
        }

        llvm::Value* notEqual(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateICmpNE(lhs, rhs);
        }

        llvm::Value* assign(llvm::Value* lhs, llvm::Value* rhs) const override {
            builder()->CreateStore(rhs, lhs);
            return lhs;
        }

        llvm::Value* asBool(llvm::Value* value) const override {
            auto zero = llvm::ConstantInt::getFalse(Type);
            auto valAsInt = builder()->CreatePtrToInt(value, Types::Int64);
            return builder()->CreateICmpNE(zero, valAsInt, "bool");
        }
    };

    class VoidType : public NativeType {
        DECLARE_RTTI(VoidType, NativeType)
      public:
        VoidType()
            : NativeType(llvm::Type::getVoidTy(Context::get().llvmContext())) {
        }

        llvm::Value* coerce(llvm::Value* value) const override {
            throw CompileError("Cannot convert {0} to void", Types::toString(value->getType()));
        }
    };

    class IntegerType : public NativeType {
        DECLARE_RTTI(IntegerType, NativeType)
        uint32_t Bits;
        bool Signed = false;

      public:
        IntegerType(llvm::Type* type)
            : NativeType(type)
            , Bits(type->getIntegerBitWidth()) {
        }

        bool isSigned() const {
            return Signed;
        }

        llvm::Value* coerce(llvm::Value* value) const override {
            if (value->getType() == *this) {
                return value;
            }
            auto type = value->getType();
            bool signedVal = !type->isIntegerTy(1) && isSigned();
            if (type->isIntegerTy()) {
                return builder()->CreateIntCast(value, *this, signedVal);
            }
            if (type->isFloatingPointTy()) {
                auto converted =
                    signedVal ? builder()->CreateFPToSI(value, *this) : builder()->CreateFPToUI(value, *this);
                return converted;
            }
            throw CompileError("Cannot convert from {0} to {0}", Types::toString(type), Types::toString(Type));
        }

        llvm::Value* add(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateNSWAdd(lhs, rhs, "add");
        }

        llvm::Value* sub(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateNSWSub(lhs, rhs, "sub");
        }

        llvm::Value* mul(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateNSWMul(lhs, rhs, "mul");
        }

        llvm::Value* div(llvm::Value* lhs, llvm::Value* rhs) const override {
            return isSigned() ? builder()->CreateSDiv(lhs, rhs, "sdiv") : builder()->CreateUDiv(lhs, rhs, "udiv");
        }

        llvm::Value* mod(llvm::Value* lhs, llvm::Value* rhs) const override {
            return isSigned() ? builder()->CreateSRem(lhs, rhs, "srem") : builder()->CreateURem(lhs, rhs, "urem");
        }

        llvm::Value* pow(llvm::Value* lhs, llvm::Value* rhs) const override {
            // auto pow = builder()->
            // Value::New(
            //     ref(), builder()->CreateCall())
            return nullptr;
        }

        llvm::Value* less(llvm::Value* lhs, llvm::Value* rhs) const override {
            return isSigned() ? builder()->CreateICmpSLT(lhs, rhs, "slt") : builder()->CreateICmpULT(lhs, rhs, "ult");
        }

        llvm::Value* lessEq(llvm::Value* lhs, llvm::Value* rhs) const override {
            return isSigned() ? builder()->CreateICmpSLE(lhs, rhs, "sle") : builder()->CreateICmpULE(lhs, rhs, "ule");
        }

        llvm::Value* greater(llvm::Value* lhs, llvm::Value* rhs) const override {
            return isSigned() ? builder()->CreateICmpSGT(lhs, rhs, "sgt") : builder()->CreateICmpUGT(lhs, rhs, "ugt");
        }

        llvm::Value* greaterEq(llvm::Value* lhs, llvm::Value* rhs) const override {
            return isSigned() ? builder()->CreateICmpSGE(lhs, rhs, "sge") : builder()->CreateICmpUGE(lhs, rhs, "uge");
        }

        llvm::Value* lshift(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateLShr(lhs, rhs, "lshr");
        }

        llvm::Value* rshift(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateAShr(lhs, rhs, "ashr");
        }

        llvm::Value* equal(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateICmpEQ(lhs, rhs, "eq");
        }

        llvm::Value* notEqual(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateICmpNE(lhs, rhs, "ne");
        }

        llvm::Value* assign(llvm::Value* lhs, llvm::Value* rhs) const override {
            builder()->CreateStore(rhs, lhs);
            return lhs;
        }

        llvm::Value* bitAnd(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateAnd(lhs, rhs, "and");
        }

        llvm::Value* bitXor(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateXor(lhs, rhs, "xor");
        }

        llvm::Value* bitOr(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateOr(lhs, rhs, "or");
        }

        llvm::Value* asBool(llvm::Value* value) const override {
            auto zero = llvm::ConstantInt::getFalse(Type);
            return builder()->CreateICmpNE(value, zero, "bool");
        }
    };

    class FloatType : public NativeType {
        DECLARE_RTTI(FloatType, NativeType)
      public:
        FloatType(llvm::Type* type)
            : NativeType(type) {
        }

        ~FloatType() = default;

        llvm::Value* coerce(llvm::Value* value) const override {
            if (value->getType() == *this) {
                return value;
            }
            if (value->getType()->isIntegerTy() || value->getType()->isFloatingPointTy()) {
                return builder()->CreateFPCast(value, *this);
            }
            throw CompileError("Cannot convert from {0} to {0}",
                               Types::toString(value->getType()),
                               Types::toString(Type));
        }

        llvm::Value* add(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateFAdd(lhs, rhs, "fdd");
        }

        llvm::Value* sub(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateFSub(lhs, rhs, "fsub");
        }

        llvm::Value* mul(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateFMul(lhs, rhs, "fmul");
        }

        llvm::Value* div(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateFDiv(lhs, rhs, "fdiv");
        }

        llvm::Value* mod(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateFRem(lhs, rhs, "frem");
        }

        llvm::Value* pow(llvm::Value* lhs, llvm::Value* rhs) const override {
            // auto pow = builder()->
            // Value::New(
            //     ref(), builder()->CreateCall())
            return nullptr;
        }

        llvm::Value* less(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateFCmpOLT(lhs, rhs, "olt");
        }

        llvm::Value* lessEq(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateFCmpOLE(lhs, rhs, "ole");
        }

        llvm::Value* greater(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateFCmpOGT(lhs, rhs, "ogt");
        }

        llvm::Value* greaterEq(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateFCmpOGE(lhs, rhs, "oge");
        }

        llvm::Value* equal(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateFCmpOEQ(lhs, rhs, "oeq");
        }

        llvm::Value* notEqual(llvm::Value* lhs, llvm::Value* rhs) const override {
            return builder()->CreateFCmpONE(lhs, rhs, "one");
        }

        llvm::Value* assign(llvm::Value* lhs, llvm::Value* rhs) const override {
            builder()->CreateStore(rhs, lhs);
            return lhs;
        }

        llvm::Value* asBool(llvm::Value* value) const override {
            auto intType = Type->getIntegerBitWidth() > 32 ? llvm::Type::getInt64Ty(builder()->getContext())
                                                           : llvm::Type::getInt32Ty(builder()->getContext());
            auto zero = llvm::ConstantInt::getFalse(intType);
            auto valAsInt = builder()->CreateFPToSI(value, intType);
            return builder()->CreateICmpNE(valAsInt, zero, "bool");
        }
    };

    Ref<TypeOps> TypeOps::get(llvm::Type* type) {
        if (type->isIntegerTy()) {
            return Ref<IntegerType>::New(type);
        }
        if (type->isFloatingPointTy()) {
            return Ref<FloatType>::New(type);
        }
        if (type->isPointerTy()) {
            return Ref<PointerType>::New(type);
        }
        if (type->isVoidTy()) {
            return Ref<VoidType>::New();
        }
        throw InternalCompilerError("Unknown type {0} found while looking for TypeOps", Types::toString(type));
    }
} // namespace pepper
