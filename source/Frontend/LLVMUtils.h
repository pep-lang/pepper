//
// Created by Justin Boswell on 12/26/22.
//

#pragma once

#include <string>

#include "Core/Exceptions.h"
#include "Core/String.h"
#include "Frontend/Context.h"
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
        return Context::get().locals()->builder();
    }

    inline llvm::Type* resolveType(Value value) {
        if (llvm::isa<llvm::AllocaInst>(*value.V)) {
            auto allocaInst = llvm::cast<llvm::AllocaInst>(value.V);
            return allocaInst->getAllocatedType();
        }
        if (llvm::isa<llvm::GetElementPtrInst>(*value.V)) {
            auto gepInst = llvm::cast<llvm::GetElementPtrInst>(value.V);
            return gepInst->getResultElementType();
        }
        return value->getType();
    }

    inline Value load(Value value) {
        if (llvm::isa<llvm::AllocaInst>(*value.V)) {
            auto type = resolveType(value);
            return Value{value.Ty, ir()->CreateLoad(type, value)};
        }
        if (llvm::isa<llvm::GetElementPtrInst>(*value.V)) {
            auto type = resolveType(value);
            // This may be a pointer to a pointer to a struct (e.g. a struct reference), so an additional
            // read pass is necessary here
            return Value{value.Ty, ir()->CreateLoad(type, value)};
        }
        return value;
    }

    inline Value read(Value value) {
        value = load(value);
        if (value.Ty->isPointer()) {
            auto type = value.Ty.as<PointerType>();
            auto pointee = type->pointeeType();
            if (pointee->isStruct()) {
                return Value{pointee, ir()->CreateLoad(*type, value)};
            }
        }
        return value;
    }

    inline Value zeroValue(Ref<Type> type) {
        if (type->llvmType()->isIntegerTy())
            return Value{type, llvm::ConstantInt::get(*type, 0)};
        if (type->llvmType()->isFloatingPointTy())
            return Value{type, llvm::ConstantFP::get(*type, 0.0f)};
        if (type->llvmType()->isPointerTy())
            return Value{type, llvm::ConstantPointerNull::get(cast<llvm::PointerType>(type->llvmType()))};
        throw InternalCompilerError("No known default value for type {0}", Types::toString(type));
    }

} // namespace pepper
