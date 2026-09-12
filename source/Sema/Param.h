
#pragma once

#include "CodeGen/LLVM/Address.h"
#include "Core/Ident.h"
#include "Core/Vector.h"

namespace pepper {
    class Type;

    struct Param {
        Ref<Type> type;
        Ident name;
        Address initializer;

        Param(const Ident& name, Ref<pepper::Type> type, Address init = {})
            : name(name)
            , type(type)
            , initializer(init) {}
    };

    using Params = Vector<Param>;
} // namespace pepper
