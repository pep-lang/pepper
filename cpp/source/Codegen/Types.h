
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
#include "Param.h"
#include "llvm/ADT/StringMap.h"

namespace llvm {
    class Type;
    class Value;
    class IRBuilderBase;
    class LLVMContext;
} // namespace llvm

namespace pepper {

    class FunctionType {
        static std::string Signature(llvm::Type* returnType, const Params& params, bool varargs = false);
    };

    class Type {
        DECLARE_RTTI(Type);

      private:
        const Name TypeName;
        llvm::Type* TypeRef;
        const bool IsSigned;

      public:
        Type(const Name& name, llvm::Type* type, bool signedInt = false)
            : TypeName(name)
            , TypeRef(type)
            , IsSigned(signedInt) {
        }

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
    };

    class Types {
        llvm::LLVMContext& Ctx;
        llvm::StringMap<Ref<Type>> KnownTypes;
        std::unordered_map<llvm::Type*, Ref<Type>> TypeCache;

        Ref<Type> addType(Ref<Type> t, const Vector<Name>& aliases = {});
        Ref<Type> getType(const Name& name) const;
        Ref<Type> getType(llvm::Type* type) const;

      public:
        Types(llvm::LLVMContext& ctx);
        ~Types() = default;

        static std::string toString(llvm::Type* ty);
        static Ref<Type> get(const Name& name);
        static Ref<Type> get(llvm::Type* type);
        static Ref<Type> add(Ref<Type> type, const Vector<Name>& aliases = {});

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
