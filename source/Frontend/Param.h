
#pragma once

#include "CodeGen/Value.h"
#include "Core/Ident.h"
#include "Core/Vector.h"

namespace pepper {
    class Type;

    struct Param {
        Ref<Type> ParamType;
        Ident ParamName;
        Value Default;

        Param(const Ident& name, Ref<Type> type, Value defaultValue = {})
            : ParamName(name)
            , ParamType(type)
            , Default(defaultValue) {
        }
    };

    using Params = Vector<Param>;
} // namespace pepper
