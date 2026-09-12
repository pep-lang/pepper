

#pragma once

#include "CodeGen/LLVM/DebugInfo.h"
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

    class LLVMModuleGenerator {
        Ident module_name;
        SemaContext& sema_ctx;
        std::unique_ptr<llvm::Module> llvm_module;
        std::unique_ptr<llvm::TargetMachine> target_machine;
        std::unique_ptr<DebugInfo> debug_info;

      public:
        LLVMModuleGenerator(SemaContext& context, const Ident& name, const std::string& sourcePath = "");

        ~LLVMModuleGenerator();

        std::unique_ptr<llvm::LLVMContext>&& take_llvm_context();
        std::unique_ptr<llvm::Module>&& take_llvm_module();

        operator llvm::Module*() const {
            return llvm_module.get();
        }

        llvm::Module& get_llvm_module() const {
            return *llvm_module.get();
        }

        llvm::LLVMContext& get_llvm_context() const {
            return sema_ctx.get_llvm_context();
        }

        DebugInfo* get_debug_info() const {
            return debug_info.get();
        }

        void init_target_machine(const std::string& triple);

        llvm::Error verify();

        std::string to_string() const;

      private:
        void finalize_debug_info();
    };
} // namespace pepper
