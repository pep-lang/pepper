
#include "Compiler/Type.h"

#include "AST/AST.h"
#include "AST/Nodes.h"
#include "Codegen/Scope.h"
#include "Codegen/Value.h"
#include "Compiler/Context.h"
#include "Compiler/Exceptions.h"
#include "llvm/IR/Value.h"
#include "llvm/Support/raw_ostream.h"
#include <sstream>

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

    static std::string toString(llvm::Type* ty) {
        std::string str;
        llvm::raw_string_ostream stream(str);
        ty->print(stream, true, true);
        return str;
    }

    uint32_t Type::bits() const {
        return TypeRef->getIntegerBitWidth();
    }

    bool Type::isInteger() const {
        return TypeRef->isIntegerTy();
    }

    bool Type::isFloat() const {
        return TypeRef->isFloatingPointTy();
    }

    bool Type::isPointer() const {
        return TypeRef->isPointerTy();
    }

    Ref<Type> Type::ref() const {
        return const_cast<Type*>(this)->shared_from_this();
    }

    llvm::Value* Type::add(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support addition", name());
    }

    llvm::Value* Type::sub(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support subtraction", name());
    }

    llvm::Value* Type::mul(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support multiplication", name());
    }

    llvm::Value* Type::div(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support division", name());
    }

    llvm::Value* Type::mod(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support modulus", name());
    }

    llvm::Value* Type::pow(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support pow", name());
    }

    llvm::Value* Type::less(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support <", name());
    }

    llvm::Value* Type::lessEq(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support <=", name());
    }

    llvm::Value* Type::greater(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support >", name());
    }

    llvm::Value* Type::greaterEq(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support >=", name());
    }

    llvm::Value* Type::lshift(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support <<", name());
    }

    llvm::Value* Type::rshift(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support >>", name());
    }

    llvm::Value* Type::equal(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support equality", name());
    }

    llvm::Value* Type::notEqual(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support non-equality", name());
    }

    llvm::Value* Type::assign(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support assignment", name());
    }

    llvm::Value* Type::bitAnd(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support bitwise and", name());
    }

    llvm::Value* Type::bitXor(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support bitwise xor", name());
    }

    llvm::Value* Type::bitOr(llvm::Value* lhs, llvm::Value* rhs) const {
        throw CompileError("Type {0} does not support bitwise or", name());
    }

    llvm::Value* Type::asBool(llvm::Value* value) const {
        throw CompileError("Type {0} does not support conversion to bool", name());
    }

    class NativeType : public Type {
        DECLARE_RTTI(NativeType, Type)
      protected:
        static Ref<llvm::IRBuilderBase> builder() {
            return Context::get().locals()->builder();
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
        }

        ~PointerType() = default;

        Ref<Type> pointer() const override {
            throw CompileError("Pointer to pointer is not supported");
        }

        llvm::Value* coerce(llvm::Value* value) const override {
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
            auto zero = llvm::ConstantInt::getFalse(*Types::Int64);
            auto valAsInt = builder()->CreatePtrToInt(value, *Types::Int64);
            return builder()->CreateICmpNE(zero, valAsInt, "bool");
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

        llvm::Value* coerce(llvm::Value* value) const override {
            throw CompileError("Cannot convert {0} to void", toString(value->getType()));
            return nullptr;
        }
    };

    class IntegerType : public NativeType {
        DECLARE_RTTI(IntegerType, NativeType)
        bool Signed = false;

      public:
        IntegerType(const std::string& name, llvm::Type* type)
            : NativeType(name, type) {
        }

        ~IntegerType() = default;

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
            }
            throw CompileError("Cannot convert from {0} to {0}", toString(type), name());
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
            auto zero = llvm::ConstantInt::getFalse(*ref());
            return builder()->CreateICmpNE(value, zero, "bool");
        }
    };

    class FloatType : public NativeType {
        DECLARE_RTTI(FloatType, NativeType)
      public:
        FloatType(const std::string& name, llvm::Type* type)
            : NativeType(name, type) {
        }

        ~FloatType() = default;

        llvm::Value* coerce(llvm::Value* value) const override {
            if (value->getType() == *this) {
                return value;
            }
            if (value->getType()->isIntegerTy() || value->getType()->isFloatingPointTy()) {
                return builder()->CreateFPCast(value, *this);
            }
            throw CompileError("Cannot convert from {0} to {0}", toString(value->getType()), name());
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
            auto intType = TypeRef->getIntegerBitWidth() > 32 ? llvm::Type::getInt64Ty(builder()->getContext())
                                                              : llvm::Type::getInt32Ty(builder()->getContext());
            auto zero = llvm::ConstantInt::getFalse(intType);
            auto valAsInt = builder()->CreateFPToSI(value, intType);
            return builder()->CreateICmpNE(valAsInt, zero, "bool");
        }
    };

    //    FunctionType::FunctionType(Ref<Type> returnType, const std::vector<Symbol>& params, bool varargs)
    //        : Type(Signature(returnType, params, varargs), llvm::FunctionType::get(*returnType, varargs)) {
    //    }
    //
    //    Ref<FunctionType> FunctionType::Create(Ref<Type> returnType, const std::vector<Symbol>& params, bool varargs)
    //    {
    //        std::string sig = Signature(returnType, params, varargs);
    //        if (auto func = Context::get().ast()->builder()->findType(sig)) {
    //                              return func.as<FunctionType>();
    //        }
    //        return nullptr;
    //    }
    //
    //    Ref<FunctionType> FunctionType::Create(Ref<Type> returnType, const std::vector<ast::Symbol>& params, bool
    //    varargs) {
    //        std::string sig = Signature(returnType, params, varargs);
    //        if (auto func = Context::get().ast()->builder()->findType(sig)) {
    //                              return func.as<FunctionType>();
    //        }
    //        return nullptr;
    //    }

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

    //    llvm::Value* FunctionType::coerce(llvm::Value* val) const {
    //        throw CompileError("Cannot coerce to a function");
    //    }
    //
    //    Ref<Type> FunctionType::pointer() const {
    //        throw CompileError("Cannot create a pointer to a function");
    //    }

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
