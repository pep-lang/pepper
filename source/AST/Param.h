
#pragma once

#include <utility>

#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/Vector.h"

namespace pepper::ast {
    class Expression;

    struct Param {
        TypeName Type;
        Ident Name;
        TNodeRef<Expression> Default = nullptr;

        Param(Ident identifier, TypeName type, Expression* defaultValue = nullptr)
            : Name(std::move(identifier))
            , Type(std::move(type))
            , Default(defaultValue) {}

        Param(const Param& rhs) = default;
        Param(Param&& rhs) = default;
        Param& operator=(const Param& rhs) = default;
    };

    using Params = Vector<Param>;
} // namespace pepper::ast
