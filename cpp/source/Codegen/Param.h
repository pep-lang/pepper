
#pragma once

#include "Core/Name.h"
#include "Core/Vector.h"

namespace llvm {
    class Type;
    class Value;
} // namespace llvm

namespace pepper {
    class Type;

    struct Param {
        Ref<Type> ParamType;
        Name ParamName;
        llvm::Value* Default;

        Param(const Name& name, Ref<Type> type, llvm::Value* defaultValue = nullptr)
            : ParamName(name)
            , ParamType(type)
            , Default(defaultValue) {
        }
    };

    using Params = Vector<Param>;
} // namespace pepper
