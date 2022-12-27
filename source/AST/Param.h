
#pragma once

#include "Core/Common.h"
#include "Core/Name.h"
#include "Core/Vector.h"

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

    using Params = Vector<Param>;
} // namespace pepper::ast
