
#pragma once

#include "fmt/format.h"
#include <functional>
#include <llvm/IR/Type.h>
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
        const Ident identifier;
        llvm::Type* ir_type;
        const bool signed_type;
        Ref<Operations> operations;

      protected:
        llvm::Type* llvmType() const {
            return ir_type;
        }

      public:
        Type(const Ident& name, llvm::Type* type, bool is_signed_type = false);

        const Ident& name() const {
            return identifier;
        }

        operator llvm::Type*() const {
            return ir_type;
        }

        bool is_signed() const {
            return signed_type;
        }

        bool is_integer() const {
            return ir_type->isIntegerTy();
        }

        virtual bool is_pointer() const {
            return false;
        }

        virtual bool is_struct() const {
            return false;
        }

        virtual Size size() const;
        virtual Size size_in_bits() const;

        virtual Size align() const {
            return Size::Fixed(0);
        }

        virtual Size align_in_bits() const {
            return Size::Fixed(0);
        }

        virtual Operations* ops();

        Ref<Type> pointer() const;
    };

    class PointerType : public Type {
        DECLARE_RTTI(PointerType, Type);

      private:
        Ref<Type> pointee;

      public:
        PointerType(Ref<Type> pointee);
        PointerType(const Ident& name, Ref<Type> pointee);

        Ref<Type> pointee_type() const {
            return pointee;
        }

        bool is_pointer() const override {
            return true;
        }
    };

    class Types {
        llvm::LLVMContext& llvm_ctx;
        llvm::StringMap<Ref<Type>> known_types;
        llvm::DenseMap<Type*, llvm::Type*> canonical_types;

        Ref<Type> add_type(Ref<Type> t, const Vector<Ident>& aliases = {});
        void alias_type(Type* t, const Ident& alias);
        void alias_type(Type* t, const Vector<Ident>& aliases);
        Ref<Type> get_type(const Ident& name) const;
        llvm::Type* get_type(const Type* ty) const;

      public:
        explicit Types(llvm::LLVMContext& ctx);
        ~Types() = default;

        static std::string to_string(llvm::Type* ty);
        static std::string to_string(Ref<Type> ty);
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
