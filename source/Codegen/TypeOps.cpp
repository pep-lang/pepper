//
// Created by Justin Boswell on 12/22/22.
//

#include "Codegen/TypeOps.h"

#include "Codegen/Context.h"
#include "Codegen/IR/Value.h"
#include "Codegen/Scope.h"
#include "Codegen/Types.h"
#include "Core/Exceptions.h"

#pragma warning(disable : 4624) // warning C4624: 'llvm::detail::move_construction_triviality_helper<T>': destructor was
                                // implicitly defined as deleted

#include "llvm/ADT/StringExtras.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

namespace pepper {
    Value TypeOps::add(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support addition", Types::toString(Type));
    }

    Value TypeOps::sub(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support subtraction", Types::toString(Type));
    }

    Value TypeOps::mul(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support multiplication", Types::toString(Type));
    }

    Value TypeOps::div(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support division", Types::toString(Type));
    }

    Value TypeOps::mod(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support modulus", Types::toString(Type));
    }

    Value TypeOps::pow(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support pow", Types::toString(Type));
    }

    Value TypeOps::less(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support <", Types::toString(Type));
    }

    Value TypeOps::lessEq(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support <=", Types::toString(Type));
    }

    Value TypeOps::greater(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support >", Types::toString(Type));
    }

    Value TypeOps::greaterEq(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support >=", Types::toString(Type));
    }

    Value TypeOps::lshift(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support <<", Types::toString(Type));
    }

    Value TypeOps::rshift(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support >>", Types::toString(Type));
    }

    Value TypeOps::equal(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support equality", Types::toString(Type));
    }

    Value TypeOps::notEqual(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support non-equality", Types::toString(Type));
    }

    Value TypeOps::assign(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support assignment", Types::toString(Type));
    }

    Value TypeOps::bitAnd(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support bitwise and", Types::toString(Type));
    }

    Value TypeOps::bitXor(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support bitwise xor", Types::toString(Type));
    }

    Value TypeOps::bitOr(Value lhs, Value rhs) const {
        throw CompileError("Type {0} does not support bitwise or", Types::toString(Type));
    }

    Value TypeOps::asBool(Value value) const {
        throw CompileError("Type {0} does not support conversion to bool", Types::toString(Type));
    }

    using llvm::cast;
    using llvm::isa;

    Ref<llvm::IRBuilderBase> ir() {
        return Context::get().locals()->builder();
    }

    static Value read(Value value) {
        if (isa<llvm::AllocaInst>(*value)) {
            auto allocaInst = cast<llvm::AllocaInst>(value.V);
            auto type = allocaInst->getAllocatedType();
            return Value(value.Ty, ir()->CreateLoad(type, value));
        }
        return value;
    }

    class NativeType : public TypeOps {
        DECLARE_RTTI(NativeType, TypeOps)
      protected:
        static Ref<llvm::IRBuilderBase> builder() {
            return Context::get().locals()->builder();
        }

      public:
        NativeType(Ref<TypeInfo> type)
            : TypeOps(type) {
        }
    };

    class PointerType : public NativeType {
        DECLARE_RTTI(PointerType, NativeType)
      public:
        PointerType(Ref<TypeInfo> type)
            : NativeType(type) {
        }

        Value coerce(Value value) const override {
            if (value.Ty->llvmType()->isPointerTy()) {
                return value;
            }
            throw CompileError("Coercion to pointer is not supported");
        }

        Value equal(Value lhs, Value rhs) const override {
            return Value(Types::Bool, builder()->CreateICmpEQ(coerce(lhs), coerce(rhs)));
        }

        Value notEqual(Value lhs, Value rhs) const override {
            return Value(Types::Bool, builder()->CreateICmpNE(coerce(lhs), coerce(rhs)));
        }

        Value assign(Value lhs, Value rhs) const override {
            builder()->CreateStore(coerce(rhs), lhs);
            return lhs;
        }

        Value asBool(Value value) const override {
            auto zero = llvm::ConstantInt::getFalse(*Type);
            auto valAsInt = builder()->CreatePtrToInt(value, *Types::Int64);
            return Value(Types::Bool, builder()->CreateICmpNE(zero, valAsInt, "bool"));
        }
    };

    class VoidType : public NativeType {
        DECLARE_RTTI(VoidType, NativeType)
      public:
        VoidType()
            : NativeType(Types::Void) {
        }

        Value coerce(Value value) const override {
            throw CompileError("Cannot convert {0} to void", Types::toString(value->getType()));
        }
    };

    class IntegerType : public NativeType {
        DECLARE_RTTI(IntegerType, NativeType)
        uint32_t Bits;
        bool Signed = false;

      public:
        IntegerType(Ref<TypeInfo> type)
            : NativeType(type)
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
            bool signedVal = !type->isIntegerTy(1) && isSigned();

            if (type->isIntegerTy()) {
                return Value(Type, builder()->CreateIntCast(value, *this, signedVal));
            }
            if (type->isFloatingPointTy()) {
                return Value(Type,
                             signedVal ? builder()->CreateFPToSI(value, *this) : builder()->CreateFPToUI(value, *this));
            }
            throw CompileError("Cannot convert from {0} to {0}", Types::toString(type), Types::toString(Type));
        }

        Value add(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateNSWAdd(coerce(lhs), coerce(rhs), "add"));
        }

        Value sub(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateNSWSub(coerce(lhs), coerce(rhs), "sub"));
        }

        Value mul(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateNSWMul(coerce(lhs), coerce(rhs), "mul"));
        }

        Value div(Value lhs, Value rhs) const override {
            return Value(Type,
                         isSigned() ? builder()->CreateSDiv(coerce(lhs), coerce(rhs), "sdiv")
                                    : builder()->CreateUDiv(coerce(lhs), coerce(rhs), "udiv"));
        }

        Value mod(Value lhs, Value rhs) const override {
            return Value(Type,
                         isSigned() ? builder()->CreateSRem(coerce(lhs), coerce(rhs), "srem")
                                    : builder()->CreateURem(coerce(lhs), coerce(rhs), "urem"));
        }

        Value pow(Value lhs, Value rhs) const override {
            // auto pow = builder()->
            // Value::New(
            //     ref(), builder()->CreateCall())
            throw InternalCompilerError("Pow not implemented");
        }

        Value less(Value lhs, Value rhs) const override {
            return Value(Types::Bool,
                         isSigned() ? builder()->CreateICmpSLT(coerce(lhs), coerce(rhs), "slt")
                                    : builder()->CreateICmpULT(coerce(lhs), coerce(rhs), "ult"));
        }

        Value lessEq(Value lhs, Value rhs) const override {
            return Value(Types::Bool,
                         isSigned() ? builder()->CreateICmpSLE(coerce(lhs), coerce(rhs), "sle")
                                    : builder()->CreateICmpULE(coerce(lhs), coerce(rhs), "ule"));
        }

        Value greater(Value lhs, Value rhs) const override {
            return Value(Types::Bool,
                         isSigned() ? builder()->CreateICmpSGT(coerce(lhs), coerce(rhs), "sgt")
                                    : builder()->CreateICmpUGT(coerce(lhs), coerce(rhs), "ugt"));
        }

        Value greaterEq(Value lhs, Value rhs) const override {
            return Value(Types::Bool,
                         isSigned() ? builder()->CreateICmpSGE(coerce(lhs), coerce(rhs), "sge")
                                    : builder()->CreateICmpUGE(coerce(lhs), coerce(rhs), "uge"));
        }

        Value lshift(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateShl(coerce(lhs), coerce(rhs), "shl"));
        }

        Value rshift(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateLShr(coerce(lhs), coerce(rhs), "lshr"));
        }

        Value equal(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateICmpEQ(coerce(lhs), coerce(rhs), "eq"));
        }

        Value notEqual(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateICmpNE(coerce(lhs), coerce(rhs), "ne"));
        }

        Value assign(Value lhs, Value rhs) const override {
            builder()->CreateStore(coerce(rhs), lhs);
            return lhs;
        }

        Value bitAnd(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateAnd(coerce(lhs), coerce(rhs), "and"));
        }

        Value bitXor(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateXor(coerce(lhs), coerce(rhs), "xor"));
        }

        Value bitOr(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateOr(coerce(lhs), coerce(rhs), "or"));
        }

        Value asBool(Value value) const override {
            auto zero = llvm::ConstantInt::getFalse(*Type);
            return Value(Types::Bool, builder()->CreateICmpNE(value, zero, "bool"));
        }
    };

    class BoolType : public IntegerType {
      public:
        BoolType(Ref<TypeInfo> type)
            : IntegerType(type) {
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
                return Value(Types::Bool, builder()->CreateICmpNE(value, zero, "bool"));
            }
            if (type->isFloatingPointTy()) {
                auto asInt = builder()->CreateFPToSI(value, *this);
                return Value(Types::Bool, builder()->CreateICmpNE(asInt, zero, "bool"));
            }
            throw CompileError("Cannot convert from {0} to {0}", Types::toString(type), Types::toString(Type));
        }
    };

    class FloatType : public NativeType {
        DECLARE_RTTI(FloatType, NativeType)
      public:
        FloatType(Ref<TypeInfo> type)
            : NativeType(type) {
        }

        ~FloatType() = default;

        Value coerce(Value value) const override {
            value = read(value);
            if (value->getType() == *this) {
                return value;
            }
            auto type = value->getType();

            if (type->isIntegerTy() || type->isFloatingPointTy()) {
                llvm::Value* cast = nullptr;
                if (type->isIntegerTy()) {
                    bool signedInt = true;
                    if (signedInt)
                        cast = builder()->CreateSIToFP(value, *this);
                    else
                        cast = builder()->CreateUIToFP(value, *this);
                } else {
                    if (Type->llvmType()->getPrimitiveSizeInBits() > type->getPrimitiveSizeInBits())
                        cast = builder()->CreateFPExt(value, *this);
                    else
                        cast = builder()->CreateFPTrunc(value, *this);
                }
                return Value(Type, cast);
            }
            throw CompileError(
                "Cannot convert from {0} to {0}", Types::toString(value->getType()), Types::toString(Type));
        }

        Value add(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateFAdd(coerce(lhs), coerce(rhs), "fdd"));
        }

        Value sub(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateFSub(coerce(lhs), coerce(rhs), "fsub"));
        }

        Value mul(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateFMul(coerce(lhs), coerce(rhs), "fmul"));
        }

        Value div(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateFDiv(coerce(lhs), coerce(rhs), "fdiv"));
        }

        Value mod(Value lhs, Value rhs) const override {
            return Value(Type, builder()->CreateFRem(coerce(lhs), coerce(rhs), "frem"));
        }

        Value less(Value lhs, Value rhs) const override {
            return Value(Types::Bool, builder()->CreateFCmpOLT(coerce(lhs), coerce(rhs), "olt"));
        }

        Value lessEq(Value lhs, Value rhs) const override {
            return Value(Types::Bool, builder()->CreateFCmpOLE(coerce(lhs), coerce(rhs), "ole"));
        }

        Value greater(Value lhs, Value rhs) const override {
            return Value(Types::Bool, builder()->CreateFCmpOGT(coerce(lhs), coerce(rhs), "ogt"));
        }

        Value greaterEq(Value lhs, Value rhs) const override {
            return Value(Types::Bool, builder()->CreateFCmpOGE(coerce(lhs), coerce(rhs), "oge"));
        }

        Value equal(Value lhs, Value rhs) const override {
            return Value(Types::Bool, builder()->CreateFCmpOEQ(coerce(lhs), coerce(rhs), "oeq"));
        }

        Value notEqual(Value lhs, Value rhs) const override {
            return Value(Types::Bool, builder()->CreateFCmpONE(coerce(lhs), coerce(rhs), "one"));
        }

        Value assign(Value lhs, Value rhs) const override {
            builder()->CreateStore(coerce(rhs), lhs);
            return lhs;
        }

        Value asBool(Value value) const override {
            auto intType = Type->llvmType()->getIntegerBitWidth() > 32
                               ? llvm::Type::getInt64Ty(builder()->getContext())
                               : llvm::Type::getInt32Ty(builder()->getContext());
            auto zero = llvm::ConstantInt::getFalse(intType);
            auto valAsInt = builder()->CreateFPToSI(value, intType);
            return Value(Types::Bool, builder()->CreateICmpNE(valAsInt, zero, "bool"));
        }
    };

    Ref<TypeOps> TypeOps::get(Ref<TypeInfo> type) {
        auto llvmTy = type->llvmType();
        if (llvmTy->isIntegerTy()) {
            if (llvmTy->getIntegerBitWidth() == 1)
                return Ref<BoolType>::New(type);
            return Ref<IntegerType>::New(type);
        }
        if (llvmTy->isFloatingPointTy()) {
            return Ref<FloatType>::New(type);
        }
        if (llvmTy->isPointerTy()) {
            return Ref<PointerType>::New(type);
        }
        if (llvmTy->isVoidTy()) {
            return Ref<VoidType>::New();
        }
        throw InternalCompilerError("Unknown type {0} found while looking for TypeOps", Types::toString(type));
    }
} // namespace pepper
