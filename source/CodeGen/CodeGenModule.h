//
// Created by Justin Boswell on 12/23/22.
//

#pragma once

#include "CodeGen/DebugInfo.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "llvm/Support/Error.h"

namespace llvm {
    class LLVMContext;
    class Module;
} // namespace llvm

namespace pepper {

    class CodeGenModule {
        Ident ModuleName;
        std::unique_ptr<llvm::LLVMContext> Context;
        std::unique_ptr<llvm::Module> Module;
        std::unique_ptr<DebugInfo> Debug;

      public:
        CodeGenModule(const Ident& name, const std::string& sourcePath);
        CodeGenModule(std::unique_ptr<llvm::LLVMContext> context, std::unique_ptr<llvm::Module> module);

        ~CodeGenModule();

        std::unique_ptr<llvm::LLVMContext>&& takeContext();
        std::unique_ptr<llvm::Module>&& takeModule();

        operator llvm::Module*() const {
            return Module.get();
        }

        llvm::Module& getModule() const {
            return *Module.get();
        }

        llvm::LLVMContext& getContext() const {
            return *Context.get();
        }

        DebugInfo* getDebugInfo() const {
            return Debug.get();
        }

        llvm::Error verify();

        std::string toString() const;

      private:
        void finalizeDebugInfo();
    };
} // namespace pepper
