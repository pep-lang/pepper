//
// Created by Justin Boswell on 12/27/22.
//

#pragma once

#include "Core/Ident.h"
#include "Frontend/Types.h"
#include "llvm/IR/Value.h"

namespace pepper {
    struct Value {
        Ident Name;
        llvm::Value* V;
        Ref<Type> Ty;

        Value(Ref<Type> type = nullptr, llvm::Value* value = nullptr, const Ident& identifier = "")
            : Name(identifier)
            , Ty(type)
            , V(value) {
        }

        operator llvm::Value*() const {
            return V;
        }

        explicit operator bool() const {
            return V;
        }

        llvm::Value* operator->() {
            return V;
        }

        static const Value& Null() {
            static Value nullValue;
            return nullValue;
        };
    };
} // namespace pepper
