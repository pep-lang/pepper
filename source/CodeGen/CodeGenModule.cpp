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
#include "llvm/Support/Host.h"
#include "llvm/Support/raw_ostream.h"

namespace pepper {
    static llvm::DataLayout getDataLayout() {
        auto EPC = llvm::orc::SelfExecutorProcessControl::Create();
        if (!EPC) {
            throw InternalCompilerError("Failed to initialize process control: {}", llvm::toString(EPC.takeError()));
        }
        auto ES = Ref<llvm::orc::ExecutionSession>::New(std::move(EPC.get()));

        llvm::orc::JITTargetMachineBuilder JTMB(ES->getExecutorProcessControl().getTargetTriple());
        auto DL = JTMB.getDefaultDataLayoutForTarget();

        if (auto err = ES->endSession()) {
            throw InternalCompilerError("Failed to end temporary execution session: {0}",
                                        llvm::toString(std::move(err)));
        }
        if (!DL) {
            throw InternalCompilerError("Unable to get default layout for target: {0}", llvm::toString(DL.takeError()));
        }
        return DL.get();
    }

    CodeGenModule::CodeGenModule(const Ident& name, const std::string& sourcePath)
        : ModuleName(name) {
        Context = std::make_unique<llvm::LLVMContext>();
        Module = std::make_unique<llvm::Module>(name, *Context);
        Debug = std::make_unique<DebugInfo>(Module.get(), sourcePath);

        Module->setSourceFileName(sourcePath);
        Module->addModuleFlag(llvm::Module::Warning, "Debug Info Version", llvm::DEBUG_METADATA_VERSION);
        Module->addModuleFlag(llvm::Module::Warning, "DWARF Version", llvm::dwarf::DWARF_VERSION);

        auto targetTriple = llvm::sys::getDefaultTargetTriple();
        Module->setTargetTriple(targetTriple);

        Module->setDataLayout(getDataLayout());
    }

    CodeGenModule::CodeGenModule(std::unique_ptr<llvm::LLVMContext> context, std::unique_ptr<llvm::Module> module)
        : Context(std::move(context))
        , Module(std::move(module)) {
        ModuleName = Module->getModuleIdentifier();
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

    std::unique_ptr<llvm::LLVMContext>&& CodeGenModule::takeContext() {
        finalizeDebugInfo();
        return std::move(Context);
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
