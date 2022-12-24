
#pragma once

#include "Core/Common.h"
#include "Core/Name.h"
#include "llvm/ADT/SmallVector.h"

namespace pepper::ast {
    class Expression;

    struct Param {
        Name Type;
        Name Identifier;
        Ref<Expression> Default;

        Param(const Name& identifier, const Name& type, Ref<Expression> defaultValue = nullptr)
            : Identifier(identifier)
            , Type(type)
            , Default(defaultValue) {
        }

        Param(const Param& rhs) {
            Type = rhs.Type;
            Identifier = rhs.Identifier;
            Default = rhs.Default;
        }
    };

    using Params = llvm::SmallVector<Param>;
} // namespace pepper::ast
