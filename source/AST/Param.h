
#pragma once

#include <utility>

#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/Vector.h"

namespace pepper::ast {
    class Expression;

    struct Param {
        Ident Type;
        Ident Name;
        Ref<Expression> Default;

        Param(Ident identifier, Ident type, Ref<Expression> defaultValue = nullptr)
            : Name(std::move(identifier))
            , Type(std::move(type))
            , Default(std::move(defaultValue)) {
        }

        Param(const Param& rhs) {
            Type = rhs.Type;
            Name = rhs.Name;
            Default = rhs.Default;
        }
    };

    using Params = Vector<Param>;
} // namespace pepper::ast
