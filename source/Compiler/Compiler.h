
#pragma once

#include <memory>
#include <string>

#include "Core/Common.h"
#include "Core/Vector.h"
#include "llvm/Support/FormatVariadic.h"

namespace llvm {
    class Module;
}

namespace pepper {
    class ModuleContext;
    class Options;

    class Compiler {
      public:
        static Ref<Compiler> Create(Ref<Options> options);

        virtual Vector<Ref<ModuleContext>> compile() = 0;
    };
} // namespace pepper
