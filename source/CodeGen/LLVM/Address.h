

#pragma once

#include "Core/Ident.h"
#include "Sema/Types.h"
#include "llvm/IR/Value.h"

namespace pepper {
    struct Address {
        Ident name;
        llvm::Value* value;
        Ref<Type> type;

        Address(Ref<Type> type = nullptr, llvm::Value* value = nullptr, const Ident& identifier = "")
            : name(identifier)
            , type(type)
            , value(value) {}

        operator llvm::Value*() const {
            return value;
        }

        explicit operator bool() const {
            return value;
        }

        llvm::Value* operator->() {
            return value;
        }

        static const Address& null() {
            static Address nullValue;
            return nullValue;
        };
    };
} // namespace pepper
