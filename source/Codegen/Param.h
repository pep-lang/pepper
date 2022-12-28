
#pragma once

#include "Codegen/IR/Value.h"
#include "Core/Name.h"
#include "Core/Vector.h"

namespace pepper {
    class TypeInfo;

    struct Param {
        Ref<TypeInfo> ParamType;
        Name ParamName;
        Value Default;

        Param(const Name& name, Ref<TypeInfo> type, Value defaultValue = {})
            : ParamName(name)
            , ParamType(type)
            , Default(defaultValue) {
        }
    };

    using Params = Vector<Param>;
} // namespace pepper
