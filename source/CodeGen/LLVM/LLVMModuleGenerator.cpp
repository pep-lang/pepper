

#include <memory>

#include "CodeGen/LLVM/LLVMModuleGenerator.h"
#include "Sema/Scope.h"
#include "llvm/ExecutionEngine/Orc/ExecutionUtils.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Verifier.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/TargetParser/Host.h"

namespace pepper {
    LLVMModuleGenerator::LLVMModuleGenerator(SemaContext& context, const Ident& name, const std::string& sourcePath)
        : module_name(name)
        , sema_ctx(context) {
        llvm_module = std::make_unique<llvm::Module>(name, sema_ctx.get_llvm_context());
        debug_info = std::make_unique<DebugInfo>(llvm_module.get(), sourcePath);

        auto targetTriple = llvm::sys::getDefaultTargetTriple();
        init_target_machine(targetTriple);

        llvm_module->setSourceFileName(sourcePath);
        llvm_module->addModuleFlag(llvm::Module::Warning, "Debug Info Version", llvm::DEBUG_METADATA_VERSION);
        llvm_module->addModuleFlag(llvm::Module::Warning, "DWARF Version", llvm::dwarf::DWARF_VERSION);
        llvm_module->setTargetTriple(targetTriple);
        llvm_module->setDataLayout(target_machine->createDataLayout());
    }

    LLVMModuleGenerator::~LLVMModuleGenerator() {
        finalize_debug_info();
    }

    void LLVMModuleGenerator::finalize_debug_info() {
        if (debug_info) {
            debug_info->finalize();
            debug_info.reset();
        }
    }

    void LLVMModuleGenerator::init_target_machine(const std::string& triple) {
        // Create `Target`
        std::string error;
        const llvm::Target* target = llvm::TargetRegistry::lookupTarget(triple, error);
        assert(target && "Failed to create Target");

        // Create `TargetMachine`
        llvm::CodeGenOpt::Level OptLevel = llvm::CodeGenOpt::Level::None;
        target_machine.reset(target->createTargetMachine(triple,
                                                         /*CPU=*/"",
                                                         /*Features=*/"",
                                                         llvm::TargetOptions(),
                                                         /*Reloc::sema=*/std::nullopt,
                                                         /*CodeModel::sema=*/std::nullopt,
                                                         OptLevel));
        assert(target_machine && "Failed to create TargetMachine");
    }

    std::unique_ptr<llvm::LLVMContext>&& LLVMModuleGenerator::take_llvm_context() {
        finalize_debug_info();
        return std::move(sema_ctx.take_llvm_context());
    }

    std::unique_ptr<llvm::Module>&& LLVMModuleGenerator::take_llvm_module() {
        finalize_debug_info();
        return std::move(llvm_module);
    }

    llvm::Error LLVMModuleGenerator::verify() {
        finalize_debug_info();

        std::string verifyOutput;
        llvm::raw_string_ostream vout(verifyOutput);
        bool debugInfoBroken = false;
        if (llvm::verifyModule(*llvm_module, &vout, &debugInfoBroken)) {
            return llvm::createStringError(std::error_code(), verifyOutput);
        }
        return llvm::Error::success();
    }

    std::string LLVMModuleGenerator::to_string() const {
        std::string ir;
        llvm::raw_string_ostream stream(ir);
        llvm_module->print(stream, nullptr, false, true);
        return ir;
    }
} // namespace pepper
