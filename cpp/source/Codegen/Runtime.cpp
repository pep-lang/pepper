//
// Created by Justin Boswell on 12/21/22.
//

#include "Codegen/Runtime.h"

#include "Codegen/Function.h"
#include "Compiler/Param.h"
#include "Compiler/Type.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Type.h"

namespace pepper {
    Runtime::Runtime()
        : Scope("Runtime") {
        Functions["puts"] = Ref<Function>::New("puts", Types::Int32, Params{{"str", Types::Int8->getPointerTo(0)}});
        Functions["print"] = Functions["puts"];
        Functions["malloc"] =
            Ref<Function>::New("malloc", Types::Void->getPointerTo(0), Params{{"size", Types::UInt64}});
        Functions["free"] = Ref<Function>::New("free", Types::Void, Params{{"ptr", Types::Void->getPointerTo(0)}});
    }
} // namespace pepper
