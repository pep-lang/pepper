
#include "Compiler/Type.h"

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "Compiler/Context.h"
#include "Compiler/Exceptions.h"
#include "Compiler/Scope.h"
#include "Compiler/Value.h"

#pragma warning(disable : 4624) // warning C4624: 'llvm::detail::move_construction_triviality_helper<T>': destructor was
                                // implicitly defined as deleted
#include "llvm/ADT/StringExtras.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper {
    llvm::Value* Type::alloc(llvm::IRBuilderBase* builder) const {
        builder = builder ? builder : Context::get().locals()->localRegisters().get();
        return builder->CreateAlloca(*this, nullptr, Name.c_str());
    }

    uint32_t Type::bits() const {
        return TypeRef->getIntegerBitWidth();
    }

    Ref<Type> Type::ref() const {
        return const_cast<Type*>(this)->shared_from_this();
    }

    Ref<Value> Type::add(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {0} does not support addition", name());
    }

    Ref<Value> Type::sub(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {0} does not support subtraction", name());
    }

    Ref<Value> Type::mul(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {0} does not support multiplication", name());
    }

    Ref<Value> Type::div(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support division", name());
    }

    Ref<Value> Type::mod(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support modulus", name());
    }

    Ref<Value> Type::pow(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support pow", name());
    }

    Ref<Value> Type::less(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support <", name());
    }

    Ref<Value> Type::lessEq(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support <=", name());
    }

    Ref<Value> Type::greater(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support >", name());
    }

    Ref<Value> Type::greaterEq(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support >=", name());
    }

    Ref<Value> Type::lshift(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support <<", name());
    }

    Ref<Value> Type::rshift(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support >>", name());
    }

    Ref<Value> Type::equal(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support equality", name());
    }

    Ref<Value> Type::notEqual(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support non-equality", name());
    }

    Ref<Value> Type::assign(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support assignment", name());
    }

    Ref<Value> Type::bitAnd(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support bitwise and", name());
    }

    Ref<Value> Type::bitXor(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support bitwise xor", name());
    }

    Ref<Value> Type::bitOr(Ref<Value> lhs, Ref<Value> rhs) const {
        throw new CompileError("Type {} does not support bitwise or", name());
    }

    Ref<Value> Type::asBool(Ref<Value> value) const {
        throw new CompileError("Type {} does not support conversion to bool", name());
    }

    class NativeType : public Type {
        DECLARE_RTTI(NativeType, Type)
      protected:
        static llvm::IRBuilderBase* builder() {
            return Context::get().locals()->ir().get();
        }

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
        PointerType(const std::string& name, llvm::Type* type)
            : NativeType(name, type) {
            IsPointer = true;
        }

        ~PointerType() = default;

        Ref<Type> pointer() const override {
            throw new CompileError("Pointer to pointer is not supported");
        }

        Ref<Value> coerce(Ref<Value> value) const override {
            throw new CompileError("Coercion to pointer is not supported");
        }

        Ref<Value> equal(Ref<Value> lhs, Ref<Value> rhs) const override {
            return Value::New(Types::Bool, builder()->CreateICmpEQ(*lhs, *rhs));
        }

        Ref<Value> notEqual(Ref<Value> lhs, Ref<Value> rhs) const override {
            return Value::New(Types::Bool, builder()->CreateICmpNE(*lhs, *rhs));
        }

        Ref<Value> assign(Ref<Value> lhs, Ref<Value> rhs) const override {
            lhs->store(rhs);
            return lhs;
        }

        Ref<Value> asBool(Ref<Value> value) const override {
            auto zero = llvm::ConstantInt::getFalse(*Types::Int64);
            auto valAsInt = builder()->CreatePtrToInt(*value, *Types::Int64);
            return Value::New(Types::Bool, builder()->CreateICmpNE(zero, valAsInt, "bool"), "bool");
        }
    };

    class VoidType : public NativeType {
        DECLARE_RTTI(VoidType, NativeType)
      public:
        VoidType(const std::string& name, llvm::Type* type)
            : NativeType(name, type) {
        }

        ~VoidType() = default;

        Ref<Type> pointer() const override {
            return Types::Int8->pointer();
        }

        Ref<Value> coerce(Ref<Value> value) const override {
            throw new CompileError("Cannot convert {} to void", value->type()->name());
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
            throw new CompileError("Cannot convert from {} to {}", value->type()->name(), name());
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
        FloatType(const std::string& name, llvm::Type* type)
            : NativeType(name, type) {
            IsReal = true;
        }

        ~FloatType() = default;

        Ref<Value> coerce(Ref<Value> value) const override {
            if (value->type().get() == this && !value->type()->isConstant()) {
                return value;
            }
            if (value->type()->isInteger() || value->type()->isFloat()) {
                return Value::New(ref(), builder()->CreateFPCast(*value, *this));
            }
            throw new CompileError("Cannot convert from {} to {}", value->type()->name(), name());
        }

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

    FunctionType::FunctionType(Ref<Type> returnType, const std::vector<Symbol>& params, bool varargs)
        : Type(Signature(returnType, params, varargs), llvm::FunctionType::get(*returnType, varargs)) {
    }

    Ref<FunctionType> FunctionType::Create(Ref<Type> returnType, const std::vector<Symbol>& params, bool varargs) {
        std::string sig = Signature(returnType, params, varargs);
        if (auto func = Context::get().ast()->builder()->findType(sig)) {
            return func.as<FunctionType>();
        }
        return nullptr;
    }

    Ref<FunctionType> FunctionType::Create(Ref<Type> returnType, const std::vector<ast::Symbol>& params, bool varargs) {
        std::string sig = Signature(returnType, params, varargs);
        if (auto func = Context::get().ast()->builder()->findType(sig)) {
            return func.as<FunctionType>();
        }
        return nullptr;
    }

    std::string FunctionType::Signature(Ref<Type> returnType, const std::vector<Symbol>& params, bool varargs) {
        std::vector<std::string> paramNames;
        std::transform(params.begin(), params.end(), std::back_inserter(paramNames), [](auto p) { return p.name(); });
        std::string paramsString = llvm::join(paramNames.begin(), paramNames.end(), ", ");
        std::string ellipsis = varargs ? ", ..." : "";
        return llvm::formatv("{0}({1}{2})", returnType->name(), paramsString, ellipsis);
    }

    std::string FunctionType::Signature(Ref<Type> returnType, const std::vector<ast::Symbol>& params, bool varargs) {
        std::vector<std::string> paramNames;
        std::transform(params.begin(), params.end(), std::back_inserter(paramNames), [](auto p) { return p.name(); });
        std::string paramsString = llvm::join(paramNames.begin(), paramNames.end(), ", ");
        std::string ellipsis = varargs ? ", ..." : "";
        return llvm::formatv("{0}({1}{2})", returnType->name(), paramsString, ellipsis);
    }

    Ref<Value> FunctionType::coerce(Ref<Value> val) const {
        throw new CompileError("Cannot coerce to a function");
    }

    Ref<Type> FunctionType::pointer() const {
        throw new CompileError("Cannot create a pointer to a function");
    }

    Ref<Type> Types::Bool;
    Ref<Type> Types::Void;
    Ref<Type> Types::Int8;
    Ref<Type> Types::UInt8;
    Ref<Type> Types::Int32;
    Ref<Type> Types::UInt32;
    Ref<Type> Types::Int64;
    Ref<Type> Types::UInt64;
    Ref<Type> Types::Double;
    Ref<Type> Types::Float;

    Types::Types(llvm::LLVMContext& ctx)
        : Ctx(ctx) {
        Void = voidType();
        Int8 = int8Type();
        UInt8 = uint8Type();
        Int32 = int32Type();
        UInt32 = uint32Type();
        Int64 = int64Type();
        UInt64 = uint64Type();
        Bool = boolType();
        Double = doubleType();
        Float = floatType();
        addType("int", Int32);
        addType("uint", UInt32);
        addType("long", Int64);
        addType("ulong", UInt64);
        addType("byte", UInt8);
        addType("char", Int8);
    }

    Ref<Type> Types::addType(const std::string& name, Ref<Type> type) {
        if (auto ty = getType(name)) {
            if (ty != type)
                throw new InternalCompilerError("Types: type collision: {0}", ty->name());
        }
        return KnownTypes[name] = type;
    }

    Ref<Type> Types::getType(const std::string& name) {
        auto it = KnownTypes.find(name);
        if (it != KnownTypes.end()) {
            return it->getValue();
        }
        return Ref<Type>(nullptr);
    }

    Ref<Type> Types::getOrCreate(const std::string& name, std::function<Ref<Type>()> createType) {
        if (auto ty = getType(name)) {
            return ty;
        }
        return KnownTypes[name] = createType();
    }

    Ref<Type> Types::voidType() {
        return getOrCreate("void",
                           [this]() { return Ref<VoidType>::create("void", llvm::Type::getVoidTy(Ctx)).as<Type>(); });
    }

    Ref<Type> Types::int8Type() {
        return getOrCreate("i8",
                           [this]() { return Ref<IntegerType>::create("i8", llvm::Type::getInt8Ty(Ctx)).as<Type>(); });
    }

    Ref<Type> Types::uint8Type() {
        return getOrCreate("u8",
                           [this]() { return Ref<IntegerType>::create("u8", llvm::Type::getInt8Ty(Ctx)).as<Type>(); });
    }

    Ref<Type> Types::int32Type() {
        return getOrCreate("i32", [this]() {
            return Ref<IntegerType>::create("i32", llvm::Type::getInt32Ty(Ctx)).as<Type>();
        });
    }

    Ref<Type> Types::uint32Type() {
        return getOrCreate("u32", [this]() {
            return Ref<IntegerType>::create("u32", llvm::Type::getInt32Ty(Ctx)).as<Type>();
        });
    }

    Ref<Type> Types::int64Type() {
        return getOrCreate("i64", [this]() {
            return Ref<IntegerType>::create("i64", llvm::Type::getInt64Ty(Ctx)).as<Type>();
        });
    }

    Ref<Type> Types::uint64Type() {
        return getOrCreate("u64", [this]() {
            return Ref<IntegerType>::create("u64", llvm::Type::getInt64Ty(Ctx)).as<Type>();
        });
    }

    Ref<Type> Types::boolType() {
        return getOrCreate("bool", [this]() {
            return Ref<IntegerType>::create("bool", llvm::Type::getInt1Ty(Ctx)).as<Type>();
        });
    }

    Ref<Type> Types::doubleType() {
        return getOrCreate("double", [this]() {
            return Ref<FloatType>::create("double", llvm::Type::getDoubleTy(Ctx)).as<Type>();
        });
    }

    Ref<Type> Types::floatType() {
        return getOrCreate("float", [this]() {
            return Ref<FloatType>::create("float", llvm::Type::getFloatTy(Ctx)).as<Type>();
        });
    }
} // namespace pepper
