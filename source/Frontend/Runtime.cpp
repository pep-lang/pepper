//
// Created by Justin Boswell on 12/21/22.
//

#include "Frontend/Runtime.h"

#include "Frontend/Function.h"
#include "Frontend/ModuleContext.h"
#include "Frontend/Param.h"
#include "Frontend/Symbols.h"
#include "Frontend/Types.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Type.h"

namespace pepper {
    Runtime::Runtime()
        : Scope("Runtime") {
        Functions["puts"] = Ref<Function>::New("puts", Types::Int32, Params{{"str", Types::get("char*")}});
        Functions["print"] = Functions["puts"];
        Functions["malloc"] = Ref<Function>::New("malloc", Types::VoidPtr, Params{{"size", Types::UInt64}});
        Functions["free"] = Ref<Function>::New("free", Types::Void, Params{{"ptr", Types::VoidPtr}});
        Functions["debug_ptr"] = Ref<Function>::New(
            "debug_ptr", Types::Void, Params{{"ptr", Types::VoidPtr}, {"name", Types::Int8->pointer()}});
        Functions["test_assert"] = Ref<Function>::New(
            "test_assert", Types::Void, Params{{"condition", Types::Bool}, {"message", Types::UInt8->pointer()}});
    }
} // namespace pepper
