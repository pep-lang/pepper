//
// Created by Justin Boswell on 12/23/22.
//

#include <memory>

#include "CodeGenModule.h"
#include "Core/Exceptions.h"
#include "Frontend/Scope.h"
#include "Frontend/Symbols.h"
#include "llvm/ExecutionEngine/Orc/ExecutionUtils.h"
#include "llvm/ExecutionEngine/Orc/ExecutorProcessControl.h"
#include "llvm/ExecutionEngine/Orc/JITTargetMachineBuilder.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Verifier.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Host.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"

namespace pepper {
    CodeGenModule::CodeGenModule(PepContext& context, const Ident& name, const std::string& sourcePath)
        : ModuleName(name)
        , Context(context) {
        Module = std::make_unique<llvm::Module>(name, Context.getContext());
        Debug = std::make_unique<DebugInfo>(Module.get(), sourcePath);

        auto targetTriple = llvm::sys::getDefaultTargetTriple();
        initTargetMachine(targetTriple);

        Module->setSourceFileName(sourcePath);
        Module->addModuleFlag(llvm::Module::Warning, "Debug Info Version", llvm::DEBUG_METADATA_VERSION);
        Module->addModuleFlag(llvm::Module::Warning, "DWARF Version", llvm::dwarf::DWARF_VERSION);
        Module->setTargetTriple(targetTriple);
        Module->setDataLayout(TM->createDataLayout());
    }

    CodeGenModule::~CodeGenModule() {
        finalizeDebugInfo();
    }

    void CodeGenModule::finalizeDebugInfo() {
        if (Debug) {
            Debug->finalize();
            Debug.reset();
        }
    }

    void CodeGenModule::initTargetMachine(const std::string& triple) {
        // Create `Target`
        std::string error;
        const llvm::Target* target = llvm::TargetRegistry::lookupTarget(triple, error);
        assert(target && "Failed to create Target");

        // Create `TargetMachine`
        llvm::CodeGenOpt::Level OptLevel = llvm::CodeGenOpt::Level::None;
        TM.reset(target->createTargetMachine(triple,
                                             /*CPU=*/"",
                                             /*Features=*/"",
                                             llvm::TargetOptions(),
                                             /*Reloc::Model=*/llvm::None,
                                             /*CodeModel::Model=*/llvm::None,
                                             OptLevel));
        assert(TM && "Failed to create TargetMachine");
    }

    std::unique_ptr<llvm::LLVMContext>&& CodeGenModule::takeContext() {
        finalizeDebugInfo();
        return std::move(Context.takeContext());
    }

    std::unique_ptr<llvm::Module>&& CodeGenModule::takeModule() {
        finalizeDebugInfo();
        return std::move(Module);
    }

    llvm::Error CodeGenModule::verify() {
        finalizeDebugInfo();

        std::string verifyOutput;
        llvm::raw_string_ostream vout(verifyOutput);
        bool debugInfoBroken = false;
        if (llvm::verifyModule(*Module, &vout, &debugInfoBroken)) {
            return llvm::createStringError(std::error_code(), verifyOutput);
        }
        return llvm::Error::success();
    }

    std::string CodeGenModule::toString() const {
        std::string ir;
        llvm::raw_string_ostream stream(ir);
        Module->print(stream, nullptr, false, true);
        return ir;
    }
} // namespace pepper
