
#pragma once

#include "CodeGen/Value.h"
#include "Core/Ident.h"
#include "Core/Vector.h"

namespace pepper {
    class Type;

    struct Param {
        Ref<Type> Type;
        Ident Name;
        Value Default;

        Param(const Ident& name, Ref<pepper::Type> type, Value defaultValue = {})
            : Name(name)
            , Type(type)
            , Default(defaultValue) {
        }
    };

    using Params = Vector<Param>;
} // namespace pepper
