
#pragma once

#include <format>
#include <functional>
#include <memory>
#include <string>
#include <unordered_map>
#include <utility>

#include "Core/Common.h"
#include "Core/Name.h"
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
        const Name TypeName;
        llvm::Type* TypeRef;
        const bool IsSigned;
        Ref<TypeOps> Ops;

      public:
        TypeInfo(const Name& name, llvm::Type* type, bool isSigned = false);

        llvm::Type* llvmType() const {
            return TypeRef;
        }

        const Name& name() const {
            return TypeName;
        }

        operator llvm::Type*() const {
            return TypeRef;
        }

        bool isSigned() const {
            return IsSigned;
        }

        TypeOps* ops();

        Ref<TypeInfo> pointer() const;
    };

    class Types {
        llvm::LLVMContext& Ctx;
        llvm::StringMap<Ref<TypeInfo>> KnownTypes;

        Ref<TypeInfo> addType(Ref<TypeInfo> t, const Vector<Name>& aliases = {});
        Ref<TypeInfo> getType(const Name& name) const;

      public:
        explicit Types(llvm::LLVMContext& ctx);
        ~Types() = default;

        static std::string toString(llvm::Type* ty);
        static std::string toString(Ref<TypeInfo> ty);
        static Ref<TypeInfo> get(const Name& name);
        static Ref<TypeInfo> add(Ref<TypeInfo> type, const Vector<Name>& aliases = {});

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
