
#pragma once

class Value;
class ValueRef;
class PointerType;
class PointerTypeRef;

namespace llvm {
    class Type;
    class Value;
    class IRBuilderBase;
} // namespace llvm

class Type {
  private:
    std::string Name;
    llvm::Type* Ref = nullptr;
    uint32_t IsInt : 1 = false;
    uint32_t IsReal : 1 = false;
    uint32_t IsPointer : 1 = false;

  public:
    Type(const std::string name, llvm::Type* type)
        : Name(name)
        , Ref(type) {}

    virtual ~Type() = default;

    operator llvm::Type*() const;

    virtual ValueRef coerce(ValueRef value) const = 0;
    virtual PointerTypeRef pointer() const = 0;
    virtual uint32_t bits() const = 0;

    llvm::Value* alloc(IRBuilderBase* builder);

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

using TypeRef = std::shared_ptr<Type>;

class NativeType : public Type {
  protected:
    static llvm::IRBuilderBase* builder();

  public:
    NativeType(const std::string& name, llvm::Type* type);
    ~NativeType() = default;

    uint32_t bits() const override;
    PointerTypeRef pointer() const override;
};

class PointerType : public NativeType {
  public:
    PointerType(const std::string& name, llvm::Type* type);
    ~PointerType() = default;

    PointerTypeRef pointer() const override;
    ValueRef coerce(ValueRef value) const override;

    ValueRef equal(ValueRef lhs, ValueRef rhs) const override;
    ValueRef notEqual(ValueRef lhs, ValueRef rhs) const override;
    ValueRef assign(ValueRef lhs, ValueRef rhs) const override;
}

using PointerTypeRef = std::shared_ptr<PointerType>;

class VoidType : public NativeType {
  public:
    VoidType(const std::string& name, llvm::Type* type);
    ~VoidType() = default;

    PointerTypeRef pointer() const override;
    ValueRef coerce(ValueRef value) const override;
}

class IntegerType : public NativeType {
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
}

class FloatType : public NativeType {
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
}

class UserType : Type {
  public:
    UserType(const std::string& name, llvm::Type* type);
    ~UserType() = default;
}

class FunctionType : Type {
    TypeRef ReturnType;
    std::vector<TypedValue> Params;
    bool Varargs = false;

  public:
    FunctionType(TypeRef returnType, const std::vector<TypedValue>& params, bool varargs = false);
    ~FunctionType() = default;

    static FunctionTypeRef(TypeRef returnType, const std::vector<TypedValue>& params, bool varargs = false);
    static std::string Signature(TypeRef returnType, const std::vector<TypedValue>& params, bool varargs = false);
}

namespace Types {
    void StaticInit();

    const VoidType Void;
    const PointerType VoidPtr;

    const IntegerType Int8;
    const PointerType Int8Ptr;

    const IntegerType UInt8;
    const PointerType UInt8Ptr;

    const IntegerType Int32;
    const PointerType Int32Ptr;

    const IntegerType UInt32;
    const PointerType UInt32Ptr;

    const IntegerType Int64;
    const PointerType Int64Ptr;

    const IntegerType UInt64;
    const PointerType UInt64Ptr;

    const IntegerType Bool;

    const FloatType Double;
    const PointerType DoublePtr;

    const FloatType Float;
    const PointerType FloatPtr;
}
