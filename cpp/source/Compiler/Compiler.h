
#pragma once

#include "Core/Common.h"
#include <memory>
#include <string>

namespace llvm {
    class Module;
}

namespace pepper {
    class Context;

    class Compiler {
      public:
        static Ref<Compiler> Create(const std::string& moduleName);

        virtual Context& context() const = 0;
        virtual llvm::Module* compile(const std::string& sourceFile) = 0;
        virtual llvm::Module* compile(std::istream& sourceStream, const std::string& sourceFile = "<stream>") = 0;
    };
} // namespace pepper
