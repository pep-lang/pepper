
#pragma once

#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/Vector.h"

namespace pepper::ast {
    class Expression;

    struct Param {
        Ident Type;
        Ident Identifier;
        Ref<Expression> Default;

        Param(const Ident& identifier, const Ident& type, Ref<Expression> defaultValue = nullptr)
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

    using Params = Vector<Param>;
} // namespace pepper::ast
