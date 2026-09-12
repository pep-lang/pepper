
#pragma once

#include <utility>

#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/Vector.h"

namespace pepper::sema {
    class Expression;

    struct Param {
        TypeName type;
        Ident name;
        TNodeRef<Expression> default_value = nullptr;

        Param(Ident identifier, TypeName type, Expression* def_value = nullptr)
            : name(std::move(identifier))
            , type(std::move(type))
            , default_value(def_value) {}

        Param(const Param& rhs) = default;
        Param(Param&& rhs) = default;
        Param& operator=(const Param& rhs) = default;
    };

    using Params = Vector<Param>;
} // namespace pepper::sema
