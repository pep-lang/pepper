
#include "Frontend/Context.h"
#include <cassert>
#include <utility>

#include "CodeGen/CodeGenModule.h"
#include "Frontend/Function.h"
#include "Frontend/Runtime.h"
#include "Frontend/Scope.h"
#include "Frontend/Types.h"
#include "JIT/Executor.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"

namespace pepper {
    Context* Context::Instance = nullptr;

    Context& Context::get() {
        assert(Instance);
        return *Instance;
    }

    Ref<llvm::IRBuilderBase> Context::ir() {
        return get().locals()->builder();
    }

    Context::Context(Ref<CodeGenModule> module) {
        assert(Instance == nullptr);
        Instance = this;

        Module = std::move(module);

        TypeMap = Ref<Types>::New(*Module->getContext());

        Builtins = Ref<Runtime>::New(Module);
        Globals = Ref<Scope>::New("Globals", Builtins);
        Locals = Globals;
    }

    Context::~Context() {
        Instance = nullptr;
    }

    void Context::pushFunction(Ref<UserFunction> function) {
        pushScope(function->name(), function->Builder);
        Locals->FunctionTarget = function;
        if (function->is<Method>()) {
            Locals->This = function.as<Method>()->This;
        }
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

} // namespace pepper
