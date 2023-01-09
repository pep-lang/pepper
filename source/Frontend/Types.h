
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
#include "llvm/ADT/StringMap.h"

namespace llvm {
    class Type;
    class Value;
    class IRBuilderBase;
    class LLVMContext;
} // namespace llvm

namespace pepper {
    class TypeOps;

    class TypeInfo : public std::enable_shared_from_this<TypeInfo> {
        DECLARE_RTTI(TypeInfo);

      private:
        const Ident TypeName;
        llvm::Type* TypeRef;
        const bool IsSigned;
        Ref<TypeOps> Ops;

      public:
        TypeInfo(const Ident& name, llvm::Type* type, bool isSigned = false);

        llvm::Type* llvmType() const {
            return TypeRef;
        }

        const Ident& name() const {
            return TypeName;
        }

        operator llvm::Type*() const {
            return TypeRef;
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

        virtual TypeOps* ops();

        Ref<TypeInfo> pointer() const;
    };

    class PointerTypeInfo : public TypeInfo {
        DECLARE_RTTI(PointerTypeInfo, TypeInfo);

      public:
        PointerTypeInfo(Ref<TypeInfo> pointee);
    };

    class Types {
        llvm::LLVMContext& Ctx;
        llvm::StringMap<Ref<TypeInfo>> KnownTypes;

        Ref<TypeInfo> addType(Ref<TypeInfo> t, const Vector<Ident>& aliases = {});
        Ref<TypeInfo> getType(const Ident& name) const;

      public:
        explicit Types(llvm::LLVMContext& ctx);
        ~Types() = default;

        static std::string toString(llvm::Type* ty);
        static std::string toString(Ref<TypeInfo> ty);
        static Ref<TypeInfo> get(const Ident& name);
        static Ref<TypeInfo> add(Ref<TypeInfo> type, const Vector<Ident>& aliases = {});

        static Ref<TypeInfo> Void;
        static Ref<TypeInfo> VoidPtr;
        static Ref<TypeInfo> Int8;
        static Ref<TypeInfo> UInt8;
        static Ref<TypeInfo> Int32;
        static Ref<TypeInfo> UInt32;
        static Ref<TypeInfo> Int64;
        static Ref<TypeInfo> UInt64;
        static Ref<TypeInfo> Bool;
        static Ref<TypeInfo> Double;
        static Ref<TypeInfo> Float;
    };

} // namespace pepper
