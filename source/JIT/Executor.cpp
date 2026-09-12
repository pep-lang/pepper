
#include "JIT/Executor.h"

#include "CodeGen/LLVM/LLVMModuleGenerator.h"
#include "Core/Exceptions.h"
#include "Core/Vector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ExecutionEngine/Orc/CompileUtils.h"
#include "llvm/ExecutionEngine/Orc/Core.h"
#include "llvm/ExecutionEngine/Orc/ExecutionUtils.h"
#include "llvm/ExecutionEngine/Orc/ExecutorProcessControl.h"
#include "llvm/ExecutionEngine/Orc/IRCompileLayer.h"
#include "llvm/ExecutionEngine/Orc/JITTargetMachineBuilder.h"
#include "llvm/ExecutionEngine/Orc/RTDyldObjectLinkingLayer.h"
#include "llvm/ExecutionEngine/SectionMemoryManager.h"
#include "llvm/IR/DataLayout.h"

namespace pepper {
    using namespace llvm;
    using namespace llvm::orc;

    class OrcExecutor : public Executor {
      private:
        Ref<ExecutionSession> session;

        DataLayout data_layout;
        const bool is_coff;
        MangleAndInterner mangler;

        RTDyldObjectLinkingLayer object_layer;
        IRCompileLayer compile_layer;

        JITDylib& jit_dylib;

        ThreadSafeModule module;

      public:
        OrcExecutor(Ref<ExecutionSession> es, JITTargetMachineBuilder jtmb, const DataLayout& layout)
            : session(std::move(es))
            , data_layout(layout)
            , is_coff(jtmb.getTargetTriple().isOSBinFormatCOFF())
            , mangler(*this->session, this->data_layout)
            , object_layer(*this->session, []() { return std::make_unique<SectionMemoryManager>(); })
            , compile_layer(*this->session, object_layer, std::make_unique<ConcurrentIRCompiler>(std::move(jtmb)))
            , jit_dylib(this->session->createBareJITDylib("<main>")) {
            // https://llvm.org/docs/ORCv2.html#how-to-add-process-and-library-symbols-to-jitdylibs
            jit_dylib.addGenerator(
                cantFail(DynamicLibrarySearchGenerator::GetForCurrentProcess(data_layout.getGlobalPrefix())));
            if (is_coff) {
                object_layer.setOverrideObjectFlagsWithResponsibilityFlags(true);
                object_layer.setAutoClaimResponsibilityForObjectSymbols(true);
            }
        }

        ~OrcExecutor() override {
            if (auto err = session->endSession())
                session->reportError(std::move(err));
        }

        static Ref<OrcExecutor> create() {
            auto epc = SelfExecutorProcessControl::Create();
            if (!epc) {
                throw InternalCompilerError("Failed to initialize process control: {}",
                                            llvm::toString(epc.takeError()));
            }
            auto es = Ref<ExecutionSession>::create(std::move(epc.get()));

            JITTargetMachineBuilder jtmb(es->getExecutorProcessControl().getTargetTriple());
            auto layout = jtmb.getDefaultDataLayoutForTarget();
            if (!layout) {
                throw InternalCompilerError("Unable to get default layout for target: {}",
                                            llvm::toString(layout.takeError()));
            }

            return Ref<OrcExecutor>::create(std::move(es), std::move(jtmb), std::move(layout.get()));
        }

        const DataLayout& get_data_layout() const {
            return data_layout;
        }

        JITDylib& get_main_dylib() {
            return jit_dylib;
        }

        Error add_module(ThreadSafeModule tsm, ResourceTrackerSP rt = nullptr) {
            if (!rt)
                rt = jit_dylib.getDefaultResourceTracker();
            return compile_layer.add(rt, std::move(tsm));
        }

        auto lookup(StringRef name) {
            return session->lookup({&jit_dylib}, mangler(name));
        }

        void prepare(const Vector<std::string>& obj_files) override {
            for (const auto& obj_file_path : obj_files) {
                auto buffer = MemoryBuffer::getFile(obj_file_path);
                if (!buffer) {
                    throw InternalCompilerError("Unable to load obj file: {0}", obj_file_path);
                }
                auto error = object_layer.add(jit_dylib.getDefaultResourceTracker(), std::move(*buffer));
                if (error) {
                    throw InternalCompilerError("Unable to import object {0}: {1}", obj_file_path, error);
                }
            }
        }

        // void prepare(Ref<LLVMModuleGenerator> context) override {
        //     if (auto err = add_module(std::move(ThreadSafeModule(std::move(context->take_llvm_module()),
        //                                                          std::move(context->take_llvm_context()))))) {
        //         throw InternalCompilerError("Unable to initialize module: {0}", toString(std::move(err)));
        //     }
        //     // reset the context, since its contents have been stolen
        //     context.reset();
        // }
        //
        // std::any execute(Ref<LLVMModuleGenerator> context, const std::string& entry) override {
        //     prepare(context);
        //     return execute_entry<int>(entry);
        // }

        std::any execute(const Vector<std::string>& obj_files, const std::string& entry) override {
            prepare(obj_files);
            return Executor::invoke<int>(entry);
        }

        void execute_entry(const std::string& entry, std::function<void(const ExecutorAddr&)>&& exec) override {
            auto entryFn = lookup(entry);
            if (auto err = entryFn.takeError()) {
                throw InternalCompilerError("Unable to resolve JIT entry function: {0}", toString(std::move(err)));
            }

            exec(entryFn->getAddress());
        }
    };

    Ref<Executor> Executor::create() {
        return OrcExecutor::create();
    }
} // namespace pepper
