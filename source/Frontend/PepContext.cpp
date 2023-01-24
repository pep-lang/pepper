
#include "Frontend/PepContext.h"
#include <cassert>

#include "CodeGen/CodeGenModule.h"
#include "Frontend/Function.h"
#include "Frontend/Scope.h"
#include "Frontend/Types.h"

namespace pepper {
    PepContext* PepContext::Instance = nullptr;

    PepContext& PepContext::get() {
        assert(Instance);
        return *Instance;
    }

    Ref<llvm::IRBuilderBase> PepContext::ir() {
        return get().locals()->builder();
    }

    PepContext::PepContext() {
        assert(Instance == nullptr);
        Instance = this;

        Context = std::make_unique<llvm::LLVMContext>();

        TypeMap = Ref<Types>::New(*Context);

        // Builtins = Ref<Runtime>::New(Module);
        Globals = Ref<Scope>::New("Globals");
        Locals = Globals;
    }

    PepContext::~PepContext() {
        Instance = nullptr;
    }

    void PepContext::pushFunction(Ref<UserFunction> function) {
        pushScope(function->name(), function->Builder);
        Locals->FunctionTarget = function;
        if (function->is<Method>()) {
            Locals->This = function.as<Method>()->This;
        }
    }

    void PepContext::pushScope(const std::string& name, Ref<llvm::IRBuilderBase> builder) {
        Locals = Ref<Scope>::New(name, Locals);
        Locals->Builder = builder;
    }

    void PepContext::popScope() {
        Locals = Locals->Outer == Globals ? Globals : Locals->Outer;
    }

} // namespace pepper
