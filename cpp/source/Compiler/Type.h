
#pragma once

#include "Core/Common.h"
#include "Core/RTTI.h"
#include "llvm/ADT/StringMap.h"
#include <format>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace llvm {
    class Type;
    class Value;
    class IRBuilderBase;
    class LLVMContext;
} // namespace llvm

namespace pepper {
    class Value;
    class Type;
    class PointerType;
    class Symbol;

    namespace ast {
        class Symbol;
    }

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

        operator std::string() const {
            return Name;
        }

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

        virtual uint32_t bits() const;

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

    class UserType : public Type {
        DECLARE_RTTI(UserType, Type)
      public:
        UserType(const std::string& name, llvm::Type* type);
        ~UserType() = default;
    };

    class FunctionType : public Type {
        DECLARE_RTTI(FunctionType, Type)
        Ref<Type> ReturnType;
        std::vector<Symbol> Params;
        bool Varargs = false;

      public:
        FunctionType(Ref<Type> returnType, const std::vector<Symbol>& params, bool varargs = false);
        ~FunctionType() = default;

        Ref<Value> coerce(Ref<Value> value) const override;
        Ref<Type> pointer() const override;

        static Ref<FunctionType> Create(Ref<Type> returnType, const std::vector<Symbol>& params, bool varargs = false);
        static Ref<FunctionType> Create(Ref<Type> returnType,
                                        const std::vector<ast::Symbol>& params,
                                        bool varargs = false);
        static std::string Signature(Ref<Type> returnType, const std::vector<Symbol>& params, bool varargs = false);
        static std::string Signature(Ref<Type> returnType,
                                     const std::vector<ast::Symbol>& params,
                                     bool varargs = false);
    };

    class Types {
        llvm::LLVMContext* Ctx;
        llvm::StringMap<Ref<Type>> KnownTypes;

        Ref<Type> getOrCreate(const std::string& name, std::function<Ref<Type>()> createType);

      public:
        Types(llvm::LLVMContext* ctx);
        ~Types() = default;

        template <typename T>
        Ref<Type> addType(const std::string& name, llvm::Type* type) {
            return addType(name, Ref<T>::create(name, type));
        }
        Ref<Type> addType(const std::string& name, Ref<Type> type);
        Ref<Type> getType(const std::string& name);

        static Ref<Type> Void;
        static Ref<Type> Int8;
        static Ref<Type> UInt8;
        static Ref<Type> Int32;
        static Ref<Type> UInt32;
        static Ref<Type> Int64;
        static Ref<Type> UInt64;
        static Ref<Type> Bool;
        static Ref<Type> Double;
        static Ref<Type> Float;

      public:
        Ref<Type> voidType();
        Ref<Type> int8Type();
        Ref<Type> uint8Type();
        Ref<Type> int32Type();
        Ref<Type> uint32Type();
        Ref<Type> int64Type();
        Ref<Type> uint64Type();
        Ref<Type> boolType();
        Ref<Type> doubleType();
        Ref<Type> floatType();
    };

} // namespace pepper

// template <> struct std::formatter<pepper::Ref<pepper::Type>> : std::formatter<std::string> {
//     auto format(pepper::Ref<pepper::Type> t, format_context& ctx) {
//         return formatter<string>::format(std::format("{}", t->name()), ctx);
//     }
// };
