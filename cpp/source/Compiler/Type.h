
#pragma once

#include "Core/Common.h"
#include "Core/RTTI.h"
#include <format>
#include <memory>
#include <string>
#include <vector>

namespace llvm {
    class Type;
    class Value;
    class IRBuilderBase;
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

    namespace Types {
        void StaticInit();

        Ref<Type> Void;
        Ref<Type> VoidPtr;

        Ref<Type> Int8;
        Ref<Type> Int8Ptr;

        Ref<Type> UInt8;
        Ref<Type> UInt8Ptr;

        Ref<Type> Int32;
        Ref<Type> Int32Ptr;

        Ref<Type> UInt32;
        Ref<Type> UInt32Ptr;

        Ref<Type> Int64;
        Ref<Type> Int64Ptr;

        Ref<Type> UInt64;
        Ref<Type> UInt64Ptr;

        Ref<Type> Bool;

        Ref<Type> Double;
        Ref<Type> DoublePtr;

        Ref<Type> Float;
        Ref<Type> FloatPtr;
    } // namespace Types

} // namespace pepper

template <> struct std::formatter<pepper::Ref<pepper::Type>> : std::formatter<std::string> {
    auto format(pepper::Ref<pepper::Type> t, format_context& ctx) {
        return formatter<string>::format(std::format("{}", t->name()), ctx);
    }
};
