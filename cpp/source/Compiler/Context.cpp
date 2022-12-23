
#include "Compiler/Context.h"

#include "AST/AST.h"
#include "Codegen/Function.h"
#include "Codegen/Runtime.h"
#include "Codegen/Scope.h"
#include "Compiler/Param.h"
#include "Compiler/Types.h"
#include "JIT/Executor.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include <cassert>

namespace pepper {
    Context* Context::Instance = nullptr;

    Context& Context::get() {
        assert(Instance);
        return *Instance;
    }

    Context::Context(const std::string& moduleName) {
        assert(Instance == nullptr);
        Instance = this;

        Exec = Executor::Create();
        Ctx = std::make_unique<llvm::LLVMContext>();
        TypeMap = Ref<Types>::New(*Ctx);
        Module = std::make_unique<llvm::Module>(moduleName, *Ctx);
        Exec->configureModule(Module.get());

        Builtins = Ref<Runtime>::New();
        Globals = Ref<Scope>::New("Globals", Builtins);
        Locals = Globals;
    }

    Context::~Context() {
        Instance = nullptr;
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
        return Module.get();
    }

    llvm::LLVMContext& Context::llvmContext() const {
        return module()->getContext();
    }

} // namespace pepper
