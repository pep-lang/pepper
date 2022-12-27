
#pragma once

#include <memory>
#include <string>

#include "Core/Common.h"
#include "llvm/Support/FormatVariadic.h"

namespace llvm {
    class Module;
}

namespace pepper {
    class ModuleContext;

    class Compiler {
      protected:
        std::string ModuleName;
        std::string SourcePath;

      public:
        static Ref<Compiler> Create(const std::string& moduleName);

        virtual Ref<ModuleContext> compile(const std::string& sourceFile) = 0;
        virtual Ref<ModuleContext> compile(std::istream& sourceStream, const std::string& sourceFile = "<stream>") = 0;
    };
} // namespace pepper
