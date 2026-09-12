
#pragma once

#include <memory>
#include <string>

#include "CodeGen/LLVM/LLVMModuleGenerator.h"
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

        virtual void compile() = 0;
        virtual void link() = 0;

        virtual Vector<std::string> get_object_file_paths() const = 0;
    };
} // namespace pepper
