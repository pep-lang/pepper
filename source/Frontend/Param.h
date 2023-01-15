
#pragma once

#include "CodeGen/Address.h"
#include "Core/Ident.h"
#include "Core/Vector.h"

namespace pepper {
    class Type;

    struct Param {
        Ref<Type> Type;
        Ident Name;
        Address Default;

        Param(const Ident& name, Ref<pepper::Type> type, Address defaultValue = {})
            : Name(name)
            , Type(type)
            , Default(defaultValue) {
        }
    };

    using Params = Vector<Param>;
} // namespace pepper
