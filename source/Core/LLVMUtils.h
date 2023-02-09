

#pragma once

#include <string>

#include "Core/Exceptions.h"
#include "Core/String.h"
#include "Sema/SemaContext.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"
#include "llvm/Support/raw_ostream.h"

namespace pepper {
    inline std::string toString(llvm::Value* value) {
        std::string str;
        if (value) {
            llvm::raw_string_ostream ostr(str);
            value->print(ostr, true);
            // trim functions down to their signature
            auto bracePos = str.find('{');
            if (bracePos != std::string::npos) {
                str = str.substr(0, bracePos - 1);
            }
        } else {
            str = "null";
        }
        return trim(str);
    }

    inline std::string toString(llvm::Type* type) {
        std::string str;
        llvm::raw_string_ostream ostr(str);
        type->print(ostr, true);
        return trim(str);
    }

    inline Ref<llvm::IRBuilderBase> ir() {
        return SemaContext::get().locals()->builder();
    }

    inline llvm::Type* resolveType(Address value) {
        if (llvm::isa<llvm::AllocaInst>(*value.Value)) {
            auto allocaInst = llvm::cast<llvm::AllocaInst>(value.Value);
            return allocaInst->getAllocatedType();
        }
        if (llvm::isa<llvm::GetElementPtrInst>(*value.Value)) {
            auto gepInst = llvm::cast<llvm::GetElementPtrInst>(value.Value);
            return gepInst->getResultElementType();
        }
        return value->getType();
    }

    inline Address load(Address value) {
        if (llvm::isa<llvm::AllocaInst>(*value.Value)) {
            auto type = resolveType(value);
            return Address{value.Ty, ir()->CreateLoad(type, value)};
        }
        if (llvm::isa<llvm::GetElementPtrInst>(*value.Value)) {
            auto type = resolveType(value);
            // This may be a pointer to a pointer to a struct (e.g. a struct reference), so an additional
            // read pass is necessary here
            return Address{value.Ty, ir()->CreateLoad(type, value)};
        }
        return value;
    }

    inline Address read(Address value) {
        value = load(value);
        if (value.Ty->isPointer()) {
            auto type = value.Ty.as<PointerType>();
            auto pointee = type->pointeeType();
            if (pointee->isStruct()) {
                return Address{pointee, ir()->CreateLoad(*type, value)};
            }
        }
        return value;
    }

    inline Address zeroValue(Ref<Type> type) {
        auto llvmType = Types::get(type.get());
        if (llvmType->isIntegerTy())
            return Address{type, llvm::ConstantInt::get(*type, 0)};
        if (llvmType->isFloatingPointTy())
            return Address{type, llvm::ConstantFP::get(*type, 0.0f)};
        if (llvmType->isPointerTy())
            return Address{type, llvm::ConstantPointerNull::get(cast<llvm::PointerType>(llvmType))};
        throw InternalCompilerError("No known default value for type {0}", Types::toString(type));
    }

} // namespace pepper
