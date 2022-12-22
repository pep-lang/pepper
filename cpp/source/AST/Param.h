
#pragma once

#include "llvm/ADT/SmallVector.h"
#include <string>

namespace llvm {
    class Type;
}

namespace pepper::ast {
    struct Param {
        llvm::Type* Type;
        const std::string Name;
        llvm::Value* Default;

        Param(std::string name, llvm::Type* type, llvm::Value* defaultValue = nullptr)
            : Name(std::move(name))
            , Type(type)
            , Default(defaultValue) {
        }
    };

    using Params = llvm::SmallVector<Param>;
} // namespace pepper::ast
