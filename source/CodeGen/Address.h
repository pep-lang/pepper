//
// Created by Justin Boswell on 12/27/22.
//

#pragma once

#include "Core/Ident.h"
#include "Frontend/Types.h"
#include "llvm/IR/Value.h"

namespace pepper {
    struct Address {
        Ident Name;
        llvm::Value* Value;
        Ref<Type> Ty;

        Address(Ref<Type> type = nullptr, llvm::Value* value = nullptr, const Ident& identifier = "")
            : Name(identifier)
            , Ty(type)
            , Value(value) {
        }

        operator llvm::Value*() const {
            return Value;
        }

        explicit operator bool() const {
            return Value;
        }

        llvm::Value* operator->() {
            return Value;
        }

        static const Address& Null() {
            static Address nullValue;
            return nullValue;
        };
    };
} // namespace pepper
