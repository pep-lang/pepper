#pragma once

#include "Core/Common.h"
#include <string>

namespace llvm {
    class LLVMContext;
    class Module;
} // namespace llvm

namespace pepper {
    class Executor {
      protected:
        Executor() = default;

      public:
        static Ref<Executor> Create();

        virtual ~Executor() = default;

        virtual void configureModule(llvm::Module* module) = 0;

        // Run a function in the module. Note that the JIT will take ownership of the module
        // so it is dead after this function is called
        virtual int execute(std::unique_ptr<llvm::LLVMContext> context,
                            std::unique_ptr<llvm::Module> module,
                            const std::string& entry = "main") = 0;
        // virtual int Interpret(llvm::Module* module, const std::string& entry = "main") = 0;
    };
} // namespace pepper
