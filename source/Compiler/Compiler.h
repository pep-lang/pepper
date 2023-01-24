
#pragma once

#include <memory>
#include <string>

#include "CodeGen/CodeGenModule.h"
#include "Compiler/Options.h"
#include "Core/Common.h"
#include "Core/Vector.h"
#include "llvm/Support/FormatVariadic.h"

namespace llvm {
    class Module;
}

namespace pepper {
    class Compiler {
      public:
        static Ref<Compiler> Create(Ref<Options> options);
        
        virtual Ref<CodeGenModule> compile() = 0;
        virtual void link() = 0;
    };
} // namespace pepper
