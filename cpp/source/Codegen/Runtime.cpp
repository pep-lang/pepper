//
// Created by Justin Boswell on 12/21/22.
//

#include "Codegen/Runtime.h"

#include "Codegen/Function.h"
#include "Compiler/Type.h"

namespace pepper {
    using Params = Function::Params;
    using Param = Function::Param;

    Runtime::Runtime()
        : Scope("Runtime") {
        Functions["puts"] = Ref<Function>::create("puts", *Types::Int32, Params{{"str", *Types::Int8->pointer()}});
        Functions["print"] = Functions["puts"];
        Functions["malloc"] =
            Ref<Function>::create("malloc", *Types::Void->pointer(), Params{{"size", *Types::UInt64}});
        Functions["free"] = Ref<Function>::create("free", *Types::Void, Params{{"ptr", *Types::Void->pointer()}});
    }
} // namespace pepper
