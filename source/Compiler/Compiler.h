
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
    class Runtime;

    class Compiler {
      public:
        static Ref<Compiler> Create(const std::string& moduleName, const std::string& sourceFilePath);

        virtual Ref<ModuleContext> compile(const std::string& sourceFile) = 0;
        virtual Ref<ModuleContext> compile(std::istream& sourceStream) = 0;
    };
} // namespace pepper
