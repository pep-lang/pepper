
#pragma once

#include "Core/Common.h"
#include "Core/RTTI.h"
#include "Param.h"
#include "llvm/ADT/StringMap.h"
#include <format>
#include <functional>
#include <memory>
#include <string>
#include <utility>
#include <vector>

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

    class Types {
        llvm::LLVMContext& Ctx;
        llvm::StringMap<llvm::Type*> KnownTypes;

        llvm::Type* getOrCreate(const std::string& name, std::function<llvm::Type*()> createType);

      public:
        Types(llvm::LLVMContext& ctx);
        ~Types() = default;

        template <typename T>
        llvm::Type* addType(const std::string& name, llvm::Type* type) {
            return addType(name, Ref<T>::New(name, type));
        }

        llvm::Type* addType(const std::string& name, llvm::Type* type);
        llvm::Type* getType(const std::string& name);

        static std::string toString(llvm::Type* ty);

        static llvm::Type* Void;
        static llvm::Type* Int8;
        static llvm::Type* UInt8;
        static llvm::Type* Int32;
        static llvm::Type* UInt32;
        static llvm::Type* Int64;
        static llvm::Type* UInt64;
        static llvm::Type* Bool;
        static llvm::Type* Double;
        static llvm::Type* Float;
    };

} // namespace pepper
