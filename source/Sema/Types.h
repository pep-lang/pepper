
#pragma once

#include <format>
#include <functional>
#include <memory>
#include <string>
#include <unordered_map>
#include <utility>

#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/RTTI.h"
#include "Core/Vector.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/Support/TypeSize.h"

namespace llvm {
    class Type;
    class Value;
    class IRBuilderBase;
    class LLVMContext;
} // namespace llvm

namespace pepper {
    class Operations;

    class Type : public std::enable_shared_from_this<Type> {
        DECLARE_RTTI(Type);

        friend class Types;
        friend class PointerType;
        using Size = llvm::TypeSize;

      private:
        const Ident Name;
        llvm::Type* IRType;
        const bool IsSigned;
        Ref<Operations> Ops;

      protected:
        llvm::Type* llvmType() const {
            return IRType;
        }

      public:
        Type(const Ident& name, llvm::Type* type, bool isSigned = false);

        const Ident& name() const {
            return Name;
        }

        operator llvm::Type*() const {
            return IRType;
        }

        bool isSigned() const {
            return IsSigned;
        }

        virtual bool isPointer() const {
            return false;
        }

        virtual bool isStruct() const {
            return false;
        }

        virtual Size size() const;
        virtual Size sizeInBits() const;

        virtual Size align() const {
            return Size::Fixed(0);
        }

        virtual Size alignInBits() const {
            return Size::Fixed(0);
        }

        virtual Operations* ops();

        Ref<Type> pointer() const;
    };

    class PointerType : public Type {
        DECLARE_RTTI(PointerType, Type);

      private:
        Ref<Type> PointeeType;

      public:
        PointerType(Ref<Type> pointee);
        PointerType(const Ident& name, Ref<Type> pointee);

        Ref<Type> pointeeType() const {
            return PointeeType;
        }

        bool isPointer() const override {
            return true;
        }
    };

    class Types {
        llvm::LLVMContext& Ctx;
        llvm::StringMap<Ref<Type>> KnownTypes;
        llvm::DenseMap<Type*, llvm::Type*> CanonicalTypes;

        Ref<Type> addType(Ref<Type> t, const Vector<Ident>& aliases = {});
        void aliasType(Type* t, const Ident& alias);
        void aliasType(Type* t, const Vector<Ident>& aliases);
        Ref<Type> getType(const Ident& name) const;
        llvm::Type* getType(const Type* ty) const;

      public:
        explicit Types(llvm::LLVMContext& ctx);
        ~Types() = default;

        static std::string toString(llvm::Type* ty);
        static std::string toString(Ref<Type> ty);
        static Ref<Type> get(const Ident& name);
        static llvm::Type* get(const Type* ty);
        static Ref<Type> add(Ref<Type> type, const Vector<Ident>& aliases = {});

        static Ref<Type> Void;
        static Ref<Type> VoidPtr;
        static Ref<Type> Int8;
        static Ref<Type> UInt8;
        static Ref<Type> Int32;
        static Ref<Type> UInt32;
        static Ref<Type> Int64;
        static Ref<Type> UInt64;
        static Ref<Type> Bool;
        static Ref<Type> Double;
        static Ref<Type> Float;
    };

} // namespace pepper
