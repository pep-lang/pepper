
#pragma once

#include "Codegen/IR/Value.h"
#include "Core/Ident.h"
#include "Core/Vector.h"

namespace pepper {
    class TypeInfo;

    struct Param {
        Ref<TypeInfo> ParamType;
        Ident ParamName;
        Value Default;

        Param(const Ident& name, Ref<TypeInfo> type, Value defaultValue = {})
            : ParamName(name)
            , ParamType(type)
            , Default(defaultValue) {
        }
    };

    using Params = Vector<Param>;
} // namespace pepper
