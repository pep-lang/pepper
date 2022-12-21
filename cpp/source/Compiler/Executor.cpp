
#include "Compiler/Executor.h"

#include "Compiler/Exceptions.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ExecutionEngine/JITSymbol.h"
#include "llvm/ExecutionEngine/Orc/CompileUtils.h"
#include "llvm/ExecutionEngine/Orc/Core.h"
#include "llvm/ExecutionEngine/Orc/ExecutionUtils.h"
#include "llvm/ExecutionEngine/Orc/ExecutorProcessControl.h"
#include "llvm/ExecutionEngine/Orc/IRCompileLayer.h"
#include "llvm/ExecutionEngine/Orc/JITTargetMachineBuilder.h"
#include "llvm/ExecutionEngine/Orc/RTDyldObjectLinkingLayer.h"
#include "llvm/ExecutionEngine/SectionMemoryManager.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"

namespace pepper {
    using namespace llvm;
    using namespace llvm::orc;

    static ExitOnError HandleError;

    class OrcExecutor : public Executor {
      private:
        Ref<ExecutionSession> ES;

        DataLayout DL;
        MangleAndInterner Mangle;

        RTDyldObjectLinkingLayer ObjectLayer;
        IRCompileLayer CompileLayer;

        JITDylib& Dylib;

        ThreadSafeModule Module;

      public:
        OrcExecutor(Ref<ExecutionSession> ES, JITTargetMachineBuilder JTMB, DataLayout DL)
            : ES(std::move(ES))
            , DL(std::move(DL))
            , Mangle(*this->ES, this->DL)
            , ObjectLayer(*this->ES, []() { return std::make_unique<SectionMemoryManager>(); })
            , CompileLayer(*this->ES, ObjectLayer, std::make_unique<ConcurrentIRCompiler>(std::move(JTMB)))
            , Dylib(this->ES->createBareJITDylib("<main>")) {
            Dylib.addGenerator(cantFail(DynamicLibrarySearchGenerator::GetForCurrentProcess(DL.getGlobalPrefix())));
            if (JTMB.getTargetTriple().isOSBinFormatCOFF()) {
                ObjectLayer.setOverrideObjectFlagsWithResponsibilityFlags(true);
                ObjectLayer.setAutoClaimResponsibilityForObjectSymbols(true);
            }
        }

        ~OrcExecutor() {
            if (auto Err = ES->endSession())
                ES->reportError(std::move(Err));
        }

        static Ref<OrcExecutor> Create() {
            auto EPC = HandleError(SelfExecutorProcessControl::Create());
            auto ES = Ref<ExecutionSession>::create(std::move(EPC));

            JITTargetMachineBuilder JTMB(ES->getExecutorProcessControl().getTargetTriple());
            auto DL = HandleError(JTMB.getDefaultDataLayoutForTarget());

            return Ref<OrcExecutor>::create(std::move(ES), std::move(JTMB), std::move(DL));
        }

        const DataLayout& getDataLayout() const {
            return DL;
        }

        JITDylib& getMainJITDylib() {
            return Dylib;
        }

        Error addModule(ThreadSafeModule TSM, ResourceTrackerSP RT = nullptr) {
            if (!RT)
                RT = Dylib.getDefaultResourceTracker();
            return CompileLayer.add(RT, std::move(TSM));
        }

        Expected<JITEvaluatedSymbol> lookup(StringRef Name) {
            return ES->lookup({&Dylib}, Mangle(Name.str()));
        }

        llvm::Module* createModule(const std::string& name) {
            auto context = std::make_unique<llvm::LLVMContext>();
            auto module = std::make_unique<llvm::Module>(name, *context);
            module->setDataLayout(getDataLayout());
            auto result = module.get();
            HandleError(addModule(std::move(ThreadSafeModule(std::move(module), std::move(context)))));
            return result;
        }

        int Execute(const std::string& entry) {
            auto entryFn = lookup(entry);
            int (*fn)() = (int (*)())(intptr_t)entryFn->getAddress();
            return fn();
        }
    };

    Ref<Executor> Executor::Create() {
        return OrcExecutor::Create();
    }
} // namespace pepper
