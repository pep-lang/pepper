

#pragma once

#include "CodeGen/DebugInfo.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "Sema/SemaContext.h"
#include "llvm/Support/Error.h"

namespace llvm {
    class LLVMContext;
    class Module;
    class TargetMachine;
} // namespace llvm

namespace pepper {

    class CodeGenModule {
        Ident ModuleName;
        SemaContext& Context;
        std::unique_ptr<llvm::Module> Module;
        std::unique_ptr<llvm::TargetMachine> TM;
        std::unique_ptr<DebugInfo> Debug;

      public:
        CodeGenModule(SemaContext& context, const Ident& name, const std::string& sourcePath = "");

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
            return Context.getContext();
        }

        DebugInfo* getDebugInfo() const {
            return Debug.get();
        }

        void initTargetMachine(const std::string& triple);

        llvm::Error verify();

        std::string toString() const;

      private:
        void finalizeDebugInfo();
    };
} // namespace pepper
