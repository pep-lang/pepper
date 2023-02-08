
#include <cassert>

#include "CodeGen/CodeGenModule.h"
#include "Function.h"
#include "Scope.h"
#include "SemaContext.h"
#include "Types.h"

namespace pepper {
    SemaContext* SemaContext::Instance = nullptr;

    SemaContext& SemaContext::get() {
        assert(Instance);
        return *Instance;
    }

    Ref<llvm::IRBuilderBase> SemaContext::ir() {
        return get().locals()->builder();
    }

    SemaContext::SemaContext() {
        assert(Instance == nullptr);
        Instance = this;

        Context = std::make_unique<llvm::LLVMContext>();

        TypeMap = Ref<Types>::New(*Context);

        // Builtins = Ref<Runtime>::New(Module);
        Globals = Ref<Scope>::New("Globals");
        Locals = Globals;
    }

    SemaContext::~SemaContext() {
        Instance = nullptr;
    }

    void SemaContext::pushFunction(Ref<UserFunction> function) {
        pushScope(function->name(), function->Builder);
        Locals->FunctionTarget = function;
        if (function->is<Method>()) {
            Locals->This = function.as<Method>()->This;
        }
    }

    void SemaContext::pushScope(const std::string& name, Ref<llvm::IRBuilderBase> builder) {
        Locals = Ref<Scope>::New(name, Locals);
        Locals->Builder = builder;
    }

    void SemaContext::popScope() {
        Locals = Locals->Outer == Globals ? Globals : Locals->Outer;
    }

} // namespace pepper
