//
// Created by Justin Boswell on 12/21/22.
//

#include "Codegen/Runtime.h"

#include "Codegen/Function.h"
#include "Codegen/ModuleContext.h"
#include "Codegen/Param.h"
#include "Codegen/Symbols.h"
#include "Codegen/Types.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Type.h"

namespace pepper {
    Runtime::Runtime()
        : Scope("Runtime") {
        Functions["puts"] = Ref<Function>::New("puts", Types::Int32, Params{{"str", Types::get("char*")}});
        Functions["print"] = Functions["puts"];
        Functions["malloc"] = Ref<Function>::New("malloc", Types::VoidPtr, Params{{"size", Types::UInt64}});
        Functions["free"] = Ref<Function>::New("free", Types::Void, Params{{"ptr", Types::VoidPtr}});
    }
} // namespace pepper
