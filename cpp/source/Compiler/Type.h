
#pragma once

#include "Core/RTTI.h"
#include <memory>
#include <string>
#include <vector>

class Value;
class ValueRef;
class Type;
using TypeRef = std::shared_ptr<Type>;
class PointerType;
class TypedValue;

namespace llvm {
    class Type;
    class Value;
    class IRBuilderBase;
} // namespace llvm

class Type {
    DECLARE_RTTI(Type);

  private:
    std::string Name;
    llvm::Type* Ref = nullptr;
    uint32_t IsInt : 1;
    uint32_t IsReal : 1;
    uint32_t IsPointer : 1;

  public:
    Type(const std::string name, llvm::Type* type)
        : Name(name)
        , Ref(type) {}

    virtual ~Type() = default;

    operator llvm::Type*() const;

    virtual ValueRef coerce(ValueRef value) const = 0;
    virtual TypeRef pointer() const = 0;
    virtual uint32_t bits() const = 0;

    llvm::Value* alloc(llvm::IRBuilderBase* builder) const;

    virtual ValueRef add(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef sub(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef mul(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef div(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef mod(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef pow(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef less(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef lessEq(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef greater(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef greaterEq(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef lshift(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef rshift(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef equal(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef notEqual(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef assign(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef bitAnd(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef bitXor(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef bitOr(ValueRef lhs, ValueRef rhs) const = 0;
    virtual ValueRef asBool(ValueRef lhs, ValueRef rhs) const = 0;
};

class NativeType : public Type {
    DECLARE_RTTI(NativeType, Type)
  protected:
    static llvm::IRBuilderBase* builder();

  public:
    NativeType(const std::string& name, llvm::Type* type);
    ~NativeType() = default;

    uint32_t bits() const override;
    TypeRef pointer() const override;
};

class PointerType : public NativeType {
    DECLARE_RTTI(PointerType, NativeType)
  public:
    PointerType(const std::string& name, llvm::Type* type);
    ~PointerType() = default;

    TypeRef pointer() const override;
    ValueRef coerce(ValueRef value) const override;

    ValueRef equal(ValueRef lhs, ValueRef rhs) const override;
    ValueRef notEqual(ValueRef lhs, ValueRef rhs) const override;
    ValueRef assign(ValueRef lhs, ValueRef rhs) const override;
};

class VoidType : public NativeType {
    DECLARE_RTTI(VoidType, NativeType)
  public:
    VoidType(const std::string& name, llvm::Type* type);
    ~VoidType() = default;

    TypeRef pointer() const override;
    ValueRef coerce(ValueRef value) const override;
};

class IntegerType : public NativeType {
    DECLARE_RTTI(IntegerType, NativeType)
    bool Signed = false;

  public:
    IntegerType(const std::string& name, llvm::Type* type);
    ~IntegerType() = default;

    ValueRef coerce(ValueRef value) const override;

    ValueRef add(ValueRef lhs, ValueRef rhs) const override;
    ValueRef sub(ValueRef lhs, ValueRef rhs) const override;
    ValueRef mul(ValueRef lhs, ValueRef rhs) const override;
    ValueRef div(ValueRef lhs, ValueRef rhs) const override;
    ValueRef mod(ValueRef lhs, ValueRef rhs) const override;
    ValueRef pow(ValueRef lhs, ValueRef rhs) const override;
    ValueRef less(ValueRef lhs, ValueRef rhs) const override;
    ValueRef lessEq(ValueRef lhs, ValueRef rhs) const override;
    ValueRef greater(ValueRef lhs, ValueRef rhs) const override;
    ValueRef greaterEq(ValueRef lhs, ValueRef rhs) const override;
    ValueRef lshift(ValueRef lhs, ValueRef rhs) const override;
    ValueRef rshift(ValueRef lhs, ValueRef rhs) const override;
    ValueRef equal(ValueRef lhs, ValueRef rhs) const override;
    ValueRef notEqual(ValueRef lhs, ValueRef rhs) const override;
    ValueRef assign(ValueRef lhs, ValueRef rhs) const override;
    ValueRef bitAnd(ValueRef lhs, ValueRef rhs) const override;
    ValueRef bitXor(ValueRef lhs, ValueRef rhs) const override;
    ValueRef bitOr(ValueRef lhs, ValueRef rhs) const override;
    ValueRef asBool(ValueRef lhs, ValueRef rhs) const override;
};

class FloatType : public NativeType {
    DECLARE_RTTI(FloatType, NativeType)
  public:
    FloatType(const std::string& name, llvm::Type* type);
    ~FloatType() = default;

    ValueRef coerce(ValueRef value) const override;

    ValueRef add(ValueRef lhs, ValueRef rhs) const override;
    ValueRef sub(ValueRef lhs, ValueRef rhs) const override;
    ValueRef mul(ValueRef lhs, ValueRef rhs) const override;
    ValueRef div(ValueRef lhs, ValueRef rhs) const override;
    ValueRef mod(ValueRef lhs, ValueRef rhs) const override;
    ValueRef pow(ValueRef lhs, ValueRef rhs) const override;
    ValueRef less(ValueRef lhs, ValueRef rhs) const override;
    ValueRef lessEq(ValueRef lhs, ValueRef rhs) const override;
    ValueRef greater(ValueRef lhs, ValueRef rhs) const override;
    ValueRef greaterEq(ValueRef lhs, ValueRef rhs) const override;
    ValueRef lshift(ValueRef lhs, ValueRef rhs) const override;
    ValueRef rshift(ValueRef lhs, ValueRef rhs) const override;
    ValueRef equal(ValueRef lhs, ValueRef rhs) const override;
    ValueRef notEqual(ValueRef lhs, ValueRef rhs) const override;
    ValueRef assign(ValueRef lhs, ValueRef rhs) const override;
    ValueRef bitAnd(ValueRef lhs, ValueRef rhs) const override;
    ValueRef bitXor(ValueRef lhs, ValueRef rhs) const override;
    ValueRef bitOr(ValueRef lhs, ValueRef rhs) const override;
    ValueRef asBool(ValueRef lhs, ValueRef rhs) const override;
};

class UserType : Type {
    DECLARE_RTTI(UserType, Type)
  public:
    UserType(const std::string& name, llvm::Type* type);
    ~UserType() = default;
};

class FunctionType : Type {
    DECLARE_RTTI(FunctionType, Type)
    TypeRef ReturnType;
    std::vector<TypedValue> Params;
    bool Varargs = false;

  public:
    FunctionType(TypeRef returnType, const std::vector<TypedValue>& params, bool varargs = false);
    ~FunctionType() = default;

    static FunctionType Create(TypeRef returnType, const std::vector<TypedValue>& params, bool varargs = false);
    static std::string Signature(TypeRef returnType, const std::vector<TypedValue>& params, bool varargs = false);
};

namespace Types {
    void StaticInit();

    const TypeRef Void;
    const TypeRef VoidPtr;

    const TypeRef Int8;
    const TypeRef Int8Ptr;

    const TypeRef UInt8;
    const TypeRef UInt8Ptr;

    const TypeRef Int32;
    const TypeRef Int32Ptr;

    const TypeRef UInt32;
    const TypeRef UInt32Ptr;

    const TypeRef Int64;
    const TypeRef Int64Ptr;

    const TypeRef UInt64;
    const TypeRef UInt64Ptr;

    const TypeRef Bool;

    const TypeRef Double;
    const TypeRef DoublePtr;

    const TypeRef Float;
    const TypeRef FloatPtr;
} // namespace Types
