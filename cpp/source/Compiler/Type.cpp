
#include "Compiler/Type.h"

#include "Compiler/Context.h"
#include "Compiler/Exceptions.h"
#include "Compiler/Scope.h"
#include "Compiler/Value.h"

#pragma warning(disable : 4624) // warning C4624: 'llvm::detail::move_construction_triviality_helper<T>': destructor was
                                // implicitly defined as deleted
#include "llvm/IR/Constants.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"

llvm::Value* Type::alloc(llvm::IRBuilderBase* builder) const {
    builder = builder ? builder : Context::get().locals()->localRegisters().get();
    return builder->CreateAlloca(*this, nullptr, Name.c_str());
}

Ref<Type> Type::ref() const {
    return const_cast<Type*>(this)->shared_from_this();
}

Ref<Value> Type::add(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support addition", ref());
}

Ref<Value> Type::sub(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support subtraction", ref());
}

Ref<Value> Type::mul(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support multiplication", ref());
}

Ref<Value> Type::div(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support division", ref());
}

Ref<Value> Type::mod(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support modulus", ref());
}

Ref<Value> Type::pow(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support pow", ref());
}

Ref<Value> Type::less(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support <", ref());
}

Ref<Value> Type::lessEq(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support <=", ref());
}

Ref<Value> Type::greater(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support >", ref());
}

Ref<Value> Type::greaterEq(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support >=", ref());
}

Ref<Value> Type::lshift(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support <<", ref());
}

Ref<Value> Type::rshift(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support >>", ref());
}

Ref<Value> Type::equal(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support equality", ref());
}

Ref<Value> Type::notEqual(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support non-equality", ref());
}

Ref<Value> Type::assign(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support assignment", ref());
}

Ref<Value> Type::bitAnd(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support bitwise and", ref());
}

Ref<Value> Type::bitXor(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support bitwise xor", ref());
}

Ref<Value> Type::bitOr(Ref<Value> lhs, Ref<Value> rhs) const {
    throw new CompileError("Type {} does not support bitwise or", ref());
}

Ref<Value> Type::asBool(Ref<Value> value) const {
    throw new CompileError("Type {} does not support conversion to bool", ref());
}

class NativeType : public Type {
    DECLARE_RTTI(NativeType, Type)
  protected:
    static llvm::IRBuilderBase* builder();

  public:
    NativeType(const std::string& name, llvm::Type* type)
        : Type(name, type) {
    }

    ~NativeType() = default;

    uint32_t bits() const override {
        return TypeRef->getIntegerBitWidth();
    }

    Ref<Type> pointer() const override {
        return std::static_pointer_cast<Type>(std::make_shared<PointerType>(Name + "*", TypeRef->getPointerTo()));
    }
};

class PointerType : public NativeType {
    DECLARE_RTTI(PointerType, NativeType)
  public:
    PointerType(const std::string& name, llvm::Type* type);
    ~PointerType() = default;

    Ref<Type> pointer() const override;
    Ref<Value> coerce(Ref<Value> value) const override;

    Ref<Value> equal(Ref<Value> lhs, Ref<Value> rhs) const override {
        builder()->CreateICmpEQ(*lhs, *rhs);
    }

    Ref<Value> notEqual(Ref<Value> lhs, Ref<Value> rhs) const override {
        builder()->CreateICmpNE(*lhs, *rhs);
    }

    Ref<Value> assign(Ref<Value> lhs, Ref<Value> rhs) const override {
        lhs->store(rhs);
        return lhs;
    }

    Ref<Value> asBool(Ref<Value> value) const override;
};

class VoidType : public NativeType {
    DECLARE_RTTI(VoidType, NativeType)
  public:
    VoidType(const std::string& name, llvm::Type* type)
        : NativeType(name, type) {
    }

    ~VoidType() = default;

    Ref<Type> pointer() const override {
        return Types::Int8Ptr;
    }

    Ref<Value> coerce(Ref<Value> value) const override {
        throw new CompileError("Cannot convert {} to void", value->type());
        return nullptr;
    }
};

class IntegerType : public NativeType {
    DECLARE_RTTI(IntegerType, NativeType)
    bool Signed = false;

  public:
    IntegerType(const std::string& name, llvm::Type* type)
        : NativeType(name, type) {
        IsInt = true;
    }

    ~IntegerType() = default;

    bool isSigned() const {
        return Signed;
    }

    Ref<Value> coerce(Ref<Value> value) const override {
        if (value->type().get() == this && !value->type()->isConstant()) {
            return value;
        }
        bool signedVal = value->type() != Types::Bool && isSigned();
        if (value->type()->isInteger()) {
            return Value::New(ref(), builder()->CreateIntCast(*value, *this, signedVal));
        }
        if (value->type()->isFloat()) {
            auto converted =
                signedVal ? builder()->CreateFPToSI(*value, *this) : builder()->CreateFPToUI(*value, *this);
        }
    }

    Ref<Value> add(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateNSWAdd(*lhs, *rhs, "add"), "add");
    }

    Ref<Value> sub(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateNSWSub(*lhs, *rhs, "sub"), "sub");
    }

    Ref<Value> mul(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateNSWMul(*lhs, *rhs, "mul"), "mul");
    }

    Ref<Value> div(Ref<Value> lhs, Ref<Value> rhs) const override {
        return isSigned() ? Value::New(ref(), builder()->CreateSDiv(*lhs, *rhs, "sdiv"), "sdiv")
                          : Value::New(ref(), builder()->CreateUDiv(*lhs, *rhs, "udiv"), "udiv");
    }

    Ref<Value> mod(Ref<Value> lhs, Ref<Value> rhs) const override {
        return isSigned() ? Value::New(ref(), builder()->CreateSRem(*lhs, *rhs, "srem"), "srem")
                          : Value::New(ref(), builder()->CreateURem(*lhs, *rhs, "urem"), "urem");
    }

    Ref<Value> pow(Ref<Value> lhs, Ref<Value> rhs) const override {
        // auto pow = builder()->
        // Value::New(
        //     ref(), builder()->CreateCall())
        return nullptr;
    }

    Ref<Value> less(Ref<Value> lhs, Ref<Value> rhs) const override {
        return isSigned() ? Value::New(ref(), builder()->CreateICmpSLT(*lhs, *rhs, "slt"), "slt")
                          : Value::New(ref(), builder()->CreateICmpULT(*lhs, *rhs, "ult"), "ult");
    }

    Ref<Value> lessEq(Ref<Value> lhs, Ref<Value> rhs) const override {
        return isSigned() ? Value::New(ref(), builder()->CreateICmpSLE(*lhs, *rhs, "sle"), "sle")
                          : Value::New(ref(), builder()->CreateICmpULE(*lhs, *rhs, "ule"), "ule");
    }

    Ref<Value> greater(Ref<Value> lhs, Ref<Value> rhs) const override {
        return isSigned() ? Value::New(ref(), builder()->CreateICmpSGT(*lhs, *rhs, "sgt"), "sgt")
                          : Value::New(ref(), builder()->CreateICmpUGT(*lhs, *rhs, "ugt"), "ugt");
    }

    Ref<Value> greaterEq(Ref<Value> lhs, Ref<Value> rhs) const override {
        return isSigned() ? Value::New(ref(), builder()->CreateICmpSGE(*lhs, *rhs, "sge"), "sge")
                          : Value::New(ref(), builder()->CreateICmpUGE(*lhs, *rhs, "uge"), "uge");
    }

    Ref<Value> lshift(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateLShr(*lhs, *rhs, "lshr"), "lshr");
    }

    Ref<Value> rshift(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateAShr(*lhs, *rhs, "ashr"), "ashr");
    }

    Ref<Value> equal(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateICmpEQ(*lhs, *rhs, "eq"), "eq");
    }

    Ref<Value> notEqual(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateICmpNE(*lhs, *rhs, "ne"), "ne");
    }

    Ref<Value> assign(Ref<Value> lhs, Ref<Value> rhs) const override {
        lhs->store(rhs);
        return lhs;
    }

    Ref<Value> bitAnd(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateAnd(*lhs, *rhs, "and"), "and");
    }

    Ref<Value> bitXor(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateXor(*lhs, *rhs, "xor"), "xor");
    }

    Ref<Value> bitOr(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateOr(*lhs, *rhs, "or"), "or");
    }

    Ref<Value> asBool(Ref<Value> value) const override {
        auto zero = llvm::ConstantInt::getFalse(*ref());
        return Value::New(ref(), builder()->CreateICmpNE(*value, zero, "bool"), "bool");
    }
};

class FloatType : public NativeType {
    DECLARE_RTTI(FloatType, NativeType)
  public:
    FloatType(const std::string& name, llvm::Type* type);
    ~FloatType() = default;

    Ref<Value> coerce(Ref<Value> value) const override;

    Ref<Value> add(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateFAdd(*lhs, *rhs, "fdd"), "fadd");
    }

    Ref<Value> sub(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateFSub(*lhs, *rhs, "fsub"), "fsub");
    }

    Ref<Value> mul(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateFMul(*lhs, *rhs, "fmul"), "fmul");
    }

    Ref<Value> div(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateFDiv(*lhs, *rhs, "fdiv"), "fdiv");
    }

    Ref<Value> mod(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateFRem(*lhs, *rhs, "frem"), "frem");
    }

    Ref<Value> pow(Ref<Value> lhs, Ref<Value> rhs) const override {
        // auto pow = builder()->
        // Value::New(
        //     ref(), builder()->CreateCall())
        return nullptr;
    }

    Ref<Value> less(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateFCmpOLT(*lhs, *rhs, "olt"), "olt");
    }

    Ref<Value> lessEq(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateFCmpOLE(*lhs, *rhs, "ole"), "ole");
    }

    Ref<Value> greater(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateFCmpOGT(*lhs, *rhs, "ogt"), "ogt");
    }

    Ref<Value> greaterEq(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateFCmpOGE(*lhs, *rhs, "oge"), "oge");
    }

    Ref<Value> equal(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateFCmpOEQ(*lhs, *rhs, "oeq"), "oeq");
    }

    Ref<Value> notEqual(Ref<Value> lhs, Ref<Value> rhs) const override {
        return Value::New(ref(), builder()->CreateFCmpONE(*lhs, *rhs, "one"), "one");
    }

    Ref<Value> assign(Ref<Value> lhs, Ref<Value> rhs) const override {
        lhs->store(rhs);
        return lhs;
    }

    Ref<Value> asBool(Ref<Value> value) const override {
        auto intType = TypeRef->getIntegerBitWidth() > 32 ? llvm::Type::getInt64Ty(builder()->getContext())
                                                          : llvm::Type::getInt32Ty(builder()->getContext());
        auto zero = llvm::ConstantInt::getFalse(intType);
        auto valAsInt = builder()->CreateFPToSI(*value, intType);
        return Value::New(Types::Bool, builder()->CreateICmpNE(valAsInt, zero, "bool"), "bool");
    }
};
