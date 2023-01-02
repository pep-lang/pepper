#pragma once

#include <string>

#include "Core/Common.h"

namespace pepper {
    class ModuleContext;
    class Runtime;

    class Executor {
      protected:
        Executor() = default;

      public:
        static Ref<Executor> Create();

        virtual ~Executor() = default;
        
        // Run a function in the module. Note that the JIT will take ownership of the module
        // so it is dead after this function is called
        virtual int execute(Ref<ModuleContext> context, const std::string& entry = "main") = 0;
        // virtual int Interpret(llvm::Module* module, const std::string& entry = "main") = 0;
    };
} // namespace pepper
