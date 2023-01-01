//
// Created by Justin Boswell on 12/23/22.
//

#pragma once

#include "Core/Common.h"
#include "Core/Ident.h"
#include "llvm/Support/Error.h"

namespace llvm {
    class LLVMContext;
    class Module;
} // namespace llvm

namespace pepper {
    class ModuleContext {
        Ident ModuleName;
        std::unique_ptr<llvm::LLVMContext> Context;
        std::unique_ptr<llvm::Module> Module;

      public:
        ModuleContext(const Ident& name);

        std::unique_ptr<llvm::LLVMContext>&& takeContext();
        std::unique_ptr<llvm::Module>&& takeModule();

        operator llvm::Module*() const {
            return Module.get();
        }

        llvm::LLVMContext* getContext() const {
            return Context.get();
        }

        llvm::Error verify() const;

        std::string toString() const;
    };
} // namespace pepper
