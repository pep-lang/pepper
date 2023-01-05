//
// Created by Justin Boswell on 12/27/22.
//

#pragma once

#include "Codegen/Types.h"
#include "Core/Ident.h"
#include "llvm/IR/Value.h"

namespace pepper {
    struct Value {
        Ident Identifier;
        llvm::Value* V;
        Ref<TypeInfo> Ty;

        Value(Ref<TypeInfo> type = nullptr, llvm::Value* value = nullptr, const Ident& identifier = "")
            : Identifier(identifier)
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
