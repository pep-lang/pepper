
#include "JIT/Executor.h"

#include "CodeGen/CodeGenModule.h"
#include "Core/Exceptions.h"
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
#include "llvm/Support/Host.h"

namespace pepper {
    using namespace llvm;
    using namespace llvm::orc;

    class OrcExecutor : public Executor {
      private:
        Ref<ExecutionSession> ES;

        DataLayout DL;
        const bool IsCOFF;
        MangleAndInterner Mangle;

        RTDyldObjectLinkingLayer ObjectLayer;
        IRCompileLayer CompileLayer;

        JITDylib& Dylib;

        ThreadSafeModule Module;

      public:
        OrcExecutor(Ref<ExecutionSession> ES, JITTargetMachineBuilder JTMB, const DataLayout& layout)
            : ES(std::move(ES))
            , DL(layout)
            , IsCOFF(JTMB.getTargetTriple().isOSBinFormatCOFF())
            , Mangle(*this->ES, this->DL)
            , ObjectLayer(*this->ES, []() { return std::make_unique<SectionMemoryManager>(); })
            , CompileLayer(*this->ES, ObjectLayer, std::make_unique<ConcurrentIRCompiler>(std::move(JTMB)))
            , Dylib(this->ES->createBareJITDylib("<main>")) {
            // https://llvm.org/docs/ORCv2.html#how-to-add-process-and-library-symbols-to-jitdylibs
            Dylib.addGenerator(cantFail(DynamicLibrarySearchGenerator::GetForCurrentProcess(DL.getGlobalPrefix())));
            if (IsCOFF) {
                ObjectLayer.setOverrideObjectFlagsWithResponsibilityFlags(true);
                ObjectLayer.setAutoClaimResponsibilityForObjectSymbols(true);
            }
        }

        ~OrcExecutor() {
            if (auto Err = ES->endSession())
                ES->reportError(std::move(Err));
        }

        static Ref<OrcExecutor> Create() {
            auto EPC = SelfExecutorProcessControl::Create();
            if (!EPC) {
                throw InternalCompilerError("Failed to initialize process control: {}",
                                            llvm::toString(EPC.takeError()));
            }
            auto ES = Ref<ExecutionSession>::New(std::move(EPC.get()));

            JITTargetMachineBuilder JTMB(ES->getExecutorProcessControl().getTargetTriple());
            auto DL = JTMB.getDefaultDataLayoutForTarget();
            if (!DL) {
                throw InternalCompilerError("Unable to get default layout for target: {}",
                                            llvm::toString(DL.takeError()));
            }

            return Ref<OrcExecutor>::New(std::move(ES), std::move(JTMB), std::move(DL.get()));
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

        auto lookup(StringRef Name) {
            return ES->lookup({&Dylib}, Mangle(Name.str()));
        }

        int execute(Ref<CodeGenModule> context, const std::string& entry) override {
            if (auto err = addModule(
                    std::move(ThreadSafeModule(std::move(context->takeModule()), std::move(context->takeContext()))))) {
                throw InternalCompilerError("Unable to initialize module: {0}", llvm::toString(std::move(err)));
            }
            // reset the context, since its contents have been stolen
            context.reset();

            auto entryFn = lookup(entry);
            if (auto err = entryFn.takeError()) {
                throw InternalCompilerError("Unable to resolve JIT entry function: {0}",
                                            llvm::toString(std::move(err)));
            }

            auto fn = entryFn->getAddress().toPtr<int()>();
            return fn();
        }
    };

    Ref<Executor> Executor::Create() {
        return OrcExecutor::Create();
    }
} // namespace pepper
