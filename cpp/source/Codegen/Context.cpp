
#include "Codegen/Context.h"
#include <cassert>

#include "AST/AST.h"
#include "Codegen/Function.h"
#include "Codegen/ModuleContext.h"
#include "Codegen/Runtime.h"
#include "Codegen/Scope.h"
#include "Codegen/Types.h"
#include "JIT/Executor.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/TargetSelect.h"

namespace pepper {
    Context* Context::Instance = nullptr;

    Context& Context::get() {
        assert(Instance);
        return *Instance;
    }

    Context::Context(const std::string& moduleName) {
        assert(Instance == nullptr);
        Instance = this;

        llvm::InitializeNativeTarget();
        llvm::InitializeNativeTargetAsmPrinter();
        llvm::InitializeNativeTargetAsmParser();

        Module = Ref<ModuleContext>::New(moduleName);

        TypeMap = Ref<Types>::New(*Module->getContext());

        Builtins = Ref<Runtime>::New();
        Globals = Ref<Scope>::New("Globals", Builtins);
        Locals = Globals;
    }

    Context::~Context() {
        Instance = nullptr;
    }

    std::unique_ptr<llvm::Module>&& Context::takeModule() {
        return std::move(Module->takeModule());
    }

    std::unique_ptr<llvm::LLVMContext>&& Context::takeContext() {
        return std::move(Module->takeContext());
    }

    void Context::pushFunction(Ref<UserFunction> function) {
        pushScope(function->name(), function->Builder);
        Locals->ReturnTarget = function;
    }

    void Context::pushScope(const std::string& name, Ref<llvm::IRBuilderBase> builder) {
        Locals = Ref<Scope>::New(name, Locals);
        Locals->Builder = builder;
    }

    void Context::popScope() {
        Locals = Locals->Outer == Globals ? Globals : Locals->Outer;
    }

    llvm::Module* Context::module() const {
        return *Module;
    }

    llvm::LLVMContext& Context::llvmContext() const {
        return module()->getContext();
    }

} // namespace pepper
