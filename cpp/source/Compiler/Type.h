
#pragma once

#include "Core/Common.h"
#include "Core/RTTI.h"
#include <format>
#include <memory>
#include <string>
#include <vector>

class Value;
class Type;
class PointerType;
class TypedValue;

namespace llvm {
    class Type;
    class Value;
    class IRBuilderBase;
} // namespace llvm

class Type : public std::enable_shared_from_this<Type> {
    DECLARE_RTTI(Type);

  protected:
    std::string Name;
    llvm::Type* TypeRef = nullptr;
    uint32_t IsInt : 1;
    uint32_t IsReal : 1;
    uint32_t IsPointer : 1;
    uint32_t IsConstant : 1;

  public:
    Type(const std::string name, llvm::Type* type)
        : Name(name)
        , TypeRef(type) {
    }

    virtual ~Type() = default;

    Ref<Type> ref() const;

    const std::string& name() const {
        return Name;
    }

    operator llvm::Type*() const {
        return TypeRef;
    }

    bool isInteger() const {
        return IsInt;
    }

    bool isFloat() const {
        return IsReal;
    }

    bool isPointer() const {
        return IsPointer;
    }

    bool isConstant() const {
        return IsConstant;
    }

    virtual Ref<Value> coerce(Ref<Value> value) const = 0;
    virtual Ref<Type> pointer() const = 0;
    virtual uint32_t bits() const = 0;

    llvm::Value* alloc(llvm::IRBuilderBase* builder) const;

    virtual Ref<Value> add(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> sub(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> mul(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> div(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> mod(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> pow(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> less(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> lessEq(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> greater(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> greaterEq(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> lshift(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> rshift(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> equal(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> notEqual(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> assign(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> bitAnd(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> bitXor(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> bitOr(Ref<Value> lhs, Ref<Value> rhs) const;
    virtual Ref<Value> asBool(Ref<Value> value) const;
};

template <> struct std::formatter<Ref<Type>> : std::formatter<std::string> {
    auto format(Ref<Type> t, format_context& ctx) {
        return formatter<string>::format(std::format("{}", t->name()), ctx);
    }
};

class UserType : Type {
    DECLARE_RTTI(UserType, Type)
  public:
    UserType(const std::string& name, llvm::Type* type);
    ~UserType() = default;
};

class FunctionType : Type {
    DECLARE_RTTI(FunctionType, Type)
    Ref<Type> ReturnType;
    std::vector<TypedValue> Params;
    bool Varargs = false;

  public:
    FunctionType(Ref<Type> returnType, const std::vector<TypedValue>& params, bool varargs = false);
    ~FunctionType() = default;

    static FunctionType Create(Ref<Type> returnType, const std::vector<TypedValue>& params, bool varargs = false);
    static std::string Signature(Ref<Type> returnType, const std::vector<TypedValue>& params, bool varargs = false);
};

namespace Types {
    void StaticInit();

    const Ref<Type> Void;
    const Ref<Type> VoidPtr;

    const Ref<Type> Int8;
    const Ref<Type> Int8Ptr;

    const Ref<Type> UInt8;
    const Ref<Type> UInt8Ptr;

    const Ref<Type> Int32;
    const Ref<Type> Int32Ptr;

    const Ref<Type> UInt32;
    const Ref<Type> UInt32Ptr;

    const Ref<Type> Int64;
    const Ref<Type> Int64Ptr;

    const Ref<Type> UInt64;
    const Ref<Type> UInt64Ptr;

    const Ref<Type> Bool;

    const Ref<Type> Double;
    const Ref<Type> DoublePtr;

    const Ref<Type> Float;
    const Ref<Type> FloatPtr;
} // namespace Types
